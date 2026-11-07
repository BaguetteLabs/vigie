import Foundation

/// An sRGB color parsed from a `#RRGGBB` token. Pure value; ``Theme`` turns it into SwiftUI/AppKit colors.
public struct ThemeColor: Sendable, Equatable, Hashable {
    /// Components in 0...1.
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red.clamped01
        self.green = green.clamped01
        self.blue = blue.clamped01
    }

    /// Parses `#RRGGBB` (case-insensitive). Returns nil for anything else.
    public init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 7, trimmed.first == "#",
            let value = UInt32(trimmed.dropFirst(), radix: 16)
        else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// `#RRGGBB`, uppercase.
    public var hex: String {
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    // MARK: HSL

    /// Hue in degrees (0..<360), saturation and lightness in 0...1.
    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let lightness = (maxC + minC) / 2
        let delta = maxC - minC
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maxC {
        case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, saturation, lightness)
    }

    public init(hue: Double, saturation: Double, lightness: Double) {
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let h = hue / 60
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        let m = lightness - c / 2
        self.init(red: r + m, green: g + m, blue: b + m)
    }

    /// The same hue and saturation at a different lightness. The only change accessibility may make (AD-14).
    public func withLightness(_ lightness: Double) -> ThemeColor {
        let (h, s, _) = hsl
        return ThemeColor(hue: h, saturation: s, lightness: lightness.clamped01)
    }
}

extension Double {
    fileprivate var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}

// MARK: - WCAG contrast

extension ThemeColor {
    /// WCAG 2.x relative luminance (sRGB).
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio with another color (1...21), unrounded.
    public func contrastRatio(with other: ThemeColor) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// This color drawn at `opacity` over an opaque `background` (source-over in sRGB, as browsers and
    /// Core Graphics composite by default).
    public func composited(opacity: Double, over background: ThemeColor) -> ThemeColor {
        let a = opacity.clamped01
        return ThemeColor(
            red: red * a + background.red * (1 - a),
            green: green * a + background.green * (1 - a),
            blue: blue * a + background.blue * (1 - a))
    }

    /// The lowest contrast against any of `surfaces` (infinity when there are none).
    public func worstContrast(against surfaces: [ThemeColor]) -> Double {
        surfaces.map(contrastRatio(with:)).min() ?? .infinity
    }

    /// Moves lightness only (hue and saturation kept, AD-14) away from the surfaces until this color reaches
    /// `minimum` against every one of them: lighter in a dark look, darker in a light look. Never lowers
    /// contrast; returns `self` when it already passes.
    public func raisingContrast(against surfaces: [ThemeColor], to minimum: Double, look: Look) -> ThemeColor {
        guard worstContrast(against: surfaces) < minimum else { return self }
        let (hue, saturation, start) = hsl
        let step = look == .dark ? 0.005 : -0.005
        var lightness = start
        while look == .dark ? lightness < 1 : lightness > 0 {
            lightness = (lightness + step).clamped01
            let candidate = ThemeColor(hue: hue, saturation: saturation, lightness: lightness)
            if candidate.worstContrast(against: surfaces) >= minimum { return candidate }
        }
        return ThemeColor(hue: hue, saturation: saturation, lightness: lightness)
    }
}

/// macOS accessibility display settings, resolved once in VigieUI (AD-14). The derived rules every surface
/// reads live in ``AccessibilityRules`` (`theme.a11y`).
public struct AccessibilityAdjustments: Sendable, Equatable {
    public var increaseContrast: Bool
    public var reduceTransparency: Bool
    public var reduceMotion: Bool

    public init(increaseContrast: Bool = false, reduceTransparency: Bool = false, reduceMotion: Bool = false) {
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
        self.reduceMotion = reduceMotion
    }

    public static let none = AccessibilityAdjustments()

    /// Roles whose contrast against the panel is raised under Increase contrast.
    static let contrastRoles: Set<ColorRole> = [.ink2, .ink3, .line, .lineSilver]

    /// Lightness shift applied to ``contrastRoles`` under Increase contrast (away from the panel).
    static let contrastShift = 0.15

    /// Text-capable roles: under Increase contrast each reaches at least 4.5:1 on every surface of its look
    /// (DESIGN Contrast, UX-DR13). The defaults already pass; this lifts a user override that does not.
    static let textFloorRoles: Set<ColorRole> = [
        .ink1, .ink2, .ink3, .goldText, .quotaWarningText, .iris1, .iris2, .iris3,
        .statusIdle, .statusWorking, .statusDone, .statusBlocked, .statusFailed, .paceOn, .paceAhead,
    ]

    /// Non-text meaning and decorative-only roles: under Increase contrast each reaches at least 3:1
    /// (WCAG 1.4.11; DESIGN Contrast "Decorative-only elements … must reach 3:1 under Increase contrast",
    /// UX-DR95).
    static let nonTextFloorRoles: Set<ColorRole> = [
        .gold, .quotaWarning, .structure, .filament1, .filament2, .filament3, .lineSilver, .line,
    ]

    public static let textMinimum = 4.5
    public static let nonTextMinimum = 3.0

    /// The surfaces a role is checked against in a look: panel and card everywhere, the black island in
    /// dark looks (the island always uses the dark set), the virtual notch in light looks.
    static func surfaceRoles(_ look: Look) -> [ColorRole] {
        look == .dark
            ? [.surfacePanel, .surfaceCard, .island]
            : [.surfacePanel, .surfaceCard, .surfaceVNTop, .surfaceVNBottom]
    }

    /// Adjusts one resolved color. Pure; it can only move lightness, so a user-chosen hue is never discarded.
    public func adjust(_ color: ThemeColor, role: ColorRole, look: Look) -> ThemeColor {
        guard increaseContrast, Self.contrastRoles.contains(role) else { return color }
        let lightness = color.hsl.lightness
        let target = look == .dark ? lightness + Self.contrastShift : lightness - Self.contrastShift
        return color.withLightness(target)
    }

    /// The accessibility step of the resolver (last, once; AD-14). Under Increase contrast: the
    /// ``contrastRoles`` shift, then text roles floored at 4.5:1 and non-text roles at 3:1 against every
    /// surface of the look. Lightness moves only, so a user override keeps its hue; contrast only rises.
    /// Reduce transparency and Reduce motion change no color (they are read through ``AccessibilityRules``).
    public func apply(to colors: [ColorRole: ThemeColor], look: Look) -> [ColorRole: ThemeColor] {
        guard increaseContrast else { return colors }
        var adjusted = colors
        for (role, color) in colors { adjusted[role] = adjust(color, role: role, look: look) }
        let surfaces = Self.surfaceRoles(look).compactMap { colors[$0] }
        guard !surfaces.isEmpty else { return adjusted }
        for (role, color) in adjusted {
            let minimum: Double
            if Self.textFloorRoles.contains(role) {
                minimum = Self.textMinimum
            } else if Self.nonTextFloorRoles.contains(role) {
                minimum = Self.nonTextMinimum
            } else {
                continue
            }
            adjusted[role] = color.raisingContrast(against: surfaces, to: minimum, look: look)
        }
        return adjusted
    }
}
