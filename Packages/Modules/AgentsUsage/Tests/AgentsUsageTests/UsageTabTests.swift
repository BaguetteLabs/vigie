import AgentKit
import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import AgentsUsage

/// Story 7.7: the Usage tab snapshot (FR54, UX-DR31, UX-DR44, UX-DR58, UX-DR78, UX-DR100).
@MainActor @Suite struct UsageTabSnapshotTests {
    /// 2026-11-08 14:48 UTC.
    nonisolated static let start = Date(timeIntervalSince1970: 1_794_149_280)

    static func window(_ name: String, used: Double, resetIn: TimeInterval) -> UsageWindow {
        UsageWindow(name: name, used: used, limit: nil, resetsAt: start + resetIn)
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func module(_ adapters: [any AgentAdapter], settings: RingSettings = RingSettings(), ingested: Bool = true)
        -> AgentsUsageModule
    {
        let module = AgentsUsageModule(
            adapters: AgentAdapters(adapters), calendar: utc, now: { UsageTabSnapshotTests.start })
        module.ringSettings = settings
        if ingested { module.lastIngest = IngestReport() }
        return module
    }

    static func windows(_ card: UsageProviderCardModel) throws -> (QuotaDialModel, [UsageBarModel]) {
        guard case .windows(let dial, let bars) = card.content else { throw RequireError(message: "no windows") }
        return (dial, bars)
    }

    @Test func maxPlanCard() throws {
        let module = Self.module([ProviderAdapter.plan("claude", "Claude")])
        // 1h52 left of 5h: 63% elapsed; 41% of the week at 32% elapsed.
        module.planStates["claude"] = PlanState(windows: [
            Self.window("weekly", used: 41, resetIn: 0.68 * 7 * 86400),
            Self.window("5h", used: 62, resetIn: 112 * 60),
        ])
        let card = try #require(module.usageTabSnapshot().providers.first)
        #expect(card.id == "claude" && card.name == "claude")
        #expect(card.meta.kind == .warn(threshold: 80) && card.meta.text == "WARN 80%")
        let (dial, bars) = try Self.windows(card)
        #expect(dial.isNested && dial.primary?.kind == .fiveHour && dial.secondary?.kind == .weekly)
        #expect(bars.map(\.window.kind) == [.fiveHour, .weekly])
        #expect(bars[0].reset == UsageReset(time: "16:40", remaining: "1H52"))
        #expect(bars[0].elapsedText == "ELAPSED 63%")
        #expect(bars[0].paceLabel?.text == "WITHIN PACE")
        #expect(bars[1].reset?.remaining == "4D18")
        #expect(bars[1].paceLabel?.text == "AHEAD OF PACE · +9")
        // Both windows are paced on the tab (the closed ring paces 5h only).
        #expect(dial.secondary?.elapsedFraction != nil)
    }

    @Test func metaVariantsFollowThePlanWindows() throws {
        let module = Self.module([ProviderAdapter.plan("claude", "Claude")])
        module.planStates["claude"] = PlanState(windows: [Self.window("weekly", used: 47, resetIn: 86400)])
        var card = try #require(module.usageTabSnapshot().providers.first)
        #expect(card.meta.kind == .weeklyOnly && card.meta.text == "WEEKLY ONLY")
        #expect(try Self.windows(card).0.isNested == false)

        module.planStates["claude"] = PlanState(windows: [Self.window("daily", used: 18, resetIn: 3600)])
        card = try #require(module.usageTabSnapshot().providers.first)
        #expect(card.meta.text == "DAILY QUOTA ONLY")

        module.planStates["claude"] = PlanState(
            windows: [Self.window("5h", used: 10, resetIn: 3600)], fetchedAt: Self.start - 600, isStale: true)
        card = try #require(module.usageTabSnapshot().providers.first)
        #expect(card.meta.stale?.hasPrefix("STALE · ") == true)
        #expect(try Self.windows(card).0.stale)

        let custom = Self.module(
            [ProviderAdapter.plan("claude", "Claude")], settings: RingSettings(providerWarnThreshold: ["claude": 90]))
        custom.planStates["claude"] = PlanState(windows: [Self.window("5h", used: 10, resetIn: 3600)])
        #expect(custom.usageTabSnapshot().providers.first?.meta.text == "WARN 90%")
    }

    @Test func warningWinsOverPaceAhead() throws {
        let module = Self.module([ProviderAdapter.plan("claude", "Claude")])
        module.planStates["claude"] = PlanState(windows: [Self.window("5h", used: 95, resetIn: 4 * 3600)])
        let (dial, bars) = try Self.windows(try #require(module.usageTabSnapshot().providers.first))
        #expect(bars[0].window.pace == .ahead)
        #expect(bars[0].paceLabel?.text == "WARN · ≥ 80%")
        #expect(bars[0].fill == .warning)
        #expect(dial.hasWarning)
    }

    @Test func paceOffDropsTheMarker() throws {
        let module = Self.module([ProviderAdapter.plan("claude", "Claude")], settings: RingSettings(pace: false))
        module.planStates["claude"] = PlanState(windows: [Self.window("5h", used: 70, resetIn: 4 * 3600)])
        let (_, bars) = try Self.windows(try #require(module.usageTabSnapshot().providers.first))
        #expect(bars[0].markerFraction == nil && bars[0].paceLabel == nil)
        #expect(bars[0].elapsedText == "ELAPSED 20%")
    }

    @Test func readingLogsBeforeTheFirstIngest() {
        let module = Self.module([ProviderAdapter.plan("claude", "Claude")], ingested: false)
        module.planStates["claude"] = PlanState(windows: [Self.window("5h", used: 62, resetIn: 3600)])
        let card = module.usageTabSnapshot().providers.first
        #expect(card?.content == .readingLogs)
        #expect(card?.meta.text == "WARN 80%")
    }

    @Test func localOnlyProvider() throws {
        let root = FileManager.default.temporaryDirectory
        let module = Self.module([LogAdapter(reader: FixtureLogReader(root: root))])
        let card = try #require(module.usageTabSnapshot().providers.first)
        #expect(card.meta.kind == .localOnly && card.meta.text == "LOCAL LOGS ONLY")
        #expect(card.content == .noPlanWindows)
        #expect(card.name == "Claude")
    }

    @Test func providersFollowTheUserOrder() {
        let adapters: [any AgentAdapter] = [
            ProviderAdapter.plan("claude", "Claude"), ProviderAdapter.plan("codex", "Codex"),
            ProviderAdapter.plan("gemini", "Gemini"),
        ]
        let module = Self.module(adapters, settings: RingSettings(order: ["gemini", "claude"]))
        for id in ["claude", "codex", "gemini"] {
            module.planStates[UsageAccountKey(stringLiteral: id)] = PlanState(windows: [
                Self.window("5h", used: 5, resetIn: 3600)
            ])
        }
        let snapshot = module.usageTabSnapshot()
        #expect(snapshot.providers.map(\.id) == ["gemini", "claude", "codex"])
        #expect(snapshot.overflows)
    }

    @Test func noProviderIsTheEmptyState() {
        // A plan adapter with plan limits off and no local logs is no usage provider.
        let module = Self.module([ProviderAdapter.plan("claude", "Claude")])
        #expect(module.usageTabSnapshot().isEmpty)
        #expect(Self.module([]).usageTabSnapshot().isEmpty)
    }

    @Test func theModuleOffersTheTab() {
        let opened = PaneLog()
        let module = AgentsUsageModule(adapters: AgentAdapters([]), openSettings: { opened.panes.append($0) })
        #expect(module.expandedView() != nil)
        #expect(module.homeCard() != nil)
        module.openSettings?(AgentsUsageModule.settingsPane)
        #expect(opened.panes == ["agents.usage"])
        #expect(String(localized: module.manifest.name) == "Usage")
    }
}

@MainActor final class PaneLog: Sendable {
    var panes: [String] = []
}
