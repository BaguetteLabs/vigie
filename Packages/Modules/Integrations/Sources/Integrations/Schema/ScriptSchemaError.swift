import Foundation

/// Why a script's front matter or output does not match `schemas/script-module.schema.json` (Story 12.1).
///
/// Thrown by the decoders of the script schema types. `path` names the offending key the way an author writes
/// it (`settings[1].type`, `widget.level`), and ``message`` is the localized sentence Story 12.2 shows in the
/// setup-problem alert and Settings › Scripts.
public struct ScriptSchemaError: Error, Equatable, Sendable, CustomStringConvertible {
    /// What kind of value a key expected.
    public enum ValueKind: String, Sendable {
        case string, integer, number, boolean, array, object
        /// `widget.value`: a string or a number.
        case stringOrNumber
    }

    /// The grammars a string value must follow.
    public enum Format: String, Sendable {
        /// Module id (Conventions: Module ids).
        case moduleID
        /// snake_case setting key.
        case settingKey
        /// Config duration grammar (`30s`, `5m`, `1h30m`).
        case duration
        /// A duration greater than zero.
        case interval
        /// SF Symbol name.
        case icon
        /// Bare executable name.
        case runtime
        /// URL with a scheme.
        case url
        /// `https://` URL with a host (front matter `source`, schema 2).
        case httpsURL
        /// A script version: `1.2.0`, `2.0.0-beta.1` (front matter `version`, schema 2).
        case version
    }

    public enum Reason: Equatable, Sendable {
        case missingKey
        /// The key is not part of the schema where unknown keys are rejected (front matter, settings).
        case unknownKey
        case wrongType(expected: ValueKind)
        /// An enum key with a value outside its options.
        case unknownValue(String, allowed: [String])
        case invalidFormat(String, Format)
        /// A host-owned key (`enabled`, `side`, `priority`, `surfaces`, `notify`) used as a setting key (AD-18).
        case reservedKey(String)
        /// A `schema` version this Vigie does not read.
        case unsupportedSchema(Int, supported: Int)
        /// A key that needs a newer `schema` than the file declares (`author` in a schema 1 file).
        case requiresSchema(Int)
        /// An empty string or list where one is required.
        case empty
        case duplicate(String)
        /// A number at or below its lower bound (a `step`).
        case notPositive
        /// `action` holds none or several of `open`, `run`, `copy`.
        case actionCount
    }

    /// Dotted key path, e.g. `settings[1].type`; empty for the document itself.
    public let path: String
    public let reason: Reason

    public init(path: String, reason: Reason) {
        self.path = path
        self.reason = reason
    }

    init(_ codingPath: [any CodingKey], _ reason: Reason) {
        self.init(path: Self.render(codingPath), reason: reason)
    }

    /// Renders a coding path the way it is written in the file: `settings[1].type`.
    static func render(_ codingPath: [any CodingKey]) -> String {
        var out = ""
        for key in codingPath {
            if let index = key.intValue {
                out += "[\(index)]"
            } else {
                out += out.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return out
    }

    /// The localized sentence naming the key and the problem.
    public var message: String {
        let key = path.isEmpty ? IntegrationsText.string("script.error.document") : path
        switch reason {
        case .missingKey:
            return IntegrationsText.format("script.error.missing_key", key)
        case .unknownKey:
            return IntegrationsText.format("script.error.unknown_key", key)
        case .wrongType(let expected):
            return IntegrationsText.format(
                "script.error.wrong_type", key, IntegrationsText.string("script.kind.\(expected.rawValue)"))
        case .unknownValue(let value, let allowed):
            return IntegrationsText.format(
                "script.error.unknown_value", key, value, allowed.joined(separator: ", "))
        case .invalidFormat(let value, let format):
            return IntegrationsText.format(
                "script.error.invalid_format", key, value, IntegrationsText.string("script.format.\(format.rawValue)"))
        case .reservedKey(let value):
            return IntegrationsText.format("script.error.reserved_key", key, value)
        case .unsupportedSchema(let version, let supported):
            return IntegrationsText.format("script.error.unsupported_schema", key, version, supported)
        case .requiresSchema(let version):
            return IntegrationsText.format("script.error.requires_schema", key, version)
        case .empty:
            return IntegrationsText.format("script.error.empty", key)
        case .duplicate(let value):
            return IntegrationsText.format("script.error.duplicate", key, value)
        case .notPositive:
            return IntegrationsText.format("script.error.not_positive", key)
        case .actionCount:
            return IntegrationsText.format("script.error.action_count", key)
        }
    }

    public var description: String { message }
}
