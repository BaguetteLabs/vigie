import Foundation
import ModuleKit
import Testing

@testable import Time

/// Story 20.4: break reminders through the module, on a fake clock, scheduler and `context.away`.
@MainActor @Suite struct BreakReminderTests {
    let clock = TestClock(Fixture.start)

    func started(_ settings: [String: any SettingValue] = ["breaks.enabled": true]) async throws -> (
        TimeModule, FakeModuleContext
    ) {
        let clock = clock
        let module = TimeModule(now: { clock.now }, calendar: Fixture.calendar)
        let context = FakeModuleContext(settings: settings)
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

    var breakPosts: (FakeModuleContext) -> [NotifierEvent] {
        { $0.fakeNotifier.posted.filter { $0.kind == TimeModule.breakReminderKind } }
    }

    // MARK: Settings and subscription

    @Test func manifestDeclaresTheBreakKindAndSettings() {
        let manifest = TimeModule.staticManifest
        #expect(manifest.alertKinds == ["time.timer_end", "time.break_reminder"])
        let keys = manifest.settings.map(\.key)
        #expect(
            keys == [
                "hotkey", "presets", "pomodoro.work", "pomodoro.short_break", "pomodoro.long_break",
                "pomodoro.long_every", "breaks.enabled", "breaks.work", "breaks.length", "breaks.away_after",
                "breaks.style",
            ])
        let byKey = Dictionary(uniqueKeysWithValues: manifest.settings.map { ($0.key, $0.kind) })
        #expect(byKey["breaks.enabled"] == .bool(default: false), "A87: off by default")
        #expect(byKey["breaks.work"] == .duration(default: .seconds(3300)))
        #expect(byKey["breaks.length"] == .duration(default: .seconds(300)))
        #expect(byKey["breaks.away_after"] == .duration(default: .seconds(90)))
        #expect(byKey["breaks.style"] == .enumeration(options: ["peek", "quiet"], default: "peek"))
    }

    @Test func offByDefaultNeverSubscribesToAway() async throws {
        let (module, context) = try await started([:])
        try? await Task.sleep(for: .milliseconds(20))
        #expect(context.fakeAway.subscribers == 0, "PRD FR-4: no presence polling while breaks are off")
        #expect(module.breaks == nil)
        #expect(module.leftWingItems().isEmpty)
    }

    @Test func turningBreaksOnAndOffSubscribesAndUnsubscribes() async throws {
        let (module, context) = try await started([:])
        try await context.fakeSettings.set(true, for: "breaks.enabled")
        #expect(await eventually { context.fakeAway.subscribers == 1 })
        #expect(module.breaks != nil)
        try await context.fakeSettings.set(false, for: "breaks.enabled")
        #expect(await eventually { context.fakeAway.subscribers == 0 })
        #expect(module.breaks == nil)
    }

    @Test func stopEndsTheSubscription() async throws {
        let (module, context) = try await started()
        #expect(await eventually { context.fakeAway.subscribers == 1 })
        await module.stop()
        #expect(await eventually { context.fakeAway.subscribers == 0 })
    }

    // MARK: Due

    @Test func dueAfterFiftyFiveMinutesPostsOneBreakAlert() async throws {
        let (module, context) = try await started()
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [Fixture.start.addingTimeInterval(3300)])
        await fireNext(context)
        let posts = breakPosts(context)
        try #require(posts.count == 1)
        let event = posts[0]
        #expect(event.kind == "time.break_reminder")
        #expect(event.severity == .info)
        #expect(event.title == "Time for a break / 5 min break")
        #expect(event.body == "Focused 55 min since 14:43")
        #expect(event.action == .module(id: "time", actionID: TimeModule.startBreakAction, payload: Data()))
        #expect(event.secondaryAction == .module(id: "time", actionID: TimeModule.skipBreakAction, payload: Data()))
        #expect(event.tertiaryAction == .module(id: "time", actionID: TimeModule.snoozeBreakAction, payload: Data()))
        #expect(event.kicker == nil, "the core kicker BREAK · DUE")
        #expect(!event.quiet)
        #expect(module.state == .alert, "the Time tab's attention marker")
    }

    @Test func dueBreakOffersTheBreakDueItemAndTabRow() async throws {
        let (module, context) = try await started()
        #expect(module.leftWingItems().isEmpty)
        await fireNext(context)
        let items = module.leftWingItems()
        #expect(items.map(\.id) == ["break-due"])
        #expect(items.first?.state == .alert)
        #expect(items.first?.priority == 3)
        let rows = module.tabSnapshot(now: clock.now).rows
        #expect(rows.first?.id == TimeModule.breakRowID)
        #expect(rows.first?.controls == [.startBreak, .snooze, .skip])
        #expect(rows.first?.visual == .breakDue)
        #expect(rows.first?.value == "5:00")
        #expect(rows.first?.returnControl == .startBreak)
    }

    @Test func noReNaggingOfItsOwn() async throws {
        let (module, context) = try await started()
        await fireNext(context)
        clock.advance(4 * 3600)
        await fireNext(context)
        #expect(breakPosts(context).count == 1, "only the Notifier's reminder rule repeats it (PRD FR-10)")
        #expect(context.fakeNotifier.unresolved.count == 1, "stays unresolved for after_focus = replay")
        #expect(module.breaks?.isDue == true)
    }

    @Test func snoozeKeepsTheItemAndReRaisesAfterFiveMinutes() async throws {
        let (module, context) = try await started()
        await fireNext(context)
        let snoozedAt = clock.now
        module.handleAlertAction(TimeModule.snoozeBreakAction, payload: Data(), intent: nil)
        #expect(breakPosts(context).count == 1)
        #expect(module.leftWingItems().count == 1, "Snooze keeps BREAK DUE showing")
        #expect(module.state == .alert)
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [snoozedAt.addingTimeInterval(300)])
        await fireNext(context)
        #expect(breakPosts(context).count == 2)
        #expect(context.fakeNotifier.unresolved.count == 1, "the first raise is resolved by the second")
    }

    @Test func skipResolvesAndStartsANewCycle() async throws {
        let (module, context) = try await started()
        await fireNext(context)
        module.handleAlertAction(TimeModule.skipBreakAction, payload: Data(), intent: nil)
        #expect(context.fakeNotifier.unresolved.isEmpty)
        #expect(module.leftWingItems().isEmpty)
        #expect(module.state == .hidden)
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [clock.now.addingTimeInterval(3300)])
    }

    @Test func startBreakRunsTheBreakThenANewCycleSilently() async throws {
        let (module, context) = try await started()
        await fireNext(context)
        module.handleAlertAction(TimeModule.startBreakAction, payload: Data(), intent: nil)
        #expect(context.fakeNotifier.unresolved.isEmpty)
        #expect(module.leftWingItems().isEmpty)
        #expect(module.state == .active)
        let row = try #require(module.tabSnapshot(now: clock.now).rows.first)
        #expect(row.visual == .breakRing(fractionLeft: 1))
        #expect(row.controls == [.skip])
        await fireNext(context)
        #expect(module.tabSnapshot(now: clock.now).rows.isEmpty)
        #expect(module.state == .hidden)
        #expect(breakPosts(context).count == 1, "a plain reminder's break end posts nothing")
        #expect(context.fakeScheduler.liveOneShots.map(\.date) == [clock.now.addingTimeInterval(3300)])
    }

    @Test func tabChipsDriveTheBreak() async throws {
        let (module, context) = try await started()
        await fireNext(context)
        module.perform(TimeModule.breakRowID, .startBreak)
        #expect(module.breaks?.breakEndsAt != nil)
        module.perform(TimeModule.breakRowID, .skip)
        #expect(module.breaks?.breakEndsAt == nil)
        #expect(module.tabSnapshot(now: clock.now).rows.isEmpty)
    }

    @Test func quietStylePostsWithoutPeekOrSoundButKeepsBreakDue() async throws {
        let (module, context) = try await started(["breaks.enabled": true, "breaks.style": "quiet"])
        await fireNext(context)
        let event = try #require(breakPosts(context).first)
        #expect(event.quiet, "the Notifier withholds peek and sound")
        #expect(module.leftWingItems().map(\.id) == ["break-due"])
        #expect(module.state == .alert)
    }

    @Test func customLengthsApply() async throws {
        let (module, context) = try await started([
            "breaks.enabled": true, "breaks.work": Duration.seconds(100 * 60), "breaks.length": Duration.seconds(900),
        ])
        await fireNext(context)
        let event = try #require(breakPosts(context).first)
        #expect(event.title == "Time for a break / 15 min break")
        #expect(event.body == "Focused 1 h 40 min since 14:43")
        #expect(module.tabSnapshot(now: clock.now).rows.first?.value == "15:00")
    }

    // MARK: Away

    @Test func awayTimeIsNotWork() async throws {
        let (module, context) = try await started()
        defer { withExtendedLifetime(module) {} }
        #expect(await eventually { context.fakeAway.subscribers == 1 })
        clock.advance(30 * 60)
        context.fakeAway.send(.away(since: clock.now))
        clock.advance(3 * 60)
        context.fakeAway.send(.present)
        #expect(
            await eventually {
                context.fakeScheduler.liveOneShots.map(\.date) == [Fixture.start.addingTimeInterval(58 * 60)]
            })
    }

    @Test func awayOfTheBreakLengthWhileDueTakesTheBreak() async throws {
        let (module, context) = try await started()
        #expect(await eventually { context.fakeAway.subscribers == 1 })
        await fireNext(context)
        context.fakeAway.send(.away(since: clock.now))
        #expect(await eventually { context.fakeScheduler.liveOneShots.count == 1 })
        await fireNext(context)
        #expect(context.fakeNotifier.unresolved.isEmpty, "the break counts as taken")
        #expect(module.leftWingItems().isEmpty)
    }

    @Test func sleepCountsAsAway() async throws {
        let (module, context) = try await started()
        #expect(await eventually { context.fakeAway.subscribers == 1 && context.fakePower.subscribers == 1 })
        await fireNext(context)
        context.fakePower.send(.willSleep)
        #expect(await eventually { module.breaks?.isAway == true })
        clock.advance(20 * 60)
        context.fakePower.send(.didWake)
        #expect(await eventually { context.fakeNotifier.unresolved.isEmpty })
        #expect(module.breaks?.isDue == false)
        #expect(module.breaks?.cycleStart == clock.now)
    }

    @Test func pomodoroPauseHookHoldsReminders() async throws {
        let (module, context) = try await started()
        var tracker = try #require(module.breaks)
        _ = tracker.pause(while: true, at: clock.now)
        module.breaks = tracker
        clock.advance(3 * 3600)
        module.breakTick()
        #expect(breakPosts(context).isEmpty)
    }
}
