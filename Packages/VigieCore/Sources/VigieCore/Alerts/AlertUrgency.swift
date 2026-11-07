import ModuleKit

/// The Notifier's single urgency table (AD-13, EXPERIENCE "Peek concurrency", Story 3.9). The peek queue reads
/// it; module code never ranks its own alerts. A lower rank is more urgent.
///
/// | Rank | Kinds |
/// | --- | --- |
/// | 1 | `session.blocked`, `session.failed` |
/// | 2 | `time.break_reminder` (break due), `time.timer_end`, `calendar.reminder` |
/// | 3 | `usage.quota_warning` |
/// | 4 | `session.done` |
/// | 5 | `setup.problem` |
/// | 6–8 | any other kind, by severity: critical, warn, info |
public enum AlertUrgency {
    /// The rank of the known kinds.
    public static let ranks: [String: Int] = [
        "session.blocked": 1,
        "session.failed": 1,
        "time.break_reminder": 2,
        "time.timer_end": 2,
        "calendar.reminder": 2,
        "usage.quota_warning": 3,
        "session.done": 4,
        "setup.problem": 5,
    ]

    /// The rank whose alerts replace a visible peek of any lower urgency (blocked, failed).
    public static let preemptingRank = 1

    /// The rank of `kind`; a kind not in ``ranks`` ranks after them by `severity`.
    public static func rank(forKind kind: String, severity: AlertSeverity = .info) -> Int {
        if let rank = ranks[kind] { return rank }
        let last = ranks.values.max() ?? 0
        switch severity {
        case .critical: return last + 1
        case .warn: return last + 2
        case .info: return last + 3
        }
    }

    public static func rank(_ alert: ActiveAlert) -> Int {
        rank(forKind: alert.kind, severity: alert.severity)
    }

    /// True when `incoming` replaces `visible` on screen at once instead of queueing behind it.
    public static func preempts(_ incoming: ActiveAlert, over visible: ActiveAlert) -> Bool {
        let rank = rank(incoming)
        return rank == preemptingRank && self.rank(visible) > rank
    }
}
