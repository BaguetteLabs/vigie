import Foundation
import ModuleKit
import Synchronization
import os

/// The `NotifyRulesProvider` backed by `ConfigStore` (SPEC §6, §11, AD-13).
///
/// - Global rules come from the typed `[notify]` keys (`quiet_hours`, `min_severity`, `cooldown`, `after_focus`).
/// - Per-kind rules come from `[modules."<id>".notify."<kind>"]` in `config.toml` (synced, like every module
///   setting), read raw through `ConfigStore.rawTable` since the schema ignores these tables on purpose: `mute`,
///   `min_severity`, `quiet_hours`, `cooldown`, `reminder`, `outputs` and any `min_<metric>` condition
///   (`min_working_time` reads `working_duration`).
///
/// `start()` re-reads after each `ConfigStore.changes` element (which also reports raw edits of unknown
/// tables); `changes` yields when the resolved rules differ from the previous ones.
public final class ConfigNotifyRules: NotifyRulesProvider {
    struct Snapshot: Equatable, Sendable {
        var global = GlobalNotifyRules()
        var kinds: [ModuleID: [String: NotifyRule]] = [:]
    }

    private let store: ConfigStore
    private let logger: Logger
    private let state = Mutex(Snapshot())
    private let task = Mutex<Task<Void, Never>?>(nil)
    public let changes: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    public init(
        store: ConfigStore,
        logger: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "notifier")
    ) {
        self.store = store
        self.logger = logger
        (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    deinit {
        task.withLock { $0?.cancel() }
        continuation.finish()
    }

    // MARK: NotifyRulesProvider

    public var global: GlobalNotifyRules { state.withLock { $0.global } }

    public func rule(module: ModuleID, kind: String) -> NotifyRule {
        state.withLock { state in
            let specific = state.kinds[module]?[kind] ?? NotifyRule()
            return specific.overriding(state.global.defaults)
        }
    }

    // MARK: Lifecycle

    /// Reads the rules now, then follows `ConfigStore.changes` until `stop()`.
    @MainActor
    public func start() {
        let storeChanges = store.changes  // subscribe before the first read so no change is missed
        refresh()
        let follow = Task { @MainActor [weak self] in
            for await _ in storeChanges {
                self?.refresh()
            }
        }
        task.withLock {
            $0?.cancel()
            $0 = follow
        }
    }

    @MainActor
    public func stop() {
        task.withLock {
            $0?.cancel()
            $0 = nil
        }
    }

    /// Re-reads the global keys and the per-kind tables; yields on `changes` when the result differs.
    @MainActor
    public func refresh() {
        let modules = store.rawTable(at: ConfigKeyPath(["modules"]), in: .synced) ?? [:]
        let next = Snapshot(global: readGlobal(), kinds: Self.kindRules(inModules: modules, logger: logger))
        let changed = state.withLock { state in
            guard state != next else { return false }
            state = next
            return true
        }
        if changed { continuation.yield() }
    }

    // MARK: Reading

    @MainActor
    private func readGlobal() -> GlobalNotifyRules {
        let severity =
            store.value(CoreSettings.path("notify", "min_severity"), as: String.self)
            .flatMap(Self.severity(named:)) ?? .info
        let cooldown = store.value(CoreSettings.path("notify", "cooldown"), as: Duration.self) ?? .zero
        let quiet = store.value(CoreSettings.path("notify", "quiet_hours"), as: String.self).flatMap(QuietHours.init)
        let afterFocus =
            store.value(CoreSettings.path("notify", "after_focus"), as: String.self).flatMap(AfterFocus.init)
            ?? .drop
        return GlobalNotifyRules(
            defaults: NotifyRule(minSeverity: severity, quietHours: quiet, cooldown: cooldown),
            afterFocus: afterFocus)
    }

    /// Every `notify."<kind>"` table under `[modules]`.
    static func kindRules(inModules modules: [String: ConfigValue], logger: Logger) -> [ModuleID: [String: NotifyRule]]
    {
        var out: [ModuleID: [String: NotifyRule]] = [:]
        for (id, moduleValue) in modules {
            guard case .table(let module) = moduleValue, case .table(let notify) = module["notify"] else { continue }
            var kinds: [String: NotifyRule] = [:]
            for (kind, kindValue) in notify {
                guard case .table(let fields) = kindValue else {
                    logger.error("modules.\(id, privacy: .public).notify.\(kind, privacy: .public) is not a table")
                    continue
                }
                kinds[kind] = rule(from: fields) { key in
                    logger.error(
                        "modules.\(id, privacy: .public).notify.\(kind, privacy: .public).\(key, privacy: .public) has an invalid value; ignored"
                    )
                }
            }
            guard let moduleID = ModuleID(id) else { continue }
            if !kinds.isEmpty { out[moduleID] = kinds }
        }
        return out
    }

    /// One kind table. Unset or invalid fields stay nil (inherit from `[notify]`).
    static func rule(from fields: [String: ConfigValue], invalid: (String) -> Void = { _ in }) -> NotifyRule {
        var rule = NotifyRule()
        var conditions: [(key: String, condition: RuleCondition)] = []
        for (key, value) in fields {
            switch key {
            case "mute":
                if case .bool(let muted) = value { rule.muted = muted } else { invalid(key) }
            case "min_severity":
                if case .string(let name) = value, let severity = severity(named: name) {
                    rule.minSeverity = severity
                } else {
                    invalid(key)
                }
            case "quiet_hours":
                if case .string(let text) = value, let quiet = QuietHours(text) {
                    rule.quietHours = quiet
                } else {
                    invalid(key)
                }
            case "cooldown", "reminder":
                guard case .string(let text) = value, let duration = ConfigDuration.parse(text) else {
                    invalid(key)
                    continue
                }
                if key == "cooldown" { rule.cooldown = duration } else { rule.reminder = duration }
            case "outputs":
                guard case .array(let items) = value else {
                    invalid(key)
                    continue
                }
                var outputs = Set<AlertOutput>()
                for item in items {
                    if case .string(let name) = item, let output = AlertOutput(rawValue: name) {
                        outputs.insert(output)
                    } else {
                        invalid(key)
                    }
                }
                rule.outputs = outputs
            default:
                guard let metric = RuleCondition.metricName(forConfigKey: key) else {
                    invalid(key)
                    continue
                }
                if let threshold = threshold(value) {
                    conditions.append((key, .minMetric(name: metric, value: threshold)))
                } else {
                    invalid(key)
                }
            }
        }
        if !conditions.isEmpty {
            rule.conditions = conditions.sorted { $0.key < $1.key }.map(\.condition)
        }
        return rule
    }

    /// A number, or a duration string in seconds (`"5m"` is 300).
    private static func threshold(_ value: ConfigValue) -> Double? {
        switch value {
        case .int(let number): Double(number)
        case .double(let number): number
        case .string(let text): ConfigDuration.parse(text)?.seconds
        default: nil
        }
    }

    static func severity(named name: String) -> AlertSeverity? {
        switch name {
        case "info": .info
        case "warn": .warn
        case "critical": .critical
        default: nil
        }
    }
}
