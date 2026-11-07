import SwiftUI

/// How a functional drain (peek dwell line, `COPIED` drain, notes clipboard drain) is drawn (UX-DR96).
public enum DrainStyle: Sendable, Equatable {
    /// A line that shrinks smoothly as the time runs out.
    case animated
    /// Reduce motion: a static full line that disappears at the end, never a smooth slide.
    case staticFullLine

    /// The share of the line drawn when `remaining` (1 at the start, 0 at the end) of the time is left.
    public func visibleFraction(remaining: Double) -> Double {
        let clamped = min(1, max(0, remaining))
        switch self {
        case .animated: return clamped
        case .staticFullLine: return clamped > 0 ? 1 : 0
        }
    }
}

/// The curve of a theme animation; the duration always comes from a `motion.*` token.
public enum MotionCurve: Sendable, Equatable {
    case easeOut
    case easeIn
    case easeInOut
    case linear
}

/// What a transition becomes under Reduce motion (EXPERIENCE "Accessibility Floor": instant or a short
/// cross-fade).
public enum ReducedMotion: Sendable, Equatable {
    /// No animation at all.
    case instant
    /// A short opacity cross-fade over `motion.exit`.
    case crossFade
}

/// The accessibility rules every surface reads from the theme (`theme.a11y`), derived from the macOS
/// settings in one place (AD-14; DESIGN "Increase contrast", EXPERIENCE "Accessibility Floor"; UX-DR65,
/// UX-DR95, UX-DR96). Surfaces never read `NSWorkspace` themselves.
public struct AccessibilityRules: Sendable, Equatable {
    public var flags: AccessibilityAdjustments

    public init(_ flags: AccessibilityAdjustments) {
        self.flags = flags
    }

    /// Reduce transparency or Increase contrast: glass gradients become flat `surface-panel` /
    /// `surface-card` fills. The island stays black either way.
    public var flatSurfaces: Bool { flags.reduceTransparency || flags.increaseContrast }

    /// Increase contrast: hairlines and zone, chip and card borders become solid 1 px `ink-3`.
    public var solidHairlines: Bool { flags.increaseContrast }

    /// Increase contrast: the Ask AI dashed border is drawn at 100 % lilac (A) / gold (C).
    public var fullStrengthAccentBorders: Bool { flags.increaseContrast }

    /// Border and hairline width: 1 px in every mode (Increase contrast changes color, not width).
    public var hairlineWidth: CGFloat { 1 }

    /// Keyboard focus and selection rings: 1 px, 2 px under Increase contrast.
    public var focusRingWidth: CGFloat { flags.increaseContrast ? 2 : 1 }

    /// The faint iris halo around the selection ring (A dark); dropped under Increase contrast.
    public var haloEnabled: Bool { !flags.increaseContrast }

    /// The least opacity of `ink-3` a track (Time ring, countdown, quota, pace) is drawn at: 0.40 under
    /// Increase contrast, 0 (no floor; the default `line` track) otherwise.
    public var minTrackOpacity: Double { flags.increaseContrast ? Self.increaseContrastTrackOpacity : 0 }

    /// DESIGN "Increase contrast": tracks at `ink-3` 40 % or more.
    public static let increaseContrastTrackOpacity = 0.40

    /// False under Reduce motion: no looping or transitional animation anywhere.
    public var motionEnabled: Bool { !flags.reduceMotion }

    /// Functional drains: a smooth slide, or a static full line under Reduce motion.
    public var drainStyle: DrainStyle { flags.reduceMotion ? .staticFullLine : .animated }
}

extension Theme {
    /// The accessibility rules in effect for this theme.
    public var a11y: AccessibilityRules { AccessibilityRules(accessibility) }

    /// Loops (rim slide, shimmer, card filament, breathing targets) run only at full presence with motion
    /// on. Static in Calm presence and under Reduce motion (DESIGN "Presence mode", UX-DR96).
    public var loopsEnabled: Bool { presence == .full && a11y.motionEnabled }

    /// The animation for a motion token, or nil under Reduce motion (state changes instantly). With
    /// `reducedMotion: .crossFade` a short opacity cross-fade over `motion.exit` is returned instead of nil;
    /// pair it with ``transition(_:)`` so only opacity changes.
    public func animation(
        _ role: MotionRole, curve: MotionCurve = .easeOut, reducedMotion: ReducedMotion = .instant
    ) -> Animation? {
        guard a11y.motionEnabled else {
            switch reducedMotion {
            case .instant: return nil
            case .crossFade: return .easeInOut(duration: motionSeconds(.exit))
            }
        }
        let seconds = motionSeconds(role)
        switch curve {
        case .easeOut: return .easeOut(duration: seconds)
        case .easeIn: return .easeIn(duration: seconds)
        case .easeInOut: return .easeInOut(duration: seconds)
        case .linear: return .linear(duration: seconds)
        }
    }

    /// A seamless loop over a motion token, or nil when loops are off (Calm presence, Reduce motion).
    public func loopAnimation(_ role: MotionRole, autoreverses: Bool = false) -> Animation? {
        guard loopsEnabled else { return nil }
        return .linear(duration: motionSeconds(role)).repeatForever(autoreverses: autoreverses)
    }

    /// A view transition, replaced by a plain opacity change under Reduce motion (no movement, no scale).
    public func transition(_ transition: AnyTransition) -> AnyTransition {
        a11y.motionEnabled ? transition : .opacity
    }

    /// A zone, chip, card or control border: `role` at `opacity`, or solid `ink-3` under Increase contrast.
    public func borderColor(_ role: ColorRole, opacity: Double) -> Color {
        a11y.solidHairlines ? color(.ink3) : color(role).opacity(opacity)
    }

    /// An accent border (the Ask AI target): `role` at `opacity`, or 100 % `role` under Increase contrast.
    public func accentBorderColor(_ role: ColorRole, opacity: Double) -> Color {
        color(role).opacity(a11y.fullStrengthAccentBorders ? 1 : opacity)
    }

    /// A track (Time ring, countdown, quota, pace): `role` at `opacity` by default; under Increase contrast
    /// `ink-3` at ``AccessibilityRules/minTrackOpacity`` (or more, when the default is already `ink-3`).
    public func trackColor(_ role: ColorRole = .line, opacity: Double = 1) -> Color {
        guard a11y.solidHairlines else { return color(role).opacity(opacity) }
        let floor = a11y.minTrackOpacity
        return color(.ink3).opacity(role == .ink3 ? max(opacity, floor) : floor)
    }

    /// A glass gradient, or the flat `flat` surface under Reduce transparency / Increase contrast.
    public func glassFill<S: ShapeStyle>(_ gradient: S, flat: ColorRole) -> AnyShapeStyle {
        a11y.flatSurfaces ? AnyShapeStyle(color(flat)) : AnyShapeStyle(gradient)
    }
}
