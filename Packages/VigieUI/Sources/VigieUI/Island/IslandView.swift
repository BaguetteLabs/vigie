import SwiftUI

/// The closed island (DESIGN.md Closed island; UX-DR9, UX-DR10, UX-DR14, UX-DR15, UX-DR42).
///
/// Draws the island with `island-closed` bottom corners, the Chrome Hologram ornaments (1 px iris rim along the
/// sides and bottom, interior glow and shimmer) and the two wing slots. Everything is clipped to the island
/// outline (strict containment). Read the theme from the environment: the Notch Host injects
/// `ThemeController.islandTheme` (the dark look) around a hardware notch and for a `black` virtual notch, and the
/// main theme for a `menu_bar` virtual notch (AD-14, UX-DR76).
public struct IslandView: View {
    @Environment(\.vigieTheme) private var theme
    @State private var isHovered = false
    @State private var hoverPasses = 0

    private let wings: IslandWings
    private let surface: IslandSurface
    private let floating: Bool
    private let hoverHighlight: Bool
    private let leading: @MainActor () -> AnyView?
    private let trailing: @MainActor () -> AnyView?

    /// - Parameters:
    ///   - surface: the island fill: black (hardware notch, `virtual_notch.style = "black"`) or the virtual-notch
    ///     menu-bar gradient (`style = "menu_bar"`).
    ///   - floating: true when the island sits below the menu bar (`virtual_notch.placement = "below"`): all four
    ///     corners are rounded, since the top edge is not the screen edge.
    ///   - hoverHighlight: drives the hover reaction from outside the view (the top-center hover strip of a plain
    ///     display, SPEC §5.5), in addition to the pointer over the island itself.
    public init(
        wings: IslandWings,
        surface: IslandSurface = .black,
        floating: Bool = false,
        hoverHighlight: Bool = false,
        leading: @escaping @MainActor () -> AnyView? = { nil },
        trailing: @escaping @MainActor () -> AnyView? = { nil }
    ) {
        self.wings = wings
        self.surface = surface
        self.floating = floating
        self.hoverHighlight = hoverHighlight
        self.leading = leading
        self.trailing = trailing
    }

    private var ornaments: IslandOrnaments {
        IslandOrnaments(
            presence: theme.presence, isHovered: isHovered || hoverHighlight,
            motionEnabled: theme.a11y.motionEnabled)
    }

    public var body: some View {
        let radius = theme.radius(.islandClosed)
        let shape = IslandShape(radius: radius, topRadius: floating ? radius : 0)
        ZStack {
            shape.fill(surface.fill(theme))
            IslandGlow(opacity: ornaments.interiorGlowOpacity)
            if ornaments.shimmerEnabled {
                IslandAmbientShimmer()
                IslandHoverShimmer(passes: hoverPasses)
            }
            IslandRim(ornaments: ornaments, radius: radius)
            wingSlots
        }
        .clipShape(shape)
        .contentShape(shape)
        .onHover { hovering in
            withAnimation(theme.animation(.enter)) {
                isHovered = hovering
            }
            if hovering && !hoverHighlight && ornaments.shimmerEnabled { hoverPasses += 1 }
        }
        .onChange(of: hoverHighlight) { _, highlighted in
            if highlighted && !isHovered && ornaments.shimmerEnabled { hoverPasses += 1 }
        }
    }

    private var wingSlots: some View {
        let padding = theme.spacing(.wingPaddingX)
        return HStack(spacing: 0) {
            wingSlot(leading(), alignment: .leading, padding: padding)
                .frame(width: wings.leading)
            Color.clear.frame(width: wings.notch)
            wingSlot(trailing(), alignment: .trailing, padding: padding)
                .frame(width: wings.trailing)
        }
        .foregroundStyle(theme.color(.ink1))
    }

    @ViewBuilder
    private func wingSlot(_ content: AnyView?, alignment: Alignment, padding: CGFloat) -> some View {
        if let content {
            content
                .padding(alignment == .leading ? .leading : .trailing, padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .clipped()
        } else {
            Color.clear
        }
    }
}

/// The island's fill (DESIGN.md Closed island, Token scheme; UX-DR76).
public enum IslandSurface: Sendable, Equatable {
    /// `base-island` black: the hardware notch, and a virtual notch in `style = "black"`.
    case black
    /// A virtual notch in `style = "menu_bar"`: `surface-vn-top` → `surface-vn-bottom`, flat `surface-vn-bottom`
    /// under Reduce transparency or Increase contrast. In a dark look both roles resolve to `island`, so the
    /// dark `menu_bar` notch falls back to the black island look (OQ15).
    case menuBar

    /// The color roles the fill reads from `theme`, top to bottom.
    public func roles(_ theme: Theme) -> [ColorRole] {
        switch self {
        case .black: [.island]
        case .menuBar: theme.a11y.flatSurfaces ? [.surfaceVNBottom] : [.surfaceVNTop, .surfaceVNBottom]
        }
    }

    /// The fill style for `theme`.
    public func fill(_ theme: Theme) -> AnyShapeStyle {
        let colors = roles(theme).map(theme.color)
        guard colors.count > 1 else { return AnyShapeStyle(colors.first ?? theme.color(.island)) }
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
    }
}

/// The island outline: flush top (or `topRadius` when it floats below the menu bar), `island-closed` radius on
/// the bottom corners.
public struct IslandShape: Shape {
    public var radius: CGFloat
    public var topRadius: CGFloat

    public init(radius: CGFloat, topRadius: CGFloat = 0) {
        self.radius = radius
        self.topRadius = topRadius
    }

    public func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: topRadius, bottomLeadingRadius: radius, bottomTrailingRadius: radius,
            topTrailingRadius: topRadius, style: .continuous
        )
        .path(in: rect)
    }
}

/// A band of `lineWidth` inside the island outline along the sides and bottom (not the top edge, which sits
/// on the screen edge). Fill it with the even-odd rule.
public struct IslandRimShape: Shape {
    public var radius: CGFloat
    public var lineWidth: CGFloat

    public init(radius: CGFloat, lineWidth: CGFloat) {
        self.radius = radius
        self.lineWidth = lineWidth
    }

    public func path(in rect: CGRect) -> Path {
        var path = IslandShape(radius: radius).path(in: rect)
        let inner = CGRect(
            x: rect.minX + lineWidth, y: rect.minY,
            width: max(rect.width - 2 * lineWidth, 0), height: max(rect.height - lineWidth, 0))
        path.addPath(IslandShape(radius: max(radius - lineWidth, 0)).path(in: inner))
        return path
    }
}

/// The 1 px rim: a sliding iris gradient at full presence, a flat platinum line at calm.
struct IslandRim: View {
    @Environment(\.vigieTheme) private var theme
    let ornaments: IslandOrnaments
    let radius: CGFloat

    var body: some View {
        Group {
            if ornaments.rimUsesIris {
                IslandIrisGradient(slides: ornaments.rimSlides)
            } else {
                theme.color(.ink1)
            }
        }
        .mask(IslandRimShape(radius: radius, lineWidth: IslandOrnaments.rimWidth).fill(style: FillStyle(eoFill: true)))
        .opacity(ornaments.rimOpacity)
        .allowsHitTesting(false)
    }
}

/// The iris gradient (`iris-1 → iris-2 → iris-3 → ink-1 → iris-1`), three island widths long, sliding by
/// one full gradient per `ambient-loop`. Two copies sit side by side so the loop is seamless.
struct IslandIrisGradient: View {
    @Environment(\.vigieTheme) private var theme
    let slides: Bool
    @State private var phase = false

    var body: some View {
        GeometryReader { proxy in
            let length = proxy.size.width * 3
            let gradient = LinearGradient(
                colors: [
                    theme.color(.iris1), theme.color(.iris2), theme.color(.iris3), theme.color(.ink1),
                    theme.color(.iris1),
                ],
                startPoint: .leading, endPoint: .trailing)
            HStack(spacing: 0) {
                gradient.frame(width: length)
                gradient.frame(width: length)
            }
            .offset(x: phase ? -length : 0)
        }
        .onAppear(perform: start)
        .onChange(of: slides) { start() }
    }

    /// Starts the slide, or parks the gradient when sliding stops (Calm, Reduce motion), live.
    private func start() {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { phase = false }
        guard slides else { return }
        withAnimation(.linear(duration: theme.motionSeconds(.ambientLoop)).repeatForever(autoreverses: false)) {
            phase = true
        }
    }
}

/// Soft `iris-2` glow rising from the island bottom; lifts on hover.
struct IslandGlow: View {
    @Environment(\.vigieTheme) private var theme
    let opacity: Double

    var body: some View {
        GeometryReader { proxy in
            EllipticalGradient(colors: [theme.color(.iris2), theme.color(.iris2).opacity(0)])
                .frame(width: proxy.size.width * 0.98, height: proxy.size.height * 1.68)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 1.5)
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

/// The shimmer highlight band (`iris-2` / `ink-1` / `iris-1`, soft edges), placed by `progress` from just
/// off the leading edge (0) to just past the trailing edge (1).
struct IslandShimmerBand: View {
    @Environment(\.vigieTheme) private var theme
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let width = IslandOrnaments.shimmerWidth
            LinearGradient(
                stops: [
                    .init(color: theme.color(.iris2).opacity(0), location: 0.2),
                    .init(color: theme.color(.iris2).opacity(0.10), location: 0.42),
                    .init(color: theme.color(.ink1).opacity(0.20), location: 0.5),
                    .init(color: theme.color(.iris1).opacity(0.10), location: 0.58),
                    .init(color: theme.color(.iris1).opacity(0), location: 0.8),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: width, height: proxy.size.height)
            .offset(x: progress * (proxy.size.width + width) - width)
        }
        .allowsHitTesting(false)
    }
}

/// The shimmer crossing the island every `ambient-loop` (eased travel, then a rest).
struct IslandAmbientShimmer: View {
    @Environment(\.vigieTheme) private var theme

    var body: some View {
        let period = theme.motionSeconds(.ambientLoop)
        let travel = period * IslandOrnaments.shimmerTravelShare
        IslandShimmerBand(progress: 0)
            .keyframeAnimator(initialValue: 0.0, repeating: true) { _, progress in
                IslandShimmerBand(progress: progress)
            } keyframes: { _ in
                LinearKeyframe(1.0, duration: travel, timingCurve: Self.travelCurve)
                LinearKeyframe(1.0, duration: period - travel)
            }
    }

    /// The mockup's `cubic-bezier(.5,0,.3,1)`.
    static let travelCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.5, y: 0), endControlPoint: UnitPoint(x: 0.3, y: 1))
}

/// One shimmer pass over `motion.enter`, each time the pointer enters the island (UX-DR15).
struct IslandHoverShimmer: View {
    @Environment(\.vigieTheme) private var theme
    let passes: Int

    var body: some View {
        let pass = theme.motionSeconds(.enter)
        IslandShimmerBand(progress: 1)
            .keyframeAnimator(initialValue: 1.0, trigger: passes) { _, progress in
                IslandShimmerBand(progress: progress)
            } keyframes: { _ in
                MoveKeyframe(0.0)
                LinearKeyframe(1.0, duration: pass, timingCurve: .easeOut)
            }
    }
}
