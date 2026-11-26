import AppKit
import ModuleKit
import Testing
import VigieUI

@testable import VigieCore

/// Story 17.2: the complete Settings window (pane order, custom color contrast, Reduce motion note, entry points).
@MainActor @Suite(.serialized) struct SettingsWindowTests {
    private func manifest(_ id: String) -> ModuleManifest {
        ModuleManifest(id: ModuleID(id)!, name: LocalizedStringResource(stringLiteral: id), icon: "star")
    }

    @Test func sidebarOrderIsTheStoryOrder() {
        // Registry order differs from the Settings order (Time is registered before Calendar).
        let registered = ["agents.sessions", "agents.usage", "shelf", "time", "calendar", "notes", "integrations"]
        let ids = SettingsPaneCatalog.panes(manifests: registered.map(manifest)).map(\.id)
        #expect(
            ids == [
                "general", "appearance", "display", "home", "agents.sessions", "agents.usage", "shelf", "calendar",
                "time", "notes", "integrations", "sounds", "sync", "updates",
            ])
    }

    @Test func unlistedModulesFollowTheListedOnesInRegistryOrder() {
        let ids = SettingsPaneCatalog.panes(manifests: ["zeta", "notes", "alpha", "shelf"].map(manifest)).map(\.id)
        #expect(Array(ids[4...7]) == ["shelf", "notes", "zeta", "alpha"])
    }

    @Test func noSupportPaneAndOldPanesFoldIntoTheirNewHome() async throws {
        let h = try await SettingsHarness()
        let ids = h.controller.panes.map(\.id)
        for gone in ["support", "activity", "closed", "notify"] { #expect(!ids.contains(gone)) }
        #expect(h.controller.resolvePane("notify") == "general")
        #expect(h.controller.resolvePane("alerts") == "general")
        #expect(h.controller.resolvePane("activity") == "general")
        #expect(h.controller.resolvePane("privacy") == "general")
        #expect(h.controller.resolvePane("closed") == "appearance")
        #expect(h.controller.resolvePane("virtual_notch") == "display")
        // General holds the Privacy controls and the alert rules; Appearance holds the closed-notch settings.
        guard case .core(let general)? = h.controller.pane("general")?.content,
            case .core(let appearance)? = h.controller.pane("appearance")?.content
        else { Issue.record("core panes expected"); return }
        let generalKeys = Set(general.flatMap(\.keys))
        #expect(generalKeys.contains(CoreSettings.path("privacy", "force")))
        #expect(generalKeys.contains(CoreSettings.path("notify", "cooldown")))
        #expect(Set(appearance.flatMap(\.keys)).contains(CoreSettings.path("closed", "slots")))
        await h.tearDown()
    }

    @Test func contrastRatioAndThresholds() {
        let white = ThemeColor(red: 1, green: 1, blue: 1)
        let black = ThemeColor(red: 0, green: 0, blue: 0)
        let onBlack = CustomColorContrast(color: white, surfaces: [black])
        #expect(onBlack?.ratioText == "21.0:1")
        #expect(onBlack?.meetsText == true)
        let grey = ThemeColor(hex: "#777777")!
        let low = CustomColorContrast(color: grey, surfaces: [white])
        #expect(low?.meetsText == false)  // 4.48:1
        #expect(low?.meetsNonText == true)
        #expect(low?.ratioText == "4.4:1")
        #expect(CustomColorContrast(color: white, surfaces: [white])?.meetsNonText == false)
        #expect(CustomColorContrast(color: white, surfaces: []) == nil)
    }

    @Test func customStatusColorShowsContrastAndIsNeverBlocked() async throws {
        let h = try await SettingsHarness()
        let theme = ThemeController(library: try ThemeLoader.loadBundled(), mode: .dark)
        h.controller.theme = theme
        let role = ColorRole.statusWorking
        #expect(h.controller.customColor(for: role) == nil)
        #expect(h.controller.contrast(for: role) == nil)

        // A color nearly equal to the dark surface: terrible contrast, still accepted and written.
        let surface = theme.theme.themeColor(.surfacePanel)
        try await h.controller.setCustomColor(surface, for: role)
        #expect(h.controller.customColor(for: role) == surface)
        #expect(h.configText().contains("[appearance.colors]"))
        #expect(h.configText().contains("status-working = \"\(surface.hex)\""))
        let poor = try #require(h.controller.contrast(for: role))
        #expect(poor.ratio < CustomColorContrast.nonTextMinimum)
        #expect(!poor.meetsText)

        let good = ThemeColor(red: 1, green: 1, blue: 1)
        try await h.controller.setCustomColor(good, for: role)
        let reading = try #require(h.controller.contrast(for: role))
        #expect(reading.meetsText)
        let expected = good.worstContrast(against: [
            theme.theme.themeColor(.surfacePanel), theme.theme.themeColor(.surfaceCard),
        ])
        #expect(abs(reading.ratio - expected) < 0.0001)

        try await h.controller.resetCustomColor(for: role)
        #expect(h.controller.customColor(for: role) == nil)
        #expect(!h.configText().contains("status-working"))
        await h.tearDown()
    }

    @Test func contrastFollowsTheCurrentLook() async throws {
        let h = try await SettingsHarness()
        let theme = ThemeController(library: try ThemeLoader.loadBundled(), mode: .dark)
        h.controller.theme = theme
        let color = ThemeColor(hex: "#E8ECF2")!
        let dark = try #require(h.controller.contrast(of: color))
        theme.mode = .light
        let light = try #require(h.controller.contrast(of: color))
        #expect(dark.ratio > light.ratio)
        await h.tearDown()
    }

    @Test func reduceMotionNoteFollowsMacOS() async throws {
        let h = try await SettingsHarness()
        h.controller.reduceMotion = { true }
        #expect(h.controller.showsReduceMotionNote)
        h.controller.reduceMotion = { false }
        #expect(!h.controller.showsReduceMotionNote)
        let text = SettingsText.string("settings.appearance.reduceMotion")
        #expect(text != "settings.appearance.reduceMotion")
        #expect(text.contains("Reduce motion"))
        #expect(text.contains("Calm"))
        await h.tearDown()
    }

    @Test func entryPointsOpenTheRelevantPane() async throws {
        let h = try await SettingsHarness()
        // Context menu / gear / ⌘, open without a pane: General.
        h.controller.open()
        #expect(h.controller.selectedPaneID == "general")
        // Alerts and empty states name a pane: a module id, a core id, or an alias.
        for (requested, shown) in [
            ("agents.sessions", "agents.sessions"), ("home", "home"), ("display", "display"), ("sounds", "sounds"),
            ("notify", "general"), ("closed", "appearance"), ("not-a-pane", "general"),
        ] {
            h.controller.open(pane: requested)
            #expect(h.controller.selectedPaneID == shown, "\(requested)")
            #expect(h.controller.selectedPane.id == shown)
        }
        await h.tearDown()
    }
}
