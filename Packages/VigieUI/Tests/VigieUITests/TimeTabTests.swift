import AppKit
import Foundation
import ModuleKit
import SwiftUI
import Testing

@testable import VigieUI

@MainActor @Suite struct TimeTabTests {
    static let ids = (0..<4).map { _ in UUID() }

    static let ended = TimeRowModel(
        id: ids[0], label: "Laundry", kind: "45 MIN TIMER", value: "0:00", subline: "ENDED 14:48", visual: .ended,
        controls: [.dismiss], isEnded: true, accessibilityLabel: "Laundry, 45 minute timer, ended 14:48")
    static let tea = TimeRowModel(
        id: ids[1], label: "Tea", kind: "5 MIN TIMER", value: "3:06", subline: "ENDS 14:52",
        visual: .ring(fractionLeft: 0.62, paused: false), controls: [.pause, .reset, .remove],
        accessibilityLabel: "Tea, 5 minute timer, 3 minutes, 6 seconds left, ends 14:52")
    static let paused = TimeRowModel(
        id: ids[2], label: "Standup notes", kind: "25 MIN TIMER", value: "18:42", subline: "PAUSED",
        visual: .ring(fractionLeft: 0.75, paused: true), controls: [.resume, .reset, .remove],
        accessibilityLabel: "Standup notes, 25 minute timer, 18 minutes, 42 seconds left, ends 15:07, paused")
    static let countdown = TimeRowModel(
        id: ids[3], label: "Release 0.3", kind: "COUNTDOWN · SAT 14 NOV · 14:00", value: "7D 23H",
        subline: "IN 191 H", visual: .track(fractionElapsed: 0.08), controls: [.remove],
        accessibilityLabel: "Release 0.3, countdown to Saturday 14 November, 14:00")

    static func snapshot(_ rows: [TimeRowModel], selected: UUID? = nil, canUndo: Bool = false) -> TimeTabSnapshot {
        TimeTabSnapshot(
            quickStart: TimeQuickStart(presets: [5, 10, 25], pomodoroLengths: "25 · 5 · 15"), rows: rows,
            runningCount: rows.filter { !$0.isEnded }.count, selectedID: selected, canUndo: canUndo)
    }

    @Test func privacyMasksLabelsOnly() {
        let snapshot = Self.snapshot([Self.tea]).privacy(true)
        let row = snapshot.rows[0]
        #expect(row.label == PrivacyMask.text)
        #expect(row.value == "3:06")
        #expect(row.accessibilityLabel.hasPrefix(PrivacyMask.text + ", 5 minute timer"))
        #expect(Self.snapshot([Self.tea]).privacy(false).rows[0].label == "Tea")
    }

    @Test func arrowKeysMoveTheSelection() {
        let snapshot = Self.snapshot([Self.ended, Self.tea, Self.paused], selected: Self.ids[1])
        #expect(snapshot.moved(by: 1) == Self.ids[2])
        #expect(snapshot.moved(by: -1) == Self.ids[0])
        #expect(Self.snapshot([Self.ended, Self.tea], selected: Self.ids[1]).moved(by: 1) == Self.ids[1])
        #expect(Self.snapshot([Self.ended, Self.tea]).moved(by: 1) == Self.ids[0])
        #expect(Self.snapshot([Self.ended, Self.tea]).moved(by: -1) == Self.ids[1])
        #expect(Self.snapshot([]).moved(by: 1) == nil)
    }

    @Test func spaceTogglesPauseOnlyWhereTheRowHasIt() {
        #expect(Self.tea.pauseToggle == .pause)
        #expect(Self.paused.pauseToggle == .resume)
        #expect(Self.countdown.pauseToggle == nil)
        #expect(Self.ended.pauseToggle == nil)
    }

    @Test func staticCopyIsInTheCatalog() {
        #expect(L10n.string("time.quickStart.title") == "QUICK START")
        #expect(L10n.string("time.quickStart.countdown") == "+ COUNTDOWN")
        #expect(L10n.format("time.running.title", 3) == "RUNNING · 3")
        #expect(
            TimeRowModel.Control.allCases.map { L10n.string("time.action.\($0.rawValue)") }
                == ["PAUSE", "RESUME", "RESET", "REMOVE", "DISMISS", "START BREAK", "SNOOZE 5M", "SKIP", "STOP"])
        #expect(String(localized: VigieCopy.nothingRunning.label) == "NOTHING RUNNING")
        #expect(L10n.format("time.quickStart.preset.a11y", 5) == "Start a 5 minute timer")
    }

    nonisolated static let looks: [(Look, String)] = [
        (.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID),
        (.dark, "twin-metal-tactical"), (.light, "twin-metal-tactical"),
    ]

    /// The tab with an ended, a running and a paused Timer (running row selected), the mockup's Timer and
    /// Countdown, and the empty list, at 720 × 350. Set `VIGIE_RENDER_DIR` to keep the PNGs.
    @Test(arguments: looks)
    func rendersTheTab(look: Look, variant: String) throws {
        let theme = SessionsTabTests.theme(look, variant: variant)
        let name = "time-\(variant)-\(look.rawValue)"
        let three = Self.snapshot([Self.ended, Self.tea, Self.paused], selected: Self.ids[1])
        let main = TimeTabView(snapshot: { three }, actions: TimeTabActions()).rendering(minutes: "45")
        #expect(SessionGlyphTests.inkedPixels(try SessionsTabTests.render(main, theme: theme, name: name)) > 4000)

        let mock = Self.snapshot([Self.tea, Self.countdown], canUndo: true)
        let second = TimeTabView(snapshot: { mock }, actions: TimeTabActions()).rendering(minutes: "")
        _ = try SessionsTabTests.render(second, theme: theme, name: "\(name)-countdown")

        let none = Self.snapshot([])
        let empty = TimeTabView(snapshot: { none }, actions: TimeTabActions()).rendering(minutes: "")
        #expect(
            SessionGlyphTests.inkedPixels(try SessionsTabTests.render(empty, theme: theme, name: "\(name)-empty")) > 500
        )
    }

    /// The Timer-end peek (DESIGN "Time peeks": Time accent rim, ring beacon, kicker with the end time).
    @Test(arguments: looks)
    func rendersTheTimerEndPeek(look: Look, variant: String) throws {
        let theme = SessionsTabTests.theme(look, variant: variant)
        let content = PeekContent(
            kind: .timerEnd, kicker: "Timer · ended 14:48", title: "Tea / 5 min", body: "Started 14:43 · ended 14:48",
            primary: PeekAction(
                label: LocalizedStringResource(stringLiteral: "Open time"), shortcut: PeekAction.primaryShortcut),
            secondary: PeekAction(
                label: LocalizedStringResource(stringLiteral: "Dismiss"), shortcut: PeekAction.secondaryShortcut),
            accentRole: theme.usesCornerMarks ? .gold : .iris1)
        let margin = theme.peekShadow.margin
        let view = PeekView(
            content: content, dwell: PeekDwellState(total: .seconds(5), remaining: .seconds(3), isRunning: false)
        )
        .padding(.horizontal, margin)
        .padding(.bottom, margin)
        .background(look == .dark ? Color(white: 0.22) : Color(white: 0.85))
        .vigieTheme(theme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(SessionGlyphTests.inkedPixels(image) > 1000)
        if let directory = ProcessInfo.processInfo.environment["VIGIE_RENDER_DIR"] {
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: directory).appendingPathComponent(
                    "peek-timer-end-\(variant)-\(look.rawValue).png"))
        }
    }

    // MARK: Breaks (Story 20.4)

    static let breakDue = TimeRowModel(
        id: UUID(), label: "Break", kind: "15 MIN BREAK", value: "15:00", subline: "BREAK DUE", visual: .breakDue,
        controls: [.startBreak, .snooze, .skip], accessibilityLabel: "Break due, 15 minute break")

    @Test func breakDueRowStartsTheBreakOnReturn() {
        #expect(Self.breakDue.returnControl == .startBreak)
        #expect(Self.ended.returnControl == .dismiss)
        #expect(Self.tea.returnControl == nil)
        #expect(TimeRowModel.Control.startBreak.isPrimary)
        #expect(!TimeRowModel.Control.skip.isPrimary)
        #expect(L10n.string("time.closed.breakDue") == "BREAK DUE")
    }

    static func write(_ image: CGImage, _ name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["VIGIE_RENDER_DIR"] else { return }
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }

    /// The break peek (DESIGN "Break", mockup 1.7e (i)): dashed ring beacon, three actions in the 196px column.
    @Test(arguments: looks)
    func rendersTheBreakPeek(look: Look, variant: String) throws {
        let theme = SessionsTabTests.theme(look, variant: variant)
        let content = PeekContent(
            kind: .breakDue, kicker: "Break · due", title: "Time for a break / 5 min break",
            body: "Focused 55 min since 13:05",
            primary: PeekAction(
                label: LocalizedStringResource(stringLiteral: "Start break"), shortcut: PeekAction.primaryShortcut),
            secondary: PeekAction(
                label: LocalizedStringResource(stringLiteral: "Skip"), shortcut: PeekAction.secondaryShortcut),
            accentRole: theme.usesCornerMarks ? .gold : .iris1,
            tertiary: PeekAction(
                label: LocalizedStringResource(stringLiteral: "Snooze 5m"), shortcut: PeekAction.tertiaryShortcut))
        let margin = theme.peekShadow.margin
        let view = PeekView(
            content: content, dwell: PeekDwellState(total: .seconds(5), remaining: .seconds(3), isRunning: false)
        )
        .padding(.horizontal, margin)
        .padding(.bottom, margin)
        .background(look == .dark ? Color(white: 0.22) : Color(white: 0.85))
        .vigieTheme(theme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(SessionGlyphTests.inkedPixels(image) > 1000)
        try Self.write(image, "peek-break-\(variant)-\(look.rawValue).png")
    }

    /// The closed-notch `BREAK DUE` readout (mockup 1.7e (ii)) on the band, readout and ring-only forms.
    @Test(arguments: looks)
    func rendersTheBreakDueReadout(look: Look, variant: String) throws {
        let theme = SessionsTabTests.theme(look, variant: variant)
        let view = HStack(spacing: 24) {
            TimeBreakDueReadout(value: "15:00", accessibilityLabel: "Break due, 15 minute break")
            TimeBreakDueReadout(value: "15:00", ringOnly: true, accessibilityLabel: "Break due, 15 minute break")
        }
        .padding(12)
        .background(theme.color(.band))
        .vigieTheme(theme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try #require(renderer.cgImage)
        #expect(SessionGlyphTests.inkedPixels(image) > 200)
        try Self.write(image, "closed-break-due-\(variant)-\(look.rawValue).png")
    }

    // MARK: Pomodoro (Story 20.5)

    static let pomodoroWork = TimeRowModel(
        id: UUID(), label: "Pomodoro", kind: "WORK · CYCLE 2/4", value: "18:42", subline: "ENDS 15:07",
        visual: .ring(fractionLeft: 0.75, paused: false), controls: [.pause, .skip, .stop],
        accessibilityLabel: "Pomodoro, Work, cycle 2 of 4, 18 minutes, 42 seconds left, ends 15:07",
        pips: .init(count: 4, current: 2, onBreak: false, accessibilityLabel: "Work, cycle 2 of 4"), removal: .stop)
    static let pomodoroAway = TimeRowModel(
        id: UUID(), label: "Pomodoro", kind: "AWAY · PAUSED", value: "18:42", subline: "PAUSED 14:31",
        visual: .ring(fractionLeft: 0.75, paused: true), controls: [.resume, .skip, .stop],
        accessibilityLabel: "Pomodoro, Work, cycle 2 of 4, away, paused since 14:31",
        pips: .init(count: 4, current: 2, onBreak: false, accessibilityLabel: "Work, cycle 2 of 4"), isAway: true,
        removal: .stop)
    static let pomodoroBreak = TimeRowModel(
        id: UUID(), label: "Pomodoro", kind: "LONG BREAK", value: "14:05", subline: "ENDS 15:20",
        visual: .breakRing(fractionLeft: 0.94), controls: [.pause, .skip, .stop],
        accessibilityLabel: "Pomodoro, Long break, cycle 4 of 4",
        pips: .init(count: 4, current: 4, onBreak: true, accessibilityLabel: "Long break, cycle 4 of 4"),
        removal: .stop)

    @Test func pipsMarkDoneCurrentAndUpcoming() {
        let work = TimeRowModel.Pips(count: 4, current: 2, onBreak: false, accessibilityLabel: "")
        #expect(work.marks == [.done, .current(hatched: false), .upcoming, .upcoming])
        let long = TimeRowModel.Pips(count: 4, current: 4, onBreak: true, accessibilityLabel: "")
        #expect(long.marks == [.done, .done, .done, .current(hatched: true)])
        let clamped = TimeRowModel.Pips(count: 3, current: 9, onBreak: false, accessibilityLabel: "")
        #expect(clamped.current == 3)
    }

    @Test func pomodoroRowStopsOnCommandDelete() {
        #expect(Self.pomodoroWork.deleteControl == .stop)
        #expect(Self.pomodoroAway.pauseToggle == .resume)
        #expect(Self.tea.deleteControl == .remove)
        #expect(Self.ended.deleteControl == .dismiss)
    }

    /// The tab with a running, an Away-paused and a long-break Pomodoro row (pips, solid and dashed arcs).
    @Test(arguments: looks)
    func rendersThePomodoroRows(look: Look, variant: String) throws {
        let theme = SessionsTabTests.theme(look, variant: variant)
        let rows = [Self.tea, Self.pomodoroWork, Self.pomodoroAway, Self.pomodoroBreak]
        var snapshot = Self.snapshot(rows, selected: Self.pomodoroWork.id)
        snapshot.quickStart.pomodoroAvailable = false
        let view = TimeTabView(snapshot: { snapshot }, actions: TimeTabActions()).rendering(minutes: "")
        let name = "time-pomodoro-\(variant)-\(look.rawValue)"
        #expect(SessionGlyphTests.inkedPixels(try SessionsTabTests.render(view, theme: theme, name: name)) > 4000)
    }

    @Test(arguments: looks)
    func rendersThePhasePips(look: Look, variant: String) throws {
        let theme = SessionsTabTests.theme(look, variant: variant)
        let view = VStack(spacing: 8) {
            PhasePips(.init(count: 4, current: 2, onBreak: false, accessibilityLabel: "Work, cycle 2 of 4"))
            PhasePips(.init(count: 4, current: 2, onBreak: true, accessibilityLabel: "Break, cycle 2 of 4"))
            TimePauseMark()
        }
        .padding(12)
        .background(theme.color(.surfacePanel))
        .vigieTheme(theme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try #require(renderer.cgImage)
        #expect(SessionGlyphTests.inkedPixels(image) > 50)
        try Self.write(image, "pips-\(variant)-\(look.rawValue).png")
    }

    /// The tab in break-due state: the break row first (selected, `START BREAK ↵`), then a Timer.
    @Test(arguments: looks)
    func rendersTheBreakDueTab(look: Look, variant: String) throws {
        let theme = SessionsTabTests.theme(look, variant: variant)
        let snapshot = Self.snapshot([Self.breakDue, Self.tea], selected: Self.breakDue.id)
        let view = TimeTabView(snapshot: { snapshot }, actions: TimeTabActions()).rendering(minutes: "")
        _ = try SessionsTabTests.render(view, theme: theme, name: "time-break-due-\(variant)-\(look.rawValue)")
    }
}
