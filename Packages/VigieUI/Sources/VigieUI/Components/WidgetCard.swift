import SwiftUI

/// The shared card frame (DESIGN "Widget card", UX-DR28): an 11px header row with the title (card-title,
/// uppercase) on the left and meta in `ink-3` on the right, over `surface-card` with `rounded.card`.
/// Chrome Hologram draws a 1px iris filament along the top edge (45% dark, 80% light) that drifts every
/// `motion.card-iris`, static in Calm presence or under Reduce motion; Twin Metal Tactical draws four 7px
/// inner corner marks in `struct` at 38%. Tab bodies reuse the same frame.
public struct WidgetCard<Content: View>: View {
    @Environment(\.vigieTheme) private var theme
    private let title: Text
    private let meta: Text?
    private let content: Content

    public init(title: Text, meta: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.meta = meta
        self.content = content()
    }

    public init(
        title: LocalizedStringResource,
        meta: LocalizedStringResource? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: Text(title), meta: meta.map { Text($0) }, content: content)
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
        VStack(alignment: .leading, spacing: theme.spacing(.rowGap)) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.vertical, theme.spacing(.cardPaddingY))
        .padding(.horizontal, theme.spacing(.cardPaddingX))
        .background(theme.color(.surfaceCard), in: shape)
        .overlay(alignment: .top) {
            if !theme.usesCornerMarks {
                IrisFilament().clipShape(shape)
            }
        }
        .overlay {
            if theme.usesCornerMarks {
                CornerMarks()
                    .stroke(
                        theme.color(.structure).opacity(ComponentMetrics.cornerMarkOpacity),
                        lineWidth: ComponentMetrics.hairline)
            } else {
                shape.strokeBorder(
                    theme.color(.ink1).opacity(ComponentMetrics.cardHairline(theme.look)),
                    lineWidth: ComponentMetrics.hairline)
            }
        }
        .clipShape(shape)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.glyphGap)) {
            title
                .font(theme.font(.cardTitle))
                .tracking(theme.tracking(.cardTitle))
                .textCase(.uppercase)
                .foregroundStyle(theme.color(.ink2))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: theme.spacing(.glyphGap))
            if let meta {
                meta
                    .font(theme.font(.cardTitle))
                    .tracking(theme.tracking(.cardTitle))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.color(.ink3))
                    .lineLimit(1)
            }
        }
    }
}

/// The A iris filament: a 1px gradient line `iris-1 → iris-2 → iris-3` (`filament-*` in light looks)
/// along the card's top edge, drifting across over `motion.card-iris`.
struct IrisFilament: View {
    @Environment(\.vigieTheme) private var theme
    @State private var phase: CGFloat = 0

    var body: some View {
        let colors = [
            theme.color(.filament1), theme.color(.filament2), theme.color(.filament3), theme.color(.filament1),
        ]
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                .frame(width: width * 2)
                .offset(x: -width * phase)
        }
        .frame(height: ComponentMetrics.hairline)
        .opacity(ComponentMetrics.filamentOpacity(theme.look))
        .accessibilityHidden(true)
        .onAppear(perform: start)
        .onChange(of: theme.stopsLoops) { start() }
    }

    private func start() {
        guard !theme.stopsLoops else {
            phase = 0
            return
        }
        phase = 0
        withAnimation(.linear(duration: theme.motionSeconds(.cardIris)).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}

#Preview("Widget card · dark") {
    WidgetCardPreview(look: .dark)
}

#Preview("Widget card · light") {
    WidgetCardPreview(look: .light)
}

#Preview("Widget card · Twin Metal") {
    WidgetCardPreview(look: .dark, variant: "twin-metal-tactical")
}

private struct WidgetCardPreview: View {
    let look: Look
    var variant = ThemeLibrary.defaultVariantID

    var body: some View {
        let theme = PreviewThemes.theme(look, variant: variant)
        WidgetCard(title: Text(verbatim: "Sessions · 9"), meta: Text(verbatim: "Sorted by urgency")) {
            VStack(alignment: .leading, spacing: theme.spacing(.rowGap)) {
                StatusLabel(.blocked, elapsed: PreviewSamples.minutes(12))
                StatusLabel(.working, elapsed: PreviewSamples.minutes(14))
                StatusLabel(.idle)
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
