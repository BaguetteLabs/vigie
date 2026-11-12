import Foundation
import ModuleKit

/// `context.scriptFolder.confirmations` (AD-18, Story 12.3): this Mac's script confirmations and declines in
/// `local.toml`, through ``ConfigStore`` (the only writer of config files, AD-8):
///
/// ```toml
/// [scripts.confirmations."modules/github.md"]
/// sha256 = "<lowercase hex SHA-256 of the confirmed file bytes>"
///
/// [scripts.declined."modules/other.md"]
/// sha256 = "<lowercase hex SHA-256 of the declined file bytes>"
/// ```
///
/// Records are read from `local.toml` only: a `[scripts]` table in the synced `config.toml` never confirms
/// anything (it is an open table there, ignored without a problem). Confirming removes the file's decline and
/// declining removes its confirmation.
public struct ConfigScriptConfirmations: ScriptConfirmationStore {
    let store: ConfigStore
    let tracker: RegistrationTracker

    public init(store: ConfigStore, tracker: RegistrationTracker) {
        self.store = store
        self.tracker = tracker
    }

    static let table = ConfigKeyPath(["scripts"])

    @MainActor public func record(for relativePath: String) -> ScriptConfirmationRecord {
        ScriptConfirmationRecord(
            confirmedSHA256: hash(.confirmations, relativePath), declinedSHA256: hash(.declined, relativePath))
    }

    @MainActor private func hash(_ kind: CoreSettings.ScriptRecordKind, _ relativePath: String) -> String? {
        guard case .string(let text) = store.rawValue(at: CoreSettings.scriptRecordPath(kind, relativePath), in: .local)
        else { return nil }
        let hash = text.trimmingCharacters(in: .whitespaces).lowercased()
        return hash.isEmpty ? nil : hash
    }

    public func confirm(_ relativePath: String, sha256: String) async throws {
        try await write(relativePath, set: .confirmations, sha256: sha256)
    }

    public func decline(_ relativePath: String, sha256: String) async throws {
        try await write(relativePath, set: .declined, sha256: sha256)
    }

    /// Sets one record, then removes the other (two ConfigStore writes; a failure of the first leaves the file
    /// untouched).
    private func write(_ relativePath: String, set kind: CoreSettings.ScriptRecordKind, sha256: String) async throws {
        let other: CoreSettings.ScriptRecordKind = kind == .confirmations ? .declined : .confirmations
        await MainActor.run { store.registerScriptRecord(relativePath) }
        try await store.set(CoreSettings.scriptRecordPath(kind, relativePath), to: .string(sha256.lowercased()))
        try await store.remove(CoreSettings.scriptRecordPath(other, relativePath))
    }

    /// Yields after each load or write that changes a key under `[scripts]`; ends when the module stops.
    @MainActor public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let source = store.changes
        let table = Self.table
        let task = Task { @MainActor in
            for await paths in source {
                if paths.contains(where: { $0.hasPrefix(table) }) { continuation.yield() }
            }
            continuation.finish()
        }
        let token = tracker.track(
            RegistrationToken {
                task.cancel()
                continuation.finish()
            })
        continuation.onTermination = { _ in token.cancel() }
        return stream
    }
}
