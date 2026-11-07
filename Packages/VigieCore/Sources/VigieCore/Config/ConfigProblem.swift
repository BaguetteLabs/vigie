import Foundation

/// A problem found while reading `config.toml` or `local.toml` (AD-8). Story 3.4 turns the actionable ones
/// (`invalidFile`, `invalidValue`, `wrongFile`) into the setup-problem alert; `unknownKey` is informational.
public struct ConfigProblem: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// TOML parse error (or unreadable file); the last valid content of that file stays active.
        case invalidFile(line: Int?)
        /// A known key with a wrong type or out-of-range value; its default applies.
        case invalidValue
        /// A `.local` key in `config.toml`, or a `.synced` key in `local.toml`; it is ignored.
        case wrongFile
        /// A key no core setting or registered module declares; it is ignored.
        case unknownKey
    }

    public let kind: Kind
    /// The file the problem is in.
    public let path: URL
    /// Canonical key path (`ConfigKeyPath.description`), nil for file-level problems.
    public let key: String?
    /// Diagnostic detail for logs (English, not localized; the UI builds its text from `kind` and `key`).
    public let message: String

    public init(kind: Kind, path: URL, key: String?, message: String) {
        self.kind = kind
        self.path = path
        self.key = key
        self.message = message
    }

    public var id: String {
        let tag =
            switch kind {
            case .invalidFile: "invalidFile"
            case .invalidValue: "invalidValue"
            case .wrongFile: "wrongFile"
            case .unknownKey: "unknownKey"
            }
        return "\(tag)|\(path.path)|\(key ?? "")"
    }
}

public enum ConfigError: Error, Equatable, Sendable {
    /// No core setting or registered module declares this key (module key, or canonical key path).
    case unknownSetting(String)
    /// The value has the wrong type for the setting or is out of range; `reason` is English diagnostic text.
    case invalidValue(key: String, reason: String)
    /// The key is defined inside an inline table or an array of tables (or under a non-table value), which
    /// the line patcher does not edit; the user has to change it by hand.
    case unsupportedLocation(key: String)
    /// The file could not be read or is not valid UTF-8 (or is an iCloud item not downloaded yet).
    case fileUnavailable(file: String, reason: String)
    /// The file has a TOML error; it must be fixed before Vigie writes to it.
    case fileHasErrors(file: String)
    /// The patched text did not parse, or decoded to something other than intended; nothing was written.
    case verificationFailed(key: String)
    /// The atomic write failed; the file is unchanged.
    case writeFailed(file: String, reason: String)
}
