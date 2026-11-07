import SwiftUI

/// Empty state (DESIGN "Empty state block", UX-DR24): centred uppercase label in `ink-3`, one factual
/// sentence in prose type, and an optional `Open settings` button to the relevant Settings pane.
public struct EmptyStateBlock: View {
    @Environment(\.vigieTheme) private var theme
    private let label: LocalizedStringResource
    private let sentence: LocalizedStringResource?
    private let settingsShortcut: String?
    private let settingsAction: (@MainActor () -> Void)?

    /// - Parameters:
    ///   - label: uppercase label from a catalog (`NO USAGE PROVIDER`).
    ///   - sentence: one factual sentence, or nil.
    ///   - settingsShortcut: shown on the button (`⌘,`), or nil.
    ///   - settingsAction: opens the relevant Settings pane; nil hides the button.
    public init(
        label: LocalizedStringResource,
        sentence: LocalizedStringResource? = nil,
        settingsShortcut: String? = nil,
        settingsAction: (@MainActor () -> Void)? = nil
    ) {
        self.label = label
        self.sentence = sentence
        self.settingsShortcut = settingsShortcut
        self.settingsAction = settingsAction
    }

    /// An empty state from ``VigieCopy``.
    public init(
        _ copy: VigieCopy.EmptyState,
        settingsShortcut: String? = nil,
        settingsAction: (@MainActor () -> Void)? = nil
    ) {
        self.init(
            label: copy.label, sentence: copy.sentence, settingsShortcut: settingsShortcut,
            settingsAction: settingsAction)
    }

    public var body: some View {
        VStack(spacing: theme.spacing(.rowGap)) {
            Text(label)
                .font(theme.font(.cardTitle))
                .tracking(theme.tracking(.cardTitle))
                .foregroundStyle(theme.color(.ink3))
                .multilineTextAlignment(.center)
            if let sentence {
                Text(sentence)
                    .font(theme.font(.prose))
                    .foregroundStyle(theme.color(.ink2))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: ComponentMetrics.emptySentenceMaxWidth)
            }
            if let settingsAction {
                ActionButton(label: VigieCopy.openSettings, shortcut: settingsShortcut, action: settingsAction)
                    .fixedSize()
                    .padding(.top, theme.spacing(.miniZoneGap))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Empty state · dark") {
    EmptyStatePreview(look: .dark)
}

#Preview("Empty state · light") {
    EmptyStatePreview(look: .light)
}

private struct EmptyStatePreview: View {
    let look: Look

    var body: some View {
        let theme = PreviewThemes.theme(look)
        WidgetCard(title: Text(verbatim: "Providers")) {
            EmptyStateBlock(VigieCopy.noUsageProvider, settingsShortcut: "⌘,") {}
        }
        .frame(width: theme.componentLength("expanded-panel", "width").map { $0 / 2 })
        .frame(height: theme.componentLength("expanded-panel", "height").map { $0 / 2 })
        .padding(theme.spacing(.gridPaddingX))
        .background(theme.color(.surfacePanel))
        .vigieTheme(theme)
    }
}
