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
/// A file installed from a `vigie://install` link also gets (Story 12.9):
///
/// ```toml
/// [scripts.sources."modules/ci-status.md"]
/// url = "https://…/ci-status.md"        # downloaded from, after redirects
/// sig = "https://…/ci-status.md.sig"    # absent when no signature was found
/// installed_at = "2026-11-12T21:04:00Z"
/// ```
///
/// An update the user declined (Story 12.10) is kept so the same content is never offered again:
///
/// ```toml
/// [scripts.declined_updates."modules/ci-status.md"]
/// sha256 = "<lowercase hex SHA-256 of the declined update's bytes>"
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

    @MainActor public func source(for relativePath: String) -> ScriptSourceRecord? {
        func text(_ key: CoreSettings.ScriptSourceKey) -> String? {
            guard
                case .string(let value) = store.rawValue(
                    at: CoreSettings.scriptSourcePath(relativePath, key), in: .local),
                !value.isEmpty
            else { return nil }
            return value
        }
        guard let url = text(.url).flatMap(URL.init(string:)) else { return nil }
        let installedAt = text(.installedAt).flatMap { try? Date($0, strategy: .iso8601) } ?? .distantPast
        return ScriptSourceRecord(
            url: url, signatureURL: text(.sig).flatMap(URL.init(string:)), installedAt: installedAt)
    }

    public func recordSource(_ relativePath: String, _ source: ScriptSourceRecord) async throws {
        await MainActor.run { store.registerScriptSource(relativePath) }
        try await store.set(CoreSettings.scriptSourcePath(relativePath, .url), to: .string(source.url.absoluteString))
        if let sig = source.signatureURL {
            try await store.set(CoreSettings.scriptSourcePath(relativePath, .sig), to: .string(sig.absoluteString))
        } else {
            try await store.remove(CoreSettings.scriptSourcePath(relativePath, .sig))
        }
        try await store.set(
            CoreSettings.scriptSourcePath(relativePath, .installedAt),
            to: .string(source.installedAt.formatted(.iso8601)))
    }

    @MainActor public func declinedUpdate(for relativePath: String) -> String? {
        hash(.declinedUpdates, relativePath)
    }

    public func declineUpdate(_ relativePath: String, sha256: String) async throws {
        await MainActor.run { store.registerScriptRecord(relativePath) }
        try await store.set(
            CoreSettings.scriptRecordPath(.declinedUpdates, relativePath), to: .string(sha256.lowercased()))
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
