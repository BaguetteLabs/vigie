import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import Time

/// Story 20.5: the Pomodoro through the module, on a fake clock, scheduler, notifier and `context.away`.
@MainActor @Suite struct PomodoroModuleTests {
    let clock = TestClock(Fixture.start)

    func started(
        _ settings: [String: any SettingValue] = [:], storage: FakeStorage = FakeStorage()
    ) async throws -> (TimeModule, FakeModuleContext) {
        let clock = clock
        let module = TimeModule(now: { clock.now }, calendar: Fixture.calendar)
        let context = FakeModuleContext(settings: settings, storage: storage)
        try await module.start(context: context)
        return (module, context)
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Advances the clock to the earliest live job and runs it.
    func fireNext(_ context: FakeModuleContext) async {
        guard let date = context.fakeScheduler.liveOneShots.compactMap(\.date).min() else { return }
        clock.advance(max(0, date.timeIntervalSince(clock.now)))
        await context.fakeScheduler.fireNext()
    }

    func posts(_ context: FakeModuleContext, _ kind: String) -> [NotifierEvent] {
        context.fakeNotifier.posted.filter { $0.kind == kind }
    }

    func row(_ module: TimeModule) throws -> TimeRowModel {
        let id = try #require(module.pomodoro?.id)
        return try #require(module.tabSnapshot(now: clock.now).rows.first { $0.id == id })
    }

    // MARK: Start

    @Test func startsFromTheQuickStartOneAtATime() async throws {
        let (module, context) = try await started()
        #expect(module.tabSnapshot().quickStart.pomodoroAvailable)
        let first = try #require(module.startPomodoro())
        #expect(module.startPomodoro() == nil, "A87: one Pomodoro at a time")
        #expect(module.pomodoro?.id == first.id)
        #expect(!module.tabSnapshot().quickStart.pomodoroAvailable)
        #expect(module.state == .active)
        #expect(module.selectedID == first.id)
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [Fixture.start.addingTimeInterval(1500)])
        #expect(module.tabSnapshot().runningCount == 1)
    }

    @Test func quickStartButtonStartsOneThroughTheTabActions() async throws {
        let (module, _) = try await started()
        module.tabActions.startPomodoro()
        #expect(module.pomodoro != nil)
    }

    @Test func configuredLengthsAreUsedAndShownOnTheButton() async throws {
        let (module, context) = try await started([
            "pomodoro.work": Duration.seconds(50 * 60), "pomodoro.short_break": Duration.seconds(600),
            "pomodoro.long_break": Duration.seconds(1800), "pomodoro.long_every": 2,
        ])
        #expect(module.tabSnapshot().quickStart.pomodoroLengths == "50 · 10 · 30")
        module.startPomodoro()
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [Fixture.start.addingTimeInterval(3000)])
        let pips = try #require(try row(module).pips)
        #expect(pips.count == 2)
        try await context.fakeSettings.set(Duration.seconds(20 * 60), for: "pomodoro.work")
        #expect(await eventually { module.tabSnapshot().quickStart.pomodoroLengths == "20 · 10 · 30" })
        #expect(module.pomodoro?.lengths.work == 1200)
    }

    // MARK: Work end

    @Test func workEndPostsTheBreakReminderWithThePomodoroKicker() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        await fireNext(context)
        #expect(posts(context, TimeModule.timerEndKind).isEmpty, "AD-13 amended: never time.timer_end")
        let event = try #require(posts(context, TimeModule.breakReminderKind).first)
        #expect(event.kicker == "Pomodoro · break")
        #expect(event.title == "1 cycle done / 5 min break")
        #expect(event.body == "Focused 25 min since 14:43")
        #expect(event.action == .module(id: "time", actionID: TimeModule.startBreakAction, payload: Data()))
        #expect(event.secondaryAction == .module(id: "time", actionID: TimeModule.skipBreakAction, payload: Data()))
        #expect(event.tertiaryAction == .module(id: "time", actionID: TimeModule.snoozeBreakAction, payload: Data()))
        #expect(!event.quiet)
        #expect(module.state == .alert)
        #expect(module.leftWingItems().map(\.id) == ["break-due"])
        let due = try row(module)
        #expect(due.controls == [.startBreak, .snooze, .skip])
        #expect(due.visual == .breakDue)
        #expect(due.subline == "BREAK DUE")
        #expect(due.kind == "BREAK · 1/4")
        #expect(due.value == "5:00")
        #expect(due.returnControl == .startBreak)
    }

    @Test func fourthWorkEndAnnouncesTheLongBreak() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        for _ in 0..<3 {
            await fireNext(context)
            module.handleAlertAction(TimeModule.startBreakAction, payload: Data(), intent: nil)
            await fireNext(context)
        }
        await fireNext(context)
        let breaks = posts(context, TimeModule.breakReminderKind)
        #expect(
            breaks.map(\.kicker) == [
                "Pomodoro · break", "Pomodoro · break", "Pomodoro · break", "Pomodoro · long break",
            ])
        #expect(breaks.last?.title == "4 cycles done / 15 min break")
        #expect(breaks.last?.body == "Focused 1 h 40 min since 14:43")
        #expect(try row(module).kind == "LONG BREAK")
        #expect(module.leftWingItems().count == 1)
    }

    @Test func quietStyleRaisesNoPeekButKeepsBreakDue() async throws {
        let (module, context) = try await started(["breaks.style": "quiet"])
        module.startPomodoro()
        await fireNext(context)
        #expect(posts(context, TimeModule.breakReminderKind).first?.quiet == true)
        #expect(module.leftWingItems().map(\.id) == ["break-due"])
    }

    @Test func breakWaitsForStartBreak() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        await fireNext(context)
        #expect(context.fakeScheduler.liveOneShots.isEmpty, "nothing starts the break on its own")
        clock.advance(3600)
        module.tick()
        #expect(module.pomodoro?.isDue == true)
        module.perform(try #require(module.pomodoro?.id), .startBreak)
        #expect(module.pomodoro?.isOnBreak == true)
        #expect(module.leftWingItems().isEmpty)
        #expect(context.fakeNotifier.unresolved.filter { $0.kind == TimeModule.breakReminderKind }.isEmpty)
        let running = try row(module)
        #expect(running.visual == .breakRing(fractionLeft: 1, paused: false))
        #expect(running.controls == [.pause, .skip, .stop])
        #expect(module.state == .active)
    }

    @Test func snoozeReRaisesAfterFiveMinutes() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        await fireNext(context)
        module.handleAlertAction(TimeModule.snoozeBreakAction, payload: Data(), intent: nil)
        #expect(module.pomodoro?.isDue == true)
        #expect(module.leftWingItems().count == 1, "Snooze keeps BREAK DUE")
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [clock.now.addingTimeInterval(300)])
        await fireNext(context)
        #expect(posts(context, TimeModule.breakReminderKind).count == 2)
        #expect(context.fakeNotifier.unresolved.filter { $0.kind == TimeModule.breakReminderKind }.count == 1)
    }

    @Test func skipOnTheDueBreakStartsTheNextWork() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        await fireNext(context)
        module.handleAlertAction(TimeModule.skipBreakAction, payload: Data(), intent: nil)
        #expect(module.pomodoro?.isWork == true)
        #expect(module.pomodoro?.cycle == 2)
        #expect(context.fakeNotifier.unresolved.isEmpty)
        #expect(try row(module).kind == "WORK · CYCLE 2/4")
    }

    // MARK: Break end

    @Test func breakEndPostsTimerEndAndWorkResumesOnItsOwn() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        await fireNext(context)
        module.startPomodoroBreak()
        let breakStart = clock.now
        await fireNext(context)
        let event = try #require(posts(context, TimeModule.timerEndKind).first)
        #expect(event.kicker == "Break · ended")
        #expect(event.title == "Back to work / 25 min")
        #expect(event.body == "Started 15:08 · ended 15:13")
        #expect(module.pomodoro?.isWork == true)
        #expect(module.pomodoro?.cycle == 2)
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [breakStart.addingTimeInterval(300 + 1500)])
        // The next work end resolves the break-end alert.
        await fireNext(context)
        #expect(context.fakeNotifier.unresolved.map(\.kind) == [TimeModule.breakReminderKind])
    }

    // MARK: Row

    @Test func workRowShowsPipsPhaseAndSolidArc() async throws {
        let (module, _) = try await started()
        module.startPomodoro()
        clock.advance(300)
        let work = try row(module)
        #expect(work.label == "Pomodoro")
        #expect(work.kind == "WORK · CYCLE 1/4")
        #expect(work.value == "20:00")
        #expect(work.subline == "ENDS 15:08")
        #expect(work.visual == .ring(fractionLeft: 0.8, paused: false))
        #expect(work.controls == [.pause, .skip, .stop])
        #expect(work.deleteControl == .stop)
        #expect(work.pauseToggle == .pause)
        let pips = try #require(work.pips)
        #expect(pips.marks == [.current(hatched: false), .upcoming, .upcoming, .upcoming])
        #expect(pips.accessibilityLabel == "Work, cycle 1 of 4")
        #expect(work.accessibilityLabel == "Pomodoro, Work, cycle 1 of 4, 20 minutes left, ends 15:08")
        #expect(!work.isAway)
    }

    @Test func breakRowHatchesTheCurrentPipAndReadsBreak() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        await fireNext(context)
        module.startPomodoroBreak()
        await fireNext(context)
        await fireNext(context)
        module.startPomodoroBreak()
        let brk = try row(module)
        #expect(brk.kind == "BREAK · 2/4")
        #expect(brk.pips?.marks == [.done, .current(hatched: true), .upcoming, .upcoming])
        #expect(brk.pips?.accessibilityLabel == "Break, cycle 2 of 4")
    }

    // MARK: Pause, skip, stop

    @Test func pauseResumeSkipAndStop() async throws {
        let (module, context) = try await started()
        let id = try #require(module.startPomodoro()?.id)
        clock.advance(600)
        module.perform(id, .pause)
        #expect(module.pomodoro?.pauseReason == .user)
        #expect(context.fakeScheduler.liveOneShots.isEmpty)
        let paused = try row(module)
        #expect(paused.controls == [.resume, .skip, .stop])
        #expect(paused.subline == "PAUSED 14:53")
        #expect(paused.visual == .ring(fractionLeft: 0.6, paused: true))
        #expect(!paused.isAway)
        clock.advance(600)
        module.perform(id, .resume)
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [clock.now.addingTimeInterval(900)])
        module.perform(id, .skip)
        #expect(module.pomodoro?.isOnBreak == true, "skipping work starts its break")
        module.perform(id, .stop)
        #expect(module.pomodoro == nil)
        #expect(module.state == .hidden)
        #expect(context.fakeScheduler.liveOneShots.isEmpty)
        #expect(module.tabSnapshot().quickStart.pomodoroAvailable)
    }

    @Test func stopResolvesADueBreak() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        await fireNext(context)
        module.stopPomodoro()
        #expect(context.fakeNotifier.unresolved.isEmpty)
        #expect(module.leftWingItems().isEmpty)
        #expect(module.state == .hidden)
    }

    // MARK: Away

    @Test func awayPausesWorkAndPresentResumes() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        #expect(await eventually { context.fakeAway.subscribers == 1 }, "subscribed while a Pomodoro runs")
        clock.advance(600)
        context.fakeAway.send(.away(since: clock.now.addingTimeInterval(-90)))
        #expect(await eventually { module.pomodoro?.isAwayPaused == true })
        let away = try row(module)
        #expect(away.kind == "AWAY · PAUSED")
        #expect(away.subline == "PAUSED 14:51")
        #expect(away.isAway)
        #expect(away.controls == [.resume, .skip, .stop])
        #expect(away.visual == .ring(fractionLeft: 990.0 / 1500, paused: true))
        #expect(away.pips?.accessibilityLabel == "Work, cycle 1 of 4")
        #expect(context.fakeScheduler.liveOneShots.isEmpty, "frozen")
        clock.advance(1200)
        context.fakeAway.send(.present)
        #expect(await eventually { module.pomodoro?.isPaused == false })
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [clock.now.addingTimeInterval(990)])
    }

    @Test func resumeEndsAnAwayPauseAtOnce() async throws {
        let (module, context) = try await started()
        let id = try #require(module.startPomodoro()?.id)
        #expect(await eventually { context.fakeAway.subscribers == 1 })
        context.fakeAway.send(.away(since: clock.now))
        #expect(await eventually { module.pomodoro?.isAwayPaused == true })
        module.perform(id, .resume)
        #expect(module.pomodoro?.isPaused == false)
    }

    @Test func awayDuringABreakDoesNotPauseIt() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        await fireNext(context)
        module.startPomodoroBreak()
        #expect(await eventually { context.fakeAway.subscribers == 1 })
        context.fakeAway.send(.away(since: clock.now))
        try await Task.sleep(for: .milliseconds(20))
        #expect(module.pomodoro?.isPaused == false)
        await fireNext(context)
        #expect(posts(context, TimeModule.timerEndKind).count == 1)
        #expect(module.pomodoro?.isAwayPaused == true, "the next work period starts paused while Away")
    }

    @Test func sleepPausesWorkAndWakeResumes() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        #expect(await eventually { context.fakePower.subscribers == 1 })
        clock.advance(300)
        context.fakePower.send(.willSleep)
        #expect(await eventually { module.pomodoro?.isAwayPaused == true })
        clock.advance(3600)
        context.fakePower.send(.didWake)
        #expect(await eventually { module.pomodoro?.isPaused == false })
        #expect(module.pomodoro?.remaining(at: clock.now) == 1200)
        #expect(posts(context, TimeModule.breakReminderKind).isEmpty)
    }

    @Test func stopEndsTheAwaySubscriptionWhenBreaksAreOff() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        #expect(await eventually { context.fakeAway.subscribers == 1 })
        module.stopPomodoro()
        #expect(await eventually { context.fakeAway.subscribers == 0 }, "PRD FR-4: no polling without a need")
    }

    // MARK: Break reminders

    @Test func breakRemindersPauseWhileAPomodoroRuns() async throws {
        let (module, context) = try await started(["breaks.enabled": true])
        module.startPomodoro()
        #expect(module.breaks?.phase == .paused)
        // Hours of presence: only the Pomodoro's own breaks are posted.
        for _ in 0..<6 {
            await fireNext(context)
            module.skipPomodoroPhase()
        }
        #expect(posts(context, TimeModule.breakReminderKind).allSatisfy { $0.kicker?.hasPrefix("Pomodoro") == true })
        module.stopPomodoro()
        #expect(module.breaks?.phase == .working)
        #expect(module.breaks?.cycleStart == clock.now, "a fresh cycle when it stops")
        #expect(context.fakeAway.subscribers == 1, "breaks still need presence")
    }

    @Test func aDueReminderIsClearedWhenAPomodoroStarts() async throws {
        let (module, context) = try await started(["breaks.enabled": true])
        await fireNext(context)
        #expect(module.breaks?.isDue == true)
        module.startPomodoro()
        #expect(module.breaks?.isDue == false)
        #expect(context.fakeNotifier.unresolved.isEmpty)
        #expect(module.tabSnapshot(now: clock.now).rows.map(\.id) == [module.pomodoro?.id], "no reminder row")
    }

    // MARK: Restore

    @Test func restoredFromItemsJsonAfterRelaunch() async throws {
        let storage = FakeStorage()
        let (module, _) = try await started(storage: storage)
        let timer = try #require(module.startTimer(minutes: 600, label: "Tea"))
        let pomodoro = try #require(module.startPomodoro())
        clock.advance(300)
        module.togglePomodoroPause()
        await module.flushed()
        await module.stop()

        clock.advance(7200)
        let (restored, context) = try await started(storage: storage)
        #expect(restored.board[timer.id] != nil)
        #expect(restored.pomodoro?.id == pomodoro.id)
        #expect(restored.pomodoro?.pauseReason == .user)
        #expect(restored.pomodoro?.remaining(at: clock.now) == 1200)
        #expect(restored.state == .active)
        #expect(context.fakeNotifier.posted.isEmpty)
        #expect(!restored.tabSnapshot().quickStart.pomodoroAvailable)
        #expect(await eventually { context.fakeAway.subscribers == 1 })
    }

    @Test func workEndPassedWhileQuitPostsTheBreakOnceOnLaunch() async throws {
        let storage = FakeStorage()
        let (module, _) = try await started(["breaks.enabled": true], storage: storage)
        module.startPomodoro()
        await module.flushed()
        await module.stop()

        clock.advance(3600)
        let (first, firstContext) = try await started(["breaks.enabled": true], storage: storage)
        #expect(posts(firstContext, TimeModule.breakReminderKind).map(\.kicker) == ["Pomodoro · break"])
        #expect(first.pomodoro?.isDue == true)
        #expect(first.breaks?.phase == .paused, "break reminders stay held after a relaunch")
        #expect(first.state == .alert)
        await first.flushed()
        await first.stop()

        let (second, secondContext) = try await started(["breaks.enabled": true], storage: storage)
        #expect(secondContext.fakeNotifier.posted.isEmpty, "posted once; BREAK DUE persists")
        #expect(second.leftWingItems().map(\.id) == ["break-due"])
    }

    @Test func breakEndPassedWhileAsleepAdvancesOnWake() async throws {
        let (module, context) = try await started()
        module.startPomodoro()
        await fireNext(context)
        module.startPomodoroBreak()
        #expect(await eventually { context.fakePower.subscribers == 1 })
        clock.advance(600)  // asleep: the job never fired
        context.fakePower.send(.willSleep)
        context.fakePower.send(.didWake)
        #expect(await eventually { posts(context, TimeModule.timerEndKind).count == 1 })
        #expect(module.pomodoro?.isWork == true)
    }
}
