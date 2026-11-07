import CoreGraphics

/// Chrome Hologram ("A") ornament strengths for the closed island (DESIGN.md Closed island, Presence levels;
/// UX-DR14, UX-DR15, UX-DR42). Pure values, so the presence and hover rules are testable without a view.
///
/// Strengths mirror `mockups/key-closed-notch-states.html`: rim at 85% (full) or a flat platinum line at 35%
/// (calm), interior glow at 16% lifted on hover, a 140 px shimmer band. Colors and timings come from the theme.
public struct IslandOrnaments: Sendable, Equatable {
    public var presence: PresenceLevel
    public var isHovered: Bool
    /// False under macOS Reduce motion (`theme.a11y.motionEnabled`): every loop and shimmer stops, the rim is
    /// static (UX-DR96). Independent of presence: Reduce motion forcing Calm is Story 18.3.
    public var motionEnabled: Bool

    public init(presence: PresenceLevel, isHovered: Bool = false, motionEnabled: Bool = true) {
        self.presence = presence
        self.isHovered = isHovered
        self.motionEnabled = motionEnabled
    }

    /// Full presence: the rim is the iris gradient (moving, or static under Reduce motion). Calm: a flat
    /// platinum (`ink-1`) line.
    public var rimUsesIris: Bool { presence == .full }

    /// The rim gradient slides along the edge on `ambient-loop` (full presence with motion only).
    public var rimSlides: Bool { loops }

    /// Rim opacity: full strength on hover (UX-DR15); static and dimmer at calm (UX-DR42).
    public var rimOpacity: Double {
        switch presence {
        case .full: isHovered ? 1 : 0.85
        case .calm: 0.35
        }
    }

    /// The interior shimmer crosses the island every `ambient-loop`, and once more on hover (full presence
    /// with motion only).
    public var shimmerEnabled: Bool { loops }

    /// Opacity of the soft `iris-2` glow rising from the island bottom; it lifts on hover. None at calm.
    public var interiorGlowOpacity: Double {
        switch presence {
        case .full: isHovered ? 0.28 : 0.16
        case .calm: 0
        }
    }

    /// Any looping animation runs: false at calm and under Reduce motion.
    public var loops: Bool { presence == .full && motionEnabled }

    /// Rim thickness, drawn inside the outline along the sides and bottom.
    public static let rimWidth: CGFloat = 1
    /// Width of the shimmer highlight band.
    public static let shimmerWidth: CGFloat = 140
    /// Share of the `ambient-loop` period the shimmer takes to cross; it rests for the remainder.
    public static let shimmerTravelShare: Double = 0.55
    /// Distance of the island marker from the leading edge.
    public static let markerInset: CGFloat = 6
}

/// The closed island split into its three horizontal parts (island-local, left to right).
public struct IslandWings: Sendable, Equatable {
    public var leading: CGFloat
    public var notch: CGFloat
    public var trailing: CGFloat

    public init(leading: CGFloat, notch: CGFloat, trailing: CGFloat) {
        self.leading = leading
        self.notch = notch
        self.trailing = trailing
    }

    public var totalWidth: CGFloat { leading + notch + trailing }
}
