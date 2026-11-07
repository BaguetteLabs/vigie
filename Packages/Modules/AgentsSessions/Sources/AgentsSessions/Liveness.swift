import AgentKit
import Foundation
import ModuleKit
import VigieUI

// Story 4.8: liveness (AD-5), failed retention, stale display state, ignored paths.

extension Session {
    /// SPEC §11 default for `stale_after`.
    public static let defaultStaleAfter: Duration = .seconds(10 * 60)

    /// A working session with no event for `staleAfter` or more (SPEC §7.1, FR36). Display only: the
    /// stored status stays `working`, and the next event returns the session to its real state.
    public func isStale(now: Date, staleAfter: Duration) -> Bool {
        status == .working && now.timeIntervalSince(lastEventAt) >= staleAfter.timeInterval
    }

    /// The status to show: `.stale` for a stale working session, else the stored status.
    public func displayStatus(now: Date, staleAfter: Duration = Session.defaultStaleAfter) -> SessionStatus {
        isStale(now: now, staleAfter: staleAfter) ? .stale : status
    }
}

extension SessionReducer {
    /// AD-5: a failed session stays this long after entering failed, unless dismissed.
    public static let failedRetention: Duration = .seconds(24 * 60 * 60)

    /// The liveness pass (AD-5, FR36). Removes:
    /// - every failed session whose `statusSince` is `failedRetention` or more before `now` (failed sessions are
    ///   never removed for a dead process: they stay until dismissed or 24 h);
    /// - every other session with an `agentProcess` for which `isDead` is true.
    ///
    /// Sessions without an `agentProcess` (the adapter could not identify the agent process) are never
    /// removed here: only their `session.end` removes them. Returns the removed keys, sorted.
    @discardableResult
    public static func reconcile(
        in sessions: inout [SessionKey: Session],
        now: Date,
        failedRetention: Duration = SessionReducer.failedRetention,
        isDead: (SessionKey, AgentProcessRef) -> Bool
    ) -> [SessionKey] {
        let retention = failedRetention.timeInterval
        var removed: [SessionKey] = []
        for (key, session) in sessions {
            let gone: Bool
            if session.status == .failed {
                gone = now.timeIntervalSince(session.statusSince) >= retention
            } else if let process = session.agentProcess {
                gone = isDead(key, process)
            } else {
                gone = false
            }
            if gone {
                sessions[key] = nil
                removed.append(key)
            }
        }
        return removed.sorted { $0.description < $1.description }
    }

    /// FR38 on display statuses: `alert` for blocked or failed, `active` for done or working, else `ambient`.
    public static func moduleState(statuses: some Sequence<SessionStatus>) -> ModuleState {
        var state = ModuleState.ambient
        for status in statuses {
            switch status {
            case .blocked, .failed: return .alert
            case .done, .working: state = .active
            case .idle, .stale: break
            }
        }
        return state
    }

    /// Urgency order on display statuses (FR34, FR36): as ``sorted(_:)``, with stale sessions after idle.
    public static func sorted(
        _ sessions: some Sequence<Session>, displayStatus: (Session) -> SessionStatus
    ) -> [Session] {
        sessions
            .map { ($0, rank(displayStatus($0))) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.0.statusSince != rhs.0.statusSince { return lhs.0.statusSince > rhs.0.statusSince }
                return lhs.0.key.description < rhs.0.key.description
            }
            .map(\.0)
    }
}

/// `ignored_paths` (SPEC §11, FR42, A44): sessions whose `cwd` is one of these folders or lies under one
/// are never tracked. `~` and `~/…` expand to the user's home folder; relative entries are ignored.
public struct IgnoredPaths: Sendable, Equatable {
    /// Standardized absolute paths, without a trailing slash.
    public let paths: [String]

    public init(_ entries: [String], home: URL) {
        let homePath = home.standardizedFileURL.path
        paths = entries.compactMap { raw in
            let entry = raw.trimmingCharacters(in: .whitespaces)
            let expanded: String
            if entry == "~" {
                expanded = homePath
            } else if entry.hasPrefix("~/") {
                expanded = homePath + "/" + entry.dropFirst(2)
            } else if entry.hasPrefix("/") {
                expanded = entry
            } else {
                return nil
            }
            let path = URL(fileURLWithPath: expanded).standardizedFileURL.path
            return path == "/" ? "/" : String(path.trimmingSuffix("/"))
        }
    }

    public var isEmpty: Bool { paths.isEmpty }

    /// True when `cwd` is an ignored folder or lies under one (whole path components only:
    /// `~/scratch` covers `~/scratch/a`, not `~/scratchpad`).
    public func contains(_ cwd: URL?) -> Bool {
        guard let cwd, !paths.isEmpty else { return false }
        let path = cwd.standardizedFileURL.path
        return paths.contains { ignored in
            ignored == "/" || path == ignored || path.hasPrefix(ignored + "/")
        }
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: Character) -> Substring {
        var result = Substring(self)
        while result.count > 1, result.last == suffix { result = result.dropLast() }
        return result
    }
}

/// The keys of ignored sessions, so their later events (which may carry no `cwd`) are dropped too. Bounded:
/// past `capacity` the oldest key is forgotten.
struct IgnoredKeys: Sendable {
    static let capacity = 256

    private(set) var order: [SessionKey] = []
    private var members: Set<SessionKey> = []

    func contains(_ key: SessionKey) -> Bool { members.contains(key) }

    var count: Int { members.count }

    mutating func insert(_ key: SessionKey) {
        guard members.insert(key).inserted else { return }
        order.append(key)
        if order.count > Self.capacity {
            members.remove(order.removeFirst())
        }
    }

    mutating func remove(_ key: SessionKey) {
        guard members.remove(key) != nil else { return }
        order.removeAll { $0 == key }
    }
}
