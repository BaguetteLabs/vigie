import Foundation
import ModuleKit
@_spi(Host) import ModuleKit
import Testing

@testable import Time

@MainActor @Suite struct TimeModuleTests {
    let clock = TestClock(Fixture.start)

    func makeModule() -> TimeModule {
        let clock = clock
        return TimeModule(now: { clock.now }, calendar: Fixture.calendar)
    }

    func started(_ context: FakeModuleContext = FakeModuleContext()) async throws -> (TimeModule, FakeModuleContext) {
        let module = makeModule()
        try await module.start(context: context)
        return (module, context)
    }

    /// Waits for main-actor tasks (the wake listener) to run.
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: Manifest and lifecycle

    @Test func manifestDeclaresTheTimerEndKindAndSettings() {
        let manifest = TimeModule.staticManifest
        #expect(manifest.id == "time")
        #expect(String(localized: manifest.name) == "Time")
        #expect(manifest.alertKinds == ["time.timer_end"])
        #expect(manifest.settings.map(\.key) == ["hotkey", "presets"])
        #expect(manifest.defaultEnabled == false, "SPEC §11: [modules.time] enabled = false")
    }

    @Test func notStartedRegistersNothingAndStartsNothing() {
        // A disabled module is never started by the Registry (PRD FR-4): nothing exists to register.
        let module = makeModule()
        #expect(module.startTimer(minutes: 5) == nil)
        #expect(module.state == .hidden)
    }

    @Test func startRegistersTheHotkeyAndStopRemovesEverything() async throws {
        let (module, context) = try await started()
        #expect(context.fakeHotkeys.names == ["hotkey"])
        #expect(context.fakeHotkeys.defaults == [nil], "SPEC §11: no default shortcut")
        module.startTimer(minutes: 5)
        module.tabVisibility(true)
        #expect(context.fakeScheduler.liveOneShots.count == 1)
        #expect(context.fakeScheduler.liveRepeating.count == 1)
        await module.stop()
        #expect(context.fakeHotkeys.cancelled == ["hotkey"])
        #expect(context.fakeScheduler.liveOneShots.isEmpty)
        #expect(context.fakeScheduler.liveRepeating.isEmpty)
        #expect(module.startTimer(minutes: 5) == nil)
    }

    // MARK: Scheduler

    @Test func oneEndJobAtTheNearestEndReArmedOnChange() async throws {
        let (module, context) = try await started()
        let long = try #require(module.startTimer(minutes: 25))
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [long.endsAt])
        let short = try #require(module.startTimer(minutes: 5))
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [short.endsAt])
        module.togglePause(short.id)
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [long.endsAt])
        module.togglePause(short.id)
        clock.advance(300)
        await context.fakeScheduler.fireNext()
        #expect(context.fakeNotifier.posted.count == 1)
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [long.endsAt])
    }

    @Test func uiTickRunsOnlyWhileTheTabIsVisible() async throws {
        let (module, context) = try await started()
        #expect(!module.isTicking)
        module.tabVisibility(true)
        #expect(module.isTicking)
        #expect(context.fakeScheduler.liveRepeating.map(\.interval) == [.seconds(1)])
        clock.advance(1)
        await context.fakeScheduler.liveRepeating[0].body()
        #expect(module.displayNow == clock.now)
        module.tabVisibility(false)
        #expect(!module.isTicking)
        #expect(context.fakeScheduler.liveRepeating.isEmpty)
    }

    // MARK: Alert

    @Test func endPostsTheTimerEndAlert() async throws {
        let (module, context) = try await started()
        let item = try #require(module.startTimer(minutes: 5, label: "Tea"))
        clock.advance(300)
        await context.fakeScheduler.fireNext()
        let event = try #require(context.fakeNotifier.posted.first)
        #expect(event.kind == "time.timer_end")
        #expect(event.title == "Tea / 5 min")
        #expect(event.body == "Started 14:43 · ended 14:48")
        #expect(event.category == "14:48", "the peek kicker reads TIMER · ENDED 14:48")
        #expect(event.dedupeKey == "time.timer_end.\(item.id.uuidString)")
        #expect(
            event.action == .module(id: "time", actionID: "open-time", payload: Data(item.id.uuidString.utf8)))
        #expect(module.state == .alert, "the Time tab carries the attention marker")
    }

    @Test func countdownAlertTitle() async throws {
        let (module, context) = try await started()
        module.startCountdown(to: clock.now.addingTimeInterval(90), label: "Release 0.3")
        clock.advance(90)
        await context.fakeScheduler.fireNext()
        #expect(context.fakeNotifier.posted.first?.title == "Release 0.3 / countdown")
    }

    @Test func dismissAcknowledgesClearsAttentionAndResolvesTheAlert() async throws {
        let (module, context) = try await started()
        let item = try #require(module.startTimer(minutes: 1))
        clock.advance(60)
        await context.fakeScheduler.fireNext()
        #expect(module.state == .alert)
        #expect(module.tabSnapshot().rows.first?.controls == [.dismiss])
        #expect(module.tabSnapshot().rows.first?.subline == "ENDED 14:44")
        module.dismiss(item.id)
        #expect(module.state == .hidden)
        #expect(module.board.items.isEmpty)
        #expect(context.fakeNotifier.resolved == 1)
    }

    @Test func openTimeActionOpensTheTabOnTheItem() async throws {
        let (module, context) = try await started()
        let item = try #require(module.startTimer(minutes: 1))
        module.selectedID = nil
        let intent = UserIntent()
        module.handleAlertAction("open-time", payload: Data(item.id.uuidString.utf8), intent: intent)
        #expect(context.fakeHost.openedOwnTab == [intent])
        #expect(module.selectedID == item.id)
        module.handleAlertAction("other", payload: Data(), intent: nil)
        #expect(context.fakeHost.openedOwnTab.count == 1)
    }

    // MARK: Persistence

    @Test func itemsPersistAndRestoreFromAbsoluteEnds() async throws {
        let storage = FakeStorage()
        let (module, _) = try await started(FakeModuleContext(storage: storage))
        let tea = try #require(module.startTimer(minutes: 5, label: "Tea"))
        let paused = try #require(module.startTimer(minutes: 20, label: "Paused"))
        module.togglePause(paused.id)
        await module.flushed()
        await module.stop()

        clock.advance(120)
        let (restored, context) = try await started(FakeModuleContext(storage: storage))
        #expect(restored.board[tea.id]?.endsAt == tea.endsAt)
        #expect(restored.board[tea.id]?.label == "Tea")
        #expect(restored.board[paused.id]?.state == .paused)
        #expect(restored.board[paused.id]?.pausedRemaining == 1200)
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [tea.endsAt])
        #expect(context.fakeNotifier.posted.isEmpty)
        #expect(restored.state == .active)
    }

    @Test func endMissedWhileQuitAlertsOnceOnLaunch() async throws {
        let storage = FakeStorage()
        let (module, _) = try await started(FakeModuleContext(storage: storage))
        module.startTimer(minutes: 5, label: "Tea")
        await module.flushed()
        await module.stop()

        clock.advance(3600)
        let (first, firstContext) = try await started(FakeModuleContext(storage: storage))
        #expect(firstContext.fakeNotifier.posted.map(\.title) == ["Tea / 5 min"])
        #expect(firstContext.fakeNotifier.posted.first?.body == "Started 14:43 · ended 14:48")
        #expect(first.state == .alert)
        await first.flushed()
        await first.stop()

        let (_, secondContext) = try await started(FakeModuleContext(storage: storage))
        #expect(secondContext.fakeNotifier.posted.isEmpty, "the alert is raised once")
    }

    @Test func endPassedWhileAsleepAlertsOnceOnWake() async throws {
        let (module, context) = try await started()
        module.startTimer(minutes: 5, label: "Tea")
        #expect(await eventually { context.fakePower.subscribers == 1 })
        clock.advance(7200)  // asleep: the job never fired
        context.fakePower.send(.willSleep)
        context.fakePower.send(.didWake)
        #expect(await eventually { context.fakeNotifier.posted.count == 1 })
        context.fakePower.send(.didWake)
        try await Task.sleep(for: .milliseconds(30))
        #expect(context.fakeNotifier.posted.count == 1)
        #expect(module.state == .alert)
    }

    // MARK: Actions

    @Test func removeKeepsAFiveSecondUndo() async throws {
        let (module, context) = try await started()
        let item = try #require(module.startTimer(minutes: 5))
        module.remove(item.id)
        #expect(module.board.items.isEmpty)
        #expect(module.tabSnapshot().canUndo)
        let undoJob = try #require(context.fakeScheduler.liveOneShots.first)
        #expect(undoJob.date == clock.now.addingTimeInterval(5))
        module.undo()
        #expect(module.board.items.map(\.id) == [item.id])
        #expect(!module.tabSnapshot().canUndo)

        module.remove(item.id)
        await context.fakeScheduler.fireNext()
        #expect(!module.tabSnapshot().canUndo)
        module.undo()
        #expect(module.board.items.isEmpty, "the undo window closed")
    }

    @Test func undoOfAnItemThatEndedMeanwhileAlerts() async throws {
        let (module, context) = try await started()
        let item = try #require(module.startTimer(minutes: 1))
        module.remove(item.id)
        clock.advance(61)
        module.undo()
        #expect(context.fakeNotifier.posted.count == 1)
        #expect(module.board[item.id]?.isEnded == true)
    }

    @Test func removeOnAnEndedItemDismissesIt() async throws {
        let (module, context) = try await started()
        let item = try #require(module.startTimer(minutes: 1))
        clock.advance(60)
        await context.fakeScheduler.fireNext()
        module.remove(item.id)
        #expect(!module.tabSnapshot().canUndo)
        #expect(module.state == .hidden)
    }

    @Test func tabActionsMapToTheTransitions() async throws {
        let (module, _) = try await started()
        let item = try #require(module.startTimer(minutes: 5))
        module.perform(item.id, .pause)
        #expect(module.board[item.id]?.state == .paused)
        module.perform(item.id, .resume)
        #expect(module.board[item.id]?.state == .running)
        clock.advance(100)
        module.perform(item.id, .reset)
        #expect(module.board[item.id]?.endsAt == clock.now.addingTimeInterval(300))
        module.perform(item.id, .remove)
        #expect(module.board.items.isEmpty)
    }

    @Test(
        arguments: [
            ("45", 45, nil), ("45m", 45, nil), (" 25 min Tea ", 25, "Tea"), ("5 Tea break", 5, "Tea break"),
            ("10minutes", 10, "minutes"),
        ] as [(String, Int, String?)])
    func parsesTheCustomField(text: String, minutes: Int, label: String?) throws {
        let parsed = try #require(TimeModule.parseCustom(text))
        #expect(parsed.minutes == minutes)
        #expect(parsed.label == label)
    }

    @Test(arguments: ["", "Tea", "0", "1441", "99999"])
    func rejectsInvalidCustomText(text: String) {
        #expect(TimeModule.parseCustom(text) == nil)
    }

    @Test func defaultNamesAreTimerAndCountdown() async throws {
        let (module, _) = try await started()
        #expect(module.startCustom("5")?.label == "Timer")
        #expect(module.startCountdown(to: clock.now.addingTimeInterval(60), label: "  ")?.label == "Countdown")
    }

    @Test func presetsComeFromTheSetting() async throws {
        let context = FakeModuleContext(settings: ["presets": ["3", "x", "3", "90", "0"]])
        let (module, _) = try await started(context)
        #expect(module.presets == [3, 90])
        #expect(module.tabSnapshot().quickStart.presets == [3, 90])
        try await context.fakeSettings.set(["7"], for: "presets")
        #expect(await eventually { module.presets == [7] })
        let (other, _) = try await started()
        #expect(other.presets == [5, 10, 25])
    }

    // MARK: Hotkey

    @Test func hotkeyOpensTheTabWithTheQuickStartFocused() async throws {
        let (module, context) = try await started()
        let intent = UserIntent()
        context.fakeHotkeys.press("hotkey", intent: intent)
        #expect(context.fakeHost.openedOwnTab == [intent])
        #expect(module.tabSnapshot().focusQuickStart)
        module.tabActions.quickStartFocused()
        #expect(!module.tabSnapshot().focusQuickStart)
    }

    // MARK: Tab snapshot

    @Test func snapshotRowsTextAndVoiceOver() async throws {
        let (module, _) = try await started()
        let tea = try #require(module.startTimer(minutes: 5, label: "Tea"))
        clock.advance(108)
        module.togglePause(tea.id)
        let snapshot = module.tabSnapshot()
        let row = try #require(snapshot.rows.first)
        #expect(row.label == "Tea")
        #expect(row.kind == "5 MIN TIMER")
        #expect(row.value == "3:12")
        #expect(row.subline == "PAUSED")
        #expect(row.controls == [.resume, .reset, .remove])
        #expect(row.visual == .ring(fractionLeft: 192.0 / 300, paused: true))
        #expect(row.accessibilityLabel == "Tea, 5 minute timer, 3 minutes, 12 seconds left, ends 14:48, paused")
        #expect(snapshot.runningCount == 1)

        module.togglePause(tea.id)
        let running = try #require(module.tabSnapshot().rows.first)
        #expect(running.subline == "ENDS 14:48")
        #expect(running.controls == [.pause, .reset, .remove])
        #expect(running.accessibilityLabel == "Tea, 5 minute timer, 3 minutes, 12 seconds left, ends 14:48")
    }

    @Test func countdownRowText() async throws {
        let (module, _) = try await started()
        // Sat 14 Nov 2026 14:00 UTC is 7 d 23 h 17 m after the fixture start.
        let target = Fixture.start.addingTimeInterval(7 * 86_400 + 23 * 3600 + 17 * 60)
        module.startCountdown(to: target, label: "Release 0.3")
        let row = try #require(module.tabSnapshot().rows.first)
        #expect(row.kind == "COUNTDOWN · SAT 14 NOV · 14:00")
        #expect(row.value == "7D 23H")
        #expect(row.subline == "IN 191 H")
        #expect(row.controls == [.remove])
        #expect(
            row.accessibilityLabel.hasPrefix("Release 0.3, countdown to Saturday 14 November, 14:00, 7 days, 23 hours"))
        clock.advance(7 * 86_400 + 23 * 3600)
        let near = try #require(module.tabSnapshot(now: clock.now).rows.first)
        #expect(near.value == "17:00")
        #expect(near.subline == "ENDS 14:00")
    }

    @Test func valueFormats() {
        #expect(TimeFormat.value(186) == "3:06")
        #expect(TimeFormat.value(185.2) == "3:06", "rounded up")
        #expect(TimeFormat.value(3850) == "1:04:10")
        #expect(TimeFormat.value(0) == "0:00")
    }

    @Test func emptyBoardSnapshot() async throws {
        let (module, _) = try await started()
        let snapshot = module.tabSnapshot()
        #expect(snapshot.rows.isEmpty)
        #expect(snapshot.runningCount == 0)
        #expect(snapshot.quickStart.pomodoroLengths == "25 · 5 · 15")
        #expect(!snapshot.quickStart.pomodoroAvailable)
        #expect(snapshot.countdownDefault == Fixture.start.addingTimeInterval(17 * 60))
    }

    @Test func privacyMasksLabelsButNotTimes() async throws {
        let (module, _) = try await started()
        module.startTimer(minutes: 5, label: "Tea")
        let row = try #require(module.tabSnapshot().privacy(true).rows.first)
        #expect(row.label == PrivacyMask.text)
        #expect(row.value == "5:00")
        #expect(!row.accessibilityLabel.contains("Tea"))
        #expect(row.accessibilityLabel.contains("5 minutes"))
    }
}
