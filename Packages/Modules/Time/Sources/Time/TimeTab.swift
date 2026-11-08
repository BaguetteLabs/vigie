import Foundation
import ModuleKit
import SwiftUI
import VigieUI

/// The Time tab (Story 20.2): the snapshot the view reads and the handlers of its actions.
extension TimeModule {
    public func expandedView() -> AnyView? {
        AnyView(
            TimeTabView(
                snapshot: { [weak self] in self?.tabSnapshot() ?? Self.placeholderSnapshot },
                actions: tabActions))
    }

    var tabActions: TimeTabActions {
        TimeTabActions(
            startPreset: { [weak self] minutes in self?.startTimer(minutes: minutes) },
            startCustom: { [weak self] text in self?.startCustom(text) != nil },
            startCountdown: { [weak self] date, label in self?.startCountdown(to: date, label: label) != nil },
            select: { [weak self] id in self?.selectedID = id },
            perform: { [weak self] id, control in self?.perform(id, control) },
            undo: { [weak self] in self?.undo() },
            visibility: { [weak self] visible in self?.tabVisibility(visible) },
            quickStartFocused: { [weak self] in self?.focusQuickStart = false })
    }

    func perform(_ id: UUID, _ control: TimeRowModel.Control) {
        switch control {
        case .pause, .resume: togglePause(id)
        case .reset: reset(id)
        case .remove: remove(id)
        case .dismiss: dismiss(id)
        case .startBreak: startBreak()
        case .snooze: snoozeBreak()
        case .skip: skipBreak()
        }
    }

    nonisolated static var placeholderSnapshot: TimeTabSnapshot {
        TimeTabSnapshot(
            quickStart: TimeQuickStart(presets: defaultPresets, pomodoroLengths: pomodoroLengths), rows: [],
            runningCount: 0)
    }

    /// What the tab shows at `date` (default: the module's display time, refreshed every second while shown).
    public func tabSnapshot(now date: Date? = nil) -> TimeTabSnapshot {
        let date = date ?? displayNow
        let items = board.sorted(now: date)
        return TimeTabSnapshot(
            quickStart: TimeQuickStart(presets: presets, pomodoroLengths: Self.pomodoroLengths),
            rows: breakRows(now: date) + items.map { TimeFormat.row($0, now: date, calendar: calendar) },
            runningCount: items.filter { !$0.isEnded }.count,
            selectedID: selectedID,
            canUndo: undoSlot != nil,
            focusQuickStart: focusQuickStart,
            countdownDefault: Self.nextHour(after: date, calendar: calendar))
    }

    /// The next full hour, the Countdown form's starting value.
    nonisolated static func nextHour(after date: Date, calendar: Calendar) -> Date {
        let hour = calendar.dateInterval(of: .hour, for: date)?.end ?? date.addingTimeInterval(3600)
        return hour
    }
}
