import AgentKit
import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import AgentsUsage

/// Story 7.5: pace indicator (FR52, UX-DR12, UX-DR16, UX-DR58, UX-DR73).
@MainActor @Suite struct PaceTests {
    static let now = Date(timeIntervalSince1970: 1_793_000_000)

    /// A window `used` percent used whose reset is `resetIn` seconds after `now`.
    static func window(_ name: String, used: Double, resetIn: TimeInterval) -> UsageWindow {
        UsageWindow(name: name, used: used, limit: nil, resetsAt: now + resetIn)
    }

    @Test func manifestDeclaresPaceAndTolerance() {
        let byKey = Dictionary(
            uniqueKeysWithValues: AgentsUsageModule.staticManifest.settings.map { ($0.key, $0) })
        #expect(byKey["pace"]?.kind == .bool(default: true))
        #expect(byKey["pace_tolerance"]?.kind == .int(default: 5, min: 0, max: 50))
        #expect(byKey["pace"]?.scope == .synced && byKey["pace_tolerance"]?.scope == .synced)
        #expect(byKey["pace"].map { String(localized: $0.label) } == "Pace indicator")
    }

    @Test func pacedWindowIs5hElseWeekly() throws {
        // 5h resets in 2 h: 60 % elapsed. Weekly is not paced while a 5h exists.
        let plan = PlanState(windows: [
            Self.window("5h", used: 40, resetIn: 2 * 3600), Self.window("weekly", used: 10, resetIn: 3 * 86400),
        ])
        let both = try #require(
            QuotaDialModel(providerName: "Claude", plan: plan, rings: .fiveHourAndWeekly, pace: true, now: Self.now))
        #expect(abs((both.primary?.elapsedFraction ?? -1) - 0.6) < 1e-9)
        #expect(both.secondary?.elapsedFraction == nil)
        #expect(both.primary?.pace == .within)

        // No 5h: weekly is paced (3.5 days left of 7 = 50 %).
        let weeklyOnly = try #require(
            QuotaDialModel(
                providerName: "Claude",
                plan: PlanState(windows: [Self.window("weekly", used: 70, resetIn: 3.5 * 86400)]),
                rings: .fiveHour, pace: true, now: Self.now))
        #expect(abs((weeklyOnly.primary?.elapsedFraction ?? -1) - 0.5) < 1e-9)
        #expect(weeklyOnly.primary?.pace == .ahead)

        // A daily-only plan has no paced window.
        let daily = try #require(
            QuotaDialModel(
                providerName: "Gemini", plan: PlanState(windows: [Self.window("daily", used: 70, resetIn: 3600)]),
                rings: .fiveHour, pace: true, now: Self.now))
        #expect(daily.primary?.elapsedFraction == nil && daily.primary?.pace == nil)
    }

    @Test func toleranceAndPaceOffComeFromTheSettings() throws {
        // 60 % elapsed, 66 % used: ahead with tolerance 5, within with 6.
        let plan = PlanState(windows: [Self.window("5h", used: 66, resetIn: 2 * 3600)])
        let five = try #require(
            QuotaDialModel(providerName: "Claude", plan: plan, rings: .fiveHour, pace: true, now: Self.now))
        #expect(five.primary?.pace == .ahead)
        let six = try #require(
            QuotaDialModel(
                providerName: "Claude", plan: plan, rings: .fiveHour, pace: true, paceTolerance: 6, now: Self.now))
        #expect(six.primary?.pace == .within)
        let off = try #require(
            QuotaDialModel(providerName: "Claude", plan: plan, rings: .fiveHour, pace: false, now: Self.now))
        #expect(off.primary?.elapsedFraction == nil && off.primary?.pace == nil)
    }

    @Test func aWindowWithoutResetTimeIsNotPaced() throws {
        let plan = PlanState(windows: [UsageWindow(name: "5h", used: 90, limit: nil, resetsAt: nil)])
        let model = try #require(
            QuotaDialModel(providerName: "Claude", plan: plan, rings: .fiveHour, pace: true, now: Self.now))
        #expect(model.primary?.pace == nil)
    }

    @Test func settingsAreReadAndFollowedLive() async throws {
        let harness = try PlanHarness(
            plan: true, script: [.success([Self.window("5h", used: 66, resetIn: 2 * 3600)])])
        let settings = MemoryAdapterSettings(["pace_tolerance": 10])
        let context = FakeModuleContext(directory: harness.sandbox.storage, settings: settings)
        try await harness.module.start(context: context)
        await harness.module.waitForInitialPlanRefresh()
        // Harness clock = `now`: 60 % elapsed, 66 % used, tolerance 10 → within.
        #expect(harness.module.ringSettings.pace && harness.module.ringSettings.paceTolerance == 10)
        #expect(harness.module.quotaRings.first?.model.primary?.pace == .within)
        try await settings.set(2, for: "pace_tolerance")
        await settle()
        #expect(harness.module.quotaRings.first?.model.primary?.pace == .ahead)
        try await settings.set(false, for: "pace")
        await settle()
        #expect(harness.module.quotaRings.first?.model.primary?.elapsedFraction == nil)
        await harness.module.stop()
    }

    @Test func theTickAdvancesWithTheClock() async throws {
        let harness = try PlanHarness(
            plan: true, script: [.success([Self.window("5h", used: 50, resetIn: 2 * 3600)])])
        try await harness.start()
        #expect(harness.context.fakeScheduler.intervals.contains(AgentsUsageModule.clockInterval))
        let before = try #require(harness.module.quotaRings.first?.model.primary?.elapsedFraction)
        harness.clock.advance(1800)
        await harness.context.fakeScheduler.fire()
        let after = try #require(harness.module.quotaRings.first?.model.primary?.elapsedFraction)
        #expect(abs(after - before - 0.1) < 1e-9)
        await harness.module.stop()
    }

    @Test func aheadOfPaceRaisesNothing() async throws {
        // 70 % used at 10 % elapsed: far ahead of pace, under the warning threshold.
        let harness = try PlanHarness(
            plan: true, script: [.success([Self.window("5h", used: 70, resetIn: 4.5 * 3600)])])
        try await harness.start()
        #expect(harness.module.quotaRings.first?.model.primary?.pace == .ahead)
        #expect(harness.module.state == .ambient)
        #expect(harness.notifier.posted.isEmpty)
        #expect(harness.module.leftWingItems().first?.state == nil)
        await harness.module.stop()
    }
}
