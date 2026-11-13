import Foundation
import ModuleKit

/// In-memory notes key store: the test sets availability, scope, iCloud status and the stored key, and can make
/// a key "arrive" (as iCloud Keychain would) with or without a change yield. Never touches the Keychain.
final class FakeSyncedKeyStore: SyncedKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SyncedKey?
    private var currentAvailability: SyncedKeyAvailability
    private var currentScope: SyncedKeyScope
    private var iCloud: ICloudKeychainStatus
    private var continuations: [AsyncStream<Void>.Continuation] = []
    private var created = 0
    private var imported: [SyncedKey] = []
    var failWrites = false

    init(
        key: SyncedKey? = nil, availability: SyncedKeyAvailability = .available, scope: SyncedKeyScope = .shared,
        iCloud: ICloudKeychainStatus = .unknown
    ) {
        stored = key
        currentAvailability = availability
        currentScope = scope
        self.iCloud = iCloud
    }

    var createCount: Int { lock.withLock { created } }
    var imports: [SyncedKey] { lock.withLock { imported } }
    var key: SyncedKey? { lock.withLock { stored } }
    var listeners: Int { lock.withLock { continuations.count } }

    /// A synced item arrives; `notify` yields on the change stream.
    func arrive(_ key: SyncedKey, notify: Bool = true) {
        let all = lock.withLock {
            stored = key
            return continuations
        }
        if notify { for continuation in all { continuation.yield() } }
    }

    func availability() async -> SyncedKeyAvailability { lock.withLock { currentAvailability } }
    func scope() async -> SyncedKeyScope { lock.withLock { currentScope } }
    func iCloudKeychainStatus() async -> ICloudKeychainStatus { lock.withLock { iCloud } }

    func readKey() async throws -> SyncedKey? {
        try lock.withLock {
            if case .unavailable(let reason) = currentAvailability { throw SyncedKeyError.unavailable(reason) }
            return stored
        }
    }

    func createKey() async throws -> SyncedKey {
        try lock.withLock {
            if case .unavailable(let reason) = currentAvailability { throw SyncedKeyError.unavailable(reason) }
            if failWrites { throw SyncedKeyError.failed(status: -1) }
            if stored != nil { throw SyncedKeyError.alreadyExists }
            let key = SyncedKey.random()
            stored = key
            created += 1
            return key
        }
    }

    func importKey(_ key: SyncedKey) async throws {
        try lock.withLock {
            if case .unavailable(let reason) = currentAvailability { throw SyncedKeyError.unavailable(reason) }
            if failWrites { throw SyncedKeyError.failed(status: -1) }
            stored = key
            imported.append(key)
        }
    }

    func delete() async throws { lock.withLock { stored = nil } }

    func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        lock.withLock { continuations.append(continuation) }
        return stream
    }
}
