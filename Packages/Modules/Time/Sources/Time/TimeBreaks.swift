import Foundation
import ModuleKit
import SwiftUI
import VigieUI

/// `breaks.style` (SPEC §11, Settings › Time › break reminder strength).
public enum BreakStyle: String, Sendable, CaseIterable {
    /// The break peek with Start break / Snooze 5m / Skip, and the `break_reminder` sound when set.
    case peek
    /// No peek and no sound: only the `BREAK DUE` readout on the left wing and the Time tab row.
    case quiet
}

/// `[modules.time.breaks]` (SPEC §11): `enabled`, `work`, `length`, `away_after`, `style`.
public struct BreakSettings: Equatable, Sendable {
    nonisolated static let enabledKey = "breaks.enabled"
    nonisolated static let workKey = "breaks.work"
    nonisolated static let lengthKey = "breaks.length"
    /// Read by the Away service in VigieCore (the threshold is the host's, SPEC §7.7); declared here so the
    /// generated Settings › Time shows it.
    nonisolated static let awayAfterKey = "breaks.away_after"
    nonisolated static let styleKey = "breaks.style"
    nonisolated static let keys = [enabledKey, workKey, lengthKey, styleKey]

    public nonisolated static let defaultWork: Duration = .seconds(55 * 60)
    public nonisolated static let defaultLength: Duration = .seconds(5 * 60)
    public nonisolated static let defaultAwayAfter: Duration = .seconds(90)

    public var enabled = false
    public var work: TimeInterval = defaultWork.timeInterval
    public var length: TimeInterval = defaultLength.timeInterval
    public var style: BreakStyle = .peek

    public init() {}

    init(_ settings: any ModuleSettings) {
        enabled = settings.value(Self.enabledKey, as: Bool.self) ?? false
        work = Self.positive(settings.value(Self.workKey, as: Duration.self), or: Self.defaultWork)
        length = Self.positive(settings.value(Self.lengthKey, as: Duration.self), or: Self.defaultLength)
        style = settings.value(Self.styleKey, as: String.self).flatMap(BreakStyle.init(rawValue:)) ?? .peek
    }

    private static func positive(_ value: Duration?, or fallback: Duration) -> TimeInterval {
        guard let value, value > .zero else { return fallback.timeInterval }
        return value.timeInterval
    }

    nonisolated static func descriptors(bundle: LocalizedStringResource.BundleDescription) -> [SettingDescriptor] {
        func text(_ key: String) -> LocalizedStringResource {
            LocalizedStringResource(String.LocalizationValue(key), bundle: bundle)
        }
        return [
            SettingDescriptor(
                key: enabledKey, label: text("time.setting.breaks.enabled"), kind: .bool(default: false),
                help: text("time.setting.breaks.enabled.help")),
            SettingDescriptor(
                key: workKey, label: text("time.setting.breaks.work"), kind: .duration(default: defaultWork),
                help: text("time.setting.breaks.work.help")),
            SettingDescriptor(
                key: lengthKey, label: text("time.setting.breaks.length"), kind: .duration(default: defaultLength),
                help: text("time.setting.breaks.length.help")),
            SettingDescriptor(
                key: awayAfterKey, label: text("time.setting.breaks.awayAfter"),
                kind: .duration(default: defaultAwayAfter), help: text("time.setting.breaks.awayAfter.help")),
            SettingDescriptor(
                key: styleKey, label: text("time.setting.breaks.style"),
                kind: .enumeration(options: BreakStyle.allCases.map(\.rawValue), default: BreakStyle.peek.rawValue),
                help: text("time.setting.breaks.style.help")),
        ]
    }
}

/// Break reminders (SPEC §7.7, Story 20.4): `context.away` drives a ``BreakTracker``; at `breaks.work` of
/// Present time the module posts `time.break_reminder` (Start break / Snooze 5m / Skip) through the Notifier,
/// quiet (no peek, no sound) with `breaks.style = "quiet"`. While the break is due the module is in `alert`
/// (the Time tab's attention marker), the left wing shows `BREAK DUE` whatever `closed_notch` says, and the
/// alert stays unresolved (so `[notify] after_focus = "replay"` replays it) until Start break, Skip or an Away
/// of the break length. Only the Notifier's reminder rule repeats it; Snooze re-raises it once after 5 min.
extension TimeModule {
    /// The break alert kind (AD-13 amended 2026-11-06), shared with the Pomodoro work-phase end (20.5).
    public nonisolated static let breakReminderKind = "time.break_reminder"
    public nonisolated static let startBreakAction = "break.start"
    public nonisolated static let snoozeBreakAction = "break.snooze"
    public nonisolated static let skipBreakAction = "break.skip"
    /// The break row's id in the Time tab.
    public nonisolated static let breakRowID = UUID(uuidString: "B2EA4D0E-0000-4000-8000-000000000020")!
    /// `[modules.time] priority` default (SPEC §11): the left-wing priority of the Time item.
    nonisolated static let defaultWingPriority = 3

    // MARK: Settings

    func startBreakSettings(_ settings: any ModuleSettings) {
        breakSettings = BreakSettings(settings)
        applyBreakSettings()
        for key in BreakSettings.keys {
            let changes = settings.observe(key)
            self.tasks.append(
                Task { @MainActor [weak self] in
                    for await _ in changes {
                        guard let self, !Task.isCancelled, let settings = self.context?.settings else { return }
                        self.breakSettings = BreakSettings(settings)
                        self.applyBreakSettings()
                    }
                })
        }
    }

    /// Starts or stops tracking, or applies new lengths.
    func applyBreakSettings() {
        guard isRunning else { return }
        if breakSettings.enabled, breaks == nil {
            startBreaks()
        } else if !breakSettings.enabled, breaks != nil {
            stopBreaks()
            changed(save: false)
        } else if var tracker = breaks {
            tracker.workLength = breakSettings.work
            tracker.breakLength = breakSettings.length
            breaks = tracker
            breakTick()
        }
    }

    /// Starts a cycle (held at once while a Pomodoro runs) and subscribes to `context.away`.
    private func startBreaks() {
        guard let context else { return }
        breaks = BreakTracker(
            workLength: breakSettings.work, breakLength: breakSettings.length, presence: context.away.presence,
            at: now())
        if pomodoro != nil { _ = breaks?.pause(while: true, at: now()) }
        updatePresenceSubscription()
        rearmBreakJob()
    }

    /// Subscribes to `context.away` (which starts the host's presence polling, PRD FR-4) while break reminders
    /// are on or a Pomodoro runs; ends the subscription otherwise (the host stops polling once nobody listens).
    func updatePresenceSubscription() {
        let needed = isRunning && (breaks != nil || pomodoro != nil)
        if needed, presenceTask == nil, let context {
            isAway = context.away.presence != .present
            let changes = context.away.changes
            presenceTask = Task { @MainActor [weak self] in
                for await presence in changes {
                    guard !Task.isCancelled else { return }
                    self?.presenceChanged(presence)
                }
            }
        } else if !needed, let task = presenceTask {
            task.cancel()
            presenceTask = nil
        }
    }

    /// Ends any due break, then the subscription unless a Pomodoro still needs it.
    func stopBreaks() {
        defer { updatePresenceSubscription() }
        breakJob?.cancel()
        breakJob = nil
        breakHandle?.resolve()
        breakHandle = nil
        breaks = nil
    }

    // MARK: Inputs

    func presenceChanged(_ presence: Presence) {
        isAway = presence != .present
        pomodoroPresence(presence)
        guard var tracker = breaks else { return }
        let events = tracker.presence(presence, at: now())
        breaks = tracker
        handle(events)
    }

    /// Sleep is Away (Story 20.4); on wake the host's current presence is applied.
    func sleepWake(_ event: SleepWakeEvent) {
        switch event {
        case .willSleep:
            presenceChanged(.away(since: now()))
        case .didWake:
            if let presence = context?.away.presence { presenceChanged(presence) }
            breakTick()
            pomodoroTick()
            evaluate()
        }
    }

    /// The deadline job, the tab tick and wake.
    func breakTick() {
        guard var tracker = breaks else { return }
        let events = tracker.tick(at: now())
        breaks = tracker
        handle(events)
    }

    private func handle(_ events: [BreakTracker.Event]) {
        for event in events {
            switch event {
            case .due(let worked, let cycleStart): raiseBreak(worked: worked, cycleStart: cycleStart)
            case .reRaise: raiseBreak(worked: breaks?.accrued ?? 0, cycleStart: breaks?.cycleStart ?? now())
            case .cleared:
                breakHandle?.resolve()
                breakHandle = nil
            case .breakEnded:
                // A plain reminder's break end is silent: a new cycle (AD-13: only a Pomodoro break end alerts).
                context?.log.debug("Break ended; new work cycle")
            }
        }
        rearmBreakJob()
        changed(save: false)
    }

    private func rearmBreakJob() {
        breakJob?.cancel()
        breakJob = nil
        guard isRunning, let context, let deadline = breaks?.nextDeadline else { return }
        breakJob = context.scheduler.at(deadline) { [weak self] in
            await MainActor.run { self?.breakTick() }
        }
    }

    // MARK: Alert

    private func raiseBreak(worked: TimeInterval, cycleStart: Date) {
        guard let context else { return }
        breakHandle?.resolve()
        breakRaises += 1
        let id = manifest.id
        let event = NotifierEvent(
            kind: Self.breakReminderKind, severity: .info,
            title: TimeFormat.breakTitle(length: breakSettings.length),
            body: TimeFormat.breakBody(worked: worked, since: cycleStart, calendar: calendar),
            action: .module(id: id, actionID: Self.startBreakAction, payload: Data()),
            dedupeKey: "\(Self.breakReminderKind).\(breakRaises)",
            secondaryAction: .module(id: id, actionID: Self.skipBreakAction, payload: Data()),
            tertiaryAction: .module(id: id, actionID: Self.snoozeBreakAction, payload: Data()),
            quiet: breakSettings.style == .quiet)
        breakHandle = context.notifier.post(event)
    }

    /// Routes the break peek's actions (and a click on the macOS notification, which is Start break).
    func handleBreakAction(_ actionID: String) -> Bool {
        switch actionID {
        case Self.startBreakAction: startBreak()
        case Self.snoozeBreakAction: snoozeBreak()
        case Self.skipBreakAction: skipBreak()
        default: return false
        }
        return true
    }

    // MARK: Actions

    /// Start break (peek, notification, Time tab): resolves the alert and runs the break.
    public func startBreak() {
        guard var tracker = breaks, tracker.isDue else { return }
        tracker.startBreak(at: now())
        breaks = tracker
        breakHandle?.resolve()
        breakHandle = nil
        handle([])
    }

    /// Snooze 5m: the break stays due (and on the left wing); the alert is raised again in 5 min.
    public func snoozeBreak() {
        guard var tracker = breaks, tracker.isDue else { return }
        tracker.snooze(at: now())
        breaks = tracker
        handle([])
    }

    /// Skip: no break counted, a new work cycle; also ends a running break.
    public func skipBreak() {
        guard var tracker = breaks, tracker.isDue || tracker.breakEndsAt != nil else { return }
        tracker.skip(at: now())
        breaks = tracker
        breakHandle?.resolve()
        breakHandle = nil
        handle([])
    }

    // MARK: Surfaces

    /// `BREAK DUE` on the left wing while a break (a reminder's or a Pomodoro's) is due, whatever
    /// `[modules.time] closed_notch` says (20.6 adds the running-item readout).
    public func leftWingItems() -> [LeftWingItem] {
        let length: TimeInterval
        if let pomodoro, pomodoro.isDue {
            length = pomodoro.breakLength
        } else if breaks?.isDue == true {
            length = breakSettings.length
        } else {
            return []
        }
        let value = TimeFormat.value(length)
        let label = TimeFormat.breakDueAccessibility(length: length)
        let priority = context?.settings.value("priority", as: Int.self) ?? Self.defaultWingPriority
        return [
            LeftWingItem(id: "break-due", priority: priority, state: .alert) { size in
                AnyView(TimeBreakDueReadout(value: value, ringOnly: size == .icon, accessibilityLabel: label))
            }
        ]
    }

    /// The break row on top of the tab: due (Start break / Snooze 5m / Skip) or running (Skip).
    func breakRows(now date: Date) -> [TimeRowModel] {
        guard let tracker = breaks else { return [] }
        let length = breakSettings.length
        if tracker.isDue {
            return [TimeFormat.breakDueRow(id: Self.breakRowID, length: length)]
        }
        if let end = tracker.breakEndsAt {
            return [
                TimeFormat.breakRunningRow(
                    id: Self.breakRowID, length: length, endsAt: end, now: date, calendar: calendar)
            ]
        }
        return []
    }
}
