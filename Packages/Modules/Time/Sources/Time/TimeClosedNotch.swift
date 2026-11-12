import Foundation
import ModuleKit
import SwiftUI
import VigieUI

/// The closed-notch Time item (SPEC §7.7, Story 20.6): one left-wing lane item with `[modules.time] priority`
/// (default 3), never the right wing; the host sorts it by state then priority and counts it in the left `+X`
/// when it does not fit.
///
/// - A due break: `BREAK DUE` in `alert`, whatever `closed_notch` says (Story 20.4); ring-only (with the center
///   triangle) in the `ring` variant.
/// - Else, with `closed_notch = "time" | "ring" | "both"` and something running: the readout in `active`, for the
///   running item nearest its end (paused items only when nothing runs).
///
/// What the lane reads here (`closedVariant`, `wingPriority`, the board, the Pomodoro, the break tracker)
/// changes only on actions, never every second: the readout's view reads the time itself (``closedReadout(now:)``)
/// and tells the module when it shows, so the 1 s tick runs only while it is on screen.
extension TimeModule {
    nonisolated static let closedNotchKey = "closed_notch"
    nonisolated static let priorityKey = "priority"
    /// The lane ids of the Time item.
    nonisolated static let breakDueItemID = "break-due"
    nonisolated static let readoutItemID = "readout"

    nonisolated static func closedNotchDescriptors(
        bundle: LocalizedStringResource.BundleDescription
    ) -> [SettingDescriptor] {
        func text(_ key: String) -> LocalizedStringResource {
            LocalizedStringResource(String.LocalizationValue(key), bundle: bundle)
        }
        return [
            SettingDescriptor(
                key: closedNotchKey, label: text("time.setting.closedNotch"),
                kind: .enumeration(
                    options: TimeClosedVariant.allCases.map(\.rawValue), default: TimeClosedVariant.off.rawValue),
                scope: .synced, help: text("time.setting.closedNotch.help")),
            SettingDescriptor(
                key: priorityKey, label: text("time.setting.priority"),
                kind: .int(default: defaultWingPriority, min: 1, max: 99), scope: .synced,
                help: text("time.setting.priority.help")),
        ]
    }

    // MARK: Settings

    func startClosedNotchSettings(_ settings: any ModuleSettings) {
        applyClosedNotchSettings(settings)
        for key in [Self.closedNotchKey, Self.priorityKey] {
            let changes = settings.observe(key)
            tasks.append(
                Task { @MainActor [weak self] in
                    for await _ in changes {
                        guard let self, !Task.isCancelled, let settings = self.context?.settings else { return }
                        self.applyClosedNotchSettings(settings)
                    }
                })
        }
    }

    func applyClosedNotchSettings(_ settings: any ModuleSettings) {
        let variant =
            settings.value(Self.closedNotchKey, as: String.self).flatMap(TimeClosedVariant.init(rawValue:)) ?? .off
        let priority = settings.value(Self.priorityKey, as: Int.self) ?? Self.defaultWingPriority
        if variant != closedVariant { closedVariant = variant }
        if priority != wingPriority { wingPriority = priority }
        updateTick()
    }

    // MARK: Lane

    /// Something the readout can show: a Timer or Countdown not ended, a Pomodoro not waiting for its break, or a
    /// break reminder's running break.
    var hasClosedCandidate: Bool {
        board.hasRunning || (pomodoro.map { !$0.isDue } ?? false) || breaks?.breakEndsAt != nil
    }

    /// The readout is offered: a variant is on, nothing is due and something runs.
    var offersClosedReadout: Bool {
        closedVariant != .off && dueBreakLength == nil && hasClosedCandidate
    }

    public func leftWingItems() -> [LeftWingItem] {
        let priority = wingPriority
        let variant = closedVariant
        if let length = dueBreakLength {
            let value = TimeFormat.value(length)
            let label = TimeFormat.breakDueAccessibility(length: length)
            return [
                LeftWingItem(id: Self.breakDueItemID, priority: priority, state: .alert) { size in
                    AnyView(
                        TimeBreakDueReadout(
                            value: value, ringOnly: size == .icon || variant == .ring, accessibilityLabel: label))
                }
            ]
        }
        guard offersClosedReadout else { return [] }
        return [
            LeftWingItem(id: Self.readoutItemID, priority: priority, state: .active) { [weak self] _ in
                guard let self else { return nil }
                return AnyView(
                    TimeClosedReadout(
                        snapshot: { [weak self] in self?.closedReadout() },
                        visibility: { [weak self] visible in self?.closedVisibility(visible) }))
            }
        ]
    }

    /// A closed readout appeared or went away (one per display): the 1 s tick runs only while one shows.
    func closedVisibility(_ visible: Bool) {
        visibleReadouts = max(0, visibleReadouts + (visible ? 1 : -1))
        updateTick()
    }

    // MARK: Readout

    /// What the readout shows at `date` (default: the module's display time, refreshed every second while it
    /// shows): the running item nearest its end; a paused one only when nothing runs. Nil when it is not offered.
    public func closedReadout(now date: Date? = nil) -> TimeClosedReadoutModel? {
        guard offersClosedReadout else { return nil }
        let date = date ?? displayNow
        let variant = closedVariant
        var candidates: [(running: Bool, end: Date, model: () -> TimeClosedReadoutModel)] = []
        for item in board.items where !item.isEnded {
            candidates.append(
                (
                    item.state == .running, item.effectiveEnd(now: date),
                    { [calendar] in TimeFormat.closedReadout(item, variant: variant, now: date, calendar: calendar) }
                ))
        }
        if let pomodoro, let end = pomodoro.effectiveEnd(at: date) {
            candidates.append(
                (
                    !pomodoro.isPaused, end,
                    { [calendar] in
                        TimeFormat.closedReadout(pomodoro, variant: variant, now: date, calendar: calendar)
                    }
                ))
        }
        if let end = breaks?.breakEndsAt {
            let length = breakSettings.length
            candidates.append(
                (
                    true, end,
                    { [calendar] in
                        TimeFormat.closedBreakReadout(
                            length: length, endsAt: end, variant: variant, now: date, calendar: calendar)
                    }
                ))
        }
        let nearest = candidates.min { lhs, rhs in
            lhs.running != rhs.running ? lhs.running : lhs.end < rhs.end
        }
        return nearest?.model()
    }
}

// MARK: - Texts

extension TimeFormat {
    /// A Timer or Countdown: its name (uppercase, user text) under its remaining time.
    static func closedReadout(
        _ item: TimeItem, variant: TimeClosedVariant, now: Date, calendar: Calendar
    ) -> TimeClosedReadoutModel {
        TimeClosedReadoutModel(
            variant: variant, value: value(item.remaining(now: now)),
            label: item.label.uppercased(with: TimeText.catalogLocale), labelIsUserText: true,
            sensitiveText: item.label, fractionLeft: item.fractionLeft(now: now), dashed: false,
            frozen: item.state == .paused,
            accessibilityLabel: accessibilityLabel(item, now: now, calendar: calendar))
    }

    /// A Pomodoro: `WORK · 2/4`, `BREAK · 2/4`, `LONG BREAK`, `AWAY · PAUSED`; dashed during a break.
    static func closedReadout(
        _ pomodoro: Pomodoro, variant: TimeClosedVariant, now: Date, calendar: Calendar
    ) -> TimeClosedReadoutModel {
        let row = pomodoroRow(pomodoro, now: now, calendar: calendar)
        return TimeClosedReadoutModel(
            variant: variant, value: row.value, label: pomodoroClosedLabel(pomodoro),
            fractionLeft: pomodoro.fractionLeft(at: now), dashed: !pomodoro.isWork, frozen: pomodoro.isPaused,
            accessibilityLabel: row.accessibilityLabel)
    }

    /// A break reminder's running break: `BREAK`, dashed.
    static func closedBreakReadout(
        length: TimeInterval, endsAt: Date, variant: TimeClosedVariant, now: Date, calendar: Calendar
    ) -> TimeClosedReadoutModel {
        let row = breakRunningRow(
            id: TimeModule.breakRowID, length: length, endsAt: endsAt, now: now, calendar: calendar)
        let fraction: Double =
            if case .breakRing(let fraction, _) = row.visual { fraction } else { 0 }
        return TimeClosedReadoutModel(
            variant: variant, value: row.value, label: TimeText.string("time.closed.break"), fractionLeft: fraction,
            dashed: true, accessibilityLabel: row.accessibilityLabel)
    }

    /// The closed readout's Pomodoro label: the tab's kind, with the shorter `WORK · 2/4` for work.
    static func pomodoroClosedLabel(_ pomodoro: Pomodoro) -> String {
        guard pomodoro.isWork, !pomodoro.isAwayPaused else { return pomodoroKind(pomodoro) }
        return TimeText.format("time.closed.pomodoro.work", pomodoro.cycle, pomodoro.lengths.longEvery)
    }
}
