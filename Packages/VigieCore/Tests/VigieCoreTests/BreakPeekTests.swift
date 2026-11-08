import AppKit
import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import VigieCore

/// Story 20.4: the break peek (three actions, `⌥⌘Z` only while visible), the quiet style, `after_focus`
/// replay and the sound table.
@MainActor @Suite struct BreakPeekTests {
    static let time: ModuleID = "time"
    static let theme = ThemeController(library: try! ThemeLoader.loadBundled()).theme

    static func action(_ id: String) -> AlertAction { .module(id: time, actionID: id, payload: Data()) }

    static func breakEvent(quiet: Bool = false, kicker: String? = nil) -> NotifierEvent {
        NotifierEvent(
            kind: "time.break_reminder", severity: .info, title: "Time for a break / 5 min break",
            body: "Focused 55 min since 13:05", action: action("break.start"), dedupeKey: "time.break_reminder.1",
            secondaryAction: action("break.skip"), tertiaryAction: action("break.snooze"), kicker: kicker,
            quiet: quiet)
    }

    // MARK: Content

    @Test func breakPeekHasThreeActions() {
        let alert = ActiveAlert(
            id: UUID(), module: Self.time, event: Self.breakEvent(), outputs: [.peek], postedAt: Date())
        let content = PeekContentMapper.content(for: alert, theme: Self.theme)
        #expect(content.kind == .breakDue)
        #expect(content.kicker == "Break · due")
        #expect(content.primary.map { String(localized: $0.label) } == "Start break")
        #expect(content.primary?.shortcut == "⌥⌘↵")
        #expect(content.tertiary.map { String(localized: $0.label) } == "Snooze 5m")
        #expect(content.tertiary?.shortcut == "⌥⌘Z")
        #expect(content.secondary.map { String(localized: $0.label) } == "Skip")
        #expect(content.secondary?.shortcut == "⌥⌘⌫")
        #expect(content.accentRole == .iris1, "Time accent")
        #expect(PeekContentMapper.announcement(for: content).contains("Break · due, Time for a break / 5 min break"))
    }

    @Test func kickerOverrideNamesThePomodoroSource() {
        let alert = ActiveAlert(
            id: UUID(), module: Self.time, event: Self.breakEvent(kicker: "Pomodoro · long break"), outputs: [.peek],
            postedAt: Date())
        #expect(PeekContentMapper.content(for: alert, theme: Self.theme).kicker == "Pomodoro · long break")
    }

    @Test func onlyTheBreakKindGetsAThirdAction() {
        let event = NotifierEvent(
            kind: "time.timer_end", severity: .info, title: "Tea", action: Self.action("open-time"),
            tertiaryAction: Self.action("x"))
        let alert = ActiveAlert(id: UUID(), module: Self.time, event: event, outputs: [.peek], postedAt: Date())
        #expect(PeekContentMapper.content(for: alert, theme: Self.theme).tertiary == nil)
    }

    @Test func threeActionColumnIsWider() {
        #expect(Self.theme.peekColumns.trailing == 176)
        #expect(Self.theme.peekColumnsThreeActions == (44, 196))
    }

    // MARK: Peek actions and shortcuts

    @MainActor final class Harness {
        let clock = TestClock()
        let backend = FakeTemporaryBackend()
        let router = RecordingActionRouter()
        let sound = RecordingSoundSink()
        let driver = RecordingPeekDriver()
        let shortcuts: TemporaryShortcuts
        let presenter: PeekPresenter
        let center: AlertCenter

        @MainActor init(global: GlobalNotifyRules = GlobalNotifyRules(), rule: NotifyRule = NotifyRule()) {
            shortcuts = TemporaryShortcuts(backend: backend)
            presenter = PeekPresenter(
                anchors: FakePeekAnchors(), theme: ThemeController(library: try! ThemeLoader.loadBundled()),
                driver: driver, clock: clock, dwell: { .seconds(5) }, pointer: { NSPoint(x: 700, y: 980) },
                announce: { _ in }, shortcuts: shortcuts, logger: testLogger)
            center = AlertCenter(
                rules: StaticNotifyRules(global: global, kinds: [BreakPeekTests.time: ["time.break_reminder": rule]]),
                clock: clock, sinks: AlertSinks(peek: presenter, sound: sound, actionRouter: router), log: testLogger)
            _ = center.makeNotifier(
                for: ModuleManifest(
                    id: BreakPeekTests.time, name: "Time", icon: "timer",
                    alertKinds: ["time.timer_end", "time.break_reminder"]))
        }
    }

    @Test func allThreeShortcutsAreBoundOnlyWhileTheBreakPeekShows() {
        let h = Harness()
        #expect(h.backend.bound.isEmpty)
        h.center.post(module: Self.time, event: Self.breakEvent())
        #expect(h.presenter.visibleContent?.tertiary != nil)
        #expect(h.backend.bound[TemporaryShortcuts.primaryName] == TemporaryShortcuts.primarySpec)
        #expect(h.backend.bound[TemporaryShortcuts.secondaryName] == TemporaryShortcuts.secondarySpec)
        #expect(h.backend.bound[TemporaryShortcuts.tertiaryName] == TemporaryShortcuts.tertiarySpec)
        #expect(TemporaryShortcuts.tertiarySpec == (try? HotkeySpec(parsing: "opt+cmd+z")))
        h.presenter.performSecondary()
        #expect(h.backend.bound.isEmpty, "unbound when the peek retracts")
    }

    @Test func otherPeeksNeverBindOptionCommandZ() {
        let h = Harness()
        h.center.post(
            module: Self.time,
            event: NotifierEvent(
                kind: "time.timer_end", severity: .info, title: "Tea", action: Self.action("open-time")))
        #expect(h.backend.bound[TemporaryShortcuts.tertiaryName] == nil)
        #expect(!h.backend.press(TemporaryShortcuts.tertiarySpec))
    }

    @Test func snoozeShortcutRoutesToTheModuleAndCancelsTheReminder() {
        let h = Harness(rule: NotifyRule(reminder: .seconds(600)))
        let handle = h.center.post(module: Self.time, event: Self.breakEvent())
        #expect(h.backend.press(TemporaryShortcuts.tertiarySpec))
        #expect(h.router.calls == [.module(Self.time, actionID: "break.snooze", payload: Data())])
        #expect(h.router.moduleIntents.first ?? nil != nil, "the press carries a user intent")
        #expect(h.presenter.visible == nil)
        #expect(h.center.history.last?.outcome == .dismissed, "the reminder is cancelled")
        #expect(h.center.active.map(\.id) == [handle.id], "still unresolved until the module resolves it")
    }

    @Test func skipShortcutRoutesToTheModule() {
        let h = Harness()
        h.center.post(module: Self.time, event: Self.breakEvent())
        #expect(h.backend.press(TemporaryShortcuts.secondarySpec))
        #expect(h.router.calls == [.module(Self.time, actionID: "break.skip", payload: Data())])
    }

    @Test func startBreakShortcutAndClickRouteToTheModule() {
        let h = Harness()
        h.center.post(module: Self.time, event: Self.breakEvent())
        #expect(h.backend.press(TemporaryShortcuts.primarySpec))
        #expect(h.router.calls == [.module(Self.time, actionID: "break.start", payload: Data())])
        // A click on Snooze (the panel's handler), on a fresh peek.
        let clicked = Harness()
        clicked.center.post(module: Self.time, event: Self.breakEvent())
        clicked.driver.presented.last?.handlers.tertiary()
        #expect(clicked.router.calls == [.module(Self.time, actionID: "break.snooze", payload: Data())])
    }

    @Test func dismissWithoutASecondaryActionRoutesNothing() {
        let h = Harness()
        h.center.post(
            module: Self.time,
            event: NotifierEvent(
                kind: "time.timer_end", severity: .info, title: "Tea", action: Self.action("open-time")))
        h.presenter.performSecondary()
        #expect(h.router.calls.isEmpty)
    }

    // MARK: Quiet style and sound

    @Test func quietStyleWithholdsPeekAndSoundButStaysActive() async {
        let h = AlertHarness()
        _ = h.center.makeNotifier(
            for: ModuleManifest(id: Self.time, name: "Time", icon: "timer", alertKinds: ["time.break_reminder"]))
        let handle = h.center.post(module: Self.time, event: Self.breakEvent(quiet: true))
        #expect(h.peek.shown.isEmpty)
        #expect(h.sound.played.isEmpty)
        #expect(h.center.active.map(\.id) == [handle.id])
        #expect(h.center.active.first?.outputs.isDisjoint(with: [.peek, .sound]) == true)
    }

    @Test func peekStylePlaysTheBreakSoundOnce() {
        let h = AlertHarness()
        _ = h.center.makeNotifier(
            for: ModuleManifest(id: Self.time, name: "Time", icon: "timer", alertKinds: ["time.break_reminder"]))
        h.center.post(module: Self.time, event: Self.breakEvent())
        #expect(h.peek.shown.count == 1)
        #expect(h.sound.played.count == 1)
        #expect(SoundTable.key(for: "time.break_reminder") == "break_reminder")
    }

    @Test func soundsPaneListsTheBreakReminder() {
        #expect(SoundTable.settingsKeys.contains("break_reminder"))
        #expect(!SoundTable.settingsKeys.contains("calendar_reminder"))
    }

    @Test func aDueBreakIsReplayedAfterFocus() async {
        let h = AlertHarness(global: GlobalNotifyRules(afterFocus: .replay), focusActive: true)
        _ = h.center.makeNotifier(
            for: ModuleManifest(id: Self.time, name: "Time", icon: "timer", alertKinds: ["time.break_reminder"]))
        let handle = h.center.post(module: Self.time, event: Self.breakEvent())
        #expect(h.peek.shown.isEmpty)
        await h.setFocus(false)
        #expect(await eventually { h.peek.shown.map(\.id) == [handle.id] })
    }

    @Test func aQuietBreakIsNotReplayedAfterFocus() async {
        let h = AlertHarness(global: GlobalNotifyRules(afterFocus: .replay), focusActive: true)
        _ = h.center.makeNotifier(
            for: ModuleManifest(id: Self.time, name: "Time", icon: "timer", alertKinds: ["time.break_reminder"]))
        h.center.post(module: Self.time, event: Self.breakEvent(quiet: true))
        await h.setFocus(false)
        for _ in 0..<10 { await Task.yield() }
        #expect(h.peek.shown.isEmpty)
        #expect(h.sound.played.isEmpty)
    }
}
