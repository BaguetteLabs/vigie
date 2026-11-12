import AppKit
import Foundation
import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import Time

/// Story 20.6: the closed-notch Time readout (`closed_notch`, `priority`) through the module, on a fake clock,
/// scheduler and `context.away`.
@MainActor @Suite struct ClosedNotchTests {
    let clock = TestClock(Fixture.start)

    func started(_ settings: [String: any SettingValue] = [:]) async throws -> (TimeModule, FakeModuleContext) {
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

    func fireNext(_ context: FakeModuleContext) async {
        guard let date = context.fakeScheduler.liveOneShots.compactMap(\.date).min() else { return }
        clock.advance(max(0, date.timeIntervalSince(clock.now)))
        await context.fakeScheduler.fireNext()
    }

    func readout(_ module: TimeModule) throws -> TimeClosedReadoutModel {
        try #require(module.closedReadout(now: clock.now))
    }

    /// The width the item's view lays out at (no window: a hosting view's fitting size).
    func width(_ item: LeftWingItem, size: CompactSize = .short) throws -> CGFloat {
        let view = try #require(item.compactView(size))
        let hosting = NSHostingView(rootView: view.fixedSize())
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.width
    }

    /// What `ClosedNotchArbiter` does with the pooled left-wing items (VigieCore, not importable here): sort by
    /// state (descending), then priority, then order; show `slots`, count the rest as `+X`.
    static func arbitrate(_ items: [LeftWingItem], slots: Int) -> (shown: [String], overflow: Int) {
        let ranked = items.sorted { lhs, rhs in
            let (ls, rs) = (lhs.state ?? .ambient, rhs.state ?? .ambient)
            if ls != rs { return ls > rs }
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.order < rhs.order
        }
        return (ranked.prefix(slots).map(\.id), max(0, ranked.count - slots))
    }

    static func other(_ id: String, priority: Int, state: ModuleState = .active) -> LeftWingItem {
        LeftWingItem(id: id, priority: priority, state: state) { _ in AnyView(Color.clear) }
    }

    // MARK: Settings

    @Test func manifestDeclaresClosedNotchAndPriority() throws {
        let byKey = Dictionary(uniqueKeysWithValues: TimeModule.staticManifest.settings.map { ($0.key, $0) })
        #expect(byKey["closed_notch"]?.kind == .enumeration(options: ["off", "time", "ring", "both"], default: "off"))
        #expect(byKey["priority"]?.kind == .int(default: 3, min: 1, max: 99))
        for key in ["closed_notch", "priority"] {
            let label = String(localized: try #require(byKey[key]).label)
            #expect(!label.hasPrefix("time."), "\(key) label from the catalog")
        }
    }

    @Test func offByDefaultShowsNothingWhileItemsRun() async throws {
        let (module, context) = try await started()
        #expect(module.closedVariant == .off)
        module.startTimer(minutes: 5, label: "Tea")
        module.startPomodoro()
        #expect(module.state == .active)
        #expect(module.leftWingItems().isEmpty)
        #expect(module.closedReadout(now: clock.now) == nil)
        module.closedVisibility(true)
        #expect(context.fakeScheduler.liveRepeating.isEmpty, "no tick with closed_notch = off")
    }

    @Test func offStillShowsBreakDue() async throws {
        let (module, _) = try await started()
        let context = try #require(module.context as? FakeModuleContext)
        module.startPomodoro()
        await fireNext(context)
        #expect(module.leftWingItems().map(\.id) == ["break-due"])
        #expect(module.leftWingItems().first?.state == .alert)
    }

    @Test func variantChangesApplyLive() async throws {
        let (module, context) = try await started()
        module.startTimer(minutes: 5)
        #expect(module.leftWingItems().isEmpty)
        try await context.fakeSettings.set("ring", for: "closed_notch")
        try await context.fakeSettings.set(7, for: "priority")
        #expect(await eventually { module.closedVariant == .ring && module.wingPriority == 7 })
        #expect(module.leftWingItems().map(\.priority) == [7])
        try await context.fakeSettings.set("off", for: "closed_notch")
        #expect(await eventually { module.leftWingItems().isEmpty })
    }

    // MARK: Item

    @Test(arguments: ["time", "ring", "both"])
    func aVariantOffersOneActiveItemWithThePriority(variant: String) async throws {
        let (module, _) = try await started(["closed_notch": variant, "priority": 5])
        #expect(module.leftWingItems().isEmpty, "nothing running")
        module.startTimer(minutes: 5)
        module.startCountdown(to: clock.now.addingTimeInterval(3600))
        module.startPomodoro()
        #expect(module.state == .active)
        let items = module.leftWingItems()
        #expect(items.map(\.id) == ["readout"])
        #expect(items.first?.priority == 5)
        #expect(items.first?.state == .active)
        let item = try #require(items.first)
        for size in CompactSize.allCases {
            #expect(item.compactView(size) != nil)
        }
        #expect(try readout(module).variant.rawValue == variant)
    }

    @Test func defaultPriorityIsThree() async throws {
        let (module, _) = try await started(["closed_notch": "time"])
        module.startTimer(minutes: 5)
        #expect(module.leftWingItems().first?.priority == 3)
    }

    @Test func sortsByStateThenPriorityAndCountsInPlusX() async throws {
        let (module, context) = try await started(["closed_notch": "both", "priority": 3])
        module.startTimer(minutes: 5)
        let others = [
            Self.other("usage.claude", priority: 1), Self.other("usage.codex", priority: 2),
            Self.other("script", priority: 4),
        ]
        var lane = Self.arbitrate(others + module.leftWingItems(), slots: 3)
        #expect(lane.shown == ["usage.claude", "usage.codex", "readout"])
        #expect(lane.overflow == 1)
        // A lower priority than every other item: it is the one counted in `+X`.
        try await context.fakeSettings.set(9, for: "priority")
        #expect(await eventually { module.wingPriority == 9 })
        lane = Self.arbitrate(others + module.leftWingItems(), slots: 3)
        #expect(lane.shown == ["usage.claude", "usage.codex", "script"])
        #expect(lane.overflow == 1)
        // An alert item from another module goes first, whatever the priorities.
        lane = Self.arbitrate(
            [Self.other("warn", priority: 50, state: .alert)] + others + module.leftWingItems(), slots: 3)
        #expect(lane.shown.first == "warn")
        #expect(lane.overflow == 2)
        // A due break is in alert: ahead of the active items despite priority 9.
        module.startPomodoro()
        while module.pomodoro?.isDue == false, !context.fakeScheduler.liveOneShots.isEmpty {
            await fireNext(context)
        }
        #expect(module.pomodoro?.isDue == true)
        lane = Self.arbitrate(others + module.leftWingItems(), slots: 3)
        #expect(lane.shown.first == "break-due")
    }

    // MARK: Content

    @Test func timerShowsItsTimeOverItsName() async throws {
        let (module, _) = try await started(["closed_notch": "time"])
        module.startTimer(minutes: 5, label: "Tea")
        clock.advance(114)
        let model = try readout(module)
        #expect(model.value == "3:06")
        #expect(model.label == "TEA")
        #expect(model.labelIsUserText)
        #expect(!model.dashed && !model.frozen)
        #expect(abs(model.fractionLeft - 186.0 / 300) < 1e-9)
        #expect(model.showsText && !model.showsRing)
        #expect(model.accessibilityLabel == "Tea, 5 minute timer, 3 minutes, 6 seconds left, ends 14:48")
    }

    @Test func countdownShowsItsTimeAndName() async throws {
        let (module, _) = try await started(["closed_notch": "both"])
        module.startCountdown(to: clock.now.addingTimeInterval(2 * 3600), label: "Release")
        let model = try readout(module)
        #expect(model.value == "2:00:00")
        #expect(model.label == "RELEASE")
        #expect(!model.dashed)
        #expect(model.fractionLeft == 1)
        #expect(model.showsRing && model.showsText)
        #expect(model.accessibilityLabel.hasPrefix("Release, countdown to"))
        #expect(model.accessibilityLabel.contains("2 hours left"))
    }

    @Test func pomodoroWorkAndBreakLabels() async throws {
        let (module, context) = try await started(["closed_notch": "ring"])
        module.startPomodoro()
        clock.advance(60)
        var model = try readout(module)
        #expect(model.label == "WORK · 1/4")
        #expect(model.value == "24:00")
        #expect(!model.dashed)
        #expect(model.showsRing && !model.showsText)
        #expect(model.accessibilityLabel.hasPrefix("Pomodoro, Work, cycle 1 of 4, 24 minutes left"))
        await fireNext(context)
        module.startPomodoroBreak()
        model = try readout(module)
        #expect(model.label == "BREAK · 1/4")
        #expect(model.value == "5:00")
        #expect(model.dashed, "breaks draw a dashed arc")
        #expect(model.fractionLeft == 1)
        #expect(model.accessibilityLabel.hasPrefix("Pomodoro, Break, cycle 1 of 4, 5 minutes left"))
        // The long break, after the fourth work period.
        for _ in 0..<3 {
            await fireNext(context)  // break ends, next work starts
            await fireNext(context)  // work ends
            module.startPomodoroBreak()
        }
        model = try readout(module)
        #expect(model.label == "LONG BREAK")
        #expect(model.dashed)
    }

    @Test func breakReminderBreakShowsDashed() async throws {
        let (module, context) = try await started(["closed_notch": "both", "breaks.enabled": true])
        #expect(module.leftWingItems().isEmpty, "a work cycle is not an item")
        await fireNext(context)
        #expect(module.breaks?.isDue == true)
        module.startBreak()
        let model = try readout(module)
        #expect(model.label == "BREAK")
        #expect(model.dashed)
        #expect(model.value == "5:00")
        #expect(model.accessibilityLabel.hasPrefix("Break, 5 minutes left"))
    }

    @Test func nearestToEndWins() async throws {
        let (module, _) = try await started(["closed_notch": "time"])
        module.startTimer(minutes: 30, label: "Long")
        module.startCountdown(to: clock.now.addingTimeInterval(600), label: "Call")
        let short = try #require(module.startTimer(minutes: 15, label: "Short"))
        module.startPomodoro()
        #expect(try readout(module).label == "CALL")
        // A paused item yields to a running one, even nearer its end.
        clock.advance(60)
        let tea = try #require(module.startTimer(minutes: 2, label: "Tea"))
        #expect(try readout(module).label == "TEA")
        module.togglePause(tea.id)
        #expect(try readout(module).label == "CALL")
        module.remove(try #require(module.board.items.first { $0.label == "Call" }).id)
        #expect(try readout(module).label == "SHORT")
        module.remove(short.id)
        #expect(try readout(module).label == "WORK · 1/4", "the Pomodoro ends 15:08, before Long at 15:13")
    }

    @Test func pausedOnlyItemShowsFrozen() async throws {
        let (module, _) = try await started(["closed_notch": "ring"])
        let tea = try #require(module.startTimer(minutes: 5, label: "Tea"))
        module.togglePause(tea.id)
        let model = try readout(module)
        #expect(model.frozen)
        #expect(model.showsPauseMark)
        #expect(model.label == "TEA")
    }

    @Test func awayFreezesThePomodoro() async throws {
        let (module, context) = try await started(["closed_notch": "ring"])
        module.startPomodoro()
        #expect(await eventually { context.fakeAway.subscribers == 1 })
        clock.advance(120)
        context.fakeAway.send(.away(since: clock.now.addingTimeInterval(-30)))
        #expect(await eventually { module.pomodoro?.isAwayPaused == true })
        let frozen = try readout(module)
        #expect(frozen.label == "AWAY · PAUSED")
        #expect(frozen.frozen)
        #expect(frozen.showsPauseMark, "ring-only adds the pause mark")
        #expect(frozen.value == "23:30")
        #expect(frozen.accessibilityLabel.contains("away, paused since"))
        clock.advance(300)
        #expect(try readout(module).value == "23:30", "the value is frozen")
        #expect(try readout(module).fractionLeft == frozen.fractionLeft, "the ring is frozen")
        // `both` keeps the label, and draws no pause mark.
        try await context.fakeSettings.set("both", for: "closed_notch")
        #expect(await eventually { module.closedVariant == .both })
        #expect(try readout(module).frozen)
        #expect(try !readout(module).showsPauseMark)
        context.fakeAway.send(.present)
        #expect(await eventually { module.pomodoro?.isAwayPaused == false })
        #expect(try readout(module).label == "WORK · 1/4")
        #expect(try !readout(module).frozen)
    }

    @Test func ringVariantDrawsBreakDueRingOnly() async throws {
        let (module, context) = try await started(["closed_notch": "ring"])
        module.startPomodoro()
        await fireNext(context)
        let ring = try #require(module.leftWingItems().first)
        #expect(ring.id == "break-due")
        #expect(module.closedReadout(now: clock.now) == nil, "one Time item: BREAK DUE")
        #expect(try width(ring) <= 24, "ring alone, with the center triangle")
        try await context.fakeSettings.set("both", for: "closed_notch")
        #expect(await eventually { module.closedVariant == .both })
        let full = try #require(module.leftWingItems().first)
        #expect(try width(full) > 30, "ring + 5:00 over BREAK DUE")
        #expect(try width(full, size: .icon) <= 24)
    }

    // MARK: Redraw

    @Test func ticksOncePerSecondOnlyWhileShown() async throws {
        let (module, context) = try await started(["closed_notch": "time"])
        module.closedVisibility(true)
        #expect(context.fakeScheduler.liveRepeating.isEmpty, "nothing to show, no tick")
        module.closedVisibility(false)
        module.startTimer(minutes: 5, label: "Tea")
        #expect(context.fakeScheduler.liveRepeating.isEmpty, "not shown, no tick")
        module.closedVisibility(true)
        module.closedVisibility(true)  // a second display
        #expect(context.fakeScheduler.liveRepeating.map(\.interval) == [.seconds(1)])
        let before = module.displayNow
        clock.advance(1)
        module.tick()
        #expect(module.displayNow == before.addingTimeInterval(1))
        #expect(module.closedReadout()?.value == "4:59")
        module.closedVisibility(false)
        #expect(context.fakeScheduler.liveRepeating.count == 1, "still on the other display")
        module.closedVisibility(false)
        #expect(context.fakeScheduler.liveRepeating.isEmpty, "hidden: no tick")
    }

    @Test func tickStopsWhenTheReadoutGoesAway() async throws {
        let (module, context) = try await started(["closed_notch": "both"])
        let tea = try #require(module.startTimer(minutes: 5))
        module.closedVisibility(true)
        #expect(context.fakeScheduler.liveRepeating.count == 1)
        module.remove(tea.id)
        #expect(context.fakeScheduler.liveRepeating.isEmpty, "nothing left to show")
        module.startTimer(minutes: 5)
        #expect(context.fakeScheduler.liveRepeating.count == 1)
        try await context.fakeSettings.set("off", for: "closed_notch")
        #expect(await eventually { context.fakeScheduler.liveRepeating.isEmpty }, "off: no tick")
    }

    @Test func tabAndReadoutShareOneTick() async throws {
        let (module, context) = try await started(["closed_notch": "time"])
        module.startTimer(minutes: 5)
        module.tabVisibility(true)
        module.closedVisibility(true)
        #expect(context.fakeScheduler.liveRepeating.count == 1)
        module.tabVisibility(false)
        #expect(context.fakeScheduler.liveRepeating.count == 1, "the readout still shows")
        module.closedVisibility(false)
        #expect(context.fakeScheduler.liveRepeating.isEmpty)
    }

    @Test func stopEndsTheTick() async throws {
        let (module, context) = try await started(["closed_notch": "time"])
        module.startTimer(minutes: 5)
        module.closedVisibility(true)
        await module.stop()
        #expect(context.fakeScheduler.liveRepeating.isEmpty)
    }

    // MARK: Privacy

    @Test func privacyMasksTheNameNotThePhase() async throws {
        let (module, _) = try await started(["closed_notch": "time"])
        module.startTimer(minutes: 5, label: "Dentist")
        let masked = try readout(module).redacted()
        #expect(masked.label == PrivacyMask.text)
        #expect(!masked.accessibilityLabel.contains("Dentist"))
        #expect(masked.value == "5:00")
        module.remove(try #require(module.board.items.first).id)
        module.startPomodoro()
        #expect(try readout(module).redacted().label == "WORK · 1/4")
    }
}
