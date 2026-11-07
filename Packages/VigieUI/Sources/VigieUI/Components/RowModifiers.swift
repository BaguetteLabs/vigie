import SwiftUI

extension View {
    /// Brightens the row while the pointer is over it (UX-DR40): an `ink-1` lift in Chrome Hologram, a 7%
    /// `struct` tint in Twin Metal Tactical, over `motion.enter` (instant under Reduce motion).
    public func rowHoverBrighten() -> some View {
        modifier(RowHoverBrighten())
    }

    /// The keyboard selection ring (UX-DR40, `components.selection-ring`): 1px `ink-1` at 55% (platinum in
    /// dark, graphite in light), plus a faint 3px iris halo in dark Chrome Hologram. It stacks on top of
    /// any alert tint. 2px under Increase contrast.
    public func keyboardSelectionRing(isSelected: Bool) -> some View {
        modifier(KeyboardSelectionRing(isSelected: isSelected))
    }
}

struct RowHoverBrighten: ViewModifier {
    @Environment(\.vigieTheme) private var theme
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius(.row), style: .continuous)
        content
            .background {
                if isHovered {
                    shape.fill(hoverTint)
                }
            }
            .contentShape(shape)
            .onHover { hovering in
                withAnimation(theme.enterAnimation) { isHovered = hovering }
            }
    }

    private var hoverTint: Color {
        theme.usesCornerMarks
            ? theme.color(.structure).opacity(ComponentMetrics.hoverLiftStruct)
            : theme.color(.ink1).opacity(ComponentMetrics.hoverLift)
    }
}

struct KeyboardSelectionRing: ViewModifier {
    @Environment(\.vigieTheme) private var theme
    let isSelected: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius(.row), style: .continuous)
        content.overlay {
            if isSelected {
                ZStack {
                    if !theme.isLight && !theme.usesCornerMarks {
                        shape.stroke(
                            theme.color(.iris1).opacity(ComponentMetrics.selectionHalo),
                            lineWidth: ComponentMetrics.selectionHaloWidth * 2)
                    }
                    shape.strokeBorder(
                        theme.color(.ink1).opacity(ComponentMetrics.selectionRing), lineWidth: theme.ringWidth)
                }
                .allowsHitTesting(false)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Rows · dark") {
    RowPreview(look: .dark)
}

#Preview("Rows · light") {
    RowPreview(look: .light)
}

private struct RowPreview: View {
    let look: Look

    var body: some View {
        let theme = PreviewThemes.theme(look)
        VStack(spacing: theme.spacing(.actionGap)) {
            ForEach(0..<3) { index in
                HStack {
                    StatusLabel(.working, elapsed: PreviewSamples.minutes(index + 5))
                    Spacer()
                    InlineChip(verbatim: "Focus ↵")
                }
                .padding(.horizontal, theme.spacing(.cardPaddingX))
                .frame(height: theme.componentLength("session-row", "height"))
                .rowHoverBrighten()
                .keyboardSelectionRing(isSelected: index == 1)
            }
        }
        .padding(theme.spacing(.gridPaddingX))
        .background(theme.color(.surfaceCard))
        .vigieTheme(theme)
    }
}
