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

/// macOS accessibility display settings, resolved once in VigieUI (AD-14).
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

    /// Adjusts one resolved color. Pure; it can only move lightness, so a user-chosen hue is never discarded.
    public func adjust(_ color: ThemeColor, role: ColorRole, look: Look) -> ThemeColor {
        guard increaseContrast, Self.contrastRoles.contains(role) else { return color }
        let lightness = color.hsl.lightness
        let target = look == .dark ? lightness + Self.contrastShift : lightness - Self.contrastShift
        return color.withLightness(target)
    }
}
