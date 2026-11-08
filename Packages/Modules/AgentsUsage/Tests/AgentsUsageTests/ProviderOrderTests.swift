import AgentKit
import Foundation
import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import AgentsUsage

/// Story 7.9: provider order by drag or Settings (FR50, FR54, UX-DR29, UX-DR51).
@MainActor @Suite struct ProviderOrderTests {
    static let fiveHour = UsageWindow(
        name: "5h", used: 30, limit: nil, resetsAt: Date(timeIntervalSince1970: 1_794_160_000))

    static func started(order: [String] = []) async throws -> (AgentsUsageModule, MemoryAdapterSettings) {
        let module = AgentsUsageModule(
            adapters: AgentAdapters([
                ProviderAdapter.plan("claude", "Claude"), ProviderAdapter.plan("codex", "Codex"),
                ProviderAdapter.plan("gemini", "Gemini"),
            ]),
            now: { UsageTabSnapshotTests.start })
        let settings = MemoryAdapterSettings(order.isEmpty ? [:] : ["order": order])
        let sandbox = try Sandbox()
        try await module.start(context: FakeModuleContext(directory: sandbox.storage, settings: settings))
        await settle()
        for id in ["claude", "codex", "gemini"] { module.planStates[AgentID(id)!] = PlanState(windows: [fiveHour]) }
        module.lastIngest = IngestReport()
        return (module, settings)
    }

    @Test func movesKeepUnshownIdsAtTheEnd() {
        #expect(
            UsageProviderOrder.merged(shown: ["b", "a"], current: ["a", "b", "c"], existing: ["x"]) == [
                "b", "a", "c", "x",
            ])
        #expect(UsageProviderOrder.moving("c", onto: "a", in: ["a", "b", "c"]) == ["c", "a", "b"])
        #expect(UsageProviderOrder.moving("a", onto: "c", in: ["a", "b", "c"]) == ["b", "c", "a"])
        #expect(
            UsageProviderOrder.moved(["a", "b", "c"], fromOffsets: IndexSet(integer: 0), toOffset: 3) == [
                "b", "c", "a",
            ])
    }

    @Test func moveBounds() {
        let ids = ["a", "b", "c"]
        #expect(UsageProviderOrder.moving("a", by: -1, in: ids) == ids)
        #expect(UsageProviderOrder.moving("c", by: 1, in: ids) == ids)
        #expect(UsageProviderOrder.moving("a", by: 1, in: ids) == ["b", "a", "c"])
        #expect(UsageProviderOrder.moving("c", by: -1, in: ids) == ["a", "c", "b"])
        #expect(UsageProviderOrder.moving("z", by: 1, in: ids) == ids)
    }

    @Test func reorderWritesFullOrderAndRingsFollowLive() async throws {
        let (module, settings) = try await Self.started()
        #expect(module.quotaRings.map(\.provider.rawValue) == ["claude", "codex", "gemini"])
        // The tab shows two of them (gemini hidden would be kept); here a drag of the shown list.
        await module.setProviderOrder(shown: ["codex", "claude"])
        #expect(settings.value("order", as: [String].self) == ["codex", "claude", "gemini"])
        await settle()
        #expect(module.quotaRings.map(\.provider.rawValue) == ["codex", "claude", "gemini"])
        #expect(module.usageTabSnapshot().providers.map(\.id) == ["codex", "claude", "gemini"])
    }

    @Test func snapshotFollowsOrderAndMovesByOne() async throws {
        let (module, settings) = try await Self.started(order: ["gemini", "claude"])
        #expect(module.usageTabSnapshot().providers.map(\.id) == ["gemini", "claude", "codex"])
        await module.moveProvider("codex", by: -1)
        #expect(settings.value("order", as: [String].self) == ["gemini", "codex", "claude"])
        await settle()
        await module.moveProvider("gemini", by: -1)
        #expect(settings.writes.count == 1)  // bounds: no write
    }

    @Test func settingsBlockRenders() async throws {
        let (module, _) = try await Self.started()
        let view = try #require(module.settingsView())
        let renderer = ImageRenderer(content: view.frame(width: 400, height: 400))
        #expect(renderer.cgImage != nil)
        #expect(module.orderableProviders.map(\.id.rawValue) == ["claude", "codex", "gemini"])
    }
}
