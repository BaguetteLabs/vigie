import CryptoKit
import Foundation
import ModuleKit

/// One `*.md` file of `<config folder>/modules/` as parsed (SPEC §9.1, Story 12.2), usable or not. Stories
/// 12.3–12.6 build on it: confirmation keys on ``relativePath`` and ``contentHash``, the runner runs ``code``
/// with the front matter's `runtime`, Settings › Scripts lists every definition with its ``status``.
public struct ScriptModuleDefinition: Equatable, Sendable, Identifiable {
    public let url: URL
    /// The path relative to the config folder (`modules/<file name>`), the key of a confirmation (AD-18).
    public let relativePath: String
    /// Lowercase hex SHA-256 of the whole file's bytes (AD-18; Story 12.3 confirms on it).
    public let contentHash: String
    /// Nil when the front matter is missing or invalid.
    public let frontMatter: ScriptFrontMatter?
    /// The front matter as written in the file (YAML), nil when missing or unclosed. Shown for review (Story 12.3).
    public let frontMatterText: String?
    /// The whole file as UTF-8 text, nil when it is not text. Shown for review (Story 12.3).
    public let source: String?
    /// The fenced code block's content, without its fences; nil unless the file has exactly one closed block.
    public let code: String?
    /// The first word of the opening fence's info string (`python`), if any.
    public let language: String?
    /// The Markdown after the front matter without the code block, trimmed.
    public let documentation: String
    public internal(set) var status: ScriptParseStatus
    /// `[modules."<id>"] enabled` (default true). Read only; Story 12.6 writes it.
    public internal(set) var enabled: Bool

    /// The file name: unique in the folder, so the identity of the definition (and of its alert).
    public var id: String { fileName }
    public var fileName: String { url.lastPathComponent }
    public var moduleID: ModuleID? { frontMatter?.id }

    /// ``ScriptParseError/message(fileName:)`` of an errored file.
    public var errorMessage: String? { status.error?.message(fileName: fileName) }

    init(url: URL, folderName: String, data: Data, enabled: (ModuleID) -> Bool?) {
        let parsed = ScriptMarkdown.parse(data)
        self.url = url
        relativePath = folderName + "/" + url.lastPathComponent
        contentHash = Self.sha256(data)
        frontMatter = parsed.frontMatter
        frontMatterText = parsed.frontMatterText
        source = String(data: data, encoding: .utf8)
        code = parsed.code
        language = parsed.language
        documentation = parsed.documentation
        status = parsed.error.map(ScriptParseStatus.errored) ?? .ok
        self.enabled = parsed.frontMatter.flatMap { enabled($0.id) } ?? true
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Builds the definitions of a folder and applies the id rules across its files (AD-18).
enum ScriptCatalog {
    /// - Parameters:
    ///   - files: each file's URL and bytes.
    ///   - builtIns: ids no script may declare.
    ///   - enabled: `[modules."<id>"] enabled`, nil when absent.
    /// - Returns: one definition per file, sorted by file name.
    static func build(
        files: [(url: URL, data: Data)], folderName: String, builtIns: Set<ModuleID>,
        enabled: (ModuleID) -> Bool?
    ) -> [ScriptModuleDefinition] {
        let definitions = files.map {
            ScriptModuleDefinition(url: $0.url, folderName: folderName, data: $0.data, enabled: enabled)
        }
        .sorted { $0.fileName < $1.fileName }
        return applyIDRules(definitions, builtIns: builtIns)
    }

    /// A built-in id or one under `agents.` errors its file; an id declared by several files errors every one of
    /// them. Files whose front matter decoded count for duplicates even when they are errored for another
    /// reason; the first problem found stays a file's status.
    static func applyIDRules(_ definitions: [ScriptModuleDefinition], builtIns: Set<ModuleID>)
        -> [ScriptModuleDefinition]
    {
        var declaring: [ModuleID: [String]] = [:]
        for definition in definitions {
            guard let id = definition.moduleID else { continue }
            declaring[id, default: []].append(definition.fileName)
        }
        return definitions.map { definition in
            guard let id = definition.moduleID, definition.status == .ok else { return definition }
            var definition = definition
            if builtIns.contains(id) {
                definition.status = .errored(.builtInID(id))
            } else if id.rawValue.hasPrefix(ScriptParseError.reservedIDPrefix) {
                definition.status = .errored(.reservedPrefix(id))
            } else if let files = declaring[id], files.count > 1 {
                definition.status = .errored(.duplicateID(id, otherFiles: files.filter { $0 != definition.fileName }))
            }
            return definition
        }
    }
}

/// Reads the folder off the main actor (AD-12).
enum ScriptFolderReader {
    enum FileRead: Equatable, Sendable {
        case data(Data)
        /// An iCloud file not downloaded yet: download started, the last good definition stays.
        case pending
        /// Gone or unreadable since it was listed.
        case unavailable
    }

    /// Every `*.md` file directly in `folder` (not recursive, hidden files skipped), with its read. An absent
    /// folder reads as empty; nothing is created.
    static func read(_ folder: URL) async -> [URL: FileRead] {
        await Task.detached { readNow(folder) }.value
    }

    static func readNow(_ folder: URL) -> [URL: FileRead] {
        var reads: [URL: FileRead] = [:]
        for url in markdownFiles(in: folder) { reads[url] = readFile(url) }
        return reads
    }

    /// URLs are built from `folder` (not resolved), so paths match the config folder the host gave.
    static func markdownFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().compactMap { name in
            guard !name.hasPrefix("."), (name as NSString).pathExtension.lowercased() == "md" else { return nil }
            let url = folder.appendingPathComponent(name, isDirectory: false)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
            return url
        }
    }

    /// Through `NSFileCoordinator`, after checking the iCloud status (AD-12, as ConfigStore reads).
    static func readFile(_ url: URL) -> FileRead {
        let fm = FileManager.default
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
            values.isUbiquitousItem == true,
            let status = values.ubiquitousItemDownloadingStatus, status != .current
        {
            try? fm.startDownloadingUbiquitousItem(at: url)
            return .pending
        }
        var coordinationError: NSError?
        var result = FileRead.unavailable
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            if let data = try? Data(contentsOf: readURL) { result = .data(data) }
        }
        return coordinationError == nil ? result : .unavailable
    }
}
