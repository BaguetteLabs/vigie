import AgentKit
import Foundation
import ModuleKit
import Observation
import SwiftUI
import VigieUI
import Wire
import os

/// `agents.sessions` (SPEC §7.1): tracks every running CLI agent session.
///
/// App assembly builds the adapter lists once and passes the same instances here and to `agents.usage`
/// (AD-4); this module never discovers adapters itself, so adding an agent needs no change here (NFR23).
///
/// Event path (AD-5, AD-7): `agent.hook` messages are decoded (`HookPayload`) and normalized by the matching
/// adapter off the main actor, then applied in arrival order to the `SessionStore` on the main actor. Replayed
/// messages go through the same path, so statuses converge. Status and membership changes are persisted to
/// `sessions.json` off the main actor; heartbeats are not.
///
/// Liveness (Story 4.8, AD-5): every 10 s, and once at start and on `host.ready`, each session's agent process
/// is checked off the main actor (pid + start time, ``ProcessLiveness``); sessions whose process is gone are
/// removed, except failed ones, which stay until ``dismiss(_:)`` or 24 h after entering failed. Sessions the
/// adapter could not tie to a process (no `agentProcess`) are left to their `session.end`. The same tick
/// refreshes the derived stale state (`stale_after`) and drops sessions under `ignored_paths`.
@MainActor @Observable
public final class AgentsSessionsModule: NotchModule, AlertActionHandler {
    nonisolated static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    /// `sessions.json`, schema 1.
    nonisolated static let storageName = "sessions"
    nonisolated static let storageSchema = 1
    /// SPEC §11 default for `done_to_idle`.
    nonisolated static let defaultDoneToIdle: Duration = .seconds(15 * 60)
    /// How often done sessions are checked against `done_to_idle`.
    nonisolated static let expiryInterval: Duration = .seconds(30)
    /// How often agent processes are checked (SPEC §7.1, FR36).
    nonisolated static let livenessInterval: Duration = .seconds(10)
    /// Posted by the host once the launch sequence completes (AD-6 step 6).
    nonisolated static let hostReadyTopic = "host.ready"

    public nonisolated static let staticManifest = ModuleManifest(
        id: "agents.sessions",
        name: LocalizedStringResource("agentsSessions.module.name", bundle: bundle),
        icon: "terminal",
        settings: [
            SettingDescriptor(
                key: "done_to_idle",
                label: LocalizedStringResource("agentsSessions.setting.doneToIdle", bundle: bundle),
                kind: .duration(default: defaultDoneToIdle),
                scope: .synced,
                help: LocalizedStringResource("agentsSessions.setting.doneToIdle.help", bundle: bundle)),
            SettingDescriptor(
                key: "terminal",
                label: LocalizedStringResource("agentsSessions.setting.terminal", bundle: bundle),
                kind: .string(default: "terminal"),
                scope: .local),
            SettingDescriptor(
                key: "adapters",
                label: LocalizedStringResource("agentsSessions.setting.adapters", bundle: bundle),
                kind: .list(of: .string, default: ["claude"]),
                scope: .synced),
            SettingDescriptor(
                key: "stale_after",
                label: LocalizedStringResource("agentsSessions.setting.staleAfter", bundle: bundle),
                kind: .duration(default: Session.defaultStaleAfter),
                scope: .synced,
                help: LocalizedStringResource("agentsSessions.setting.staleAfter.help", bundle: bundle)),
            SettingDescriptor(
                key: "ignored_paths",
                label: LocalizedStringResource("agentsSessions.setting.ignoredPaths", bundle: bundle),
                kind: .list(of: .string, default: []),
                scope: .synced,
                help: LocalizedStringResource("agentsSessions.setting.ignoredPaths.help", bundle: bundle)),
        ],
        alertKinds: AlertKind.allCases.map(\.rawValue),
        defaultEnabled: true
    )

    public let manifest = AgentsSessionsModule.staticManifest
    public private(set) var state: ModuleState = .hidden

    public let adapters: AgentAdapters
    /// Terminal adapters plus the fallback (App assembly passes `GenericTerminalAdapter`, A16).
    public let terminals: TerminalAdapters
    /// Per-adapter contexts built by App assembly (AD-19), for adapter calls that need services.
    public let adapterContexts: [AgentID: any AdapterContext]
    /// Per-terminal-adapter contexts; a terminal without one gets a context built from this module's services.
    public let terminalContexts: [TerminalID: any AdapterContext]
    /// Opens a Settings pane by id (the `NO AGENT CONNECTED` button goes to Settings › Agents); nil hides it.
    @ObservationIgnored public let openSettings: (@MainActor @Sendable (String) -> Void)?

    /// The session table. Only its reducer writes statuses (AD-5).
    public let store = SessionStore()
    /// Urgency-sorted sessions (FR34), by stored status.
    public var sessions: [Session] { store.sessions }
    /// Urgency-sorted sessions by display status: stale sessions after idle (FR36). Refreshed on every event
    /// and every liveness tick.
    public private(set) var displaySessions: [Session] = []
    /// Display status per session key: the stored status, or `.stale` (FR36).
    public private(set) var displayStatuses: [SessionKey: SessionStatus] = [:]
    /// Sessions whose agent process the last liveness pass found dead. Only failed sessions stay listed with a
    /// dead process (FR36); those can be dismissed from the Agents tab.
    public private(set) var endedProcesses: Set<SessionKey> = []

    /// Checks agent processes (pid + start time).
    public let liveness: any ProcessLiveness
    /// Where `~` in `ignored_paths` points.
    public let homeDirectory: URL

    @ObservationIgnored var eventTask: Task<Void, Never>?
    @ObservationIgnored var readyTask: Task<Void, Never>?
    @ObservationIgnored private var expiryToken: RegistrationToken?
    @ObservationIgnored private var livenessToken: RegistrationToken?
    @ObservationIgnored private var settings: (any ModuleSettings)?
    @ObservationIgnored var ignoredKeys = IgnoredKeys()
    @ObservationIgnored private var persister: SessionPersister?
    @ObservationIgnored var log: Logger?
    @ObservationIgnored var activity: (any ActivityLog)?
    @ObservationIgnored var notifier: (any Notifier)?
    /// The open alert per session and the status it was posted for (AD-13: resolved when the session leaves it).
    @ObservationIgnored var alertHandles: [SessionKey: OpenAlert] = [:]
    /// The focus started by the last alert action (tests await it).
    @ObservationIgnored var alertActionTask: Task<FocusResult, Never>?
    /// Built at start from the module context, for terminal adapters without their own context.
    @ObservationIgnored var fallbackTerminalContext: (any AdapterContext)?

    public init(
        adapters: AgentAdapters,
        terminals: TerminalAdapters,
        contexts: [AgentID: any AdapterContext] = [:],
        terminalContexts: [TerminalID: any AdapterContext] = [:],
        liveness: any ProcessLiveness = SystemProcessLiveness(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        openSettings: (@MainActor @Sendable (String) -> Void)? = nil
    ) {
        self.adapters = adapters
        self.terminals = terminals
        self.adapterContexts = contexts
        self.terminalContexts = terminalContexts
        self.openSettings = openSettings
        self.liveness = liveness
        self.homeDirectory = homeDirectory
    }

    public func start(context: any ModuleContext) async throws {
        let log = context.log
        self.log = log
        settings = context.settings
        activity = context.activity
        notifier = context.notifier
        fallbackTerminalContext = AdapterContextBox(
            settings: DefaultsReadOnlySettings(descriptors: []), secrets: context.secrets,
            executables: context.executables, http: URLSessionHTTPClient(), log: log)
        let persister = SessionPersister(storage: context.storage, log: log)
        self.persister = persister

        let saved: [Session]?
        do {
            saved = try await context.storage.readJSON(
                Self.storageName, as: [Session].self, schema: Self.storageSchema)
        } catch {
            log.error("sessions.json not loaded: \(String(describing: error), privacy: .public)")
            saved = nil
        }
        store.load(saved ?? [])
        if let save = expireDone(settings: context.settings) {
            await persister.write(save.sessions, generation: save.generation)
        }
        syncState()

        // Subscribe before returning (AD-6 launch order: modules subscribe before the spool replay).
        let stream = context.events.subscribe(topicPrefix: "agent.")
        let pipeline = HookPipeline(adapters: adapters, log: log)
        eventTask = Task.detached { [weak self] in
            for await message in stream {
                let events = pipeline.normalize(message)
                guard !events.isEmpty else { continue }
                let save = await self?.apply(events, replayed: message.replayed)
                if let save { await persister.write(save.sessions, generation: save.generation) }
            }
        }

        let settings = context.settings
        expiryToken = context.scheduler.every(Self.expiryInterval) { [weak self] in
            guard let save = await self?.expireDone(settings: settings) else { return }
            await persister.write(save.sessions, generation: save.generation)
        }
        livenessToken = context.scheduler.every(Self.livenessInterval) { [weak self] in
            await self?.runLiveness()
        }

        // AD-5: one reconcile over the persisted sessions once the launch sequence is done (`host.ready`).
        // The host does not post `host.ready` yet, so the module also reconciles here, at the end of its own
        // start; a dead session recreated by the spool replay goes at the next 10 s tick.
        let ready = context.events.subscribe(topicPrefix: Self.hostReadyTopic)
        readyTask = Task.detached { [weak self] in
            for await _ in ready {
                await self?.runLiveness()
            }
        }
        await runLiveness()
    }

    public func stop() async {
        eventTask?.cancel()
        eventTask = nil
        readyTask?.cancel()
        readyTask = nil
        expiryToken?.cancel()
        expiryToken = nil
        livenessToken?.cancel()
        livenessToken = nil
        // Heartbeat metadata (last action, last event time) is saved once on the way out.
        await persister?.write(store.snapshot, generation: store.generation, force: true)
        resolveAllAlerts()
    }

    /// The right-wing content (FR37, A19). `ClosedNotchArbiter` routes `agents.sessions` items to the trailing
    /// side, sorts them by item state, then `priority`, then `order`, and shows the first `closed.slots` with
    /// `+X` after them. One glyph per session: the item state is the session's urgency (blocked / failed →
    /// alert, done / working → active, idle / stale → ambient) and `order` its index in ``displaySessions``,
    /// so blocked and failed (most recent first) fill the slots before any less urgent session. No count,
    /// project name or label. With no session, one label-only readout: `NO AGENT CONNECTED` without adapters,
    /// else `NO ACTIVE SESSIONS`.
    public func leftWingItems() -> [LeftWingItem] {
        Self.wingItems(
            sessions: displaySessions, statuses: displayStatuses, empty: wingEmptyState, text: rowText,
            now: Date())
    }

    /// The right wing's empty state, or nil when there are sessions.
    public var wingEmptyState: WingEmptyState? {
        guard displaySessions.isEmpty else { return nil }
        return adapters.adapters.isEmpty ? .noAgentConnected : .noActiveSessions
    }

    /// Id of the empty-state readout item.
    nonisolated static let emptyItemID = "empty"

    static func wingItems(
        sessions: [Session], statuses: [SessionKey: SessionStatus], empty: WingEmptyState?,
        text: SessionRowText, now: Date
    ) -> [LeftWingItem] {
        if let empty {
            let copy = empty.copy
            return [
                LeftWingItem(id: emptyItemID, priority: 0, state: .ambient) { size in
                    size == .icon ? nil : AnyView(WingEmptyReadout(copy))
                }
            ]
        }
        return sessions.enumerated().map { index, session in
            let status = statuses[session.key] ?? session.status
            let label = text.accessibilityLabel(session, now: now)
            return LeftWingItem(
                id: session.key.description, priority: 0, state: wingState(status), order: index
            ) { _ in
                AnyView(SessionGlyphView(status, accessibilityLabel: label))
            }
        }
    }

    /// FR38 per session: the state the arbiter ranks a glyph by.
    nonisolated static func wingState(_ status: SessionStatus) -> ModuleState {
        switch status {
        case .blocked, .failed: .alert
        case .done, .working: .active
        case .idle, .stale: .ambient
        }
    }

    /// Removes a failed session now (the Agents tab dismiss, Story 4.10). Other statuses are never dismissed
    /// (SPEC §7.1: dismissing does not change state). Returns true when a session was removed.
    @discardableResult
    public func dismiss(_ key: SessionKey) async -> Bool {
        guard store.table[key]?.status == .failed else { return false }
        store.remove([key])
        syncState()
        await persister?.write(store.snapshot, generation: store.generation)
        return true
    }

    /// The display status of a session (stale or its stored status).
    public func displayStatus(of key: SessionKey) -> SessionStatus? {
        displayStatuses[key]
    }

    /// Text for rows, glyphs and peeks with the current `stale_after`.
    public var rowText: SessionRowText { SessionRowText(staleAfter: staleAfter) }

    /// `stale_after` (SPEC §11), default 10 min.
    var staleAfter: Duration {
        settings?.value("stale_after", as: Duration.self) ?? Session.defaultStaleAfter
    }

    /// `ignored_paths` (SPEC §11), `~` expanded.
    var ignoredPaths: IgnoredPaths {
        IgnoredPaths(settings?.value("ignored_paths", as: [String].self) ?? [], home: homeDirectory)
    }

    /// Applies normalized events in order; returns the table to persist when status or membership changed.
    ///
    /// Ignored paths (FR42, A44): an event whose `cwd` lies under `ignored_paths` marks its session key as
    /// ignored (and removes the session if it was tracked); every later event for that key is dropped, even
    /// without a `cwd`, until its `session.end`.
    ///
    /// Alerts (Story 4.11): a session entering blocked, done or failed posts once, after the whole batch is
    /// applied; `replayed` events older than ``replayAlertWindow`` update state without posting (AD-5).
    @discardableResult
    func apply(
        _ events: [AgentEvent], replayed: Bool = false, now: Date = Date()
    ) -> (sessions: [Session], generation: Int)? {
        var persist = false
        var pending: [SessionKey: PendingAlert] = [:]
        let ignored = ignoredPaths
        for event in events {
            let key = event.context.sessionKey
            if ignoredKeys.contains(key) {
                if case .sessionEnd = event { ignoredKeys.remove(key) }
                continue
            }
            if ignored.contains(event.context.cwd) {
                if case .sessionEnd = event {} else { ignoredKeys.insert(key) }
                if !store.remove([key]).isEmpty { persist = true }
                continue
            }
            let previous = store.table[key]
            let change = store.apply(event)
            if change.persists { persist = true }
            noteAlert(change, previous: previous, at: event.context.at, replayed: replayed, now: now, in: &pending)
        }
        syncState(now: now)
        postAlerts(pending, now: now)
        return persist ? (store.snapshot, store.generation) : nil
    }

    /// One liveness pass with the processes checked off the main actor; persists any removal.
    nonisolated func runLiveness(now: Date = Date()) async {
        let refs = await processRefs()
        let dead = refs.filter { !liveness.isAlive($0.value) }
        guard let save = await reconcile(now: now, dead: dead), let persister = await persister else { return }
        await persister.write(save.sessions, generation: save.generation)
    }

    /// The agent process of every session that has one.
    func processRefs() -> [SessionKey: AgentProcessRef] {
        store.table.compactMapValues(\.agentProcess)
    }

    /// Removes sessions whose checked process is dead (unless the session's process changed since the check),
    /// failed sessions past their 24 h retention, and sessions now under `ignored_paths`; refreshes the stale
    /// state. Returns the table to persist when a session was removed.
    @discardableResult
    func reconcile(now: Date, dead: [SessionKey: AgentProcessRef]) -> (sessions: [Session], generation: Int)? {
        var removed = store.reconcile(now: now) { key, process in dead[key] == process }
        let ended = Set(dead.keys.filter { store.table[$0]?.agentProcess == dead[$0] })
        if ended != endedProcesses { endedProcesses = ended }
        let ignored = ignoredPaths
        if !ignored.isEmpty {
            let keys = store.table.values.filter { ignored.contains($0.cwd) }.map(\.key)
            for key in keys { ignoredKeys.insert(key) }
            removed += store.remove(keys)
        }
        if !removed.isEmpty {
            log?.info("liveness removed \(removed.count, privacy: .public) session(s)")
        }
        syncState(now: now)
        return removed.isEmpty ? nil : (store.snapshot, store.generation)
    }

    /// Runs the `done_to_idle` check now; returns the table to persist when a session moved.
    @discardableResult
    func expireDone(settings: any ModuleSettings, now: Date = Date()) -> (sessions: [Session], generation: Int)? {
        let delay = settings.value("done_to_idle", as: Duration.self) ?? Self.defaultDoneToIdle
        let expired = store.expireDone(now: now, doneToIdle: delay)
        syncState(now: now)
        return expired.isEmpty ? nil : (store.snapshot, store.generation)
    }

    /// Refreshes the display statuses, the display order and the module state (FR38 on display statuses: a
    /// stale session counts like idle).
    func syncState(now: Date = Date()) {
        let staleAfter = staleAfter
        var statuses: [SessionKey: SessionStatus] = [:]
        for session in store.sessions {
            statuses[session.key] = session.displayStatus(now: now, staleAfter: staleAfter)
        }
        let display = SessionReducer.sorted(store.sessions) { statuses[$0.key] ?? $0.status }
        if statuses != displayStatuses { displayStatuses = statuses }
        if display != displaySessions { displaySessions = display }
        let next = SessionReducer.moduleState(statuses: statuses.values)
        if state != next { state = next }
        resolveEndedAlerts()
    }
}

/// The right wing's label-only empty states (FR37, DESIGN "Readout").
public enum WingEmptyState: Sendable, Equatable {
    /// No agent adapter is set up.
    case noAgentConnected
    /// Adapters exist but no session runs.
    case noActiveSessions

    public var copy: VigieCopy.EmptyState {
        switch self {
        case .noAgentConnected: VigieCopy.noAgentConnected
        case .noActiveSessions: VigieCopy.noActiveSessions
        }
    }
}

/// Decodes `agent.hook` payloads and normalizes them with the matching adapter. Runs off the main actor;
/// logs an unknown agent once per id.
final class HookPipeline: Sendable {
    static let hookTopic = "agent.hook"

    private let adapters: AgentAdapters
    private let log: Logger
    private let reported = OSAllocatedUnfairLock(initialState: Set<String>())

    init(adapters: AgentAdapters, log: Logger) {
        self.adapters = adapters
        self.log = log
    }

    func normalize(_ message: EventMessage) -> [AgentEvent] {
        // TODO(generic path, AD-5): `agent.generic` from `vigie agent` / `vigie run`.
        guard message.topic == Self.hookTopic else { return [] }
        let payload: HookPayload
        do {
            payload = try JSONDecoder().decode(HookPayload.self, from: message.payload)
        } catch {
            log.error("agent.hook payload not decoded: \(String(describing: error), privacy: .public)")
            return []
        }
        guard let id = AgentID(payload.agent), let adapter = adapters.adapter(for: id) else {
            let first = reported.withLock { $0.insert(payload.agent).inserted }
            if first {
                log.notice("agent.hook from unknown agent \(payload.agent, privacy: .public): ignored")
            }
            return []
        }
        return adapter.normalize(payload, sentAt: message.sentAt)
    }
}

/// Writes `sessions.json` through `ModuleStorage` off the main actor, dropping snapshots older than the last one
/// written (two writers: the event loop and the expiry job).
actor SessionPersister {
    private let storage: any ModuleStorage
    private let log: Logger
    private var written = -1

    init(storage: any ModuleStorage, log: Logger) {
        self.storage = storage
        self.log = log
    }

    func write(_ sessions: [Session], generation: Int, force: Bool = false) async {
        guard force || generation > written else { return }
        written = max(written, generation)
        do {
            try await storage.writeJSON(
                sessions, name: AgentsSessionsModule.storageName, schema: AgentsSessionsModule.storageSchema)
        } catch {
            log.error("sessions.json not written: \(String(describing: error), privacy: .public)")
        }
    }
}
