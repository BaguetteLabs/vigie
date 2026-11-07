import Foundation
import os

/// A setup problem found while loading or resolving themes. Story 3.4 turns these into setup-problem alerts.
public enum ThemeProblem: Error, Sendable, Equatable, Hashable {
    /// The file declares a `schema` newer than this build reads; the base/default theme is used instead.
    case schemaTooNew(themeID: String, file: String?, found: Int, supported: Int)
    /// A custom theme reuses a built-in id; the custom file is ignored.
    case idClash(themeID: String, file: String)
    /// A file could not be read or decoded.
    case unreadable(file: String, reason: String)
    /// The requested theme id does not exist; the default theme is used instead.
    case unknownTheme(themeID: String)
}

/// `[appearance.colors]` overrides: `all` applies to every look, then the look-specific table (AD-14).
public struct ColorOverrides: Sendable, Equatable, ExpressibleByDictionaryLiteral {
    public var all: [ColorRole: String]
    public var dark: [ColorRole: String]
    public var light: [ColorRole: String]

    public init(all: [ColorRole: String] = [:], dark: [ColorRole: String] = [:], light: [ColorRole: String] = [:]) {
        self.all = all
        self.dark = dark
        self.light = light
    }

    /// Overrides for every look.
    public init(dictionaryLiteral elements: (ColorRole, String)...) {
        self.init(all: Dictionary(elements, uniquingKeysWith: { _, last in last }), dark: [:], light: [:])
    }

    public static let none = ColorOverrides(all: [:], dark: [:], light: [:])

    func forLook(_ look: Look) -> [ColorRole: String] {
        look == .dark ? dark : light
    }
}

/// The result of resolving a theme: always a usable theme, plus any problems to report.
public struct ThemeResolution: Sendable, Equatable {
    public var theme: Theme
    public var problems: [ThemeProblem]
}

/// Pure theme resolution (AD-14). Last wins: base -> variant (skin) -> look -> custom theme file ->
/// `[appearance.colors]` -> `[appearance.colors.<look>]` -> accessibility adjustments.
public enum ThemeResolver {
    static let logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "theme")

    /// - Parameters:
    ///   - base: the shared base file.
    ///   - variant: the built-in skin.
    ///   - custom: an optional custom theme file layered on the skin.
    ///   - fallbackVariant: used when `variant` declares a newer schema (the default built-in theme).
    public static func resolve(
        base: BaseThemeFile,
        variant: ThemeFile,
        custom: ThemeFile? = nil,
        fallbackVariant: ThemeFile? = nil,
        look: Look,
        customOverrides: ColorOverrides = .none,
        accessibility: AccessibilityAdjustments = .none
    ) -> ThemeResolution {
        var problems: [ThemeProblem] = []
        var skin = variant
        if variant.schema > supportedThemeSchema {
            problems.append(
                .schemaTooNew(themeID: variant.id, file: nil, found: variant.schema, supported: supportedThemeSchema))
            let usable = fallbackVariant.flatMap { $0.schema <= supportedThemeSchema ? $0 : nil }
            skin = usable ?? ThemeFile(id: baseThemeID, name: base.name)
        }
        var layer = custom
        if let c = custom, c.schema > supportedThemeSchema {
            problems.append(.schemaTooNew(themeID: c.id, file: nil, found: c.schema, supported: supportedThemeSchema))
            layer = nil
        }

        // Colors as strings, merged in order.
        var raw: [String: String] = base.colors
        raw.merge(skin.tokens(for: look).colors) { _, new in new }
        if let layer { raw.merge(layer.tokens(for: look).colors) { _, new in new } }

        var colors: [ColorRole: ThemeColor] = [:]
        for (key, value) in raw {
            guard let role = ColorRole(rawValue: key) else {
                logger.debug("theme \(skin.id, privacy: .public): ignoring unknown color role \(key, privacy: .public)")
                continue
            }
            guard let color = ThemeColor(hex: value) else {
                logger.error("theme \(skin.id, privacy: .public): invalid color \(key, privacy: .public)")
                continue
            }
            colors[role] = color
        }
        for (role, value) in customOverrides.all.merging(customOverrides.forLook(look), uniquingKeysWith: { $1 }) {
            if let color = ThemeColor(hex: value) { colors[role] = color }
        }
        // DESIGN.md Token scheme: in a dark look, quota-warning-text resolves to quota-warning.
        if look == .dark, colors[.quotaWarningText] == nil, let warning = colors[.quotaWarning] {
            colors[.quotaWarningText] = warning
        }
        for (role, color) in colors {
            colors[role] = accessibility.adjust(color, role: role, look: look)
        }

        var typographyRaw = skin.typography
        if let layer { typographyRaw.merge(layer.typography) { _, new in new } }
        var typography: [TypographyRole: TypographyToken] = [:]
        for (key, token) in typographyRaw {
            if let role = TypographyRole(rawValue: key) { typography[role] = token }
        }

        var rounded = base.rounded.merging(skin.rounded) { _, new in new }
        var motion = base.motion.merging(skin.motion) { _, new in new }
        if let layer {
            rounded.merge(layer.rounded) { _, new in new }
            motion.merge(layer.motion) { _, new in new }
        }

        let theme = Theme(
            variantID: layer?.id ?? skin.id,
            variantName: layer?.name ?? skin.name,
            look: look,
            colors: colors,
            typography: typography,
            rounded: rounded,
            spacing: base.spacing,
            motion: motion,
            components: base.components,
            accessibility: accessibility,
            presence: accessibility.reduceMotion ? .calm : .full
        )
        return ThemeResolution(theme: theme, problems: problems)
    }
}
