import AppKit
import SwiftUI

/// A fully resolved theme for one look (AD-14): base -> variant -> look -> custom theme -> user overrides
/// -> accessibility. Views read every color, metric, radius, duration and font role from here.
public struct Theme: Sendable, Equatable {
    public var variantID: String
    public var variantName: String
    public var look: Look
    public var colors: [ColorRole: ThemeColor]
    public var typography: [TypographyRole: TypographyToken]
    public var rounded: [String: String]
    public var spacing: [String: String]
    public var motion: [String: String]
    public var components: [String: [String: String]]
    public var accessibility: AccessibilityAdjustments
    /// Presence level in effect (calm when the user chose it or Reduce motion is on).
    public var presence: PresenceLevel

    public init(
        variantID: String,
        variantName: String,
        look: Look,
        colors: [ColorRole: ThemeColor] = [:],
        typography: [TypographyRole: TypographyToken] = [:],
        rounded: [String: String] = [:],
        spacing: [String: String] = [:],
        motion: [String: String] = [:],
        components: [String: [String: String]] = [:],
        accessibility: AccessibilityAdjustments = .none,
        presence: PresenceLevel = .full
    ) {
        self.variantID = variantID
        self.variantName = variantName
        self.look = look
        self.colors = colors
        self.typography = typography
        self.rounded = rounded
        self.spacing = spacing
        self.motion = motion
        self.components = components
        self.accessibility = accessibility
        self.presence = presence
    }

    /// An empty theme, used only when the bundled themes cannot be read (a build defect).
    public static let empty = Theme(variantID: "", variantName: "", look: .dark)

    // MARK: Colors

    /// The resolved color for a role, following documented fallbacks for roles a look does not define:
    /// `quota-warning-text` -> `quota-warning`, `gold-text` -> `gold`, `filament-n` -> `iris-n`,
    /// `surface-vn-*` -> `island` in dark looks (DESIGN.md Token scheme) or `surface-panel` in light,
    /// anything else -> `ink-1`.
    public func themeColor(_ role: ColorRole) -> ThemeColor {
        if let value = colors[role] { return value }
        let fallback: ColorRole? =
            switch role {
            case .quotaWarningText: .quotaWarning
            case .goldText: .gold
            case .filament1: .iris1
            case .filament2: .iris2
            case .filament3: .iris3
            case .surfaceVNTop, .surfaceVNBottom: look == .dark ? .island : .surfacePanel
            case .ink1: nil
            default: .ink1
            }
        if let fallback, fallback != role { return themeColor(fallback) }
        return ThemeColor(red: 0, green: 0, blue: 0)
    }

    /// True when the active look defines the role itself (no fallback).
    public func defines(_ role: ColorRole) -> Bool { colors[role] != nil }

    public func color(_ role: ColorRole) -> Color {
        let c = themeColor(role)
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }

    public func nsColor(_ role: ColorRole) -> NSColor {
        let c = themeColor(role)
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    // MARK: Typography

    /// Parsed typography token. Prose falls back to body (Chrome Hologram uses body for prose).
    public func fontSpec(_ role: TypographyRole) -> FontSpec {
        let token = typography[role] ?? (role == .prose ? typography[.body] : nil)
        guard let token else { return FontSpec(family: .system, size: 13, weight: 400, tabularDigits: false) }
        return FontSpec(token: token, role: role)
    }

    public func font(_ role: TypographyRole) -> Font { fontSpec(role).font }

    /// Letter spacing in points for `.tracking(_:)`.
    public func tracking(_ role: TypographyRole) -> CGFloat { fontSpec(role).tracking }

    // MARK: Metrics

    public func radius(_ role: RadiusRole) -> CGFloat {
        rounded[role.rawValue].flatMap(ThemeValue.length) ?? 0
    }

    public func spacing(_ role: SpacingRole) -> CGFloat {
        spacing[role.rawValue].flatMap(ThemeValue.length) ?? 0
    }

    /// A copy whose `spacing.band-height` is at least `height`: the band over a physical notch must cover the
    /// glass (reported height plus `closed.notch_overlap`).
    public func withBandHeight(atLeast height: CGFloat) -> Theme {
        guard height > spacing(.bandHeight) else { return self }
        return withBandHeight(height)
    }

    /// A copy whose `spacing.band-height` is exactly `height`, lower or higher: a virtual notch is as tall as
    /// its display's menu bar (Story 2.16), and the closed-notch content scales to that band
    /// (``ClosedBandMetrics``). A non-positive or non-finite `height` keeps the theme as it is.
    public func withBandHeight(_ height: CGFloat) -> Theme {
        guard height > 0, height.isFinite, height != spacing(.bandHeight) else { return self }
        var copy = self
        copy.spacing[SpacingRole.bandHeight.rawValue] = "\(height)px"
        return copy
    }

    public func motion(_ role: MotionRole) -> Duration {
        motion[role.rawValue].flatMap(ThemeValue.duration) ?? .zero
    }

    /// The motion token in seconds, for SwiftUI `Animation` APIs.
    public func motionSeconds(_ role: MotionRole) -> TimeInterval {
        let d = motion(role).components
        return Double(d.seconds) + Double(d.attoseconds) / 1e18
    }

    // MARK: Components

    /// Raw component spec value (`components.<name>.<key>`), e.g. `"540px"` or `"{spacing.band-height}"`.
    public func component(_ name: String, _ key: String) -> String? {
        components[name]?[key]
    }

    /// A component length in points, following `{spacing.*}` and `{rounded.*}` references.
    public func componentLength(_ name: String, _ key: String) -> CGFloat? {
        guard let raw = component(name, key) else { return nil }
        guard raw.hasPrefix("{"), raw.hasSuffix("}") else { return ThemeValue.length(raw) }
        let reference = raw.dropFirst().dropLast().split(separator: ".", maxSplits: 1).map(String.init)
        guard reference.count == 2 else { return nil }
        let table: [String: String]
        switch reference[0] {
        case "spacing": table = spacing
        case "rounded": table = rounded
        default: return nil
        }
        let key = reference[1]
        let value = table[key] ?? table[ThemeValue.strippingVariantPrefix(key)]
        return value.flatMap(ThemeValue.length)
    }
}

/// A typography token parsed into SwiftUI terms.
public struct FontSpec: Sendable, Equatable {
    public enum Family: Sendable, Equatable {
        /// SF Pro.
        case system
        /// SF Mono.
        case monospaced
        /// A macOS-installed family by PostScript name (Avenir Next Condensed).
        case custom(String)
    }

    public var family: Family
    public var size: CGFloat
    /// CSS weight (100...900).
    public var weight: Int
    /// Tabular (monospaced) digits for live numerals.
    public var tabularDigits: Bool
    /// Letter spacing in points.
    public var tracking: CGFloat
    /// Line height in points, when the token sets one.
    public var lineHeight: CGFloat?

    public init(
        family: Family,
        size: CGFloat,
        weight: Int,
        tabularDigits: Bool,
        tracking: CGFloat = 0,
        lineHeight: CGFloat? = nil
    ) {
        self.family = family
        self.size = size
        self.weight = weight
        self.tabularDigits = tabularDigits
        self.tracking = tracking
        self.lineHeight = lineHeight
    }

    init(token: TypographyToken, role: TypographyRole) {
        let size = ThemeValue.length(token.fontSize) ?? 13
        let weight = Int(token.fontWeight) ?? 400
        let familyName = token.fontFamily
        let family: Family
        if familyName.hasPrefix("SF Mono") {
            family = .monospaced
        } else if familyName.hasPrefix("SF Pro") {
            family = .system
        } else {
            family = .custom(FontSpec.postScriptName(family: familyName, weight: weight))
        }
        self.init(
            family: family,
            size: size,
            weight: weight,
            tabularDigits: family == .monospaced || role.usesTabularDigits,
            tracking: token.letterSpacing.flatMap { ThemeValue.em($0, size: size) } ?? 0,
            lineHeight: token.lineHeight.flatMap { ThemeValue.lineHeight($0, size: size) }
        )
    }

    /// `Avenir Next Condensed` + 600 -> `AvenirNextCondensed-DemiBold`.
    static func postScriptName(family: String, weight: Int) -> String {
        let face =
            switch weight {
            case ..<250: "UltraLight"
            case ..<450: "Regular"
            case ..<550: "Medium"
            case ..<650: "DemiBold"
            case ..<750: "Bold"
            default: "Heavy"
            }
        return family.replacingOccurrences(of: " ", with: "") + "-" + face
    }

    public var swiftUIWeight: Font.Weight {
        switch weight {
        case ..<150: .ultraLight
        case ..<250: .thin
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
    }

    public var font: Font {
        var font: Font =
            switch family {
            case .system: .system(size: size, weight: swiftUIWeight)
            case .monospaced: .system(size: size, weight: swiftUIWeight, design: .monospaced)
            case .custom(let name): .custom(name, fixedSize: size)
            }
        if tabularDigits { font = font.monospacedDigit() }
        return font
    }
}

/// Parsers for token strings (`14px`, `0.24em`, `1.45`, `280ms`, `1.5s`).
enum ThemeValue {
    /// `14px` or `14` -> 14 (px map 1:1 to points).
    static func length(_ raw: String) -> CGFloat? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let number = s.hasSuffix("px") ? String(s.dropLast(2)) : s
        return Double(number).map { CGFloat($0) }
    }

    /// `0.24em` -> 0.24 * size.
    static func em(_ raw: String, size: CGFloat) -> CGFloat? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("em"), let v = Double(s.dropLast(2)) { return CGFloat(v) * size }
        return length(s)
    }

    /// `13px` -> 13; unitless `1.45` -> 1.45 * size.
    static func lineHeight(_ raw: String, size: CGFloat) -> CGFloat? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("px") { return length(s) }
        return Double(s).map { CGFloat($0) * size }
    }

    /// `280ms` / `1.5s` -> Duration.
    static func duration(_ raw: String) -> Duration? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("ms"), let v = Double(s.dropLast(2)) { return .nanoseconds(Int64((v * 1e6).rounded())) }
        if s.hasSuffix("s"), let v = Double(s.dropLast(1)) { return .nanoseconds(Int64((v * 1e9).rounded())) }
        return nil
    }

    /// `a-card` -> `card` (DESIGN.md variant prefixes `a-` and `c-`).
    static func strippingVariantPrefix(_ key: String) -> String {
        for prefix in ["a-", "c-"] where key.hasPrefix(prefix) { return String(key.dropFirst(2)) }
        return key
    }
}
