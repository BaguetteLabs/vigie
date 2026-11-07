import AgentKit
import Foundation
import ModuleKit
import Observation
import VigieUI

/// What applying one event did to the session table.
public enum SessionChange: Hashable, Sendable {
    /// Nothing changed (e.g. `session.end` for an unknown session, or a late `session.end`).
    case none
    /// Only metadata or `lastEventAt` changed (heartbeats, late events). Not persisted.
    case metadataOnly(SessionKey)
    /// A new session appeared with this status.
    case created(SessionKey, SessionStatus)
    /// An existing session moved between two different statuses.
    case status(SessionKey, from: SessionStatus, to: SessionStatus)
    /// The session ended and was removed (`gone`).
    case removed(SessionKey, last: SessionStatus)

    /// True for status or membership changes: the only ones persisted (AD-5).
    public var persists: Bool {
        switch self {
        case .none, .metadataOnly: false
        case .created, .status, .removed: true
        }
    }
}

/// The SPEC §7.1 transition table: the only code that writes a session status (AD-5). Pure.
///
/// | Event | Status after (from any status) |
/// |---|---|
/// | `session.start` | idle (creates the session) |
/// | `prompt.submit`, `tool.start`, `tool.end`, `subagent.end` | working |
/// | `turn.end` | done |
/// | `needs.input` | blocked |
/// | `session.error` | failed |
/// | `session.end` | removed |
///
/// Rules:
/// - All timing uses `context.at` (the envelope `sent_at`), never arrival time.
/// - An event older than the session's `lastEventAt` never changes status or membership; it only fills
///   metadata the session does not have yet (it never overwrites newer metadata).
/// - `statusSince` is the `at` of the event that entered the status; re-entering the same status keeps it.
/// - An event for an unknown session (other than `session.end`) creates it in the event's status, so a session
///   whose `session.start` was missed (app started mid-session) still shows.
public enum SessionReducer {
    @discardableResult
    public static func apply(_ event: AgentEvent, to sessions: inout [SessionKey: Session]) -> SessionChange {
        let context = event.context
        let key = context.sessionKey

        guard var session = sessions[key] else {
            guard let target = targetStatus(of: event) else { return .none }
            var created = Session(key: key, status: target, statusSince: context.at, lastEventAt: context.at)
            updateMetadata(of: &created, with: event, overwrite: true)
            sessions[key] = created
            return .created(key, target)
        }

        guard context.at >= session.lastEventAt else {
            // Out of order (AD-5): never status or membership, only metadata we lack.
            let before = session
            updateMetadata(of: &session, with: event, overwrite: false)
            guard session != before else { return .none }
            sessions[key] = session
            return .metadataOnly(key)
        }

        session.lastEventAt = context.at
        guard let target = targetStatus(of: event) else {
            sessions[key] = nil
            return .removed(key, last: session.status)
        }

        let from = session.status
        if target != from {
            session.status = target
            session.statusSince = context.at
        }
        if target != .blocked { session.blockReason = nil }
        if target != .blocked && target != .failed { session.lastMessage = nil }
        updateMetadata(of: &session, with: event, overwrite: true)
        sessions[key] = session
        return target == from ? .metadataOnly(key) : .status(key, from: from, to: target)
    }

    /// The status an event enters; nil for `session.end` (removed).
    public static func targetStatus(of event: AgentEvent) -> SessionStatus? {
        switch event {
        case .sessionStart: .idle
        case .promptSubmit, .toolStart, .toolEnd, .subagentEnd: .working
        case .turnEnd: .done
        case .needsInput: .blocked
        case .sessionError: .failed
        case .sessionEnd: nil
        }
    }

    /// Turns every `done` session whose `statusSince` is at least `doneToIdle` before `now` into `idle`
    /// (SPEC §7.1). The idle `statusSince` is the moment the delay ran out, not `now`. Returns the keys moved.
    @discardableResult
    public static func expireDone(
        in sessions: inout [SessionKey: Session], now: Date, doneToIdle: Duration
    ) -> [SessionKey] {
        let delay = doneToIdle.timeInterval
        var expired: [SessionKey] = []
        for (key, session) in sessions where session.status == .done {
            let deadline = session.statusSince.addingTimeInterval(delay)
            guard deadline <= now else { continue }
            sessions[key]?.status = .idle
            sessions[key]?.statusSince = deadline
            expired.append(key)
        }
        return expired.sorted { $0.description < $1.description }
    }

    /// Urgency order (SPEC §7.1, FR34): blocked and failed share the top (most recent `statusSince` first),
    /// then done, working, idle (stale, Story 4.8, after idle). Within a group the most recent `statusSince`
    /// comes first; full ties fall back to the key for a stable order.
    public static func sorted(_ sessions: some Sequence<Session>) -> [Session] {
        sessions.sorted { lhs, rhs in
            let (lr, rr) = (rank(lhs.status), rank(rhs.status))
            if lr != rr { return lr < rr }
            if lhs.statusSince != rhs.statusSince { return lhs.statusSince > rhs.statusSince }
            return lhs.key.description < rhs.key.description
        }
    }

    /// FR38 / SPEC §7.1: `alert` if any session is blocked or failed, `active` if any is done or working,
    /// `ambient` otherwise, including no session at all (so the empty-state label shows).
    public static func moduleState(for sessions: some Sequence<Session>) -> ModuleState {
        moduleState(statuses: sessions.lazy.map(\.status))
    }

    static func rank(_ status: SessionStatus) -> Int {
        switch status {
        case .blocked, .failed: 0
        case .done: 1
        case .working: 2
        case .idle: 3
        case .stale: 4
        }
    }

    /// Copies the event's metadata. `overwrite == false` (late events) only fills fields that are nil.
    private static func updateMetadata(of session: inout Session, with event: AgentEvent, overwrite: Bool) {
        func set<T>(_ path: WritableKeyPath<Session, T?>, _ value: T?) {
            guard let value, overwrite || session[keyPath: path] == nil else { return }
            session[keyPath: path] = value
        }
        let context = event.context
        set(\.cwd, context.cwd)
        set(\.tty, context.tty)
        set(\.terminal, context.terminal)
        set(\.agentProcess, context.agentProcess)
        switch event {
        case .sessionStart(_, let model):
            set(\.model, model)
        case .toolStart(_, let tool), .toolEnd(_, let tool):
            set(\.lastAction, tool)
        case .needsInput(_, let reason, let message):
            guard overwrite else { return }
            session.blockReason = reason
            session.lastMessage = message
        case .sessionError(_, let message):
            guard overwrite else { return }
            session.lastMessage = message
        case .promptSubmit, .subagentEnd, .turnEnd, .sessionEnd:
            break
        }
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

/// The observable session table the module and its views read. Every status write goes through
/// `SessionReducer` (AD-5).
@MainActor @Observable
public final class SessionStore {
    public private(set) var table: [SessionKey: Session] = [:]
    /// Urgency-sorted (`SessionReducer.sorted`).
    public private(set) var sessions: [Session] = []
    /// FR38.
    public private(set) var state: ModuleState = .ambient
    /// Bumped on every persisted change, so writes can be ordered off the main actor.
    public private(set) var generation = 0

    public init(sessions: [Session] = []) {
        load(sessions)
    }

    /// Replaces the table, e.g. with `sessions.json` at launch. A later duplicate key wins.
    public func load(_ sessions: [Session]) {
        table = Dictionary(sessions.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        refresh()
    }

    @discardableResult
    public func apply(_ event: AgentEvent) -> SessionChange {
        let change = SessionReducer.apply(event, to: &table)
        if change != .none { refresh() }
        if change.persists { generation += 1 }
        return change
    }

    @discardableResult
    public func expireDone(now: Date, doneToIdle: Duration) -> [SessionKey] {
        let expired = SessionReducer.expireDone(in: &table, now: now, doneToIdle: doneToIdle)
        if !expired.isEmpty {
            refresh()
            generation += 1
        }
        return expired
    }

    /// The liveness pass (``SessionReducer/reconcile(in:now:failedRetention:isDead:)``); returns the removed keys.
    @discardableResult
    public func reconcile(
        now: Date,
        failedRetention: Duration = SessionReducer.failedRetention,
        isDead: (SessionKey, AgentProcessRef) -> Bool
    ) -> [SessionKey] {
        let removed = SessionReducer.reconcile(
            in: &table, now: now, failedRetention: failedRetention, isDead: isDead)
        if !removed.isEmpty {
            refresh()
            generation += 1
        }
        return removed
    }

    /// Removes sessions outright (ignored paths, dismissed failed sessions); returns the keys that were there.
    @discardableResult
    public func remove(_ keys: some Sequence<SessionKey>) -> [SessionKey] {
        var removed: [SessionKey] = []
        for key in keys where table.removeValue(forKey: key) != nil {
            removed.append(key)
        }
        if !removed.isEmpty {
            refresh()
            generation += 1
        }
        return removed
    }

    /// Records the terminal chosen for a session (Story 5.1). Metadata, but persisted: the locator is captured
    /// once and must survive a relaunch. Returns true when the session changed.
    @discardableResult
    public func setTerminal(_ key: SessionKey, adapter: TerminalID, locator: TerminalLocator?) -> Bool {
        guard var session = table[key],
            session.terminalAdapterID != adapter || session.terminalLocator != locator
        else { return false }
        session.terminalAdapterID = adapter
        session.terminalLocator = locator
        table[key] = session
        refresh()
        generation += 1
        return true
    }

    /// The table to persist, in urgency order.
    public var snapshot: [Session] { sessions }

    private func refresh() {
        sessions = SessionReducer.sorted(table.values)
        state = SessionReducer.moduleState(for: sessions)
    }
}
