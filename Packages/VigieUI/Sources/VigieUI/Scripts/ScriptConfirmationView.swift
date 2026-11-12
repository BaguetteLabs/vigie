import SwiftUI

/// What the Script Confirmation shows (UX-DR87, SPEC §9.2, Story 12.3): the whole file, split the way the user
/// reads it. Built by the integrations module from a parsed script file; plain values so it can cross actors.
public struct ScriptConfirmationContent: Equatable, Sendable, Identifiable {
    /// The file name (`github.md`).
    public var fileName: String
    /// Where the file is, as shown to the user (absolute path).
    public var path: String
    /// The Markdown around the code block, rendered.
    public var documentation: String
    /// The front matter as written (YAML), or nil when the file has none.
    public var frontMatter: String?
    /// The code block's content, or nil when the file has no single closed block.
    public var code: String?
    /// The code block's language tag (`python`), if any.
    public var language: String?
    /// The whole file as text: rendered Markdown can hide text (comments, link targets), so the exact file is
    /// one click away. Nil when the file is not UTF-8.
    public var fileText: String?
    /// Why the file cannot run even once confirmed (a parse problem), or nil.
    public var problem: String?

    public var id: String { path }

    public init(
        fileName: String, path: String, documentation: String, frontMatter: String?, code: String?,
        language: String?, fileText: String?, problem: String? = nil
    ) {
        self.fileName = fileName
        self.path = path
        self.documentation = documentation
        self.frontMatter = frontMatter
        self.code = code
        self.language = language
        self.fileText = fileText
        self.problem = problem
    }
}

/// The copy of the Script Confirmation, from the VigieUI catalog (AD-15).
public enum ScriptConfirmationCopy {
    public static var title: String { L10n.string("script.confirmation.title") }
    /// SPEC §9.2, verbatim: scripts run as the user, with no sandbox.
    public static var warning: String { L10n.string("script.confirmation.warning") }
    public static var explanation: String { L10n.string("script.confirmation.explanation") }
    public static var documentation: String { L10n.string("script.confirmation.documentation") }
    public static var noDocumentation: String { L10n.string("script.confirmation.noDocumentation") }
    public static var frontMatter: String { L10n.string("script.confirmation.frontMatter") }
    public static var noFrontMatter: String { L10n.string("script.confirmation.noFrontMatter") }
    public static var code: String { L10n.string("script.confirmation.code") }
    public static var noCode: String { L10n.string("script.confirmation.noCode") }
    public static var fileText: String { L10n.string("script.confirmation.fileText") }
    public static var privacy: String { L10n.string("script.confirmation.privacy") }
    public static var confirm: String { L10n.string("script.confirmation.confirm") }
    public static var decline: String { L10n.string("script.confirmation.decline") }
    public static var cancel: String { L10n.string("script.confirmation.cancel") }

    /// `Code · python`, or `Code` without a language tag.
    public static func codeHeading(language: String?) -> String {
        guard let language, !language.isEmpty else { return code }
        return L10n.format("script.confirmation.code.language", language)
    }

    /// Every catalog key the confirmation uses (catalog completeness tests).
    public static let keys = [
        "script.confirmation.title", "script.confirmation.warning", "script.confirmation.explanation",
        "script.confirmation.documentation", "script.confirmation.noDocumentation",
        "script.confirmation.frontMatter", "script.confirmation.noFrontMatter", "script.confirmation.code",
        "script.confirmation.code.language", "script.confirmation.noCode", "script.confirmation.fileText",
        "script.confirmation.privacy", "script.confirmation.confirm", "script.confirmation.decline",
        "script.confirmation.cancel", "script.state.notConfirmed", "script.state.notConfirmed.hint",
    ]
}

/// The Script Confirmation (EXPERIENCE "Script Confirmation", UX-DR87): a regular macOS window or sheet, so native
/// controls and system text styles (DESIGN "Settings window"), no island tokens. Shows the file's name and path,
/// the "runs as the user, no sandbox" warning, the documentation (Markdown), the front matter and the code
/// (monospaced), the whole file as text on demand, then Cancel, Decline and Confirm.
///
/// Keyboard: Escape cancels (nothing recorded). Return does nothing: confirming or declining takes an explicit
/// click. While Privacy mode is on the file's text is masked and Confirm is disabled (nothing is confirmed
/// unseen).
public struct ScriptConfirmationView: View {
    @Environment(\.privacyActive) private var privacyActive
    @State private var showsFileText = false
    private let content: ScriptConfirmationContent
    private let onConfirm: @MainActor () -> Void
    private let onDecline: @MainActor () -> Void
    private let onCancel: @MainActor () -> Void

    public init(
        content: ScriptConfirmationContent,
        onConfirm: @escaping @MainActor () -> Void,
        onDecline: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.content = content
        self.onConfirm = onConfirm
        self.onDecline = onDecline
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ScriptConfirmationMetrics.sectionSpacing) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: ScriptConfirmationMetrics.sectionSpacing) {
                    documentationSection
                    textSection(
                        ScriptConfirmationCopy.frontMatter, text: content.frontMatter,
                        empty: ScriptConfirmationCopy.noFrontMatter)
                    textSection(
                        ScriptConfirmationCopy.codeHeading(language: content.language), text: content.code,
                        empty: ScriptConfirmationCopy.noCode)
                    if let fileText = content.fileText {
                        DisclosureGroup(isExpanded: $showsFileText) {
                            CodeBlock(text: fileText)
                        } label: {
                            Text(verbatim: ScriptConfirmationCopy.fileText).font(.headline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(ScriptConfirmationMetrics.padding)
        .frame(
            minWidth: ScriptConfirmationMetrics.minWidth, idealWidth: ScriptConfirmationMetrics.idealWidth,
            minHeight: ScriptConfirmationMetrics.minHeight, idealHeight: ScriptConfirmationMetrics.idealHeight)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ScriptConfirmationMetrics.lineSpacing) {
            Text(verbatim: ScriptConfirmationCopy.title).font(.title2.weight(.semibold))
            Text(verbatim: content.fileName).font(.headline).sensitive()
            Text(verbatim: content.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .sensitive()
            Label {
                Text(verbatim: ScriptConfirmationCopy.warning)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .padding(.top, ScriptConfirmationMetrics.lineSpacing)
            Text(verbatim: ScriptConfirmationCopy.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem = content.problem {
                Label {
                    Text(verbatim: problem).fixedSize(horizontal: false, vertical: true).sensitive()
                } icon: {
                    Image(systemName: "xmark.octagon")
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder private var documentationSection: some View {
        VStack(alignment: .leading, spacing: ScriptConfirmationMetrics.lineSpacing) {
            Text(verbatim: ScriptConfirmationCopy.documentation).font(.headline)
            let blocks = ScriptDocumentationBlock.parse(content.documentation)
            if blocks.isEmpty {
                Text(verbatim: ScriptConfirmationCopy.noDocumentation).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: ScriptConfirmationMetrics.paragraphSpacing) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        DocumentationBlockView(block: block)
                    }
                }
                .textSelection(.enabled)
                .sensitive()
            }
        }
    }

    private func textSection(_ title: String, text: String?, empty: String) -> some View {
        VStack(alignment: .leading, spacing: ScriptConfirmationMetrics.lineSpacing) {
            Text(verbatim: title).font(.headline)
            if let text {
                CodeBlock(text: text)
            } else {
                Text(verbatim: empty).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .trailing, spacing: ScriptConfirmationMetrics.lineSpacing) {
            if privacyActive {
                Text(verbatim: ScriptConfirmationCopy.privacy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack {
                Button(action: onCancel) { Text(verbatim: ScriptConfirmationCopy.cancel) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                // No `.defaultAction` on either: Return never confirms or declines (explicit click only).
                Button(action: onDecline) { Text(verbatim: ScriptConfirmationCopy.decline) }
                Button(action: onConfirm) { Text(verbatim: ScriptConfirmationCopy.confirm) }
                    .disabled(privacyActive)
            }
        }
    }
}

/// Native-window metrics of the Script Confirmation (not island tokens: DESIGN "Settings window").
enum ScriptConfirmationMetrics {
    static let padding: CGFloat = 20
    static let sectionSpacing: CGFloat = 16
    static let paragraphSpacing: CGFloat = 8
    static let lineSpacing: CGFloat = 4
    static let codePadding: CGFloat = 8
    static let codeCornerRadius: CGFloat = 6
    static let codeBackgroundOpacity: Double = 0.5
    static let minWidth: CGFloat = 520
    static let idealWidth: CGFloat = 640
    static let minHeight: CGFloat = 420
    static let idealHeight: CGFloat = 640
}

/// Monospaced, selectable, scrolls sideways for long lines.
struct CodeBlock: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(verbatim: text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize()
                .padding(ScriptConfirmationMetrics.codePadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .quaternary.opacity(ScriptConfirmationMetrics.codeBackgroundOpacity),
            in: RoundedRectangle(cornerRadius: ScriptConfirmationMetrics.codeCornerRadius)
        )
        .sensitive()
    }
}

/// One block of a script's documentation: an ATX heading or a paragraph (inline Markdown, line breaks kept).
/// Script documentation has no fenced code (the file's one block is the script), so headings and paragraphs
/// cover it; lists and quotes read as written.
enum ScriptDocumentationBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)

    static func parse(_ markdown: String) -> [ScriptDocumentationBlock] {
        var blocks: [ScriptDocumentationBlock] = []
        var paragraph: [String] = []
        func flush() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph = []
        }
        for line in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else if let heading = heading(trimmed) {
                flush()
                blocks.append(heading)
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    /// `# Title` … `###### Title` (a `#` run followed by a space, or alone).
    private static func heading(_ line: String) -> ScriptDocumentationBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return .heading(level: hashes, text: text.trimmingCharacters(in: .whitespaces))
    }

    /// The paragraph with its inline Markdown (emphasis, code spans, links) applied; plain text when it does
    /// not parse.
    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct DocumentationBlockView: View {
    let block: ScriptDocumentationBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(ScriptDocumentationBlock.attributed(text))
                .font(level <= 1 ? .title3.weight(.semibold) : .headline)
        case .paragraph(let text):
            Text(ScriptDocumentationBlock.attributed(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
