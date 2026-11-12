import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import VigieCore

/// Story 11.4: `[general] home_after` keeps the current tab on a quick re-open.
@MainActor @Suite struct HomeAfterTests {
    private static let path = CoreSettings.path("general", "home_after")

    /// Opens the view, selects `tab`, closes it and lets `elapsed` pass on the fake clock.
    private func closeOn(_ tab: String, _ f: ExpandedFixture, after elapsed: Duration) {
        f.host.expand(focus: f.intent)
        f.host.selectedTabID = tab
        f.host.collapse()
        f.clock.advance(by: elapsed)
    }

    // MARK: Landing tab

    @Test func reopeningInsideTheWindowKeepsTheLastTab() async {
        let f = ExpandedFixture()
        await f.start()
        closeOn("shelf", f, after: .seconds(119))
        f.host.expand(focus: f.intent)
        #expect(f.host.selectedTabID == "shelf")
    }

    @Test func reopeningOutsideTheWindowLandsOnHome() async {
        let f = ExpandedFixture()
        await f.start()
        closeOn("shelf", f, after: .seconds(120))
        f.host.expand(focus: f.intent)
        #expect(f.host.selectedTabID == ExpandedTab.homeID)
    }

    @Test func neverKeepsTheLastTabEvenHoursLater() async {
        let f = ExpandedFixture()
        f.homeAfter = { .never }
        await f.start()
        closeOn("agents.usage", f, after: .seconds(10 * 3600))
        f.host.expand(focus: f.intent)
        #expect(f.host.selectedTabID == "agents.usage")
    }

    @Test func zeroSecondsAlwaysLandsOnHome() async {
        let f = ExpandedFixture()
        f.homeAfter = { .after(.zero) }
        await f.start()
        closeOn("shelf", f, after: .zero)
        f.host.expand(focus: f.intent)
        #expect(f.host.selectedTabID == ExpandedTab.homeID)
    }

    @Test func firstOpenAndATabThatIsGoneLandOnHome() async {
        let f = ExpandedFixture()
        f.homeAfter = { .never }
        await f.start()
        f.host.selectedTabID = "shelf"
        f.host.expand(focus: f.intent)
        #expect(f.host.selectedTabID == ExpandedTab.homeID, "no close yet")
        f.host.selectedTabID = "shelf"
        f.host.collapse()
        f.enablement.set("shelf", false)
        #expect(await eventually { !f.host.expandedTabs.contains { $0.id == "shelf" } })
        f.host.expand(focus: f.intent)
        #expect(f.host.selectedTabID == ExpandedTab.homeID)
    }

    @Test func anExplicitRequestWinsInEveryMode() async {
        for mode in [HomeAfter.never, .after(.zero), .default] {
            let f = ExpandedFixture()
            f.homeAfter = { mode }
            await f.start()
            closeOn("shelf", f, after: .seconds(1))
            f.host.openTab("agents.usage", focus: f.intent)
            #expect(f.host.selectedTabID == "agents.usage", "\(mode)")
            f.host.collapse()
            // A module hotkey or an alert's Open action reaches the host through its host control.
            CoreHostControl(moduleID: "agents.sessions", link: NotchHostLink(host: f.host)).openOwnTab(focus: f.intent)
            #expect(f.host.selectedTabID == "agents.sessions", "\(mode)")
        }
    }

    @Test func aSettingChangeAppliesToTheNextOpen() async {
        let f = ExpandedFixture()
        var mode = HomeAfter.never
        f.homeAfter = { mode }
        await f.start()
        closeOn("shelf", f, after: .seconds(5))
        mode = .after(.zero)
        f.host.expand(focus: f.intent)
        #expect(f.host.selectedTabID == ExpandedTab.homeID)
        f.host.selectedTabID = "shelf"
        f.host.collapse()
        mode = .never
        f.host.expand(focus: f.intent)
        #expect(f.host.selectedTabID == "shelf")
    }

    @Test func theHostFollowsLiveConfigEdits() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(config: "[general]\nhome_after = \"never\"\n")
        let f = ExpandedFixture()
        f.homeAfter = { HomeAfter(configStore: store) }
        await f.start()
        closeOn("shelf", f, after: .seconds(3600))
        f.host.expand(focus: f.intent)
        #expect(f.host.selectedTabID == "shelf")
        f.host.collapse()
        try fixture.writeConfig("[general]\nhome_after = \"0s\"\n")
        await store.fireAndSettle(watcher)
        f.host.expand(focus: f.intent)
        #expect(f.host.selectedTabID == ExpandedTab.homeID)
    }

    // MARK: Config value

    @Test func parsesDurationsAndNever() {
        #expect(HomeAfter(configValue: "never") == .never)
        #expect(HomeAfter(configValue: "0s") == .after(.zero))
        #expect(HomeAfter(configValue: "2m") == .after(.seconds(120)))
        #expect(HomeAfter(configValue: "1h30m") == .after(.seconds(5400)))
        #expect(HomeAfter(configValue: "soon") == nil)
        #expect(HomeAfter.default == .after(.seconds(120)))
        #expect(!HomeAfter.never.returnsHome(after: .seconds(1_000_000)))
        #expect(HomeAfter.after(.zero).returnsHome(after: .zero))
    }

    @Test func defaultIsTwoMinutesAndAnyDurationIsAccepted() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore()
        #expect(store.value(Self.path, as: String.self) == "2m")
        #expect(HomeAfter(configStore: store) == .default)
        for (written, read) in [("5m", "5m"), ("120s", "2m"), ("never", "never"), ("0ms", "0s")] {
            try fixture.writeConfig("[general]\nhome_after = \"\(written)\"\n")
            await store.fireAndSettle(watcher)
            #expect(store.value(Self.path, as: String.self) == read, "\(written)")
        }
        try fixture.writeConfig("[general]\nhome_after = \"soon\"\n")
        await store.fireAndSettle(watcher)
        #expect(store.value(Self.path, as: String.self) == "2m", "an invalid value falls back to the default")
        #expect(HomeAfter(configStore: store) == .default)
        #expect(!store.problems.isEmpty, "and is reported as a setup problem")
    }

    // MARK: Settings › General

    @Test func settingsGeneralShowsTheFiveChoices() async throws {
        let h = try await SettingsHarness()
        let general = try #require(h.controller.panes.first { $0.id == "general" })
        guard case .core(let sections) = general.content else {
            Issue.record("General is not a generated pane")
            return
        }
        #expect(sections.flatMap(\.keys).contains(Self.path))
        let row = try #require(h.controller.rowModel(for: Self.path))
        #expect(String(localized: row.label) == "Return to Home after")
        guard case .enumeration(let options, let defaultValue) = row.kind else {
            Issue.record("home_after is not a choice")
            return
        }
        #expect(options == ["0s", "30s", "2m", "10m", "never"])
        #expect(defaultValue == "2m")
        #expect(options.map(row.optionLabel) == ["Immediately", "30 s", "2 min", "10 min", "Never"])
    }

    @Test func choosingInSettingsWritesTheRawValue() async throws {
        let h = try await SettingsHarness()
        let row = try #require(h.controller.rowModel(for: Self.path))
        try await row.binding.set(.string("never"))  // the picker's write
        #expect(h.store.value(Self.path, as: String.self) == "never")
        #expect(HomeAfter(configStore: h.store) == .never)
    }
}
