import SwiftUI

/// The 6-dot reorder grip (2 × 3) in `ink-3`, `ink-1` while active (hovered or dragged) (UX-DR29).
/// Reorderable cards carry it in their header (Usage providers, Shelf rows).
public struct GripGlyph: View {
    @Environment(\.vigieTheme) private var theme
    private let isActive: Bool

    public init(isActive: Bool = false) {
        self.isActive = isActive
    }

    public var body: some View {
        let dot = ComponentMetrics.gripDot
        let pitch = ComponentMetrics.gripPitch
        let color = theme.color(isActive ? .ink1 : .ink3)
        Canvas { context, _ in
            for column in 0..<2 {
                for row in 0..<3 {
                    let rect = CGRect(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .frame(width: pitch + dot, height: pitch * 2 + dot)
        .accessibilityElement()
        .accessibilityLabel(Text(L10n.resource("a11y.grip")))
    }
}

#Preview("Grip · dark") {
    GripPreview(look: .dark)
}

#Preview("Grip · light") {
    GripPreview(look: .light)
}

private struct GripPreview: View {
    let look: Look

    var body: some View {
        let theme = PreviewThemes.theme(look)
        HStack(spacing: theme.spacing(.gridGap)) {
            GripGlyph()
            GripGlyph(isActive: true)
        }
        .padding(theme.spacing(.gridPaddingX))
        .background(theme.color(.surfaceCard))
        .vigieTheme(theme)
    }
}
