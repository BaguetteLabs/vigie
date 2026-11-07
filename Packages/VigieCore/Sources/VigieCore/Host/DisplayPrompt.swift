import SwiftUI
import VigieUI

/// The answer to the one-time display prompt (Story 2.7, A60): where Vigie should appear.
public enum DisplayPromptAnswer: Sendable, Equatable {
    /// Write this `[display] display` value to `local.toml`.
    case choose(DisplaySelection)
    /// Closed without choosing; the default rule stays and the prompt is not shown again.
    case dismissed
}

/// The display prompt card in the expanded view: "Where should Vigie appear?" with This display, The notched
/// display, All displays and Not now. Shown while ``NotchHost/showsDisplayPrompt``; it never opens the view or
/// takes focus by itself (the island carries a marker instead).
struct DisplayPromptCard: View {
    @Environment(\.vigieTheme) private var theme
    let host: NotchHost

    var body: some View {
        WidgetCard(title: Self.text("vigiecore.displayPrompt.title")) {
            VStack(alignment: .leading, spacing: theme.spacing(.rowGap)) {
                Text(Self.text("vigiecore.displayPrompt.body"))
                    .font(theme.font(.prose))
                    .foregroundStyle(theme.color(.ink2))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: theme.spacing(.actionGap)) {
                    ActionButton(label: Self.text("vigiecore.displayPrompt.thisDisplay"), role: .primary) {
                        host.answerDisplayPromptWithThisDisplay()
                    }
                    ActionButton(label: Self.text("vigiecore.displayPrompt.notched")) {
                        host.answerDisplayPrompt(.choose(.notched))
                    }
                    ActionButton(label: Self.text("vigiecore.displayPrompt.all")) {
                        host.answerDisplayPrompt(.choose(.all))
                    }
                    ActionButton(label: Self.text("vigiecore.displayPrompt.dismiss")) {
                        host.answerDisplayPrompt(.dismissed)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    static func text(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(Bundle.module.bundleURL))
    }
}
