import Foundation
import Testing
import VigieUI

@testable import VigieCore

@MainActor @Suite struct AppearanceConfigBridgeTests {
    let fixture = ConfigFixture()

    func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    func makeThemes() throws -> ThemeController {
        ThemeController(library: try ThemeLoader.loadBundled(), mode: .dark)
    }

    func writeTheme(_ name: String, _ text: String) throws {
        let folder = fixture.configFolder.appendingPathComponent("themes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appendingPathComponent(name))
    }

    static let mineTheme = """
        schema = 1
        id = "mine"
        name = "Mine"
        extends = "chrome-hologram"
        [looks.dark.colors]
        ink-1 = "#010203"
        status-blocked = "#111111"
        """

    @Test func themeFromConfigAppliesAtStart() async throws {
        let (store, _) = try await fixture.makeStore(config: "[appearance]\ntheme = \"twin-metal-tactical\"\n")
        let themes = try makeThemes()
        let bridge = AppearanceConfigBridge(store: store, themes: themes)
        bridge.start()
        #expect(themes.variantID == "twin-metal-tactical")
        #expect(themes.theme.variantID == "twin-metal-tactical")
        #expect(themes.islandTheme.variantID == "twin-metal-tactical")
        bridge.stop()
    }

    @Test func changingTheKeyReSkinsLive() async throws {
        let (store, _) = try await fixture.makeStore()
        let themes = try makeThemes()
        let bridge = AppearanceConfigBridge(store: store, themes: themes)
        bridge.start()
        #expect(themes.theme.variantID == ThemeLibrary.defaultVariantID)
        try await store.set(CoreSettings.path("appearance", "theme"), to: .string("twin-metal-tactical"))
        try await wait { themes.variantID == "twin-metal-tactical" }
        #expect(themes.theme.variantID == "twin-metal-tactical")
        try await store.set(CoreSettings.path("appearance", "theme"), to: .string(ThemeLibrary.defaultVariantID))
        try await wait { themes.variantID == ThemeLibrary.defaultVariantID }
        #expect(themes.theme.variantID == ThemeLibrary.defaultVariantID)
        bridge.stop()
    }

    @Test func unknownThemeFallsBackToTheDefault() async throws {
        let (store, _) = try await fixture.makeStore(config: "[appearance]\ntheme = \"nope\"\n")
        let themes = try makeThemes()
        let bridge = AppearanceConfigBridge(store: store, themes: themes)
        bridge.start()
        #expect(themes.theme.variantID == ThemeLibrary.defaultVariantID)
        bridge.stop()
    }

    // MARK: mode (Story 18.2, approved addition)

    @Test func modeFromConfigAppliesAtStartAndLive() async throws {
        let (store, _) = try await fixture.makeStore(config: "[appearance]\nmode = \"light\"\n")
        let themes = try makeThemes()
        let bridge = AppearanceConfigBridge(store: store, themes: themes, watcher: ManualDirectoryWatcher())
        bridge.start()
        #expect(themes.mode == .light)
        #expect(themes.theme.look == .light)
        #expect(themes.islandTheme.look == .dark)  // the physical notch stays dark
        try await store.set(CoreSettings.path("appearance", "mode"), to: .string("dark"))
        try await wait { themes.mode == .dark }
        #expect(themes.theme.look == .dark)
        bridge.stop()
    }

    // MARK: color overrides

    @Test func colorOverridesFollowTheResolutionOrder() async throws {
        let (store, _) = try await fixture.makeStore(
            config: """
                [appearance]
                theme = "mine"
                mode = "dark"
                [appearance.colors]
                ink-1 = "#AAAAAA"
                blocked = "#FF0000"
                pace-on = "not a color"
                [appearance.colors.dark]
                status-blocked = "#00FF00"
                [appearance.colors.light]
                status-blocked = "#0000FF"
                """)
        try writeTheme("mine.toml", Self.mineTheme)
        let themes = try makeThemes()
        let bridge = AppearanceConfigBridge(store: store, themes: themes, watcher: ManualDirectoryWatcher())
        bridge.start()
        // custom file < [appearance.colors] < [appearance.colors.<look>]
        #expect(themes.theme.themeColor(.ink1).hex == "#AAAAAA")
        #expect(themes.theme.themeColor(.statusBlocked).hex == "#00FF00")
        #expect(themes.islandTheme.themeColor(.statusBlocked).hex == "#00FF00")
        // A bad value is ignored: the look's own color stays.
        let ownPaceOn = themes.library.resolve(themeID: "mine", look: .dark).theme.themeColor(.paceOn)
        #expect(themes.theme.themeColor(.paceOn).hex == ownPaceOn.hex)
        // The light look takes its own table, and the notch stays dark.
        try await store.set(CoreSettings.path("appearance", "mode"), to: .string("light"))
        try await wait { themes.mode == .light }
        #expect(themes.theme.themeColor(.statusBlocked).hex == "#0000FF")
        #expect(themes.islandTheme.themeColor(.statusBlocked).hex == "#00FF00")
        bridge.stop()
    }

    @Test func editingColorsAppliesLiveAndRemovingResetsThem() async throws {
        let (store, _) = try await fixture.makeStore()
        let themes = try makeThemes()
        let bridge = AppearanceConfigBridge(store: store, themes: themes, watcher: ManualDirectoryWatcher())
        bridge.start()
        let original = themes.theme.themeColor(.statusBlocked).hex
        try await store.set(StatusColors.path(.statusBlocked), to: .string("#123456"))
        try await wait { themes.theme.themeColor(.statusBlocked).hex == "#123456" }
        #expect(themes.theme.themeColor(.statusBlocked).hex == "#123456")
        try await store.remove(StatusColors.path(.statusBlocked))
        try await wait { themes.theme.themeColor(.statusBlocked).hex == original }
        #expect(themes.theme.themeColor(.statusBlocked).hex == original)
        bridge.stop()
    }

    // MARK: custom theme files

    @Test func customThemeInTheThemesFolderAppearsAndApplies() async throws {
        try writeTheme("mine.toml", Self.mineTheme)
        let (store, _) = try await fixture.makeStore(config: "[appearance]\ntheme = \"mine\"\nmode = \"dark\"\n")
        let themes = try makeThemes()
        let bridge = AppearanceConfigBridge(store: store, themes: themes, watcher: ManualDirectoryWatcher())
        bridge.start()
        #expect(themes.library.choices.map(\.id).contains("mine"))
        #expect(themes.theme.variantID == "mine")
        #expect(themes.theme.themeColor(.ink1).hex == "#010203")
        #expect(store.location.themesFolderURL.lastPathComponent == "themes")
        bridge.stop()
    }

    @Test func aThemeFileAddedOrEditedLaterAppliesLive() async throws {
        let (store, _) = try await fixture.makeStore(config: "[appearance]\ntheme = \"mine\"\nmode = \"dark\"\n")
        let watcher = ManualDirectoryWatcher()
        let themes = try makeThemes()
        let bridge = AppearanceConfigBridge(store: store, themes: themes, watcher: watcher)
        bridge.start()
        #expect(themes.theme.variantID == ThemeLibrary.defaultVariantID)  // unknown for now
        try writeTheme("mine.toml", Self.mineTheme)
        watcher.fire()
        #expect(themes.theme.variantID == "mine")
        #expect(themes.library.choices.map(\.id).contains("mine"))
        try writeTheme("mine.toml", Self.mineTheme.replacingOccurrences(of: "#010203", with: "#0A0B0C"))
        watcher.fire()
        #expect(themes.theme.themeColor(.ink1).hex == "#0A0B0C")
        try FileManager.default.removeItem(at: store.location.themesFolderURL.appendingPathComponent("mine.toml"))
        watcher.fire()
        #expect(!themes.library.choices.map(\.id).contains("mine"))
        #expect(themes.theme.variantID == ThemeLibrary.defaultVariantID)
        bridge.stop()
    }

    @Test func customThemeProblemsBecomeSetupAlerts() async throws {
        try writeTheme("clash.toml", "schema = 1\nid = \"chrome-hologram\"\n")
        try writeTheme("later.toml", "schema = 5\nid = \"later\"\n")
        let (store, _) = try await fixture.makeStore(config: "[appearance]\ntheme = \"later\"\n")
        let notifier = SetupRecordingNotifier()
        let reporter = ThemeProblemReporter(notifier: notifier, log: testLogger)
        let themes = try makeThemes()
        let watcher = ManualDirectoryWatcher()
        let bridge = AppearanceConfigBridge(store: store, themes: themes, problems: reporter, watcher: watcher)
        bridge.start()
        // Ignored id clash, and the newer schema falls back to the default theme: one alert each, no extra
        // "unknown theme" alert for the file that failed.
        #expect(themes.theme.variantID == ThemeLibrary.defaultVariantID)
        let titles = Set(notifier.events.map(\.title))
        #expect(
            titles == [
                "Custom theme clash.toml reuses the built-in id chrome-hologram, so it is ignored",
                "Theme later.toml needs a newer Vigie (schema 5), using the default theme",
            ])
        #expect(notifier.events.allSatisfy { $0.kind == SetupProblemReporter.alertKind })
        #expect(notifier.events.allSatisfy { $0.action == .openSettings(pane: "appearance") })
        #expect(notifier.events.allSatisfy { $0.category == "THEME" })
        // Fixing the files resolves the alerts.
        try FileManager.default.removeItem(at: store.location.themesFolderURL.appendingPathComponent("clash.toml"))
        try FileManager.default.removeItem(at: store.location.themesFolderURL.appendingPathComponent("later.toml"))
        try await store.set(CoreSettings.path("appearance", "theme"), to: .string(ThemeLibrary.defaultVariantID))
        watcher.fire()
        try await wait { reporter.openProblems.isEmpty }
        #expect(reporter.openProblems.isEmpty)
        #expect(notifier.resolveCount >= 2)
        bridge.stop()
    }

    @Test func unknownThemeRaisesOneAlertAndClearsWhenFixed() async throws {
        let (store, _) = try await fixture.makeStore(config: "[appearance]\ntheme = \"nope\"\n")
        let notifier = SetupRecordingNotifier()
        let reporter = ThemeProblemReporter(notifier: notifier, log: testLogger)
        let themes = try makeThemes()
        let bridge = AppearanceConfigBridge(
            store: store, themes: themes, problems: reporter, watcher: ManualDirectoryWatcher())
        bridge.start()
        #expect(notifier.events.map(\.title) == ["Theme nope not found, using the default theme"])
        try await store.set(CoreSettings.path("appearance", "theme"), to: .string("twin-metal-tactical"))
        try await wait { notifier.resolveCount == 1 }
        #expect(notifier.resolveCount == 1)
        #expect(reporter.openProblems.isEmpty)
        bridge.stop()
    }
}
