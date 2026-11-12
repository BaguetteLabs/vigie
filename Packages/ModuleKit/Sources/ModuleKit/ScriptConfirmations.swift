import Foundation

/// What this Mac recorded for one script file (AD-18, Story 12.3): the SHA-256 of the bytes the user confirmed,
/// and of the bytes the user declined. A record only counts for the exact bytes it names: when the file changes,
/// neither hash matches and the script is awaiting confirmation again.
public struct ScriptConfirmationRecord: Hashable, Sendable {
    /// Lowercase hex SHA-256 of the confirmed file bytes, or nil.
    public var confirmedSHA256: String?
    /// Lowercase hex SHA-256 of the declined file bytes, or nil.
    public var declinedSHA256: String?

    public init(confirmedSHA256: String? = nil, declinedSHA256: String? = nil) {
        self.confirmedSHA256 = confirmedSHA256
        self.declinedSHA256 = declinedSHA256
    }

    public static let none = ScriptConfirmationRecord()
}

/// `context.scriptFolder.confirmations` (AD-18, Story 12.3): per-Mac confirmation records of script files, keyed by
/// the file's path relative to the config folder (`modules/github.md`). Implemented by VigieCore over ConfigStore
/// (`local.toml` only, AD-8); a record is never read from or written to the synced `config.toml`.
public protocol ScriptConfirmationStore: Sendable {
    /// The record of `relativePath` on this Mac (``ScriptConfirmationRecord/none`` when there is none).
    @MainActor func record(for relativePath: String) -> ScriptConfirmationRecord
    /// Records that the user confirmed the file whose bytes hash to `sha256`, and removes its decline. Call only
    /// from a user action.
    func confirm(_ relativePath: String, sha256: String) async throws
    /// Records that the user declined the file whose bytes hash to `sha256`, and removes its confirmation. Call
    /// only from a user action.
    func decline(_ relativePath: String, sha256: String) async throws
    /// Yields once after any record changes, including an edit of `local.toml` made outside the app. The stream
    /// ends when the module stops.
    @MainActor func changes() -> AsyncStream<Void>
}

/// The default store: nothing is ever confirmed (no script can run), writes throw
/// ``ModuleServiceError/notAvailable``.
public struct NoScriptConfirmations: ScriptConfirmationStore {
    public init() {}
    @MainActor public func record(for relativePath: String) -> ScriptConfirmationRecord { .none }
    public func confirm(_ relativePath: String, sha256: String) async throws { throw ModuleServiceError.notAvailable }
    public func decline(_ relativePath: String, sha256: String) async throws { throw ModuleServiceError.notAvailable }
    @MainActor public func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
