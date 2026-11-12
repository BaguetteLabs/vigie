import Foundation
import ModuleKit

/// Why a script module file cannot be used (SPEC §9.1, AD-18, Story 12.2). Shown in the file's setup-problem
/// alert and, from Story 12.6, in Settings › Scripts.
public enum ScriptParseError: Error, Equatable, Sendable {
    /// The bytes are not UTF-8 text.
    case notText
    /// The file does not start with a `---` line.
    case frontMatterMissing
    /// No `---` (or `...`) line closes the front matter.
    case frontMatterUnclosed
    /// The front matter is not YAML; `line` is the file line Yams reported, when it did.
    case invalidYAML(line: Int?)
    /// The front matter does not follow `schemas/script-module.schema.json` (Story 12.1), host-owned setting
    /// keys included (`settings[n].key`).
    case schema(ScriptSchemaError)
    case noCodeBlock
    case severalCodeBlocks(count: Int)
    /// A fence opened on `line` (1-based, in the file) is never closed.
    case codeBlockUnclosed(line: Int)
    /// `id` is a built-in module's id.
    case builtInID(ModuleID)
    /// `id` starts with `agents.`, reserved for the agent modules.
    case reservedPrefix(ModuleID)
    /// Another file declares the same `id`; `otherFiles` are their names.
    case duplicateID(ModuleID, otherFiles: [String])

    /// The prefix no script id may start with (AD-18).
    public static let reservedIDPrefix = "agents."

    /// The front-matter key the problem is about (`settings[1].type`, `id`), nil for a problem with the file.
    public var keyPath: String? {
        switch self {
        case .schema(let error): error.path
        case .builtInID, .reservedPrefix, .duplicateID: "id"
        default: nil
        }
    }

    /// The localized sentence, naming the key when there is one.
    public var message: String {
        switch self {
        case .notText:
            IntegrationsText.string("script.parse.not_text")
        case .frontMatterMissing:
            IntegrationsText.string("script.parse.front_matter_missing")
        case .frontMatterUnclosed:
            IntegrationsText.string("script.parse.front_matter_unclosed")
        case .invalidYAML(let line?):
            IntegrationsText.format("script.parse.yaml_line", line)
        case .invalidYAML(nil):
            IntegrationsText.string("script.parse.yaml")
        case .schema(let error):
            error.message
        case .noCodeBlock:
            IntegrationsText.string("script.parse.no_code_block")
        case .severalCodeBlocks(let count):
            IntegrationsText.format("script.parse.several_code_blocks", count)
        case .codeBlockUnclosed(let line):
            IntegrationsText.format("script.parse.code_block_unclosed", line)
        case .builtInID(let id):
            IntegrationsText.format("script.parse.builtin_id", id.rawValue)
        case .reservedPrefix(let id):
            IntegrationsText.format("script.parse.reserved_prefix", id.rawValue, Self.reservedIDPrefix)
        case .duplicateID(let id, let others):
            IntegrationsText.format(
                "script.parse.duplicate_id", id.rawValue, others.joined(separator: ", "))
        }
    }

    /// ``message`` prefixed with the file name: `github.md: settings[0].key: …`.
    public func message(fileName: String) -> String {
        IntegrationsText.format("script.parse.in_file", fileName, message)
    }
}

/// Whether a script module file can be used.
public enum ScriptParseStatus: Equatable, Sendable {
    case ok
    case errored(ScriptParseError)

    public var error: ScriptParseError? {
        if case .errored(let error) = self { return error }
        return nil
    }
}
