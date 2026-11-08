import Foundation
import ModuleKit
import SwiftUI

/// One item of the Time tab's running list (DESIGN "Time tab", Story 1.7e), every text already formatted by
/// the Time module from its catalog.
public struct TimeRowModel: Identifiable, Equatable, Sendable {
    /// What the 30px leading column draws (decoration: hidden from VoiceOver).
    public enum Visual: Equatable, Sendable {
        /// A Timer's ring: the accent arc is the share left; paused draws it in `ink-3`.
        case ring(fractionLeft: Double, paused: Bool)
        /// A Countdown: a short track with the now dot at the elapsed share.
        case track(fractionElapsed: Double)
        /// An ended item: a full ring in the accent.
        case ended
        /// A due break (Story 20.4): a full dashed ring in the accent.
        case breakDue
        /// A break running: the dashed arc is the share left.
        case breakRing(fractionLeft: Double)
    }

    /// A row chip, in display order.
    public enum Control: String, CaseIterable, Equatable, Hashable, Sendable {
        case pause
        case resume
        case reset
        case remove
        case dismiss
        /// Break due (Story 20.4): the primary chip, `↵` on the selected row.
        case startBreak
        /// Break due: re-raise in 5 minutes.
        case snooze
        /// Break due or running: no break, a new work cycle.
        case skip

        /// Drawn as the primary chip (Time accent).
        public var isPrimary: Bool { self == .startBreak }
    }

    public let id: UUID
    /// User text (AD-24).
    @Sensitive public var label: String
    /// `5 MIN TIMER`, `COUNTDOWN · FRI 14 NOV · 14:00`.
    public var kind: String
    /// Remaining time (`3:06`, `1:04:10`, `7D 23H`), tabular numerals.
    public var value: String
    /// `ENDS 14:52`, `IN 191 H`, `PAUSED`, `ENDED 14:48`.
    public var subline: String
    public var visual: Visual
    public var controls: [Control]
    public var isEnded: Bool
    /// "Tea, 5 minute timer, 3 minutes, 12 seconds left, ends 14:52, paused".
    public var accessibilityLabel: String

    public init(
        id: UUID, label: String, kind: String, value: String, subline: String, visual: Visual, controls: [Control],
        isEnded: Bool = false, accessibilityLabel: String
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.value = value
        self.subline = subline
        self.visual = visual
        self.controls = controls
        self.isEnded = isEnded
        self.accessibilityLabel = accessibilityLabel
    }

    /// `↵` on the selected row: Dismiss on an ended item, Start break on a due break.
    public var returnControl: Control? {
        if controls.contains(.startBreak) { return .startBreak }
        return isEnded ? .dismiss : nil
    }

    /// Space on the selected row: Pause or Resume, when the row has it.
    public var pauseToggle: Control? {
        controls.first { $0 == .pause || $0 == .resume }
    }
}

extension TimeRowModel: PrivacyRedactable {
    /// The label masked, in the row and its VoiceOver label; kind and remaining time stay.
    public func redacted() -> TimeRowModel {
        var copy = self
        copy.accessibilityLabel = PrivacyMask.scrub(accessibilityLabel, removing: [label])
        copy.label = $label.masked
        return copy
    }
}

/// The quick-start card's content.
public struct TimeQuickStart: Equatable, Sendable {
    /// Preset buttons, in minutes (`5 / 10 / 25`).
    public var presets: [Int]
    /// The Pomodoro lengths shown on its button (`25 · 5 · 15`).
    public var pomodoroLengths: String
    /// False draws the Pomodoro button disabled (Pomodoro is Story 20.5).
    public var pomodoroAvailable: Bool

    public init(presets: [Int], pomodoroLengths: String, pomodoroAvailable: Bool = false) {
        self.presets = presets
        self.pomodoroLengths = pomodoroLengths
        self.pomodoroAvailable = pomodoroAvailable
    }
}

/// What the Time tab shows now.
public struct TimeTabSnapshot: Sendable {
    public var quickStart: TimeQuickStart
    /// Ended items first, then running and paused by end time.
    public var rows: [TimeRowModel]
    /// Running and paused items (the `RUNNING · N` count; ended ones are not counted).
    public var runningCount: Int
    public var selectedID: UUID?
    /// True for 5 s after a Remove: the `UNDO ⌘Z` chip shows.
    public var canUndo: Bool
    /// The Time hotkey asked for the quick start to take focus (A87); the view clears it once done.
    public var focusQuickStart: Bool
    /// The default Countdown target the `+ COUNTDOWN` form opens on.
    public var countdownDefault: Date

    public init(
        quickStart: TimeQuickStart, rows: [TimeRowModel], runningCount: Int, selectedID: UUID? = nil,
        canUndo: Bool = false, focusQuickStart: Bool = false, countdownDefault: Date = Date()
    ) {
        self.quickStart = quickStart
        self.rows = rows
        self.runningCount = runningCount
        self.selectedID = selectedID
        self.canUndo = canUndo
        self.focusQuickStart = focusQuickStart
        self.countdownDefault = countdownDefault
    }

    /// The snapshot as Privacy mode shows it (AD-24).
    public func privacy(_ privacyActive: Bool) -> TimeTabSnapshot {
        guard privacyActive else { return self }
        var copy = self
        copy.rows = rows.map { $0.redacted() }
        return copy
    }

    /// The selection, if it is still a row.
    public var validSelection: UUID? {
        guard let selectedID, rows.contains(where: { $0.id == selectedID }) else { return nil }
        return selectedID
    }

    /// `↑↓`: the row `offset` away from the selection, clamped; the first or last row without one.
    public func moved(by offset: Int) -> UUID? {
        guard !rows.isEmpty else { return nil }
        guard let current = validSelection, let index = rows.firstIndex(where: { $0.id == current }) else {
            return offset < 0 ? rows.last?.id : rows.first?.id
        }
        return rows[min(max(index + offset, 0), rows.count - 1)].id
    }
}

/// What the Time tab asks of its module. Every closure runs on the main actor.
public struct TimeTabActions {
    /// A preset button: a Timer of that many minutes.
    public var startPreset: @MainActor (Int) -> Void
    /// The custom field's text (`45`, or `45 Tea` to name it); false when it is not a valid length.
    public var startCustom: @MainActor (String) -> Bool
    /// The `+ COUNTDOWN` form: target and optional name; false when the target is not in the future.
    public var startCountdown: @MainActor (Date, String) -> Bool
    public var select: @MainActor (UUID?) -> Void
    /// A row chip or its key (Space, `⌘R`, `⌘⌫`).
    public var perform: @MainActor (UUID, TimeRowModel.Control) -> Void
    /// `⌘Z` or the `UNDO` chip, within 5 s of a Remove.
    public var undo: @MainActor () -> Void
    /// The tab appeared (true) or went away (false): the 1 s tick runs only while it shows.
    public var visibility: @MainActor (Bool) -> Void
    /// The quick start took the focus the hotkey asked for.
    public var quickStartFocused: @MainActor () -> Void

    public init(
        startPreset: @escaping @MainActor (Int) -> Void = { _ in },
        startCustom: @escaping @MainActor (String) -> Bool = { _ in false },
        startCountdown: @escaping @MainActor (Date, String) -> Bool = { _, _ in false },
        select: @escaping @MainActor (UUID?) -> Void = { _ in },
        perform: @escaping @MainActor (UUID, TimeRowModel.Control) -> Void = { _, _ in },
        undo: @escaping @MainActor () -> Void = {},
        visibility: @escaping @MainActor (Bool) -> Void = { _ in },
        quickStartFocused: @escaping @MainActor () -> Void = {}
    ) {
        self.startPreset = startPreset
        self.startCustom = startCustom
        self.startCountdown = startCountdown
        self.select = select
        self.perform = perform
        self.undo = undo
        self.visibility = visibility
        self.quickStartFocused = quickStartFocused
    }
}
