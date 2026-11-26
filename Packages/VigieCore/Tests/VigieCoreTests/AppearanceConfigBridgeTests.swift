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
}
