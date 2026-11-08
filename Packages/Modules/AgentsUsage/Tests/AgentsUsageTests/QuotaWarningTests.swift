import AgentKit
import Foundation
@_spi(Host) import ModuleKit
import Testing
import VigieUI

@testable import AgentsUsage

/// Story 7.6: quota warning (FR15, FR51, FR53, UX-DR58, UX-DR91, AD-13 `usage.quota_warning`, A36).
@MainActor @Suite struct QuotaWarningTests {
    /// 2026-11-08 14:48 UTC.
    static let start = Date(timeIntervalSince1970: 1_794_149_280)

    static func window(_ name: String, used: Double, resetIn: TimeInterval) -> UsageWindow {
        UsageWindow(name: name, used: used, limit: nil, resetsAt: start + resetIn)
    }

    /// A module with one Claude provider, a UTC calendar, a movable clock and recording notifier and host.
    @MainActor struct Harness {
        let clock = FakeClock(QuotaWarningTests.start)
        let notifier = RecordingNotifier()
        let host = RecordingHost()
        let module: AgentsUsageModule

        init(_ settings: RingSettings = RingSettings()) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let clock = clock
            module = AgentsUsageModule(
                adapters: AgentAdapters([ProviderAdapter.plan("claude", "Claude")]), calendar: calendar,
                now: { clock.now })
            module.notifier = notifier
            module.host = host
            module.ringSettings = settings
        }

        func plan(_ windows: UsageWindow...) {
            module.planStates["claude"] = PlanState(windows: windows)
        }
    }

    @Test func manifestDeclaresTheKindAndTheSettings() {
        let manifest = AgentsUsageModule.staticManifest
        #expect(manifest.alertKinds.contains("usage.quota_warning"))
        let byKey = Dictionary(uniqueKeysWithValues: manifest.settings.map { ($0.key, $0) })
        #expect(byKey["warn_threshold"]?.kind == .int(default: 80, min: 1, max: 100))
        #expect(byKey["warn_action"]?.kind == .enumeration(options: ["alert", "visual"], default: "alert"))
        #expect(byKey["providers.claude.warn_threshold"]?.kind == .int(default: 0, min: 0, max: 100))
        #expect(manifest.settings.allSatisfy { $0.scope == .synced })
        #expect(
            byKey["providers.claude.warn_threshold"].map { String(localized: $0.label) }
                == "Claude warning threshold (percent used)")
    }

    @Test func thresholdCrossingPerWindow() throws {
        let harness = Harness()
        harness.plan(Self.window("5h", used: 79, resetIn: 3600), Self.window("weekly", used: 40, resetIn: 86400))
        var ring = try #require(harness.module.quotaRings.first)
        #expect(!ring.model.hasWarning && harness.module.state == .ambient)
        #expect(harness.notifier.posted.isEmpty)

        harness.plan(Self.window("5h", used: 80, resetIn: 3600), Self.window("weekly", used: 40, resetIn: 86400))
        ring = try #require(harness.module.quotaRings.first)
        #expect(ring.model.primary?.isWarning == true && ring.model.secondary?.isWarning == false)
        #expect(harness.module.state == .alert)
        #expect(harness.module.leftWingItems().first?.state == .alert)

        // The weekly window alone, on the outer ring.
        harness.plan(Self.window("5h", used: 10, resetIn: 3600), Self.window("weekly", used: 95, resetIn: 86400))
        ring = try #require(harness.module.quotaRings.first)
        #expect(ring.model.primary?.isWarning == false && ring.model.secondary?.isWarning == true)
        #expect(ring.model.hasWarning)
    }

    @Test func aWarningOnAWindowTheDialDoesNotDrawStillShows() throws {
        let harness = Harness(RingSettings(rings: .fiveHour))
        harness.plan(Self.window("5h", used: 10, resetIn: 3600), Self.window("weekly", used: 95, resetIn: 86400))
        let ring = try #require(harness.module.quotaRings.first)
        #expect(!ring.model.isNested && ring.model.hiddenWarning && ring.model.hasWarning)
        #expect(harness.notifier.posted.count == 1)
    }

    @Test func theProviderOverrideWins() throws {
        let harness = Harness(RingSettings(warnThreshold: 80, providerWarnThreshold: ["claude": 90]))
        harness.plan(Self.window("5h", used: 85, resetIn: 3600))
        #expect(harness.module.quotaRings.first?.model.hasWarning == false)
        #expect(harness.notifier.posted.isEmpty)
        harness.plan(Self.window("5h", used: 90, resetIn: 3600))
        #expect(harness.module.quotaRings.first?.model.hasWarning == true)
        #expect(harness.notifier.posted.count == 1)
        // 0 inherits the general threshold.
        #expect(RingSettings(providerWarnThreshold: ["claude": 0]).warnThreshold(for: "claude") == 80)
    }

    @Test func postedOncePerProviderWindowAndReset() {
        let harness = Harness()
        harness.plan(Self.window("5h", used: 82, resetIn: 3600))
        harness.plan(Self.window("5h", used: 84, resetIn: 3600))
        harness.module.tickClock()
        #expect(harness.notifier.posted.count == 1)
        let reset = (Self.start + 3600).formatted(.iso8601)
        #expect(harness.notifier.posted.first?.dedupeKey == "quota:claude:5h:\(reset)")

        // Dropping below then crossing again in the same window: no second alert.
        harness.plan(Self.window("5h", used: 60, resetIn: 3600))
        harness.plan(Self.window("5h", used: 85, resetIn: 3600))
        #expect(harness.notifier.posted.count == 1)

        // Weekly crosses too: its own alert.
        harness.plan(Self.window("5h", used: 85, resetIn: 3600), Self.window("weekly", used: 81, resetIn: 86400))
        #expect(harness.notifier.posted.count == 2)
        #expect(harness.notifier.posted.last?.dedupeKey?.hasPrefix("quota:claude:weekly:") == true)

        // The next 5h window (new reset time) alerts again.
        harness.plan(
            Self.window("5h", used: 81, resetIn: 5 * 3600 + 3600), Self.window("weekly", used: 81, resetIn: 86400))
        #expect(harness.notifier.posted.count == 3)
    }

    @Test func resolvesWhenUsageDropsBelow() {
        let harness = Harness()
        harness.plan(Self.window("5h", used: 82, resetIn: 3600))
        #expect(harness.notifier.resolved == 0)
        harness.plan(Self.window("5h", used: 79, resetIn: 3600))
        #expect(harness.notifier.resolved == 1)
        #expect(harness.module.state == .ambient)
    }

    @Test func resolvesWhenTheWindowResets() {
        let harness = Harness()
        harness.plan(Self.window("5h", used: 90, resetIn: 600))
        #expect(harness.module.state == .alert)
        harness.clock.advance(601)
        harness.module.tickClock()
        #expect(harness.notifier.resolved == 1)
        #expect(harness.module.quotaRings.first?.model.hasWarning == false)
        #expect(harness.module.state == .ambient)
    }

    @Test func visualModeChangesStateOnly() {
        let harness = Harness(RingSettings(warnAction: .visual))
        harness.plan(Self.window("5h", used: 90, resetIn: 3600))
        #expect(harness.notifier.posted.isEmpty)
        #expect(harness.module.state == .active)
        #expect(harness.module.leftWingItems().first?.state == .active)
        #expect(harness.module.quotaRings.first?.model.hasWarning == true)
    }

    @Test func switchingToVisualResolvesTheOpenAlert() async throws {
        let harness = try PlanHarness(plan: true, script: [.success([Self.window("5h", used: 90, resetIn: 3600)])])
        let settings = MemoryAdapterSettings()
        let context = FakeModuleContext(directory: harness.sandbox.storage, settings: settings)
        try await harness.module.start(context: context)
        await harness.module.waitForInitialPlanRefresh()
        #expect(context.recordingNotifier.posted.map(\.kind) == ["usage.quota_warning"])
        #expect(harness.module.state == .alert)
        try await settings.set("visual", for: "warn_action")
        await settle()
        #expect(context.recordingNotifier.resolved == 1)
        #expect(harness.module.state == .active)
        try await settings.set(95, for: "warn_threshold")
        await settle()
        #expect(harness.module.state == .ambient)
        await harness.module.stop()
    }

    @Test func titleDetailAndAction() throws {
        let harness = Harness()
        // Resets at 16:40 UTC, 1 h 52 min from 14:48.
        harness.plan(Self.window("5h", used: 82, resetIn: 112 * 60))
        let event = try #require(harness.notifier.posted.first)
        #expect(event.kind == "usage.quota_warning")
        #expect(event.severity == .warn)
        #expect(event.title == "CLAUDE · 5H 82 %")
        #expect(event.body == "RESET 16:40 · IN 1H52")
        #expect(event.category == nil)
        #expect(event.action == .module(id: "agents.usage", actionID: "open-usage", payload: Data("claude".utf8)))
    }

    @Test func detailFormats() {
        let utc = TimeZone(identifier: "UTC")!
        let detail = { (seconds: TimeInterval) in
            AgentsUsageModule.quotaDetail(resetsAt: Self.start + seconds, now: Self.start, timeZone: utc)
        }
        #expect(detail(45 * 60) == "RESET 15:33 · IN 0H45")
        #expect(detail(23 * 3600 + 59 * 60) == "RESET 14:47 · IN 23H59")
        // A day or more: weekday and days + hours (2026-11-08 is a Sunday).
        #expect(detail(3 * 86400 + 4 * 3600) == "RESET WED 18:48 · IN 3D04")
        // Already past: nothing left.
        #expect(detail(-60) == "RESET 14:47 · IN 0H00")
        let paris = TimeZone(identifier: "Europe/Paris")!
        #expect(
            AgentsUsageModule.quotaDetail(resetsAt: Self.start + 3600, now: Self.start, timeZone: paris)
                == "RESET 16:48 · IN 1H00")
        let weekly = QuotaDialModel.Window(kind: .weekly, fraction: 0.91)
        #expect(AgentsUsageModule.quotaTitle(provider: "Claude", window: weekly) == "CLAUDE · WEEK 91 %")
    }

    @Test func openUsageOpensTheModulesTab() {
        let harness = Harness()
        let intent = UserIntent()
        harness.module.handleAlertAction("open-usage", payload: Data("claude".utf8), intent: intent)
        harness.module.handleAlertAction("unknown", payload: Data(), intent: intent)
        #expect(harness.host.openedTabs == [intent])
        // The host lands on this module's tab: the Usage tab (Story 7.7).
        #expect(harness.module.expandedView() != nil)
    }

    @Test func stopResolvesOpenAlerts() async throws {
        let harness = try PlanHarness(plan: true, script: [.success([Self.window("5h", used: 90, resetIn: 3600)])])
        try await harness.start()
        #expect(harness.notifier.posted.count == 1)
        await harness.module.stop()
        #expect(harness.notifier.resolved == 1)
    }

    @Test func paceAheadAloneRaisesNothing() {
        let harness = Harness()
        // 79 % used with 10 % of the window gone: far ahead of pace, under the threshold.
        harness.plan(Self.window("5h", used: 79, resetIn: 4.5 * 3600))
        #expect(harness.module.quotaRings.first?.model.primary?.pace == .ahead)
        #expect(harness.notifier.posted.isEmpty && harness.module.state == .ambient)
    }
}
