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

/// `UPDATE AVAILABLE` (UX-DR87, A88, Story 12.10): a newer version of the script was found and waits for review;
/// the confirmed version keeps running. Mono label in `quota-warning-text` (SPEC: yellow for script warnings), no
/// glyph. With an `action` it is a button that opens the update review.
public struct ScriptUpdateBadge: View {
    @Environment(\.vigieTheme) private var theme
    private let action: (@MainActor () -> Void)?

    public init(action: (@MainActor () -> Void)? = nil) {
        self.action = action
    }

    /// `UPDATE AVAILABLE`, from the VigieUI catalog.
    public static var text: String { L10n.string("script.state.updateAvailable") }
    /// VoiceOver hint of the button.
    public static var hint: String { L10n.string("script.state.updateAvailable.hint") }

    public var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .accessibilityHint(Text(verbatim: Self.hint))
        } else {
            label
        }
    }

    private var label: some View {
        Text(verbatim: Self.text)
            .font(theme.font(.cardTitle))
            .tracking(theme.tracking(.cardTitle))
            .foregroundStyle(theme.color(.quotaWarningText))
            .lineLimit(1)
            .fixedSize()
    }
}
