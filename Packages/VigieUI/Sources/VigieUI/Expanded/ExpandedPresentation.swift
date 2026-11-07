import SwiftUI

/// How the expanded panel grows out of the notch and collapses back (DESIGN "Presence mode", UX-DR96):
/// it grows over `motion.enter` and collapses over `motion.exit`; in Calm mode it cross-fades over the same
/// tokens; under Reduce motion it is instant.
public enum ExpansionStyle: Sendable, Equatable {
    case grow
    case fade
    case instant

    public init(theme: Theme) {
        if !theme.a11y.motionEnabled {
            self = .instant
        } else if theme.presence == .calm {
            self = .fade
        } else {
            self = .grow
        }
    }

    /// How long the host keeps the panel on screen after a collapse starts.
    public func collapseDuration(_ theme: Theme) -> Duration {
        self == .instant ? .zero : theme.motion(.exit)
    }

    func animation(opening: Bool, theme: Theme) -> Animation? {
        switch self {
        case .instant: nil
        case .grow, .fade: theme.animation(opening ? .enter : .exit, curve: opening ? .easeOut : .easeIn)
        }
    }
}

extension View {
    /// Presents the expanded panel content: masked to a shape that grows from the closed island (`origin`, the
    /// island's size, top-centred) to the full panel with `rounded.expanded` corners, with the panel's neutral
    /// drop shadow. `isShown` changes animate per ``ExpansionStyle``.
    public func expandedPanelPresentation(isShown: Bool, origin: CGSize) -> some View {
        modifier(ExpandedPanelPresentation(isShown: isShown, origin: origin))
    }
}

struct ExpandedPanelPresentation: ViewModifier {
    @Environment(\.vigieTheme) private var theme
    @State private var shown = false
    let isShown: Bool
    let origin: CGSize

    func body(content: Content) -> some View {
        let style = ExpansionStyle(theme: theme)
        let size = theme.expandedPanelSize
        let open = shown || style != .grow
        content
            .mask(alignment: .top) {
                ExpansionMaskShape(
                    width: open ? size.width : min(origin.width, size.width),
                    height: open ? size.height : min(origin.height, size.height),
                    radius: open ? theme.radius(.expanded) : theme.radius(.islandClosed))
            }
            .opacity(shown ? 1 : 0)
            .compositingGroup()
            .shadow(
                color: theme.color(.shadow).opacity(ExpandedMetrics.shadowOpacity(theme.look)),
                radius: ExpandedMetrics.shadowRadius, y: ExpandedMetrics.shadowOffsetY
            )
            .onChange(of: isShown, initial: true) { _, newValue in
                withAnimation(style.animation(opening: newValue, theme: theme)) { shown = newValue }
            }
    }
}

/// A top-centred rectangle of `width` × `height` with `radius` bottom corners, inside the full panel frame.
struct ExpansionMaskShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(width, height), radius) }
        set {
            width = newValue.first.first
            height = newValue.first.second
            radius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let frame = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
        return IslandShape(radius: min(radius, height / 2, width / 2)).path(in: frame)
    }
}
