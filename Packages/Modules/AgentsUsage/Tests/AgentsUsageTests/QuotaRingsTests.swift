import AgentKit
import Foundation
import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import AgentsUsage

/// A provider with fixed windows, for ring tests that set `planStates` directly.
struct FixedProvider: UsageProvider {
    let id: AgentID
    let display: String
    var name: LocalizedStringResource { LocalizedStringResource(stringLiteral: display) }
    var refreshInterval: Duration { .seconds(300) }
    func fetch(context: any AdapterContext) async throws -> UsageSnapshot {
        UsageSnapshot(windows: [], fetchedAt: Date(timeIntervalSince1970: 0))
    }
}

struct ProviderAdapter: AgentAdapter {
    let id: AgentID
    let provider: FixedProvider?
    var name: LocalizedStringResource { LocalizedStringResource(stringLiteral: id.rawValue) }
    var capabilities: Set<AgentCapability> { provider == nil ? [.logReader] : [.usage] }
    var usageProvider: (any UsageProvider)? { provider }
    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] { [] }

    static func plan(_ id: AgentID, _ name: String) -> ProviderAdapter {
        ProviderAdapter(id: id, provider: FixedProvider(id: id, display: name))
    }
}

/// Story 7.4: quota rings in the closed notch (FR50, FR53, UX-DR16, UX-DR17, UX-DR58, UX-DR73, A18, A69).
@MainActor @Suite struct QuotaRingsTests {
    static let daily = UsageWindow(name: "daily", used: 40, limit: nil, resetsAt: nil)

    static func module(_ adapters: [ProviderAdapter]) -> AgentsUsageModule {
        AgentsUsageModule(adapters: AgentAdapters(adapters))
    }

    @Test func manifestDeclaresTheRingSettings() {
        let settings = AgentsUsageModule.staticManifest.settings
        let keys = settings.map(\.key)
        #expect(Array(keys.prefix(3)) == ["priority", "order", "rings"])
        #expect(keys.contains("providers.claude.priority"))
        let byKey = Dictionary(uniqueKeysWithValues: settings.map { ($0.key, $0) })
        #expect(settings[0].kind == .int(default: 2, min: 1, max: 99))
        #expect(settings[1].kind == .list(of: .string, default: []))
        #expect(settings[2].kind == .enumeration(options: ["5h", "5h+weekly"], default: "5h+weekly"))
        #expect(byKey["providers.claude.priority"]?.kind == .int(default: 0, min: 0, max: 99))
        #expect(settings.allSatisfy { $0.scope == .synced })
        #expect(String(localized: settings[2].label) == "Quota rings")
        #expect(byKey["providers.claude.priority"].map { String(localized: $0.label) } == "Claude ring priority")
    }

    @Test func noProviderMeansAnEmptyLeftWing() {
        let module = Self.module([])
        #expect(module.leftWingItems().isEmpty)
        #expect(module.state == .hidden)
    }

    @Test func localOnlyProvidersDrawNoRing() {
        let module = Self.module([ProviderAdapter(id: "claude", provider: nil), .plan("codex", "Codex")])
        // Codex offers a provider but has no windows yet; Claude has local logs only.
        #expect(module.leftWingItems().isEmpty)
        module.planStates["codex"] = PlanState(windows: [])
        #expect(module.leftWingItems().isEmpty && module.state == .hidden)
        module.planStates["codex"] = PlanState(windows: [fiveHour])
        #expect(module.leftWingItems().map(\.id) == ["ring.codex"])
        #expect(module.state == .ambient)
        module.planStates["codex"] = nil
        #expect(module.state == .hidden)
    }

    @Test func defaultsArePriorityTwoAndRegistrationOrder() {
        let module = Self.module([.plan("claude", "Claude"), .plan("codex", "Codex"), .plan("gemini", "Gemini")])
        for id in ["gemini", "claude", "codex"] {
            module.planStates[UsageAccountKey(stringLiteral: id)] = PlanState(windows: [fiveHour])
        }
        let items = module.leftWingItems()
        #expect(items.map(\.id) == ["ring.claude", "ring.codex", "ring.gemini"])
        #expect(items.map(\.priority) == [2, 2, 2])
        #expect(items.map(\.order) == [0, 1, 2])
    }

    @Test func orderAndPerProviderPriorityOverride() {
        let module = Self.module([.plan("claude", "Claude"), .plan("codex", "Codex"), .plan("gemini", "Gemini")])
        for id in ["claude", "codex", "gemini"] {
            module.planStates[UsageAccountKey(stringLiteral: id)] = PlanState(windows: [fiveHour])
        }
        module.ringSettings = RingSettings(priority: 4, order: ["gemini", "claude"], providerPriority: ["codex": 1])
        let items = module.leftWingItems()
        #expect(items.map(\.id) == ["ring.codex", "ring.gemini", "ring.claude"])
        #expect(items.map(\.priority) == [1, 4, 4])
        // Listed first by `order`; codex is unlisted so it ranks after the listed ones among equal priorities.
        #expect(items.map(\.order) == [3, 0, 1])
    }

    @Test func settingsAreReadAtStartAndFollowedLive() async throws {
        let harness = try PlanHarness(plan: true, script: [.success([fiveHour, weekly])])
        let settings = MemoryAdapterSettings(["priority": 5, "rings": "5h", "providers.claude.priority": 0])
        let context = FakeModuleContext(directory: harness.sandbox.storage, settings: settings)
        try await harness.module.start(context: context)
        await harness.module.waitForInitialPlanRefresh()
        let item = try #require(harness.module.leftWingItems().first)
        #expect(item.priority == 5)
        #expect(harness.module.quotaRings.first?.model.isNested == false)

        try await settings.set(1, for: "providers.claude.priority")
        try await settings.set("5h+weekly", for: "rings")
        await settle()
        #expect(harness.module.leftWingItems().first?.priority == 1)
        #expect(harness.module.quotaRings.first?.model.isNested == true)
        await harness.module.stop()
    }

    @Test func ringsSelectNesting() throws {
        let plan = PlanState(windows: [fiveHour, weekly])
        let nested = try #require(QuotaDialModel(providerName: "Claude", plan: plan, rings: .fiveHourAndWeekly))
        #expect(nested.isNested && nested.primary?.kind == .fiveHour && nested.secondary?.kind == .weekly)
        #expect(nested.primary?.percent == 37 && nested.secondary?.percent == 12)
        let only5h = try #require(QuotaDialModel(providerName: "Claude", plan: plan, rings: .fiveHour))
        #expect(!only5h.isNested && only5h.primary?.kind == .fiveHour)
    }

    @Test func aPlanWithout5hShowsItsOnlyWindow() throws {
        for rings in RingsMode.allCases {
            let weeklyPlan = try #require(
                QuotaDialModel(providerName: "Claude", plan: PlanState(windows: [weekly]), rings: rings))
            #expect(!weeklyPlan.isNested && weeklyPlan.primary?.kind == .weekly)
            #expect(weeklyPlan.readoutLabel == "CLAUDE · WEEK")
            let dailyPlan = try #require(
                QuotaDialModel(providerName: "Gemini", plan: PlanState(windows: [Self.daily]), rings: rings))
            #expect(dailyPlan.primary?.kind == .daily && dailyPlan.primary?.percent == 40)
        }
        let unknown = UsageWindow(name: "seven_day_opus", used: 3, limit: nil, resetsAt: nil)
        #expect(QuotaDialModel(providerName: "Claude", plan: PlanState(windows: [unknown]), rings: .fiveHour) == nil)
        let limited = UsageWindow(name: "5h", used: 30, limit: 120, resetsAt: nil)
        let model = QuotaDialModel(providerName: "Claude", plan: PlanState(windows: [limited]), rings: .fiveHour)
        #expect(model?.primary?.percent == 25)
    }

    @Test func aStaleRingKeepsItsLastValue() async throws {
        let harness = try PlanHarness(plan: true, script: [.success([fiveHour, weekly]), .failure(.formatChanged)])
        try await harness.start()
        harness.module.ringSettings.pace = false
        #expect(harness.module.quotaRings.first?.model.stale == false)
        await harness.module.refreshPlan("claude")
        let ring = try #require(harness.module.quotaRings.first)
        #expect(ring.model.stale)
        #expect(ring.model.primary?.percent == 37 && ring.model.secondary?.percent == 12)
        #expect(ring.model.accessibilityLabel == "Claude, 5 hour window 37 percent, weekly 12 percent, stale")
        #expect(harness.module.state == .ambient)
        await harness.module.stop()
    }

    @Test func singleProviderReadoutOnlyWhenOneRing() {
        let module = Self.module([.plan("claude", "Claude"), .plan("codex", "Codex")])
        module.planStates["claude"] = PlanState(windows: [fiveHour, weekly])
        let single = module.leftWingItems()
        #expect(single.count == 1)
        #expect(single[0].compactView(.wide) != nil)
        #expect(single[0].compactView(.short) != nil && single[0].compactView(.icon) != nil)

        module.planStates["codex"] = PlanState(windows: [weekly])
        let two = module.leftWingItems()
        #expect(two.count == 2)
        #expect(two.allSatisfy { $0.compactView(.wide) == nil && $0.compactView(.short) != nil })
    }

    @Test func voiceOverLabel() throws {
        let model = try #require(
            QuotaDialModel(
                providerName: "Claude",
                plan: PlanState(
                    windows: [
                        UsageWindow(name: "5h", used: 38, limit: nil, resetsAt: nil),
                        UsageWindow(name: "weekly", used: 52, limit: nil, resetsAt: nil),
                    ]), rings: .fiveHourAndWeekly))
        #expect(model.accessibilityLabel == "Claude, 5 hour window 38 percent, weekly 52 percent")
    }

    /// The lane (VigieCore `ClosedNotchArbiter`, Story 2.8) sorts by state, then `priority`, then `order` and
    /// collapses what does not fit into `+X`. The module cannot import VigieCore (AD-1), so this checks the
    /// item fields that ranking reads: with a priority-1 item from another module and one slot, a ring at
    /// the default priority 2 ranks after it and is the one counted in `+X`.
    @Test func aLowerPriorityRingRanksAfterHigherPriorityItems() {
        let module = Self.module([.plan("claude", "Claude"), .plan("codex", "Codex")])
        module.planStates["claude"] = PlanState(windows: [fiveHour])
        module.planStates["codex"] = PlanState(windows: [weekly])
        let script = LeftWingItem(id: "script", priority: 1) { _ in AnyView(EmptyView()) }
        let lane = ([script] + module.leftWingItems()).sorted {
            ($0.priority, $0.order) < ($1.priority, $1.order)
        }
        let slots = 2
        #expect(lane.prefix(slots).map(\.id) == ["script", "ring.claude"])
        #expect(lane.dropFirst(slots).map(\.id) == ["ring.codex"])
    }
}
