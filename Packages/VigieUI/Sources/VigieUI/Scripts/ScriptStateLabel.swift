import SwiftUI

/// A script's per-Mac state on island surfaces (UX-DR61, UX-DR87): `NOT CONFIRMED` in `ink-3`, with no level
/// glyph. Clicking it runs `action`, which opens the Script Confirmation. Story 12.3 provides it; the script
/// widget, side-slot item and page (Stories 12.5, 12.11) place it.
public struct ScriptStateLabel: View {
    @Environment(\.vigieTheme) private var theme
    private let action: @MainActor () -> Void

    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// `NOT CONFIRMED`, from the VigieUI catalog.
    public static var notConfirmedText: String { L10n.string("script.state.notConfirmed") }

    public var body: some View {
        Button(action: action) {
            Text(verbatim: Self.notConfirmedText)
                .font(theme.font(.rowStatus))
                .tracking(theme.tracking(.rowStatus))
                .foregroundStyle(theme.color(.ink3))
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(verbatim: L10n.string("script.state.notConfirmed.hint")))
    }
}
