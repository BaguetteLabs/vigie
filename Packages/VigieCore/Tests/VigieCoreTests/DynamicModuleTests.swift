import Foundation
import ModuleKit
import Observation
import SwiftUI
import Testing
import VigieUI

@testable import VigieCore

/// A script-like dynamic module (AD-18): a tab, a Home card and one left-wing item.
@MainActor @Observable
final class DynamicTestModule: NotchModule {
    let manifest: ModuleManifest
    var state: ModuleState = .ambient
    var priority = 5

    init(_ id: ModuleID) {
        manifest = ModuleManifest(id: id, name: "Script", icon: "terminal")
    }

    func expandedView() -> AnyView? { AnyView(Color.clear) }
    func homeCard() -> AnyView? { AnyView(Color.clear) }
    func leftWingItems() -> [LeftWingItem] {
        [LeftWingItem(id: "script", priority: priority) { _ in AnyView(Color.clear.frame(width: 16, height: 16)) }]
    }
    func start(context: any ModuleContext) async throws {}
    func stop() async {}
}

/// Story 12.5: `context.host.registerDynamicModule` puts a script module in arbitration, Home, the tabs and
/// Settings › Home like any other module, and takes it out on cancel or when its owner stops.
@MainActor @Suite(.serialized) struct DynamicModuleTests {
    static let owner: ModuleID = "integrations"

    func fixture() -> ExpandedFixture {
        ExpandedFixture(ids: ["agents.sessions", "integrations", "shelf"], withoutTab: ["integrations"])
    }

    func control(_ f: ExpandedFixture) -> CoreHostControl {
        CoreHostControl(moduleID: Self.owner, link: NotchHostLink(host: f.host))
    }

    @Test func aRegisteredModuleJoinsTabsHomeSettingsAndTheRegistry() async throws {
        let f = fixture()
        await f.start()
        let script = DynamicTestModule("github.prs")
        let token = try control(f).registerDynamicModule(script)

        #expect(f.registry.module("github.prs") === script)
        #expect(f.registry.status(of: "github.prs") == .running)
        #expect(f.registry.dynamicModuleIDs == ["github.prs"])
        // Right after its owner, in registry order.
        #expect(
            f.registry.runningModules.map(\.manifest.id) == ["agents.sessions", "integrations", "github.prs", "shelf"])
        #expect(f.host.expandedTabs.map(\.id) == ["home", "agents.sessions", "github.prs", "shelf"])
        #expect(f.host.expandedContent(for: "github.prs") != nil)
        f.homeCards = ["github.prs"]
        #expect(f.host.homeCards.map(\.id) == ["github.prs"])
        #expect(SettingsController.moduleHomeProviders(f.registry).map(\.id) == ["github.prs"])

        token.cancel()
        #expect(f.registry.module("github.prs") == nil)
        #expect(f.registry.status(of: "github.prs") == .disabled)
        #expect(!f.host.expandedTabs.map(\.id).contains("github.prs"))
        #expect(f.host.homeCards.isEmpty)
        token.cancel()  // idempotent
        await f.registry.shutdown()
    }

    @Test func idsMustBeFreeAndTheLinkBound() async throws {
        let f = fixture()
        await f.start()
        let token = try control(f).registerDynamicModule(DynamicTestModule("github.prs"))
        #expect(throws: DynamicModuleError.duplicateID("github.prs")) {
            try control(f).registerDynamicModule(DynamicTestModule("github.prs"))
        }
        #expect(throws: DynamicModuleError.duplicateID("shelf")) {
            try control(f).registerDynamicModule(DynamicTestModule("shelf"))
        }
        #expect(throws: DynamicModuleError.unavailable) {
            try CoreHostControl(moduleID: "unknown", link: NotchHostLink(host: f.host))
                .registerDynamicModule(DynamicTestModule("other.script"))
        }
        token.cancel()
        // Free again once unregistered.
        let again = try control(f).registerDynamicModule(DynamicTestModule("github.prs"))
        again.cancel()
        await f.registry.shutdown()
        #expect(throws: DynamicModuleError.unavailable) {
            try control(f).registerDynamicModule(DynamicTestModule("late.script"))
        }
    }

    @Test func stoppingTheOwnerRemovesItsDynamicModules() async throws {
        let f = fixture()
        await f.start()
        _ = try control(f).registerDynamicModule(DynamicTestModule("a.script"))
        _ = try control(f).registerDynamicModule(DynamicTestModule("b.script"))
        #expect(f.registry.dynamicModuleIDs == ["a.script", "b.script"])
        f.enablement.set(Self.owner, false)
        #expect(await eventually { f.registry.dynamicModuleIDs.isEmpty })
        #expect(f.registry.module("a.script") == nil)
        #expect(!f.host.expandedTabs.map(\.id).contains("b.script"))
        await f.registry.shutdown()
    }

    @Test func aDynamicModuleTakesPartInArbitration() async throws {
        let f = fixture()
        await f.start()
        f.host.rearbitrate()
        let script = DynamicTestModule("site.status")
        let token = try control(f).registerDynamicModule(script)
        #expect(await eventually { f.host.leadingLayout.shown.map(\.id) == ["site.status/script"] })
        // Hidden modules offer nothing; the lane follows the module's state.
        script.state = .hidden
        #expect(await eventually { f.host.leadingLayout.isEmpty })
        script.state = .alert
        #expect(await eventually { f.host.leadingLayout.shown.map(\.id) == ["site.status/script"] })
        // Never the right wing (sessions only).
        #expect(f.host.trailingLayout.isEmpty)
        token.cancel()
        #expect(await eventually { f.host.leadingLayout.isEmpty })
        await f.registry.shutdown()
    }
}
