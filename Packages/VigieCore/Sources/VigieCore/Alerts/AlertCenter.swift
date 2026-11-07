import Foundation
import ModuleKit
import Observation
import Synchronization
import os

/// Why an event was not delivered.
public enum DropReason: String, Hashable, Sendable, CaseIterable {
    /// The kind is not in the posting module's manifest `alertKinds`.
    case undeclaredKind
    case muted
    case belowMinSeverity
    case quietHours
    /// A rule condition (e.g. `min_working_time`, A54) was not met.
    case conditionNotMet
    /// Within the cooldown of the same module, kind and `dedupe_key`.
    case cooldown
    /// The rule routes the kind nowhere (`outputs = []`).
    case noOutputs
}

/// One entry of the in-memory alert history (the activity log, Story 3.8, persists its own).
public struct AlertHistoryEntry: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case delivered(Set<AlertOutput>)
        case dropped(DropReason)
        case reminded(Set<AlertOutput>)
        /// The reminder came due inside quiet hours and was not replayed.
        case reminderSuppressed
        /// Activated during a Focus mode (Story 3.5): peek and sound withheld, the other outputs (`system`)
        /// delivered. The alert is active like a delivered one.
        case suppressedByFocus(delivered: Set<AlertOutput>)
        /// The reminder came due during a Focus mode and was not replayed.
        case reminderSuppressedByFocus
        /// `after_focus = "replay"`: shown when the Focus mode ended.
        case replayedAfterFocus(Set<AlertOutput>)
        /// The user dismissed its peek (`⌥⌘⌫`, Story 3.3): the reminder is cancelled, the alert stays active.
        case dismissed
        /// Its visible peek was replaced by a more urgent one (Story 3.9); it peeks again only via its reminder.
        case preempted
        case resolved
    }

    public let alertID: UUID
    public let module: ModuleID
    public let kind: String
    public let severity: AlertSeverity
    public let outcome: Outcome
    public let at: Date
}

/// The single `Notifier` (AD-13): applies the rules to every module event and routes it to the outputs.
///
/// Order of checks in `post`: declared kind, mute, `min_severity`, quiet hours, rule conditions, cooldown per
/// `dedupe_key`, outputs. Every drop is logged at debug level with its reason (kind only, never title or body).
///
/// Focus modes (FR17, Story 3.5): while `focus` reports a Focus (Do Not Disturb included), an alert that passes
/// the rules is still activated (it is in `active`, its module's closed-notch state and tab update, the
/// activity log records it) but its peek and sound are withheld; reminders falling inside the Focus are
/// suppressed, not deferred. `system` notifications are delivered as usual: macOS applies the Focus to them
/// itself and the user may allow Vigie in a given Focus. There is no bypass (UX-DR55). When the Focus ends,
/// `[notify] after_focus` decides: `drop` (default, A21) shows nothing; `replay` shows, for each module, the
/// latest suppressed alert still unresolved, as a normal peek with its normal sound.
@MainActor @Observable
public final class AlertCenter {
    /// Delivered and not yet resolved, oldest first.
    public private(set) var active: [ActiveAlert] = []
    /// Newest last, capped at `historyLimit`.
    public private(set) var history: [AlertHistoryEntry] = []
    public private(set) var dropCounts: [DropReason: Int] = [:]
    /// Bumped each time the rule cache is cleared after a rules change.
    public private(set) var rulesRevision = 0

    public let historyLimit: Int

    @ObservationIgnored private let rules: any NotifyRulesProvider
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: @Sendable () -> Calendar
    @ObservationIgnored private let sinks: AlertSinks
    @ObservationIgnored private let focus: any FocusModeMonitor
    @ObservationIgnored private let activity: (any ActivityLog)?
    @ObservationIgnored private let log: Logger

    private struct RuleKey: Hashable {
        let module: ModuleID
        let kind: String
    }

    private struct CooldownKey: Hashable {
        let module: ModuleID
        let kind: String
        /// Empty when the event has no `dedupe_key`: the cooldown then covers the whole kind.
        let dedupeKey: String
    }

    @ObservationIgnored private var declaredKinds: [ModuleID: Set<String>] = [:]
    @ObservationIgnored private var ruleCache: [RuleKey: NotifyRule] = [:]
    @ObservationIgnored private var lastDelivered: [CooldownKey: Date] = [:]
    @ObservationIgnored private var peekTokens: [UUID: PeekToken] = [:]
    @ObservationIgnored private var reminders: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let lifetime = TaskLifetime()
    @ObservationIgnored private let focusLifetime = TaskLifetime()
    /// Alerts whose peek and sound a Focus withheld, in activation order; cleared when the Focus ends.
    @ObservationIgnored private var focusSuppressed: [UUID] = []

    /// The Focus state as this center last saw it (from `focus.changes`).
    public private(set) var isFocusActive: Bool

    /// - Parameters:
    ///   - rules: global `[notify]` and per-kind rules; `changes` clears the resolved-rule cache.
    ///   - clock: drives reminders.
    ///   - now: wall time for quiet hours, cooldowns and timestamps.
    ///   - calendar: the calendar and time zone quiet hours are read in.
    ///   - focus: macOS Focus / Do Not Disturb state (`SystemFocusModeMonitor` in the App).
    ///   - activity: where every history entry is also recorded (the activity log, Story 3.8); nil for none.
    public init(
        rules: any NotifyRulesProvider,
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent },
        sinks: AlertSinks = AlertSinks(),
        focus: any FocusModeMonitor = ManualFocusModeMonitor(),
        activity: (any ActivityLog)? = nil,
        historyLimit: Int = 200,
        log: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "notifier")
    ) {
        self.rules = rules
        self.clock = clock
        self.now = now
        self.calendar = calendar
        self.sinks = sinks
        self.focus = focus
        self.activity = activity
        self.isFocusActive = focus.isActive
        self.historyLimit = historyLimit
        self.log = log
        sinks.peek.events = self
        let focusChanges = focus.changes
        focusLifetime.set(
            Task { @MainActor [weak self] in
                for await active in focusChanges {
                    self?.focusChanged(active)
                }
            })
        let changes = rules.changes
        lifetime.set(
            Task { @MainActor [weak self] in
                for await _ in changes {
                    self?.invalidateRules()
                }
            })
    }

    deinit {
        lifetime.cancel()
        focusLifetime.cancel()
    }

    // MARK: Notifier

    /// The `context.notifier` for a module: posts carry its id and are checked against its `alertKinds`.
    public func makeNotifier(for manifest: ModuleManifest) -> any Notifier {
        declaredKinds[manifest.id] = Set(manifest.alertKinds)
        return ModuleNotifier(module: manifest.id, center: self)
    }

    /// Applies the rules to `event` from `module` and delivers it. A dropped event gets an inert handle.
    @discardableResult
    public func post(module: ModuleID, event: NotifierEvent) -> AlertHandle {
        post(module: module, event: event, id: UUID())
    }

    @discardableResult
    func post(module: ModuleID, event: NotifierEvent, id: UUID) -> AlertHandle {
        let timestamp = now()
        guard declaredKinds[module]?.contains(event.kind) == true else {
            log.error(
                "Dropped alert: kind \(event.kind, privacy: .public) is not declared by \(module.rawValue, privacy: .public)"
            )
            return drop(module: module, event: event, id: id, reason: .undeclaredKind, at: timestamp)
        }
        let rule = resolvedRule(module: module, kind: event.kind)
        if rule.isMuted {
            return drop(module: module, event: event, id: id, reason: .muted, at: timestamp)
        }
        if let minimum = rule.minSeverity, event.severity < minimum {
            return drop(module: module, event: event, id: id, reason: .belowMinSeverity, at: timestamp)
        }
        // SPEC §5.2: under Do Not Disturb alerts are suppressed and, by default, not replayed afterwards (A21).
        // Quiet hours (A53) are a scheduled DND, so an alert inside them is dropped, not deferred.
        if let quiet = rule.quietHours, quiet.contains(timestamp, calendar: calendar()) {
            return drop(module: module, event: event, id: id, reason: .quietHours, at: timestamp)
        }
        if !rule.effectiveConditions.allSatisfy({ $0.isMet(by: event.metrics) }) {
            return drop(module: module, event: event, id: id, reason: .conditionNotMet, at: timestamp)
        }
        let cooldownKey = CooldownKey(module: module, kind: event.kind, dedupeKey: event.dedupeKey ?? "")
        if let cooldown = rule.cooldown, cooldown > .zero, let last = lastDelivered[cooldownKey],
            timestamp.timeIntervalSince(last) < cooldown.seconds
        {
            return drop(module: module, event: event, id: id, reason: .cooldown, at: timestamp)
        }
        let outputs = rule.effectiveOutputs(for: event.severity)
        if outputs.isEmpty {
            return drop(module: module, event: event, id: id, reason: .noOutputs, at: timestamp)
        }

        lastDelivered[cooldownKey] = timestamp
        let alert = ActiveAlert(id: id, module: module, event: event, outputs: outputs, postedAt: timestamp)
        active.append(alert)
        if isFocusActive, !outputs.isDisjoint(with: Self.focusWithheld) {
            let remaining = outputs.subtracting(Self.focusWithheld)
            focusSuppressed.append(id)
            deliver(alert, to: remaining)
            log.debug("Alert \(event.kind, privacy: .public): peek and sound withheld by Focus")
            record(alert, .suppressedByFocus(delivered: remaining), at: timestamp)
        } else {
            deliver(alert, to: outputs)
            record(alert, .delivered(outputs), at: timestamp)
        }
        if let reminder = rule.reminder, reminder > .zero {
            scheduleReminder(for: id, after: reminder)
        }
        return Self.handle(id: id, center: self)
    }

    // MARK: Lifecycle

    /// Ends the alert: cancels its reminder and retracts its peek. Unknown or already resolved ids are ignored.
    public func resolve(_ id: UUID) {
        guard let index = active.firstIndex(where: { $0.id == id }) else { return }
        let alert = active.remove(at: index)
        focusSuppressed.removeAll { $0 == id }
        reminders.removeValue(forKey: id)?.cancel()
        if let token = peekTokens.removeValue(forKey: id) {
            sinks.peek.retract(token)
        }
        record(alert, .resolved, at: now())
    }

    /// The user dismissed the alert's peek (Story 3.3): cancels its pending reminder and records `.dismissed`.
    /// The alert stays active (the module's state is untouched) until the module resolves it.
    public func dismiss(_ id: UUID) {
        guard let alert = active.first(where: { $0.id == id }) else { return }
        reminders.removeValue(forKey: id)?.cancel()
        if let token = peekTokens.removeValue(forKey: id) {
            sinks.peek.retract(token)
        }
        record(alert, .dismissed, at: now())
    }

    // MARK: Actions

    /// Carries out `action` for `alert` (AD-13). `.module` always goes back to the module that posted the alert,
    /// with `intent` when a user gesture took the action.
    public func perform(_ action: AlertAction, for alert: ActiveAlert, intent: UserIntent? = nil) {
        switch action {
        case .module(let id, let actionID, let payload):
            if id != alert.module {
                log.error(
                    "Alert action names \(id.rawValue, privacy: .public); routed to poster \(alert.module.rawValue, privacy: .public)"
                )
            }
            sinks.actionRouter.routeToModule(alert.module, actionID: actionID, payload: payload, intent: intent)
        case .openSettings(let pane):
            sinks.actionRouter.openSettings(pane: pane)
        case .openURL(let url):
            sinks.actionRouter.openURL(url)
        }
    }

    /// Performs the alert's own action (a click on the peek or notification); does nothing without one.
    public func activate(_ alert: ActiveAlert, intent: UserIntent? = nil) {
        guard let action = alert.event.action else { return }
        perform(action, for: alert, intent: intent)
    }

    // MARK: Internals

    private func resolvedRule(module: ModuleID, kind: String) -> NotifyRule {
        let key = RuleKey(module: module, kind: kind)
        if let cached = ruleCache[key] { return cached }
        let rule = rules.rule(module: module, kind: kind)
        ruleCache[key] = rule
        return rule
    }

    private func invalidateRules() {
        ruleCache.removeAll()
        rulesRevision += 1
    }

    private func drop(
        module: ModuleID, event: NotifierEvent, id: UUID, reason: DropReason, at timestamp: Date
    ) -> AlertHandle {
        dropCounts[reason, default: 0] += 1
        log.debug(
            "Dropped alert \(event.kind, privacy: .public) from \(module.rawValue, privacy: .public): \(reason.rawValue, privacy: .public)"
        )
        appendHistory(
            AlertHistoryEntry(
                alertID: id, module: module, kind: event.kind, severity: event.severity, outcome: .dropped(reason),
                at: timestamp),
            dedupeKey: event.dedupeKey)
        return AlertHandle(id: id) {}
    }

    private func deliver(_ alert: ActiveAlert, to outputs: Set<AlertOutput>) {
        if outputs.contains(.peek) {
            if let previous = peekTokens[alert.id] { sinks.peek.retract(previous) }
            peekTokens[alert.id] = sinks.peek.show(alert)
        }
        if outputs.contains(.system) { sinks.system.deliver(alert) }
        if outputs.contains(.sound) { sinks.sound.play(for: alert) }
    }

    private func scheduleReminder(for id: UUID, after delay: Duration) {
        let clock = clock
        reminders[id] = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            self?.fireReminder(id)
        }
    }

    /// SPEC §6: the reminder replays the peek and the sound once if the alert is still unresolved.
    private func fireReminder(_ id: UUID) {
        reminders[id] = nil
        guard let index = active.firstIndex(where: { $0.id == id }) else { return }
        let timestamp = now()
        var alert = active[index]
        let rule = resolvedRule(module: alert.module, kind: alert.kind)
        if let quiet = rule.quietHours, quiet.contains(timestamp, calendar: calendar()) {
            log.debug("Reminder for \(alert.kind, privacy: .public) suppressed by quiet hours")
            record(alert, .reminderSuppressed, at: timestamp)
            return
        }
        if isFocusActive {
            log.debug("Reminder for \(alert.kind, privacy: .public) suppressed by Focus")
            record(alert, .reminderSuppressedByFocus, at: timestamp)
            return
        }
        alert.isReminder = true
        active[index] = alert
        let replay = alert.outputs.intersection([.peek, .sound])
        deliver(alert, to: replay)
        record(alert, .reminded(replay), at: timestamp)
    }

    // MARK: Focus

    /// The outputs a Focus withholds (FR17).
    static let focusWithheld: Set<AlertOutput> = [.peek, .sound]

    private func focusChanged(_ active: Bool) {
        guard active != isFocusActive else { return }
        isFocusActive = active
        guard !active else { return }
        let suppressed = focusSuppressed
        focusSuppressed = []
        guard rules.global.afterFocus == .replay else { return }
        replayAfterFocus(suppressed)
    }

    /// Shows the latest still-unresolved suppressed alert of each module, oldest first, through the normal
    /// outputs (one sound per peek when the rule has sound). Nothing is shown inside quiet hours.
    private func replayAfterFocus(_ suppressed: [UUID]) {
        var latest: [ModuleID: ActiveAlert] = [:]
        for id in suppressed {
            guard let alert = active.first(where: { $0.id == id }) else { continue }
            latest[alert.module] = alert
        }
        let timestamp = now()
        for alert in latest.values.sorted(by: { $0.postedAt < $1.postedAt }) {
            let rule = resolvedRule(module: alert.module, kind: alert.kind)
            if let quiet = rule.quietHours, quiet.contains(timestamp, calendar: calendar()) { continue }
            let replay = alert.outputs.intersection(Self.focusWithheld)
            deliver(alert, to: replay)
            record(alert, .replayedAfterFocus(replay), at: timestamp)
        }
    }

    // MARK: History

    private func record(_ alert: ActiveAlert, _ outcome: AlertHistoryEntry.Outcome, at timestamp: Date) {
        appendHistory(
            AlertHistoryEntry(
                alertID: alert.id, module: alert.module, kind: alert.kind, severity: alert.severity, outcome: outcome,
                at: timestamp),
            dedupeKey: alert.event.dedupeKey)
    }

    private func appendHistory(_ entry: AlertHistoryEntry, dedupeKey: String?) {
        activity?.record(
            .alert(
                module: entry.module, kind: entry.kind, severity: entry.severity, dedupeKey: dedupeKey,
                outcome: entry.outcome.activityOutcome, at: entry.at))
        history.append(entry)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    /// A handle whose `resolve()` reaches the center on the main queue, in order with posts made from other
    /// threads (both hop through `DispatchQueue.main`).
    nonisolated static func handle(id: UUID, center: AlertCenter) -> AlertHandle {
        AlertHandle(id: id) { [weak center] in
            onMain { center?.resolve(id) }
        }
    }
}

// MARK: - Peek events (Story 3.3)

extension AlertCenter: PeekSinkEvents {
    /// `⌥⌘↵` or a click on the peek's primary action: performs the alert's action with the gesture's intent.
    public func peekPrimary(_ alert: ActiveAlert, intent: UserIntent) {
        peekTokens[alert.id] = nil
        activate(alert, intent: intent)
    }

    /// `⌥⌘⌫` or Dismiss: cancels the reminder (``dismiss(_:)``).
    public func peekDismissed(_ alert: ActiveAlert) {
        peekTokens[alert.id] = nil
        dismiss(alert.id)
    }

    /// A blocked or failed peek replaced this alert's peek: recorded as `.preempted`; the alert stays active and
    /// its reminder still replays it.
    public func peekPreempted(_ alert: ActiveAlert) {
        peekTokens[alert.id] = nil
        guard let current = active.first(where: { $0.id == alert.id }) else { return }
        record(current, .preempted, at: now())
    }
}

/// Runs `body` on the main actor: now when already on the main thread, else in FIFO order on the main queue.
func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { body() }
    } else {
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }
}

/// `context.notifier`: binds posts to one module.
struct ModuleNotifier: Notifier {
    let module: ModuleID
    let center: AlertCenter

    func post(_ event: NotifierEvent) -> AlertHandle {
        let id = UUID()
        let module = module
        let center = center
        onMain { center.post(module: module, event: event, id: id) }
        return AlertCenter.handle(id: id, center: center)
    }
}

/// Holds a task that ends with its owner (cancelled from a nonisolated `deinit`).
final class TaskLifetime: Sendable {
    private let task = Mutex<Task<Void, Never>?>(nil)

    func set(_ new: Task<Void, Never>) { task.withLock { $0 = new } }
    func cancel() { task.withLock { $0?.cancel() } }
}

extension AlertHistoryEntry.Outcome {
    /// The activity log outcome (Story 3.8; suppression reasons as `ActivityOutcome` documents them).
    var activityOutcome: ActivityOutcome {
        switch self {
        case .delivered: .posted
        case .dropped(let reason): .suppressed(reason: reason.activityReason)
        case .reminded: .repeated
        case .reminderSuppressed: .suppressed(reason: "quietHours")
        case .suppressedByFocus, .reminderSuppressedByFocus: .suppressed(reason: "dnd")
        case .replayedAfterFocus: .shown
        case .dismissed: .dismissed
        case .preempted: .custom("preempted")
        case .resolved: .resolved
        }
    }
}

extension DropReason {
    var activityReason: String {
        switch self {
        case .undeclaredKind: "undeclaredKind"
        case .muted: "mute"
        case .belowMinSeverity: "minSeverity"
        case .quietHours: "quietHours"
        case .conditionNotMet: "condition"
        case .cooldown: "cooldown"
        case .noOutputs: "noOutputs"
        }
    }
}
