import SwiftUI

/// Fixed proportions of the shared components that DESIGN.md states in prose rather than as tokens
/// (opacities of hairlines and fills, mark sizes). Lengths and colors still come from the theme.
enum ComponentMetrics {
    /// 1px hairlines, rings and filaments.
    static let hairline: CGFloat = 1
    /// How far a card meta may shrink when the card keeps its title whole.
    static let metaMinimumScale: CGFloat = 0.5
    /// C inner corner marks: 7px arms.
    static let cornerMark: CGFloat = 7
    /// Action button height when `components.action-button.height` is missing.
    static let actionHeight: CGFloat = 30
    /// The break peek's half-width actions (mockup 1.7e `.acts3 .act`): 11px side padding, and how far the label
    /// may shrink before it truncates.
    static let compactActionPaddingX: CGFloat = 11
    static let compactActionMinimumScale: CGFloat = 0.8
    /// Setup card max width when `components.setup-card.max-width` is missing.
    static let setupMaxWidth: CGFloat = 380
    /// Empty-state sentence max width (mock: 320px).
    static let emptySentenceMaxWidth: CGFloat = 320
    /// `i`-in-square mark (mock: 12px, 3px radius).
    static let infoMark: CGFloat = 12
    /// Scroll fade mask height.
    static let scrollFade: CGFloat = 18
    /// Minimum scroll thumb length.
    static let minimumThumb: CGFloat = 14
    /// Grip dots: 2 columns × 3 rows, 2px dots on a 4px pitch.
    static let gripDot: CGFloat = 2
    static let gripPitch: CGFloat = 4

    // Opacities (DESIGN "Components", "Elevation & Depth").
    /// A widget-card iris filament: 45% dark, 80% light.
    static func filamentOpacity(_ look: Look) -> Double { look == .dark ? 0.45 : 0.8 }
    /// A card inner hairline: translucent platinum (dark) / graphite (light).
    static func cardHairline(_ look: Look) -> Double { look == .dark ? 0.06 : 0.08 }
    /// C corner marks: struct at 38%.
    static let cornerMarkOpacity = 0.38
    /// A action border: platinum at 22% (secondary dimmer).
    static let actionBorderPrimary = 0.22
    static let actionBorderSecondary = 0.12
    /// A glass gradient on primary actions (dark): white 12% → 3%.
    static let glassTop = 0.12
    static let glassBottom = 0.03
    /// C: struct inner border at 30%; primary gold gradient 16% → 3%.
    static let structBorder = 0.30
    static let goldTop = 0.16
    static let goldBottom = 0.03
    /// Setup card: neutral outline (A platinum 16% dark / graphite 14% light) and 2.5% fill.
    static func setupOutline(_ look: Look) -> Double { look == .dark ? 0.16 : 0.14 }
    static let setupFill = 0.025
    /// Row hover lift (A ink tint; C 7% struct tint).
    static let hoverLift = 0.05
    static let hoverLiftStruct = 0.07
    /// Keyboard selection ring at 55% plus (A dark only) a 3px iris halo at 12%.
    static let selectionRing = 0.55
    static let selectionHalo = 0.12
    static let selectionHaloWidth: CGFloat = 3
    /// Chips: neutral border and fill.
    static let chipBorder = 0.22
    static let chipFill = 0.04
    /// Pressed and disabled controls.
    static let pressedOpacity = 0.8
    static let disabledOpacity = 0.5
    /// Scroll thumb.
    static let thumbOpacity = 0.6
}

extension Theme {
    /// Twin Metal Tactical frames (square, struct corner marks); Chrome Hologram uses hairlines and iris.
    var usesCornerMarks: Bool { defines(.structure) }

    /// Action button and chip corner radius: `rounded.action` where the variant sets it (C: 0), else the
    /// A pill (`rounded.full`), clamped to half the height.
    func actionRadius(height: CGFloat) -> CGFloat {
        let raw = rounded[RadiusRole.action.rawValue] != nil ? radius(.action) : radius(.full)
        return min(raw, height / 2)
    }

    /// A CSS-style padding component value (`"18px 20px"`, or one, three or four lengths) as insets.
    func componentInsets(_ name: String, _ key: String) -> EdgeInsets? {
        guard let raw = component(name, key) else { return nil }
        let values = raw.split(separator: " ").compactMap { ThemeValue.length(String($0)) }
        switch values.count {
        case 1: return EdgeInsets(top: values[0], leading: values[0], bottom: values[0], trailing: values[0])
        case 2: return EdgeInsets(top: values[0], leading: values[1], bottom: values[0], trailing: values[1])
        case 3: return EdgeInsets(top: values[0], leading: values[1], bottom: values[2], trailing: values[1])
        case 4: return EdgeInsets(top: values[0], leading: values[3], bottom: values[2], trailing: values[1])
        default: return nil
        }
    }

    var actionHeight: CGFloat {
        componentLength("action-button", "height") ?? ComponentMetrics.actionHeight
    }

    /// A light look: glows dropped, graphite rings.
    var isLight: Bool { look == .light }

    /// The neutral accent: iris in A, gold text in C.
    var accentRole: ColorRole { usesCornerMarks ? .goldText : .iris1 }
}

/// C inner corner marks: four L-shaped 7px marks drawn inside the frame.
struct CornerMarks: Shape {
    var arm: CGFloat = ComponentMetrics.cornerMark

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: ComponentMetrics.hairline / 2, dy: ComponentMetrics.hairline / 2)
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY + arm))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX + arm, y: r.minY))
        path.move(to: CGPoint(x: r.maxX - arm, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + arm))
        path.move(to: CGPoint(x: r.maxX, y: r.maxY - arm))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX - arm, y: r.maxY))
        path.move(to: CGPoint(x: r.minX + arm, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - arm))
        return path
    }
}
