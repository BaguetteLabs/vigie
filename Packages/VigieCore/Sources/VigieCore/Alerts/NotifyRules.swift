import Foundation
import ModuleKit
import Synchronization

// The Notifier rules model (SPEC §6, §11 `[notify]`, AD-13). Pure values: ConfigStore parses the TOML tables
// into these and hands them to `AlertCenter` through a `NotifyRulesProvider`.

/// Where a delivered alert goes (SPEC §6: combinable outputs).
public enum AlertOutput: String, CaseIterable, Hashable, Sendable, Codable {
    /// The notch peek (Notch Host, Story 3.2).
    case peek
    /// A macOS notification (Story 3.6).
    case system
    /// A sound from the `[sounds]` table (Story 10.1).
    case sound
}

/// A daily quiet window, `"HH:MM-HH:MM"` in local time (A53). The end is exclusive; a window whose start is
/// after its end crosses midnight (`"22:00-08:00"`).
public struct QuietHours: Hashable, Sendable, CustomStringConvertible {
    /// Minutes after local midnight, `0..<1440`.
    public let startMinute: Int
    public let endMinute: Int

    public init?(startMinute: Int, endMinute: Int) {
        let day = 0..<(24 * 60)
        guard day.contains(startMinute), day.contains(endMinute), startMinute != endMinute else { return nil }
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    /// Parses `"22:00-08:00"`. Returns nil for an empty string (no quiet hours), a malformed value, or an empty
    /// window (start equals end).
    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let start = Self.minute(parts[0]), let end = Self.minute(parts[1]) else { return nil }
        self.init(startMinute: start, endMinute: end)
    }

    private static func minute(_ text: Substring) -> Int? {
        let fields = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 2, (1...2).contains(fields[0].count), fields[1].count == 2,
            fields.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
            let hour = Int(fields[0]), let minute = Int(fields[1]), (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    /// Whether `date` falls inside the window, read on `calendar` in `timeZone` (default: the calendar's own).
    public func contains(_ date: Date, calendar: Calendar = .autoupdatingCurrent, timeZone: TimeZone? = nil) -> Bool {
        var calendar = calendar
        if let timeZone { calendar.timeZone = timeZone }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }

    public var description: String {
        func format(_ minute: Int) -> String {
            let hour = minute / 60
            let rest = minute % 60
            return (hour < 10 ? "0" : "") + "\(hour):" + (rest < 10 ? "0" : "") + "\(rest)"
        }
        return format(startMinute) + "-" + format(endMinute)
    }
}

/// A condition an event must meet to be delivered (A54).
public enum RuleCondition: Hashable, Sendable {
    /// `event.metrics[name] >= value`; a missing metric fails the condition.
    case minMetric(name: String, value: Double)

    /// The metric a `working_duration` condition reads (A54; Story 4.11 sends it in seconds).
    public static let workingDurationMetric = "working_duration"

    /// SPEC §6 `min_working_time = "30s"`: the session's working time, in seconds.
    public static func minWorkingTime(_ duration: Duration) -> RuleCondition {
        .minMetric(name: workingDurationMetric, value: duration.seconds)
    }

    /// The metric a `min_<name>` rule key compares against: `min_working_time` reads `working_duration` (A54),
    /// any other `min_<metric>` reads `<metric>`. Nil when `key` is not a condition key (`min_severity` is a
    /// rule field, not a condition).
    public static func metricName(forConfigKey key: String) -> String? {
        guard key.hasPrefix("min_"), key != "min_severity" else { return nil }
        if key == "min_working_time" { return workingDurationMetric }
        let name = String(key.dropFirst(4))
        return name.isEmpty ? nil : name
    }

    func isMet(by metrics: [String: Double]) -> Bool {
        switch self {
        case .minMetric(let name, let value):
            guard let actual = metrics[name] else { return false }
            return actual >= value
        }
    }
}

extension Duration {
    /// The duration in (fractional) seconds.
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

/// One layer of rule fields. `nil` means "not set at this layer": the resolved rule takes the field from the
/// layer below (global `[notify]`, then `[modules."<id>".notify."<kind>"]`, specific wins field by field).
public struct NotifyRule: Hashable, Sendable {
    public var muted: Bool?
    public var minSeverity: AlertSeverity?
    public var quietHours: QuietHours?
    /// Per `dedupe_key`; zero means none.
    public var cooldown: Duration?
    /// Replays peek and sound once if the alert is still unresolved after this delay (SPEC §6).
    public var reminder: Duration?
    /// nil: `NotifyRule.defaultOutputs`. Empty: the kind is silenced (SPEC §6 `outputs = []`).
    public var outputs: Set<AlertOutput>?
    /// nil: inherit; a set list (even empty) replaces the lower layer's conditions.
    public var conditions: [RuleCondition]?

    public init(
        muted: Bool? = nil,
        minSeverity: AlertSeverity? = nil,
        quietHours: QuietHours? = nil,
        cooldown: Duration? = nil,
        reminder: Duration? = nil,
        outputs: Set<AlertOutput>? = nil,
        conditions: [RuleCondition]? = nil
    ) {
        self.muted = muted
        self.minSeverity = minSeverity
        self.quietHours = quietHours
        self.cooldown = cooldown
        self.reminder = reminder
        self.outputs = outputs
        self.conditions = conditions
    }

    /// Outputs when no layer sets `outputs`. SPEC §6 gives no default; we use peek and sound for every severity:
    /// sound is still gated per kind by `[sounds]` (§11, Story 10.1: `done` and the `time.*` keys default to
    /// off), and `system` is opt-in only so the notifications permission is never requested unless a rule asks
    /// for it (Story 3.6, A70).
    public static func defaultOutputs(for severity: AlertSeverity) -> Set<AlertOutput> { [.peek, .sound] }

    /// `self` over `base`: each field set here wins, unset fields come from `base`.
    public func overriding(_ base: NotifyRule) -> NotifyRule {
        NotifyRule(
            muted: muted ?? base.muted,
            minSeverity: minSeverity ?? base.minSeverity,
            quietHours: quietHours ?? base.quietHours,
            cooldown: cooldown ?? base.cooldown,
            reminder: reminder ?? base.reminder,
            outputs: outputs ?? base.outputs,
            conditions: conditions ?? base.conditions
        )
    }

    public var isMuted: Bool { muted ?? false }
    public var effectiveConditions: [RuleCondition] { conditions ?? [] }
    public func effectiveOutputs(for severity: AlertSeverity) -> Set<AlertOutput> {
        outputs ?? Self.defaultOutputs(for: severity)
    }
}

/// `[notify] after_focus` (A21; behavior in Story 3.5).
public enum AfterFocus: String, Hashable, Sendable, Codable {
    case drop
    case replay
}

/// The global `[notify]` table (SPEC §11): `quiet_hours`, `min_severity`, `cooldown` (rule defaults for every
/// kind) and `after_focus`.
public struct GlobalNotifyRules: Hashable, Sendable {
    /// The bottom rule layer, from `quiet_hours`, `min_severity` and `cooldown`.
    public var defaults: NotifyRule
    public var afterFocus: AfterFocus

    /// SPEC §11 defaults: no quiet hours, `min_severity = "info"`, `cooldown = "0s"`, `after_focus = "drop"`.
    public init(
        defaults: NotifyRule = NotifyRule(minSeverity: .info, cooldown: .zero),
        afterFocus: AfterFocus = .drop
    ) {
        self.defaults = defaults
        self.afterFocus = afterFocus
    }
}

/// Where `AlertCenter` gets its rules. ConfigStore implements it (PM wiring); `StaticNotifyRules` until then.
public protocol NotifyRulesProvider: Sendable {
    var global: GlobalNotifyRules { get }
    /// The resolved rule for `kind` posted by `module`: global `[notify]` overridden by
    /// `[modules."<id>".notify."<kind>"]`.
    func rule(module: ModuleID, kind: String) -> NotifyRule
    /// Yields after any rule changes. Consumed by one `AlertCenter`.
    var changes: AsyncStream<Void> { get }
}

/// Rules held in memory: for tests and for the App until ConfigStore provides them.
public final class StaticNotifyRules: NotifyRulesProvider {
    private struct State {
        var global: GlobalNotifyRules
        var kinds: [ModuleID: [String: NotifyRule]]
    }

    private let state: Mutex<State>
    public let changes: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    public init(global: GlobalNotifyRules = GlobalNotifyRules(), kinds: [ModuleID: [String: NotifyRule]] = [:]) {
        state = Mutex(State(global: global, kinds: kinds))
        (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    deinit { continuation.finish() }

    public var global: GlobalNotifyRules { state.withLock { $0.global } }

    public func rule(module: ModuleID, kind: String) -> NotifyRule {
        state.withLock { state in
            let specific = state.kinds[module]?[kind] ?? NotifyRule()
            return specific.overriding(state.global.defaults)
        }
    }

    /// Replaces the rules and signals `changes`.
    public func update(global: GlobalNotifyRules? = nil, kinds: [ModuleID: [String: NotifyRule]]? = nil) {
        state.withLock { state in
            if let global { state.global = global }
            if let kinds { state.kinds = kinds }
        }
        continuation.yield()
    }
}
