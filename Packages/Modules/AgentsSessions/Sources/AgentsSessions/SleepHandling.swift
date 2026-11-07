import AgentKit
import Foundation
import ModuleKit
import VigieUI

/// Story 4.12: keep-awake while sessions work, and sessions interrupted by sleep (FR45, FR46, AD-5, A20, A24).
///
/// Keep-awake: the module holds one `context.power.preventIdleSleep` token while any session shows `working`
/// (stale sessions do not count) and cancels it when none does. It always asks: the power service honours
/// `[general] prevent_idle_sleep` and keeps the request inert when the setting is off.
///
/// Sleep/wake (see `docs/decisions/host-slept-detection.md`): on `.willSleep` the module notes the sessions
/// that are working and pauses liveness. On `.didWake` it first marks each noted session that is still working,
/// and has had no event since the sleep, `failed (host_slept)` through the reducer, persists, posts one alert
/// for the wake, and only then resumes liveness and runs a pass.
extension AgentsSessionsModule {
    /// The `preventIdleSleep` reason (shown by `pmset -g assertions`).
    nonisolated static let keepAwakeReason = "Agent session working"
    /// The sleep-summary alert's primary action: open the Agents tab.
    nonisolated static let openAgentsActionID = "open-agents"
    /// The sleep-summary alert's dedupe key.
    nonisolated static let hostSleptDedupeKey = "host_slept"

    /// What the module noted when the Mac went to sleep.
    struct SleepSnapshot: Sendable, Equatable {
        let at: Date
        /// Working sessions and their last action (the action the sleep interrupted).
        let working: [SessionKey: String?]
    }

    /// The open sleep-summary alert and the sessions it covers; resolved once none of them is failed.
    struct SleepSummaryAlert {
        let keys: Set<SessionKey>
        let handle: AlertHandle
    }

    // MARK: Keep-awake

    /// Holds or releases the keep-awake token to match the display statuses. Called from `syncState`.
    func updateKeepAwake() {
        guard let power else { return }
        let working = displayStatuses.values.contains(.working)
        if working, keepAwakeToken == nil {
            keepAwakeToken = power.preventIdleSleep(reason: Self.keepAwakeReason)
        } else if !working, let token = keepAwakeToken {
            keepAwakeToken = nil
            token.cancel()
        }
    }

    func releaseKeepAwake() {
        keepAwakeToken?.cancel()
        keepAwakeToken = nil
    }

    // MARK: Sleep and wake

    /// Handles one `context.power.sleepWake` event. `now` is the sleep or wake time (the event carries none).
    func handleSleepWake(_ event: SleepWakeEvent, now: Date = Date()) async {
        switch event {
        case .willSleep:
            let working = store.table.values.filter { $0.status == .working }
            sleepSnapshot = SleepSnapshot(
                at: now, working: Dictionary(uniqueKeysWithValues: working.map { ($0.key, $0.lastAction) }))
            livenessPaused = true
        case .didWake:
            if let save = markInterrupted(wakeAt: now), let persister {
                await persister.write(save.sessions, generation: save.generation)
            }
            livenessPaused = false
            await runLiveness(now: now)
        }
    }

    /// Marks the sessions the sleep interrupted `failed (host_slept)` and posts the wake alert. Returns the table
    /// to persist when a session was marked.
    @discardableResult
    func markInterrupted(wakeAt now: Date) -> (sessions: [Session], generation: Int)? {
        guard let snapshot = sleepSnapshot else { return nil }
        sleepSnapshot = nil
        // A session with an event after the sleep began survived it; leave it to that event.
        let keys = snapshot.working.keys.filter { key in
            guard let session = store.table[key] else { return false }
            return session.status == .working && session.lastEventAt <= snapshot.at
        }
        let changes = store.markHostSlept(keys, at: now)
        guard !changes.isEmpty else { return nil }
        let marked: [SessionKey] = changes.compactMap {
            if case .status(let key, _, _) = $0 { key } else { nil }
        }
        log?.notice("wake: \(marked.count, privacy: .public) session(s) interrupted by sleep")
        syncState(now: now)
        postWakeAlert(marked)
        return (store.snapshot, store.generation)
    }

    /// A20: one alert for the wake. One session: its usual `session.failed` alert (`HOST SLEPT`, Focus). Several:
    /// a single summary `session.failed` whose action opens the Agents tab.
    func postWakeAlert(_ keys: [SessionKey]) {
        guard let notifier, !keys.isEmpty else { return }
        for key in keys { alertHandles.removeValue(forKey: key)?.handle.resolve() }
        if keys.count == 1, let session = store.table[keys[0]] {
            let handle = notifier.post(notifierEvent(.failed, session: session, previous: nil))
            alertHandles[session.key] = OpenAlert(status: .failed, handle: handle)
            return
        }
        sleepSummary?.handle.resolve()
        let handle = notifier.post(sleepSummaryEvent(count: keys.count))
        sleepSummary = SleepSummaryAlert(keys: Set(keys), handle: handle)
    }

    /// `FAILED · HOST SLEPT` · `<n> sessions interrupted by sleep` · Open Agents.
    func sleepSummaryEvent(count: Int) -> NotifierEvent {
        NotifierEvent(
            kind: AlertKind.failed.rawValue,
            severity: AlertKind.failed.severity,
            title: SessionRowText.format("agentsSessions.alert.hostSlept.summary", count),
            action: .module(id: manifest.id, actionID: Self.openAgentsActionID, payload: Data()),
            dedupeKey: Self.hostSleptDedupeKey,
            category: Self.string("agentsSessions.alert.hostSlept.category"))
    }

    /// Resolves the sleep summary once none of its sessions is still failed.
    func resolveEndedSleepSummary() {
        guard let summary = sleepSummary else { return }
        guard !summary.keys.contains(where: { store.table[$0]?.status == .failed }) else { return }
        sleepSummary = nil
        summary.handle.resolve()
    }

    func resolveSleepSummary() {
        sleepSummary?.handle.resolve()
        sleepSummary = nil
    }
}
