import AgentKit
import Foundation
import ModuleKit
import VigieUI

/// Story 4.11: session alerts (FR12, FR13, FR15, FR33; AD-5 replay suppression, AD-13 kinds and resolve; A54).
extension AgentsSessionsModule {
    /// The Notifier kinds `agents.sessions` posts (AD-13 canonical kinds).
    public enum AlertKind: String, CaseIterable, Sendable {
        case blocked = "session.blocked"
        case done = "session.done"
        case failed = "session.failed"

        init?(_ status: SessionStatus) {
            switch status {
            case .blocked: self = .blocked
            case .done: self = .done
            case .failed: self = .failed
            case .idle, .working, .stale: return nil
            }
        }

        public var status: SessionStatus {
            switch self {
            case .blocked: .blocked
            case .done: .done
            case .failed: .failed
            }
        }

        /// Blocked and failed wait for the user; done is informational.
        public var severity: AlertSeverity {
            switch self {
            case .blocked, .failed: .critical
            case .done: .info
            }
        }

        /// The label of the kind in the generated alert settings (Story 3.7).
        public var label: LocalizedStringResource {
            switch self {
            case .blocked: LocalizedStringResource("agentsSessions.alert.kind.blocked", bundle: bundle)
            case .done: LocalizedStringResource("agentsSessions.alert.kind.done", bundle: bundle)
            case .failed: LocalizedStringResource("agentsSessions.alert.kind.failed", bundle: bundle)
            }
        }
    }

    /// The peek's primary action: Focus the session's terminal (payload: the session key, UTF-8).
    nonisolated static let focusActionID = "focus"
    /// AD-5: a replayed transition older than this updates state but posts nothing.
    nonisolated static let replayAlertWindow: TimeInterval = 5 * 60
    /// `metrics` key compared with `min_working_time` by the Notifier (A54), in seconds.
    nonisolated static let workingDurationMetric = "working_duration"

    /// An alert waiting for the end of the batch.
    struct PendingAlert {
        let kind: AlertKind
        /// The session before the entering event (for `working_duration`).
        let previous: Session?
        let at: Date
    }

    /// A posted alert: resolved when the session leaves `status` or goes away.
    struct OpenAlert {
        let status: SessionStatus
        let handle: AlertHandle
    }

    /// Records (or cancels) the batch's pending alert for the changed session.
    func noteAlert(
        _ change: SessionChange, previous: Session?, at: Date, replayed: Bool, now: Date,
        in pending: inout [SessionKey: PendingAlert]
    ) {
        let entered: (SessionKey, SessionStatus)
        switch change {
        case .created(let key, let status): entered = (key, status)
        case .status(let key, _, let status): entered = (key, status)
        case .removed(let key, _):
            pending[key] = nil
            return
        case .none, .metadataOnly:
            return
        }
        let (key, status) = entered
        guard let kind = AlertKind(status) else {
            pending[key] = nil
            return
        }
        if replayed && now.timeIntervalSince(at) > Self.replayAlertWindow {
            pending[key] = nil
            return
        }
        pending[key] = PendingAlert(kind: kind, previous: previous, at: at)
    }

    /// Posts each pending alert whose session still shows that status (a later event in the batch, or stale,
    /// never alerts).
    func postAlerts(_ pending: [SessionKey: PendingAlert], now: Date) {
        guard let notifier, !pending.isEmpty else { return }
        for (key, alert) in pending.sorted(by: { $0.key.description < $1.key.description }) {
            guard let session = store.table[key], session.status == alert.kind.status,
                displayStatus(of: key) == alert.kind.status
            else { continue }
            alertHandles.removeValue(forKey: key)?.handle.resolve()
            let handle = notifier.post(notifierEvent(alert.kind, session: session, previous: alert.previous))
            alertHandles[key] = OpenAlert(status: alert.kind.status, handle: handle)
        }
    }

    /// AD-13: resolves the alert of every session that left the status it alerted for, or went away.
    func resolveEndedAlerts() {
        guard !alertHandles.isEmpty else { return }
        for (key, alert) in alertHandles where store.table[key]?.status != alert.status {
            alertHandles[key] = nil
            alert.handle.resolve()
        }
    }

    func resolveAllAlerts() {
        let open = alertHandles.values
        alertHandles.removeAll()
        for alert in open { alert.handle.resolve() }
    }

    /// The Notifier event for a session that entered `kind`'s status.
    func notifierEvent(_ kind: AlertKind, session: Session, previous: Session?) -> NotifierEvent {
        let agent = agentName(session.agentID)
        var metrics: [String: Double] = [:]
        let body: String
        let category: String?
        switch kind {
        case .blocked:
            body = blockedDetail(session, agent: agent)
            category = Self.string("agentsSessions.alert.blocked.category")
        case .done:
            body = SessionRowText.format("agentsSessions.alert.done", agent)
            category = nil
            metrics[Self.workingDurationMetric] = Self.workingDuration(before: session, previous: previous)
        case .failed where session.failureReason == .hostSlept:
            body = rowText.interruptedLine(session)
            category = Self.string("agentsSessions.alert.hostSlept.category")
        case .failed:
            let reason = session.lastMessage ?? Self.string("agentsSessions.alert.failed.unknown")
            body = SessionRowText.format("agentsSessions.alert.failed", agent, reason)
            category = Self.string("agentsSessions.alert.failed.category")
        }
        return NotifierEvent(
            kind: kind.rawValue,
            severity: kind.severity,
            title: alertTitle(session),
            body: body,
            action: .module(id: manifest.id, actionID: Self.focusActionID, payload: Data(session.key.description.utf8)),
            dedupeKey: session.key.description,
            metrics: metrics,
            category: category)
    }

    /// `project / branch-or-path`. Branches arrive with Epic 8; until then the last two components of `cwd`
    /// (`www / vigie`), or the project alone.
    func alertTitle(_ session: Session) -> String {
        let project = rowText.project(session)
        guard let cwd = session.cwd?.standardizedFileURL else { return project }
        let parent = cwd.deletingLastPathComponent().lastPathComponent
        guard !parent.isEmpty, parent != "/", parent != project else { return project }
        return SessionRowText.format("agentsSessions.alert.title", parent, project)
    }

    /// `Claude Code wants to run Bash` (the tool from the last `tool.start`), else the agent's own message, else
    /// `Claude Code needs input` / `asks a question`.
    func blockedDetail(_ session: Session, agent: String) -> String {
        if session.blockReason != .question, let tool = session.lastAction, !tool.isEmpty {
            return SessionRowText.format("agentsSessions.alert.blocked.tool", agent, tool)
        }
        if let message = session.lastMessage, !message.isEmpty { return message }
        let key =
            session.blockReason == .question
            ? "agentsSessions.alert.blocked.question" : "agentsSessions.alert.blocked.input"
        return SessionRowText.format(key, agent)
    }

    /// Seconds the session worked before this `turn.end` (A54): from entering working to the event; 0 when the
    /// session was not working (e.g. it appeared done).
    nonisolated static func workingDuration(before session: Session, previous: Session?) -> Double {
        guard let previous, previous.status == .working else { return 0 }
        return max(0, session.statusSince.timeIntervalSince(previous.statusSince))
    }

    /// Alert action (AD-13, Story 3.3 `AlertActionHandler`): `focus` brings the session's terminal forward, the
    /// same path as the Agents tab. Terminal adapters take no `UserIntent` (activation is their own), so `intent`
    /// is not used. The focus runs in a task (``alertActionTask``). `open-agents` (the sleep summary, Story
    /// 4.12) opens the Agents tab, with focus when the action came from the user.
    public func handleAlertAction(_ actionID: String, payload: Data, intent: UserIntent?) {
        if actionID == Self.openAgentsActionID {
            host?.openOwnTab(focus: intent)
            return
        }
        guard actionID == Self.focusActionID, let key = SessionKey(String(decoding: payload, as: UTF8.self)) else {
            log?.notice("alert action \(actionID, privacy: .public) ignored")
            return
        }
        alertActionTask = Task { await self.focus(key) }
    }

    nonisolated static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }
}
