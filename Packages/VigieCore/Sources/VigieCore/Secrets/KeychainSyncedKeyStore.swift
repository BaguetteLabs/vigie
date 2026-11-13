import Foundation
import ModuleKit
import Security
import Wire
import os

/// `context.notesKey` for the `notes` module (Story 15.1, AD-9, AD-10): the one notes encryption key, a
/// synchronizable generic password in the data protection keychain, account `notes`.
///
/// Where it lives, probed once on first use:
/// 1. `<TeamID>.<release bundle id>.notes`, service `<release bundle id>.notes`: shared by Vigie and Vigie Dev
///    (scope `.shared`).
/// 2. Vigie Dev only, when the shared group is refused (`errSecMissingEntitlement`): its own group
///    `<TeamID>.<dev bundle id>`, service `<dev bundle id>.notes` (scope `.ownBuild`, own notes folder).
/// 3. Otherwise unavailable: no team (ad-hoc builds) or no entitlement. Every call then throws
///    ``SyncedKeyError/unavailable(_:)``; nothing crashes.
///
/// The item is `kSecAttrAccessibleAfterFirstUnlock` (not `ThisDeviceOnly`, so it can sync). When iCloud Keychain
/// is off it simply stays on this Mac. Key bytes are never logged; only the `key_id` is.
public actor KeychainSyncedKeyStore: SyncedKeyStore {
    /// The item's account.
    public static let account = "notes"
    /// How often a listened-to store re-reads the item to notice a key that arrived through iCloud Keychain.
    public static let defaultPollInterval: Duration = .seconds(30)

    /// The group and service the store resolved to.
    struct Target: Equatable, Sendable {
        let accessGroup: String
        let service: String
        let scope: SyncedKeyScope
    }

    public nonisolated let identity: SecretStoreIdentity
    /// The dev build's own notes folder name (the app's display name, `Vigie Dev`).
    nonisolated let ownFolderName: String
    private let client: any KeychainClient
    private let log: Logger
    private let pollInterval: Duration
    private var resolved: Result<Target, SyncedKeyError>?
    private var listeners: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var pollTask: Task<Void, Never>?
    private var lastSeenKeyID: String??

    public init(
        identity: SecretStoreIdentity, ownFolderName: String, client: any KeychainClient = SystemKeychainClient(),
        log: Logger, pollInterval: Duration = KeychainSyncedKeyStore.defaultPollInterval
    ) {
        self.identity = identity
        self.ownFolderName = ownFolderName
        self.client = client
        self.log = log
        self.pollInterval = pollInterval
    }

    /// The store for the running app: its signing team, `environment`'s bundle ids and display name, the real
    /// Keychain. Nothing touches the Keychain until the first call.
    public init(environment: AppEnvironment) {
        self.init(
            identity: SecretStoreIdentity(environment: environment), ownFolderName: environment.displayName,
            log: Logger(subsystem: environment.logSubsystem, category: "notes-key"))
    }

    // MARK: Availability

    public func availability() -> SyncedKeyAvailability {
        switch target() {
        case .success: .available
        case .failure(.unavailable(let reason)): .unavailable(reason)
        case .failure: .unavailable(.missingEntitlement)
        }
    }

    public func scope() -> SyncedKeyScope {
        if case .success(let target) = target() { return target.scope }
        return identity.isDevBuild ? .ownBuild(folderName: ownFolderName) : .shared
    }

    /// macOS offers no public API to tell whether iCloud Keychain is on.
    public func iCloudKeychainStatus() -> ICloudKeychainStatus { .unknown }

    private func target() -> Result<Target, SyncedKeyError> {
        if let resolved { return resolved }
        let result = resolve()
        resolved = result
        switch result {
        case .success(let target):
            log.info(
                "Notes key store in \(target.accessGroup, privacy: .public) (\(target.scope == .shared ? "shared" : "own build", privacy: .public))"
            )
        case .failure(let error):
            log.error("Notes key store unavailable: \(String(describing: error), privacy: .public)")
        }
        return result
    }

    private func resolve() -> Result<Target, SyncedKeyError> {
        guard let shared = identity.notesAccessGroup else { return .failure(.unavailable(.noSigningTeam)) }
        let sharedStatus = probe(group: shared, service: identity.notesService)
        if sharedStatus != errSecMissingEntitlement {
            return .success(Target(accessGroup: shared, service: identity.notesService, scope: .shared))
        }
        guard identity.isDevBuild, let own = identity.accessGroup else {
            return .failure(.unavailable(.missingEntitlement))
        }
        let ownStatus = probe(group: own, service: identity.ownNotesService)
        guard ownStatus != errSecMissingEntitlement else { return .failure(.unavailable(.missingEntitlement)) }
        return .success(
            Target(
                accessGroup: own, service: identity.ownNotesService, scope: .ownBuild(folderName: ownFolderName)))
    }

    private func probe(group: String, service: String) -> OSStatus {
        var query = Self.itemQuery(accessGroup: group, service: service)
        query[kSecMatchLimit] = kSecMatchLimitOne
        return client.copyMatching(query).0
    }

    // MARK: Item

    public func readKey() throws -> SyncedKey? {
        let target = try target().get()
        let key = try read(target)
        lastSeenKeyID = .some(key?.keyID)
        return key
    }

    private func read(_ target: Target) throws(SyncedKeyError) -> SyncedKey? {
        var query = Self.itemQuery(accessGroup: target.accessGroup, service: target.service)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        let (status, data) = client.copyMatching(query)
        switch status {
        case errSecSuccess:
            guard let data, let key = SyncedKey(data: data) else {
                log.error("Notes key item is not a 32-byte key")
                throw .corrupt
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw failure(status, "read")
        }
    }

    public func createKey() throws -> SyncedKey {
        let target = try target().get()
        if try read(target) != nil { throw SyncedKeyError.alreadyExists }
        let key = SyncedKey.random()
        let status = client.add(Self.addAttributes(target: target, key: key))
        if status == errSecDuplicateItem { throw SyncedKeyError.alreadyExists }
        guard status == errSecSuccess else { throw failure(status, "create") }
        log.notice("Notes key created (key_id \(key.keyID, privacy: .public))")
        didWrite(key.keyID)
        return key
    }

    public func importKey(_ key: SyncedKey) throws {
        let target = try target().get()
        var status = client.add(Self.addAttributes(target: target, key: key))
        if status == errSecDuplicateItem {
            status = client.update(
                Self.itemQuery(accessGroup: target.accessGroup, service: target.service),
                [kSecValueData: key.data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock])
        }
        guard status == errSecSuccess else { throw failure(status, "import") }
        log.notice("Notes key imported from a recovery key (key_id \(key.keyID, privacy: .public))")
        didWrite(key.keyID)
    }

    public func delete() throws {
        let target = try target().get()
        let status = client.delete(Self.itemQuery(accessGroup: target.accessGroup, service: target.service))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status, "delete") }
        log.notice("Notes key deleted")
        didWrite(nil)
    }

    private func failure(_ status: OSStatus, _ operation: StaticString) -> SyncedKeyError {
        log.error("Notes key \(operation) failed: \(status, privacy: .public)")
        return status == errSecMissingEntitlement ? .unavailable(.missingEntitlement) : .failed(status: status)
    }

    // MARK: Changes

    public nonisolated func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        Task { await self.addListener(id, continuation) }
        return stream
    }

    private func addListener(_ id: UUID, _ continuation: AsyncStream<Void>.Continuation) {
        listeners[id] = continuation
        guard pollTask == nil else { return }
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                await self.poll()
            }
        }
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
        if listeners.isEmpty {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    /// Re-reads the item; yields when its `key_id` (or its presence) changed since the last read.
    func poll() {
        guard case .success(let target) = target() else { return }
        let current: String?
        do {
            current = try read(target)?.keyID
        } catch {
            return
        }
        if let lastSeenKeyID, lastSeenKeyID == current { return }
        lastSeenKeyID = .some(current)
        yieldAll()
    }

    private func didWrite(_ keyID: String?) {
        lastSeenKeyID = .some(keyID)
        yieldAll()
    }

    private func yieldAll() {
        for continuation in listeners.values { continuation.yield() }
    }

    var listenerCount: Int { listeners.count }

    // MARK: Queries

    /// The attributes every notes key query carries (AD-9): data protection keychain, the group, synchronizable.
    nonisolated static func itemQuery(accessGroup: String, service: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain: true,
            kSecAttrAccessGroup: accessGroup,
            kSecAttrSynchronizable: true,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    nonisolated static func addAttributes(target: Target, key: SyncedKey) -> [CFString: Any] {
        var attributes = itemQuery(accessGroup: target.accessGroup, service: target.service)
        attributes[kSecValueData] = key.data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        return attributes
    }
}
