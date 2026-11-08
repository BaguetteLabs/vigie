import SwiftUI

/// Scroll position of a list, from `onScrollGeometryChange`. Pure, so the fade, thumb and hint logic is
/// testable.
public struct ScrollMetrics: Sendable, Equatable {
    /// Distance scrolled from the top.
    public var offset: CGFloat
    public var contentHeight: CGFloat
    public var visibleHeight: CGFloat

    public init(offset: CGFloat = 0, contentHeight: CGFloat = 0, visibleHeight: CGFloat = 0) {
        self.offset = offset
        self.contentHeight = contentHeight
        self.visibleHeight = visibleHeight
    }

    /// Half a point of slack so rounding never leaves a fade on at the ends.
    static let tolerance: CGFloat = 0.5

    public var overflows: Bool { contentHeight > visibleHeight + Self.tolerance }
    public var hasMoreAbove: Bool { overflows && offset > Self.tolerance }
    public var hasMoreBelow: Bool { overflows && offset + visibleHeight < contentHeight - Self.tolerance }

    /// Thumb length and top position in the visible track.
    public func thumb(minimumLength: CGFloat) -> (length: CGFloat, top: CGFloat)? {
        guard overflows, visibleHeight > 0 else { return nil }
        let length = min(visibleHeight, max(minimumLength, visibleHeight * visibleHeight / contentHeight))
        let range = contentHeight - visibleHeight
        let progress = min(1, max(0, offset / range))
        return (length, (visibleHeight - length) * progress)
    }
}

/// A vertical list that fades rows under top and bottom masks while more content lies beyond them, shows
/// a slim thumb inside the right edge (2px Agents, 3px Usage) and an optional `SCROLL ↓` hint while more
/// content is below (UX-DR29). The hint hides once the list is scrolled to the end.
public struct ScrollFadeList<Content: View>: View {
    @Environment(\.vigieTheme) private var theme
    @State private var metrics = ScrollMetrics()
    private let thumbWidth: CGFloat
    private let showsHint: Bool
    private let showsTrack: Bool
    private let content: Content

    /// - Parameter showsTrack: draws the thumb's track (`line`) the whole height while the list overflows (the
    ///   3px Usage track).
    public init(
        thumbWidth: CGFloat = 2, showsHint: Bool = true, showsTrack: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.thumbWidth = thumbWidth
        self.showsHint = showsHint
        self.showsTrack = showsTrack
        self.content = content()
    }

    public var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                offset: geometry.contentOffset.y + geometry.contentInsets.top,
                contentHeight: geometry.contentSize.height,
                visibleHeight: geometry.containerSize.height)
        } action: { _, new in
            metrics = new
        }
        .mask(fadeMask)
        .overlay(alignment: .topTrailing) { thumb }
        .overlay(alignment: .bottomTrailing) {
            if showsHint && metrics.hasMoreBelow {
                Text(VigieCopy.scrollHint)
                    .font(theme.font(.cardTitle))
                    .tracking(theme.tracking(.cardTitle))
                    .foregroundStyle(theme.color(.ink3))
                    .padding(.trailing, thumbWidth + theme.spacing(.glyphGap))
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .animation(theme.animation(.enter), value: metrics.hasMoreBelow)
    }

    private var fadeMask: some View {
        VStack(spacing: 0) {
            fade(on: metrics.hasMoreAbove, from: .top)
            Rectangle()
            fade(on: metrics.hasMoreBelow, from: .bottom)
        }
    }

    @ViewBuilder private func fade(on: Bool, from edge: VerticalEdge) -> some View {
        if on {
            LinearGradient(
                colors: [.clear, .black], startPoint: edge == .top ? .top : .bottom,
                endPoint: edge == .top ? .bottom : .top
            )
            .frame(height: ComponentMetrics.scrollFade)
        } else {
            Rectangle().frame(height: ComponentMetrics.scrollFade)
        }
    }

    @ViewBuilder private var thumb: some View {
        if let thumb = metrics.thumb(minimumLength: ComponentMetrics.minimumThumb) {
            if showsTrack {
                Capsule()
                    .fill(theme.trackColor())
                    .frame(width: thumbWidth, height: metrics.visibleHeight)
                    .accessibilityHidden(true)
            }
            Capsule()
                .fill(theme.color(.ink3).opacity(ComponentMetrics.thumbOpacity))
                .frame(width: thumbWidth, height: thumb.length)
                .offset(y: thumb.top)
                .accessibilityHidden(true)
        }
    }
}

#Preview("Scroll list · dark") {
    ScrollListPreview(look: .dark)
}

#Preview("Scroll list · light") {
    ScrollListPreview(look: .light)
}

private struct ScrollListPreview: View {
    let look: Look

    var body: some View {
        let theme = PreviewThemes.theme(look)
        WidgetCard(title: Text(verbatim: "Sessions · 9"), meta: Text(verbatim: "Sorted by urgency")) {
            ScrollFadeList {
                VStack(alignment: .leading, spacing: theme.spacing(.rowGap)) {
                    ForEach(SessionStatus.allCases, id: \.self) { status in
                        HStack {
                            GripGlyph()
                            StatusLabel(status, elapsed: PreviewSamples.minutes(12))
                        }
                    }
                    ForEach(StatusLevel.allCases, id: \.self) { level in
                        StatusMark(level: level, size: .small)
                    }
                }
            }
        }
        .frame(
            width: theme.componentLength("script-card", "width"),
            height: theme.componentLength("home-grid", "card-height")
        )
        .padding(theme.spacing(.gridPaddingX))
        .background(theme.color(.surfacePanel))
        .vigieTheme(theme)
    }
}
