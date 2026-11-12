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
    /// Link installs (Story 12.9): the HTTPS URL the file was downloaded from; nil for a file already in the folder.
    public var sourceURL: String?
    /// Link installs: the front matter's `author`, as the file states it (nil when it names none).
    public var author: String?
    /// Link installs: the signature state, nil for a file already in the folder (no line is shown).
    public var verification: Verification?
    /// Link installs: whether there is a file to review yet (UX-DR100).
    public var availability: Availability
    /// Updates (Story 12.10): the diff from the confirmed version and the versions; nil for a first review. The
    /// other fields describe the new version.
    public var update: Update?

    /// An update of an installed script (Story 12.10, Flow 7 step 6).
    public struct Update: Equatable, Sendable {
        /// Every line of the confirmed file and the new one (``ScriptLineDiff/lines(old:new:)``).
        public var diff: [ScriptLineDiff.Line]
        /// The front matter `version` of the confirmed file and of the new one, when they state one.
        public var oldVersion: String?
        public var newVersion: String?

        public init(diff: [ScriptLineDiff.Line], oldVersion: String? = nil, newVersion: String? = nil) {
            self.diff = diff
            self.oldVersion = oldVersion
            self.newVersion = newVersion
        }
    }

    /// Where a link-installed file comes from (SPEC §9.4, AD-18).
    public enum Verification: Equatable, Sendable {
        /// A valid Script repository signature: `Verified: Vigie Script repository`.
        case verified
        /// No signature found (none at `<url>.sig` or the link's `sig`).
        case unsigned
        /// A signature that matches no key built into this Vigie (tampered file, wrong or unknown key).
        case badSignature
        /// The file's `source` names another site than the one it was downloaded from.
        case otherSite

        public var isVerified: Bool { self == .verified }
    }

    /// Whether the sheet has a file to show.
    public enum Availability: Equatable, Sendable {
        case ready
        /// The link's file is being downloaded: only Close.
        case downloading
        /// Nothing to confirm (download failed, invalid file): the reason and only Close (UX-DR100).
        case failed(title: String, detail: String?)

        public var canConfirm: Bool { self == .ready }
    }

    public var id: String { path }

    public init(
        fileName: String, path: String, documentation: String, frontMatter: String?, code: String?,
        language: String?, fileText: String?, problem: String? = nil, sourceURL: String? = nil,
        author: String? = nil, verification: Verification? = nil, availability: Availability = .ready,
        update: Update? = nil
    ) {
        self.fileName = fileName
        self.path = path
        self.documentation = documentation
        self.frontMatter = frontMatter
        self.code = code
        self.language = language
        self.fileText = fileText
        self.problem = problem
        self.sourceURL = sourceURL
        self.author = author
        self.verification = verification
        self.availability = availability
        self.update = update
    }

    /// A link install with nothing to review yet (downloading) or nothing to confirm (failed).
    public static func unavailable(sourceURL: String, availability: Availability) -> ScriptConfirmationContent {
        ScriptConfirmationContent(
            fileName: "", path: sourceURL, documentation: "", frontMatter: nil, code: nil, language: nil,
            fileText: nil, sourceURL: sourceURL, availability: availability)
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
    public static var close: String { L10n.string("script.confirmation.close") }
    /// SPEC §9.4, verbatim.
    public static var verified: String { L10n.string("script.confirmation.verified") }
    public static var unverifiedExplanation: String { L10n.string("script.confirmation.unverified.explanation") }
    public static var installNote: String { L10n.string("script.confirmation.installNote") }
    public static var downloading: String { L10n.string("script.confirmation.downloading") }
    public static var noAuthor: String { L10n.string("script.confirmation.author.none") }
    /// Story 12.10: the update variant.
    public static var updateTitle: String { L10n.string("script.confirmation.update.title") }
    public static var updateNote: String { L10n.string("script.confirmation.update.note") }
    public static var changes: String { L10n.string("script.confirmation.update.changes") }
    public static var newFileText: String { L10n.string("script.confirmation.update.fileText") }

    /// `Version 1.0.0 → 1.1.0`; a side that states none reads `not given`.
    public static func version(old: String?, new: String?) -> String {
        let none = L10n.string("script.confirmation.update.version.none")
        return L10n.format("script.confirmation.update.version", old ?? none, new ?? none)
    }

    /// `+3 −1 lines`.
    public static func changeCounts(added: Int, removed: Int) -> String {
        L10n.format("script.confirmation.update.counts", added, removed)
    }

    /// `12 unchanged lines`, a folded run of the diff.
    public static func skipped(_ count: Int) -> String { L10n.format("script.confirmation.update.skipped", count) }

    /// What VoiceOver reads for a diff line: `Added: …`, `Removed: …`, or the line itself.
    public static func spoken(_ line: ScriptLineDiff.Line) -> String {
        switch line.kind {
        case .added: L10n.format("script.confirmation.update.added", line.text)
        case .removed: L10n.format("script.confirmation.update.removed", line.text)
        case .context: line.text
        }
    }

    /// The verification line: `Verified: Vigie Script repository`, or the stronger warning's reason.
    public static func verification(_ state: ScriptConfirmationContent.Verification) -> String {
        switch state {
        case .verified: verified
        case .unsigned: L10n.string("script.confirmation.unverified.unsigned")
        case .badSignature: L10n.string("script.confirmation.unverified.badSignature")
        case .otherSite: L10n.string("script.confirmation.unverified.otherSite")
        }
    }

    /// `Source: https://…`.
    public static func source(_ url: String) -> String { L10n.format("script.confirmation.source", url) }

    /// `Author: Léa`, or `Author: Léa (claimed by the file)` unless the file is verified.
    public static func author(_ name: String?, verified: Bool) -> String {
        guard let name, !name.isEmpty else { return noAuthor }
        return verified
            ? L10n.format("script.confirmation.author", name) : L10n.format("script.confirmation.author.claimed", name)
    }

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
        "script.confirmation.close", "script.confirmation.verified", "script.confirmation.unverified.unsigned",
        "script.confirmation.unverified.badSignature", "script.confirmation.unverified.otherSite",
        "script.confirmation.unverified.explanation", "script.confirmation.installNote",
        "script.confirmation.downloading", "script.confirmation.source", "script.confirmation.author",
        "script.confirmation.author.claimed", "script.confirmation.author.none", "script.meta.checkedJustNow",
        "script.confirmation.update.title", "script.confirmation.update.note", "script.confirmation.update.changes",
        "script.confirmation.update.fileText", "script.confirmation.update.version",
        "script.confirmation.update.version.none", "script.confirmation.update.counts",
        "script.confirmation.update.skipped", "script.confirmation.update.added", "script.confirmation.update.removed",
        "script.state.updateAvailable", "script.state.updateAvailable.hint",
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
            switch content.availability {
            case .ready:
                if let update = content.update { updateSections(update) } else { fileSections }
            case .downloading: downloadingSection
            case .failed(let title, let detail): failureSection(title: title, detail: detail)
            }
            footer
        }
        .padding(ScriptConfirmationMetrics.padding)
        .frame(
            minWidth: ScriptConfirmationMetrics.minWidth, idealWidth: ScriptConfirmationMetrics.idealWidth,
            minHeight: ScriptConfirmationMetrics.minHeight, idealHeight: ScriptConfirmationMetrics.idealHeight)
    }

    private var fileSections: some View {
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
    }

    /// Story 12.10: the diff from the confirmed version, then the whole new file on demand.
    private func updateSections(_ update: ScriptConfirmationContent.Update) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScriptConfirmationMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: ScriptConfirmationMetrics.lineSpacing) {
                    let counts = ScriptLineDiff.counts(update.diff)
                    HStack {
                        Text(verbatim: ScriptConfirmationCopy.changes).font(.headline)
                        Spacer()
                        Text(
                            verbatim: ScriptConfirmationCopy.changeCounts(added: counts.added, removed: counts.removed)
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    ScriptDiffView(lines: update.diff)
                }
                if let fileText = content.fileText {
                    DisclosureGroup(isExpanded: $showsFileText) {
                        CodeBlock(text: fileText)
                    } label: {
                        Text(verbatim: ScriptConfirmationCopy.newFileText).font(.headline)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var downloadingSection: some View {
        HStack(spacing: ScriptConfirmationMetrics.paragraphSpacing) {
            ProgressView().controlSize(.small)
            Text(verbatim: ScriptConfirmationCopy.downloading).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// UX-DR100: the reason, and nothing to confirm.
    private func failureSection(title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: ScriptConfirmationMetrics.lineSpacing) {
            Label {
                Text(verbatim: title).font(.headline).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "xmark.octagon")
            }
            if let detail {
                Text(verbatim: detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .sensitive()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Link installs (Story 12.9): source URL, author and the verification line, with the stronger warning when
    /// the file is not verified. Source and author are user text: masked in Privacy mode (UX-DR98).
    @ViewBuilder private var provenance: some View {
        if let sourceURL = content.sourceURL {
            Text(verbatim: ScriptConfirmationCopy.source(sourceURL))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .sensitive()
        }
        if let verification = content.verification, content.availability.canConfirm {
            Text(verbatim: ScriptConfirmationCopy.author(content.author, verified: verification.isVerified))
                .font(.callout)
                .sensitive()
            if verification.isVerified {
                Label {
                    Text(verbatim: ScriptConfirmationCopy.verified).font(.callout.weight(.semibold))
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                }
            } else {
                Label {
                    VStack(alignment: .leading, spacing: ScriptConfirmationMetrics.lineSpacing) {
                        Text(verbatim: ScriptConfirmationCopy.verification(verification))
                            .font(.callout.weight(.bold))
                        Text(verbatim: ScriptConfirmationCopy.unverifiedExplanation).font(.callout)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.shield.fill")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ScriptConfirmationMetrics.lineSpacing) {
            Text(verbatim: content.update == nil ? ScriptConfirmationCopy.title : ScriptConfirmationCopy.updateTitle)
                .font(.title2.weight(.semibold))
            if content.availability.canConfirm {
                Text(verbatim: content.fileName).font(.headline).sensitive()
                if let update = content.update {
                    Text(verbatim: ScriptConfirmationCopy.version(old: update.oldVersion, new: update.newVersion))
                        .font(.callout)
                        .sensitive()
                }
                Text(verbatim: content.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .sensitive()
            }
            provenance
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
            if content.verification != nil, content.availability.canConfirm {
                Text(
                    verbatim: content.update == nil
                        ? ScriptConfirmationCopy.installNote : ScriptConfirmationCopy.updateNote
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
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
                if content.availability.canConfirm {
                    // An update's Close leaves the candidate pending (Story 12.10); a first review's Cancel records nothing.
                    Button(action: onCancel) {
                        Text(
                            verbatim: content.update == nil
                                ? ScriptConfirmationCopy.cancel : ScriptConfirmationCopy.close)
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    // No `.defaultAction` on either: Return never confirms or declines (explicit click only).
                    Button(action: onDecline) { Text(verbatim: ScriptConfirmationCopy.decline) }
                    Button(action: onConfirm) { Text(verbatim: ScriptConfirmationCopy.confirm) }
                        .disabled(!Self.confirmEnabled(content, privacyActive: privacyActive))
                } else {
                    // Nothing to confirm (UX-DR100): Close only.
                    Spacer()
                    Button(action: onCancel) { Text(verbatim: ScriptConfirmationCopy.close) }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}

extension ScriptConfirmationView {
    /// Confirm is offered only with a file to confirm and never while Privacy mode hides it (PRD FR-39, UX-DR98).
    public static func confirmEnabled(_ content: ScriptConfirmationContent, privacyActive: Bool) -> Bool {
        content.availability.canConfirm && !privacyActive
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
    /// The tint behind an added or removed diff line (Story 12.10).
    static let diffTintOpacity: Double = 0.16
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
