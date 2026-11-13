import SwiftUI

/// The floating panel frame (DESIGN "Floating notes panel", `components.notes-panel`, Story 15.3): the
/// `surface-panel` body with `rounded.notes-panel` corners, no black band, and the widget cards' iris filament
/// along the top edge (Chrome Hologram) or the four struct corner marks (Twin Metal Tactical). The host wraps the
/// module's content in it; the window draws the drop shadow.
public struct FloatingPanelFrame<Content: View>: View {
    @Environment(\.vigieTheme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let radius = theme.radius(.notesPanel)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.color(.surfacePanel), in: shape)
            .overlay(alignment: .top) {
                if !theme.usesCornerMarks {
                    // The mockup keeps the filament off the rounded corners (`left/right: 16px`).
                    IrisFilament().padding(.horizontal, radius)
                }
            }
            .overlay {
                if theme.usesCornerMarks {
                    CornerMarks()
                        .stroke(
                            theme.borderColor(.structure, opacity: ComponentMetrics.cornerMarkOpacity),
                            lineWidth: theme.a11y.hairlineWidth)
                } else {
                    shape.strokeBorder(
                        theme.borderColor(.ink1, opacity: ComponentMetrics.cardHairline(theme.look)),
                        lineWidth: theme.a11y.hairlineWidth)
                }
            }
            .clipShape(shape)
    }
}

extension Theme {
    /// The floating notes panel size (`components.notes-panel` width × height, DESIGN 460 × 372).
    public var notesPanelSize: CGSize {
        CGSize(
            width: componentLength("notes-panel", "width") ?? FloatingPanelMetrics.defaultSize.width,
            height: componentLength("notes-panel", "height") ?? FloatingPanelMetrics.defaultSize.height)
    }

    /// The gap between the bottom of the menu bar and the top of a floating panel. DESIGN has no token for it;
    /// the mockup leaves a hand's breadth, so the grid padding (`spacing.grid-padding-x`) is reused.
    public var floatingPanelTopGap: CGFloat { spacing(.gridPaddingX) }
}

/// DESIGN values for the floating panel, used only if a theme file lacks `components.notes-panel`.
enum FloatingPanelMetrics {
    static let defaultSize = CGSize(width: 460, height: 372)
}
