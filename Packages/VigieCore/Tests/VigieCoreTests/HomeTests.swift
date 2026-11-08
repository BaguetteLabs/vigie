import Foundation
import ModuleKit
import Observation
import SwiftUI
import Testing
import VigieUI

@testable import VigieCore

@MainActor @Suite(.serialized) struct HomeTests {
    // MARK: Selection

    @Test func selectionKeepsTheSetOrderAndDropsIdsWithoutACard() {
        let offered = ["shelf": "S", "agents.usage": "U", "agents.sessions": "A"]
        let result = HomeCardSelection.resolve(
            order: ["agents.usage", "nope", "shelf", "agents.usage", "calendar"], offered: offered)
        #expect(result.cards == ["U", "S"])
        #expect(result.missing == ["nope", "calendar"])
        #expect(HomeCardSelection.resolve(order: [], offered: offered).cards.isEmpty)
    }

    // MARK: Host

    @Test func homeIsTheFirstTabAndNeverInTabOrder() async {
        let f = ExpandedFixture()
        await f.start()
        f.tabOrder = ["shelf", "home"]
        #expect(f.host.expandedTabs.map(\.id) == ["home", "shelf", "agents.sessions", "agents.usage"])
        #expect(f.host.expandedTabs.first?.title == "Home")
    }

    @Test func expandLandsOnHomeEveryTime() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: f.intent)
        #expect(f.host.selectedTabID == ExpandedTab.homeID)
        f.host.selectedTabID = "shelf"
        f.host.collapse()
        f.host.toggleExpanded(focus: f.intent)
        #expect(f.host.selectedTabID == ExpandedTab.homeID)
        f.host.collapse()
        f.host.islandClicked()
        #expect(f.host.selectedTabID == ExpandedTab.homeID)
        #expect(f.host.expandedContent(for: ExpandedTab.homeID) != nil)
    }

    @Test func homeShowsTheChosenCardsInOrderFromRunningProviders() async {
        let f = ExpandedFixture(
            ids: ["agents.sessions", "agents.usage", "shelf", "time"], withoutTab: ["time"],
            withCard: ["agents.sessions", "agents.usage", "time"])
        await f.start()
        #expect(f.host.homeCards.isEmpty)
        // `shelf` offers no card; `calendar` is unknown: both skipped.
        f.homeCards = ["agents.usage", "shelf", "calendar", "agents.sessions", "time"]
        #expect(f.host.homeCards.map(\.id) == ["agents.usage", "agents.sessions", "time"])
        #expect(f.host.homeCards.map(\.opensTab) == [true, true, false])
        #expect(f.host.loggedMissingHomeCards == ["shelf", "calendar"])
        // A module that stops takes its card away.
        f.enablement.set("agents.usage", false)
        #expect(await eventually { f.host.homeCards.map(\.id) == ["agents.sessions", "time"] })
    }

    @Test func providersThatAreNotModulesJoinHome() async {
        let f = ExpandedFixture(withCard: ["shelf"])
        await f.start()
        let script = HomeCardModel(
            id: "script.vigie-site", title: "vigie.app", opensTab: false, content: AnyView(Color.clear))
        let host = NotchHost(
            themeController: f.host.themeController, registry: f.registry, contextMenu: NotchContextMenu(),
            displays: { [] }, homeCardOrder: { ["script.vigie-site", "shelf"] }, additionalHomeCards: { [script] },
            logger: testLogger)
        #expect(host.homeCards.map(\.id) == ["script.vigie-site", "shelf"])
    }

    @Test func clickingACardOpensItsTab() async {
        let f = ExpandedFixture(withoutTab: ["agents.usage"], withCard: ["shelf", "agents.usage"])
        await f.start()
        f.homeCards = ["shelf", "agents.usage"]
        f.host.expand(focus: f.intent)
        f.host.openHomeCard("shelf")
        #expect(f.host.selectedTabID == "shelf")
        f.host.selectedTabID = ExpandedTab.homeID
        f.host.openHomeCard("agents.usage")  // no tab: stays on Home
        #expect(f.host.selectedTabID == ExpandedTab.homeID)
        f.host.openHomeCard("unknown")
        #expect(f.host.selectedTabID == ExpandedTab.homeID)
    }

    @Test func emptyHomeOpensSettingsOnTheHomePane() async {
        let f = ExpandedFixture()
        await f.start()
        #expect(f.host.homeCards.isEmpty)
        f.host.openHomeSettings()
        #expect(f.openedPanes == ["home"])
        #expect(SettingsPaneCatalog.corePaneIDs.contains(SettingsPaneCatalog.homePaneID))
    }

    @Test func homeFollowsHomeCardsInConfigLive() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore()
        let f = ExpandedFixture(withCard: ["shelf", "agents.usage"])
        await f.start()
        let host = NotchHost(
            themeController: f.host.themeController, registry: f.registry, contextMenu: NotchContextMenu(),
            displays: { [] },
            homeCardOrder: { store.value(HomePaneModel.cardsPath, as: [String].self) ?? [] },
            logger: testLogger)
        #expect(host.homeCards.isEmpty)
        let changed = Flag(false)
        withObservationTracking {
            _ = host.homeCards
        } onChange: {
            changed.isOn = true
        }
        try await store.set(HomePaneModel.cardsPath, to: .strings(["agents.usage", "shelf"]))
        #expect(changed.isOn)
        #expect(host.homeCards.map(\.id) == ["agents.usage", "shelf"])
    }

    // MARK: Settings › Home

    private func paneModel(
        cards: [String]? = nil,
        providers: [HomeProviderDescriptor] = HomeTests.providers
    ) async throws -> (HomePaneModel, ConfigStore) {
        let fixture = ConfigFixture()
        let config = cards.map { "[home]\ncards = [\($0.map { "\"\($0)\"" }.joined(separator: ", "))]\n" }
        let (store, _) = try await fixture.makeStore(config: config)
        return (HomePaneModel(configStore: store, providers: { providers }), store)
    }

    static let providers = [
        HomeProviderDescriptor(id: "agents.sessions", name: "Agents"),
        HomeProviderDescriptor(id: "agents.usage", name: "Usage"),
        HomeProviderDescriptor(id: "shelf", name: "Shelf"),
    ]

    @Test func paneListsTickedRowsFirstThenTheRestInProviderOrder() async throws {
        let (model, _) = try await paneModel(cards: ["shelf", "gone", "agents.sessions"])
        #expect(model.rows.map(\.id) == ["shelf", "agents.sessions", "agents.usage"])
        #expect(model.rows.map(\.isOn) == [true, true, false])
    }

    @Test func tickingAppendsAndUntickingRemoves() async throws {
        let (model, store) = try await paneModel()
        #expect(model.rows.allSatisfy { !$0.isOn })
        await model.setOn("shelf", true)
        #expect(store.value(HomePaneModel.cardsPath, as: [String].self) == ["shelf"])
        await model.setOn("agents.sessions", true)
        #expect(model.cards == ["shelf", "agents.sessions"])
        #expect(model.rows.map(\.id) == ["shelf", "agents.sessions", "agents.usage"])
        await model.setOn("shelf", false)
        #expect(model.cards == ["agents.sessions"])
        #expect(model.rows.map(\.id) == ["agents.sessions", "agents.usage", "shelf"])
        #expect(model.error == nil)
        let text = try String(contentsOf: store.configURL, encoding: .utf8)
        #expect(text.contains("cards = [\"agents.sessions\"]"))
    }

    @Test func draggingReordersTheTickedRows() async throws {
        let (model, _) = try await paneModel(cards: ["agents.sessions", "agents.usage"])
        await model.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(model.cards == ["agents.usage", "agents.sessions"])
        // Dragging an unticked row among ticked ones does not tick it.
        await model.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(model.cards == ["agents.usage", "agents.sessions"])
        await model.move("agents.sessions", by: -1)
        #expect(model.cards == ["agents.sessions", "agents.usage"])
        await model.move("agents.sessions", by: 1)
        #expect(model.cards == ["agents.usage", "agents.sessions"])
    }

    @Test func writesKeepIdsWhoseProviderIsAwayNow() async throws {
        let (model, _) = try await paneModel(cards: ["script.site", "shelf"])
        await model.setOn("agents.usage", true)
        #expect(model.cards == ["shelf", "agents.usage", "script.site"])
    }

    @Test func homePaneListsRunningModulesWithACard() async throws {
        let f = ExpandedFixture(withCard: ["shelf", "agents.sessions"])
        await f.start()
        #expect(
            SettingsController.moduleHomeProviders(f.registry).map(\.id) == ["agents.sessions", "shelf"])
        let pane = SettingsPaneCatalog.corePanes().first { $0.id == SettingsPaneCatalog.homePaneID }
        guard case .core(let sections) = pane?.content else {
            Issue.record("home pane missing")
            return
        }
        // `[home] cards` is the card list, not a generated row; `tab_order` stays a row.
        #expect(sections.flatMap(\.keys) == [CoreSettings.path("general", "tab_order")])
        #expect(SettingsText.string("settings.home.empty") != "settings.home.empty")
    }
}
