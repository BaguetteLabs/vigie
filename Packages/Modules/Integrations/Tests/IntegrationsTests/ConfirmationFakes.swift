import Foundation
import ModuleKit

@testable import Integrations

/// `context.scriptFolder.confirmations` in memory (Story 12.3): records by relative path, every write in order,
/// and `edit` standing for an outside edit of `local.toml`. It models `local.toml` only; the synced side is
/// asserted by VigieCore's `ScriptConfirmationsConfigTests`.
final class MemoryScriptConfirmations: ScriptConfirmationStore, @unchecked Sendable {
    enum Write: Equatable {
        case confirm(String, String)
        case decline(String, String)
    }

    private let lock = NSLock()
    private var stored: [String: ScriptConfirmationRecord] = [:]
    private var log: [Write] = []
    private var sources: [String: ScriptSourceRecord] = [:]
    var sourceRecords: [String: ScriptSourceRecord] { lock.withLock { sources } }
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    /// Set to make the next write throw.
    var failure: (any Error)?

    var records: [String: ScriptConfirmationRecord] { lock.withLock { stored } }
    var writes: [Write] { lock.withLock { log } }
    var subscribers: Int { lock.withLock { continuations.count } }

    @MainActor func record(for relativePath: String) -> ScriptConfirmationRecord {
        lock.withLock { stored[relativePath] ?? .none }
    }

    func confirm(_ relativePath: String, sha256: String) async throws {
        if let failure = lock.withLock({ failure }) { throw failure }
        lock.withLock {
            stored[relativePath] = ScriptConfirmationRecord(confirmedSHA256: sha256)
            log.append(.confirm(relativePath, sha256))
        }
        notify()
    }

    func decline(_ relativePath: String, sha256: String) async throws {
        if let failure = lock.withLock({ failure }) { throw failure }
        lock.withLock {
            stored[relativePath] = ScriptConfirmationRecord(declinedSHA256: sha256)
            log.append(.decline(relativePath, sha256))
        }
        notify()
    }

    @MainActor func source(for relativePath: String) -> ScriptSourceRecord? { lock.withLock { sources[relativePath] } }

    func recordSource(_ relativePath: String, _ source: ScriptSourceRecord) async throws {
        if let failure = lock.withLock({ failure }) { throw failure }
        lock.withLock { sources[relativePath] = source }
    }

    /// An outside edit of `local.toml`.
    func edit(_ relativePath: String, _ record: ScriptConfirmationRecord?) {
        lock.withLock { stored[relativePath] = record }
        notify()
    }

    @MainActor func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let id = UUID()
        lock.withLock { continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    private func notify() {
        for continuation in lock.withLock({ Array(continuations.values) }) { continuation.yield() }
    }
}
