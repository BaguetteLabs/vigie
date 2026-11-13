import ModuleKit
import SwiftUI

/// A plain text editor whose text Privacy mode hides like a password field (AD-24, UX-DR98, Story 15.3): while
/// `privacyActive`, the text is drawn transparent and each non-empty line shows as ``PrivacyMask/text`` (the same
/// fixed number of dots whatever its length, so nothing is given away) in the code face, `ink-3`. Typing,
/// selection and the caret keep working; only the drawing changes.
public struct SensitiveTextEditor: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    @Binding private var text: String
    private let font: TypographyRole

    public init(text: Binding<String>, font: TypographyRole = .prose) {
        _text = text
        self.font = font
    }

    public var body: some View {
        TextEditor(text: $text)
            .font(theme.font(font))
            .foregroundStyle(privacyActive ? Color.clear : theme.color(.ink1))
            .scrollContentBackground(.hidden)
            .overlay(alignment: .topLeading) {
                if privacyActive {
                    PrivacyLineDots(text: text)
                        // Line up with the editor's first line (NSTextView's line fragment padding).
                        .padding(.leading, SensitiveEditorMetrics.lineFragmentPadding)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// The dots that stand for a hidden multi-line text: one ``PrivacyMask/text`` per non-empty line, an empty line
/// for an empty one.
public struct PrivacyLineDots: View {
    @Environment(\.vigieTheme) private var theme
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(verbatim: PrivacyLineMask.masked(text))
            .font(theme.font(.code))
            .foregroundStyle(theme.color(.ink3))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityLabel(Text(L10n.resource("privacy.hidden")))
    }
}

/// The line rule of ``SensitiveTextEditor``.
public enum PrivacyLineMask {
    /// `text` with each non-empty line replaced by ``PrivacyMask/text`` and each empty (or blank) line kept empty.
    /// The line count stays; line lengths do not.
    public static func masked(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? "" : PrivacyMask.text }
            .joined(separator: "\n")
    }
}

enum SensitiveEditorMetrics {
    /// `NSTextContainer.lineFragmentPadding` default, which TextEditor keeps.
    static let lineFragmentPadding: CGFloat = 5
}
