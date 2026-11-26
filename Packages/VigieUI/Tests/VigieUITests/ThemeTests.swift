import Foundation
import Testing

@testable import VigieUI

enum Fixtures {
    static let library: ThemeLibrary = {
        do { return try ThemeLoader.loadBundled() } catch { fatalError("bundled themes: \(error)") }
    }()
    static var chrome: ThemeFile { library.builtIns["chrome-hologram"]! }
}

@Suite struct ThemeDecodingTests {
    @Test func bundledBaseDecodes() {
        let base = Fixtures.library.base
        #expect(base.schema == 1)
        #expect(base.id == "base")
        #expect(base.colors["island"] == "#000000")
        #expect(base.spacing["band-height"] == "34px")
        #expect(base.motion["enter"] == "280ms")
        #expect(base.rounded["peek"] == "22px")
        #expect(base.components["island-closed"]?["width"] == "540px")
        #expect(base.ignoredKeys.isEmpty)
    }

    @Test func chromeHologramDecodesBothLooks() {
        let chrome = Fixtures.chrome
        #expect(chrome.schema == 1)
        #expect(chrome.name == "Chrome Hologram")
        #expect(chrome.extends == "base")
        #expect(chrome.looks["dark"]?.colors["ink-1"] == "#E8ECF2")
        #expect(chrome.looks["light"]?.colors["quota-warning-text"] == "#7E6300")
        #expect(chrome.typography["readout-value"]?.fontSize == "14px")
        #expect(chrome.rounded["card"] == "16px")
        #expect(chrome.motion["card-iris"] == "12s")
        #expect(Fixtures.library.problems.isEmpty)
    }

    @Test func everyLookDefinesTheSharedRoles() {
        let shared: [ColorRole] = [
            .surfacePanel, .surfaceCard, .ink1, .ink2, .ink3, .line, .statusIdle, .statusWorking, .statusDone,
            .statusBlocked, .statusFailed, .paceOn, .paceAhead, .quotaWarning,
        ]
        for look in Look.allCases {
            let colors = Fixtures.chrome.tokens(for: look).colors
            for role in shared { #expect(colors[role.rawValue] != nil, "\(look) \(role)") }
            for key in colors.keys { #expect(ColorRole(rawValue: key) != nil, "unknown role \(key)") }
        }
        for key in Fixtures.chrome.typography.keys { #expect(TypographyRole(rawValue: key) != nil) }
    }

    @Test func unknownKeysAreIgnored() throws {
        let toml = """
            schema = 1
            id = "mine"
            future = "x"
            [looks.dark.colors]
            ink-1 = "#112233"
            sparkle = "#445566"
            [future-table]
            a = 1
            """
        let theme = try ThemeLoader.decodeVariant(Data(toml.utf8), file: "mine.toml").get()
        #expect(theme.ignoredKeys == ["future", "future-table"])
        let resolved = ThemeResolver.resolve(base: Fixtures.library.base, variant: theme, look: .dark).theme
        #expect(resolved.themeColor(.ink1).hex == "#112233")
    }
}

@Suite struct ThemeResolverTests {
    let base = Fixtures.library.base
    let chrome = Fixtures.chrome

    @Test func lookSuppliesColorsAndBaseSuppliesIsland() {
        let dark = ThemeResolver.resolve(base: base, variant: chrome, look: .dark).theme
        let light = ThemeResolver.resolve(base: base, variant: chrome, look: .light).theme
        #expect(dark.themeColor(.surfacePanel).hex == "#0A0E16")
        #expect(light.themeColor(.surfacePanel).hex == "#F3F5F9")
        #expect(light.themeColor(.island).hex == "#000000")
        #expect(dark.radius(.card) == 16)
        #expect(dark.radius(.peek) == 22)
        #expect(dark.radius(.full) == 9999)
        #expect(dark.spacing(.bandHeight) == 34)
        #expect(dark.motion(.enter) == .milliseconds(280))
        #expect(dark.motion(.workingCycle) == .milliseconds(1500))
        #expect(dark.motion(.cardIris) == .seconds(12))
        #expect(dark.motionSeconds(.exit) == 0.2)
        #expect(dark.component("island-closed", "width") == "540px")
        #expect(dark.componentLength("island-closed", "height") == 34)
        #expect(dark.componentLength("drop-display", "zone-radius-a") == 13)
    }

    @Test func orderIsBaseVariantLookCustomOverridesThenLookOverrides() {
        var custom = ThemeFile(id: "mine", name: "Mine", extends: "chrome-hologram")
        custom.looks["dark"] = LookTokens(colors: ["ink-1": "#101010", "ink-2": "#202020", "island": "#010101"])
        let overrides = ColorOverrides(
            all: [.ink2: "#303030", .statusBlocked: "#FF0000"],
            dark: [.statusBlocked: "#00FF00"],
            light: [.statusBlocked: "#0000FF"])
        let theme = ThemeResolver.resolve(
            base: base, variant: chrome, custom: custom, look: .dark, customOverrides: overrides
        ).theme
        #expect(theme.themeColor(.ink1).hex == "#101010")  // custom file wins over look
        #expect(theme.themeColor(.island).hex == "#010101")  // custom file wins over base
        #expect(theme.themeColor(.ink2).hex == "#303030")  // [appearance.colors] wins over custom file
        #expect(theme.themeColor(.statusBlocked).hex == "#00FF00")  // look-specific override wins last
        #expect(theme.themeColor(.ink3).hex == "#7A8393")  // untouched role from the look
        #expect(theme.variantID == "mine")
    }

    @Test func customOverrideWinsOverLook() {
        let theme = ThemeResolver.resolve(
            base: base, variant: chrome, look: .light, customOverrides: [.statusBlocked: "#123456"]
        ).theme
        #expect(theme.themeColor(.statusBlocked).hex == "#123456")
    }

    @Test func accessibilityKeepsTheUserHue() {
        let userHue = "#3366CC"
        let plain = ThemeResolver.resolve(
            base: base, variant: chrome, look: .dark, customOverrides: [.ink3: userHue]
        ).theme
        let contrast = ThemeResolver.resolve(
            base: base, variant: chrome, look: .dark, customOverrides: [.ink3: userHue],
            accessibility: AccessibilityAdjustments(increaseContrast: true)
        ).theme
        let before = plain.themeColor(.ink3).hsl
        let after = contrast.themeColor(.ink3).hsl
        #expect(plain.themeColor(.ink3).hex == userHue)
        #expect(after.lightness > before.lightness)
        #expect(abs(after.hue - before.hue) < 1)
        #expect(abs(after.saturation - before.saturation) < 0.01)
    }

    @Test func accessibilityOnlyChangesLightness() {
        let adjustments = AccessibilityAdjustments(increaseContrast: true, reduceTransparency: true, reduceMotion: true)
        for hex in ["#FF7B8C", "#126F8C", "#5D6676", "#8A93A2"] {
            let color = ThemeColor(hex: hex)!
            for look in Look.allCases {
                for role in ColorRole.allCases {
                    let adjusted = adjustments.adjust(color, role: role, look: look)
                    #expect(abs(adjusted.hsl.hue - color.hsl.hue) < 1)
                }
            }
        }
        let light = ThemeResolver.resolve(
            base: base, variant: chrome, look: .light,
            accessibility: AccessibilityAdjustments(increaseContrast: true)
        ).theme
        #expect(light.themeColor(.ink3).hsl.lightness < ThemeColor(hex: "#5D6676")!.hsl.lightness)
        #expect(light.themeColor(.statusBlocked).hex == "#C8243F")
    }

    @Test func darkQuotaWarningTextFallsBackToQuotaWarning() {
        let dark = ThemeResolver.resolve(base: base, variant: chrome, look: .dark).theme
        #expect(chrome.looks["dark"]?.colors["quota-warning-text"] == nil)
        #expect(dark.defines(.quotaWarningText))
        #expect(dark.themeColor(.quotaWarningText).hex == "#FFE14D")
        let overridden = ThemeResolver.resolve(
            base: base, variant: chrome, look: .dark, customOverrides: [.quotaWarning: "#ABCDEF"]
        ).theme
        #expect(overridden.themeColor(.quotaWarningText).hex == "#ABCDEF")
        let light = ThemeResolver.resolve(base: base, variant: chrome, look: .light).theme
        #expect(light.themeColor(.quotaWarningText).hex == "#7E6300")
    }

    @Test func schemaTooNewFallsBackAndReports() {
        var future = chrome
        future.id = "future"
        future.schema = supportedThemeSchema + 1
        future.looks["dark"] = LookTokens(colors: ["ink-1": "#FF0000"])
        let resolution = ThemeResolver.resolve(base: base, variant: future, fallbackVariant: chrome, look: .dark)
        #expect(resolution.problems == [.schemaTooNew(themeID: "future", file: nil, found: 2, supported: 1)])
        #expect(resolution.theme.variantID == "chrome-hologram")
        #expect(resolution.theme.themeColor(.ink1).hex == "#E8ECF2")

        let customOnly = ThemeResolver.resolve(base: base, variant: chrome, custom: future, look: .dark)
        #expect(customOnly.problems.count == 1)
        #expect(customOnly.theme.themeColor(.ink1).hex == "#E8ECF2")
    }

    @Test func schemaTooNewFileIsReportedByTheLoader() throws {
        let toml = """
            schema = 99
            id = "later"
            [looks.dark.colors]
            ink-1 = { new = "shape" }
            """
        let result = ThemeLoader.decodeVariant(Data(toml.utf8), file: "later.toml")
        #expect(throws: ThemeProblem.schemaTooNew(themeID: "later", file: "later.toml", found: 99, supported: 1)) {
            try result.get()
        }
    }

    @Test func unknownThemeIDFallsBackToDefault() {
        let resolution = Fixtures.library.resolve(themeID: "nope", look: .dark)
        #expect(resolution.problems == [.unknownTheme(themeID: "nope")])
        #expect(resolution.theme.variantID == "chrome-hologram")
    }
}

@Suite struct ThemeTypographyTests {
    let dark = Fixtures.library.resolve(themeID: "chrome-hologram", look: .dark).theme

    @Test func readoutValueIsSFProWithTabularDigits() {
        let spec = dark.fontSpec(.readoutValue)
        #expect(spec.family == .system)
        #expect(spec.tabularDigits)
        #expect(spec.size == 14)
        #expect(spec.weight == 300)
        #expect(spec.lineHeight == 13)
    }

    @Test func liveNumeralRolesUseTabularDigitsAndSystemFonts() {
        for role in [TypographyRole.readoutValue, .numeralBig, .timeValue, .rowStatus] {
            let spec = dark.fontSpec(role)
            #expect(spec.tabularDigits, "\(role)")
            #expect(spec.family == .system || spec.family == .monospaced, "\(role)")
        }
    }

    @Test func codeIsSFMonoAndTrackingIsEmTimesSize() {
        #expect(dark.fontSpec(.code).family == .monospaced)
        #expect(abs(dark.tracking(.kicker) - 9 * 0.24) < 0.0001)
        #expect(abs(dark.tracking(.numeralBig) - 38 * -0.02) < 0.0001)
    }

    @Test func proseFallsBackToBodyInChromeHologram() {
        #expect(dark.fontSpec(.prose) == dark.fontSpec(.body))
    }

    @Test func twinMetalUsesCondensedAndUnitlessLineHeight() throws {
        let c = Fixtures.library.resolve(themeID: "twin-metal-tactical", look: .dark).theme
        #expect(c.fontSpec(.readoutLabel).family == .custom("AvenirNextCondensed-DemiBold"))
        let prose = c.fontSpec(.prose)
        #expect(abs(try #require(prose.lineHeight) - 11.5 * 1.45) < 0.0001)
        #expect(c.fontSpec(.readoutValue).family == .monospaced)
    }

    @Test func twinMetalLightKeepsGoldTextApartFromGoldFills() {
        let light = Fixtures.library.resolve(themeID: "twin-metal-tactical", look: .light).theme
        #expect(light.defines(.gold) && light.defines(.goldText))
        #expect(light.themeColor(.goldText) != light.themeColor(.gold))
        #expect(light.themeColor(.goldText).hex == "#765709")
        #expect(light.themeColor(.gold).hex == "#A07418")
    }

    @Test func twinMetalHasDarkAndLightLooksWithSameRolesAsChrome() {
        for look in Look.allCases {
            let c = Fixtures.library.resolve(themeID: "twin-metal-tactical", look: look).theme
            #expect(c.variantID == "twin-metal-tactical" && c.look == look)
            #expect(c.defines(.ink1) && c.defines(.surfacePanel) && c.defines(.statusBlocked))
        }
    }
}

@Suite struct ThemeFilesTests {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let repoThemes = root.appending(path: "Themes")
    static let resourceThemes = root.appending(path: "Packages/VigieUI/Sources/VigieUI/Resources/Themes")

    static func tomlFiles(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".toml") }.sorted()
    }

    @Test func resourceCopyIsByteIdenticalToRepositoryThemes() throws {
        let repo = try Self.tomlFiles(in: Self.repoThemes)
        #expect(repo == ["base.toml", "chrome-hologram.toml", "twin-metal-tactical.toml"])
        #expect(try Self.tomlFiles(in: Self.resourceThemes) == repo)
        for name in repo {
            let a = try Data(contentsOf: Self.repoThemes.appending(path: name))
            let b = try Data(contentsOf: Self.resourceThemes.appending(path: name))
            #expect(a == b, "\(name) differs between Themes/ and VigieUI resources")
        }
        let bundled = try #require(ThemeLoader.bundledThemesURL)
        for name in repo {
            #expect(
                try Data(contentsOf: bundled.appending(path: name))
                    == Data(contentsOf: Self.repoThemes.appending(path: name)))
        }
    }

    @Test func everyColorIsSixDigitHex() throws {
        let library = Fixtures.library
        var colors = Array(library.base.colors.values)
        for theme in library.builtIns.values {
            for look in theme.looks.values { colors += look.colors.values }
        }
        #expect(colors.count > 40)
        let pattern = /^#[0-9A-F]{6}$/
        for color in colors { #expect(color.wholeMatch(of: pattern) != nil, "\(color)") }
    }

    @Test func customThemesRejectBuiltInIDs() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vigie-themes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("schema = 1\nid = \"chrome-hologram\"\n".utf8).write(to: folder.appending(path: "a.toml"))
        try Data("schema = 1\nid = \"mine\"\nextends = \"base\"\n".utf8).write(to: folder.appending(path: "b.toml"))
        try Data("schema = 7\nid = \"later\"\n".utf8).write(to: folder.appending(path: "c.toml"))
        let (themes, problems) = ThemeLoader.loadCustom(from: folder)
        #expect(themes.map(\.id) == ["mine"])
        #expect(
            problems == [
                .idClash(themeID: "chrome-hologram", file: "a.toml"),
                .schemaTooNew(themeID: "later", file: "c.toml", found: 7, supported: 1),
            ])
    }

    @Test func libraryLoadsCustomThemesFromAFolderAndListsThem() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vigie-themes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(
            """
            schema = 1
            id = "mine"
            name = "Aardvark"
            extends = "twin-metal-tactical"
            [looks.dark.colors]
            ink-1 = "#010203"
            """.utf8
        ).write(to: folder.appending(path: "mine.toml"))
        try Data("schema = 1\nid = \"twin-metal-tactical\"\n".utf8).write(to: folder.appending(path: "clash.toml"))
        let library = Fixtures.library.replacingCustomThemes(from: folder)
        #expect(library.choices.map(\.id) == ["chrome-hologram", "twin-metal-tactical", "mine"])
        #expect(library.choices.map(\.isCustom) == [false, false, true])
        #expect(library.problems == [.idClash(themeID: "twin-metal-tactical", file: "clash.toml")])
        // It extends the shared base and a built-in skin, and overrides token values.
        let resolved = library.resolve(themeID: "mine", look: .dark).theme
        #expect(resolved.variantID == "mine")
        #expect(resolved.themeColor(.ink1).hex == "#010203")
        #expect(resolved.themeColor(.gold).hex == library.builtIns["twin-metal-tactical"]!.tokens(for: .dark).colors["gold"])
        // A missing folder means no custom themes.
        #expect(Fixtures.library.replacingCustomThemes(from: nil).customs.isEmpty)
        #expect(Fixtures.library.replacingCustomThemes(from: folder.appending(path: "nope")).customs.isEmpty)
    }

    @Test func newerSchemaCustomThemeFallsBackToTheDefaultTheme() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vigie-themes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("schema = 9\nid = \"later\"\n".utf8).write(to: folder.appending(path: "later.toml"))
        let library = Fixtures.library.replacingCustomThemes(from: folder)
        #expect(library.customs.isEmpty)
        #expect(library.problems == [.schemaTooNew(themeID: "later", file: "later.toml", found: 9, supported: 1)])
        let resolution = library.resolve(themeID: "later", look: .dark)
        #expect(resolution.theme.variantID == ThemeLibrary.defaultVariantID)
    }
}

@MainActor @Suite struct ThemeControllerTests {
    @Test func islandIsDarkEvenWhenModeIsLight() {
        let controller = ThemeController(library: Fixtures.library, mode: .light)
        #expect(controller.theme.look == .light)
        #expect(controller.islandTheme.look == .dark)
        #expect(controller.islandTheme.themeColor(.surfacePanel).hex == "#0A0E16")
        #expect(controller.theme.themeColor(.surfacePanel).hex == "#F3F5F9")
    }

    @Test func systemModeFollowsMacOSLiveAndForcedModesDoNot() {
        let controller = ThemeController(library: Fixtures.library, mode: .system, systemIsDark: false)
        #expect(controller.theme.look == .light)
        controller.updateSystemAppearance(isDark: true)
        #expect(controller.theme.look == .dark)
        controller.mode = .light
        #expect(controller.theme.look == .light)
        controller.updateSystemAppearance(isDark: false)
        controller.mode = .dark
        #expect(controller.theme.look == .dark)
        #expect(controller.islandTheme.look == .dark)
    }

    @Test func reduceMotionForcesCalm() {
        let controller = ThemeController(library: Fixtures.library, presence: .full)
        #expect(controller.effectivePresence == .full)
        controller.updateAccessibility(AccessibilityAdjustments(reduceMotion: true))
        #expect(controller.effectivePresence == .calm)
        #expect(controller.theme.presence == .calm)
        controller.updateAccessibility(.none)
        controller.presence = .calm
        #expect(controller.theme.presence == .calm)
    }

    @Test func overridesApplyToPanelsAndIsland() {
        let controller = ThemeController(library: Fixtures.library, mode: .light)
        controller.overrides = ColorOverrides(dark: [.statusBlocked: "#111111"], light: [.statusBlocked: "#222222"])
        #expect(controller.theme.themeColor(.statusBlocked).hex == "#222222")
        #expect(controller.islandTheme.themeColor(.statusBlocked).hex == "#111111")
    }

    @Test func environmentDefaultIsChromeHologramDark() {
        #expect(ThemeEnvironmentDefaults.theme.variantID == "chrome-hologram")
        #expect(ThemeEnvironmentDefaults.theme.look == .dark)
    }
}
