import Foundation
import ModuleKit
import Security
import Wire
import os

/// The core secret store (Story 7.2, AD-9, NFR6): every secret Vigie keeps is a generic-password item in the
/// data protection keychain, in access group `<TeamID>.<bundle id>`, never synchronized, readable after first
/// unlock on this Mac only. The account is `<owner id>/<key>`.
///
/// Modules and adapters never reach this type: they get ``scoped(to:)`` (`context.secrets`,
/// `AdapterContext.secrets`), which fixes the owner, so one owner can never name another's key.
///
/// Availability is probed once, on first use: a build that is not signed with the keychain entitlement
/// (ad-hoc dev builds, `errSecMissingEntitlement`) or has no team makes the store unavailable, and every call
/// throws ``SecretStoreError/unavailable(status:)``. ``reportAvailability(to:)`` posts one `setup.problem`
/// for it. Values are never logged.
public actor KeychainSecretStore {
    public enum Availability: Equatable, Sendable {
        case available
        case unavailable(status: Int32)
    }

    /// `setup.problem` dedupe key for "secrets are unavailable in this build".
    public static let unavailableDedupeKey = "secrets.unavailable"
    /// Account of the probe query. Owner ids never contain `/`, so it cannot collide with `<owner>/<key>`.
    static let probeAccount = "vigie.availability-probe"

    public nonisolated let identity: SecretStoreIdentity
    private let client: any KeychainClient
    private let log: Logger
    private var probed: Availability?
    private var problemPosted = false

    public init(identity: SecretStoreIdentity, client: any KeychainClient = SystemKeychainClient(), log: Logger) {
        self.identity = identity
        self.client = client
        self.log = log
    }

    /// The store for the running app: its signing team, `environment`'s bundle id, the real Keychain.
    public init(environment: AppEnvironment) {
        self.init(
            identity: SecretStoreIdentity(environment: environment),
            log: Logger(subsystem: environment.logSubsystem, category: "secrets"))
    }

    // MARK: - Availability

    /// Probes once (a `SecItemCopyMatching` on a sentinel item) and caches the result.
    public func availability() -> Availability {
        if let probed { return probed }
        let result = probe()
        probed = result
        switch result {
        case .available:
            log.info("Secrets available (access group \(self.identity.accessGroup ?? "", privacy: .public))")
        case .unavailable(let status):
            log.error("Secrets unavailable in this build (status \(status, privacy: .public))")
        }
        return result
    }

    /// Probes, and posts one `setup.problem` (category `SECRETS`) the first time the store is unavailable.
    @discardableResult
    public func reportAvailability(to notifier: any Notifier) -> Availability {
        let result = availability()
        if case .unavailable = result, !problemPosted {
            problemPosted = true
            notifier.post(Self.unavailableEvent())
        }
        return result
    }

    private func probe() -> Availability {
        guard let group = identity.accessGroup else {
            log.error("No team identifier in the code signature (ad-hoc signed build)")
            return .unavailable(status: errSecMissingEntitlement)
        }
        var query = Self.itemQuery(identity: identity, accessGroup: group, account: Self.probeAccount)
        query[kSecMatchLimit] = kSecMatchLimitOne
        let (status, _) = client.copyMatching(query)
        return status == errSecMissingEntitlement ? .unavailable(status: status) : .available
    }

    // MARK: - Items

    /// The secret stored for `owner` under `key`. Throws `.notFound` when there is none.
    public func get(owner: String, key: String) throws(SecretStoreError) -> String {
        var query = try query(owner: owner, key: key)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        let (status, data) = client.copyMatching(query)
        try check(status, "read", owner: owner, key: key)
        guard let data, let value = String(data: data, encoding: .utf8) else {
            log.error("Secret \(owner, privacy: .public)/\(key, privacy: .public) is not UTF-8 text")
            throw .failed(status: errSecDecode)
        }
        return value
    }

    /// Whether a secret is stored for `owner` under `key`.
    public func exists(owner: String, key: String) throws(SecretStoreError) -> Bool {
        var query = try query(owner: owner, key: key)
        query[kSecMatchLimit] = kSecMatchLimitOne
        let (status, _) = client.copyMatching(query)
        if status == errSecItemNotFound { return false }
        try check(status, "check", owner: owner, key: key)
        return true
    }

    /// Stores `value`, replacing any earlier one.
    public func set(_ value: String, owner: String, key: String) throws(SecretStoreError) {
        let query = try query(owner: owner, key: key)
        let data = Data(value.utf8)
        var attributes = query
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var status = client.add(attributes)
        if status == errSecDuplicateItem {
            status = client.update(
                query, [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly])
        }
        try check(status, "write", owner: owner, key: key)
    }

    /// Deletes the secret. Throws `.notFound` when there is none.
    public func remove(owner: String, key: String) throws(SecretStoreError) {
        let status = client.delete(try query(owner: owner, key: key))
        try check(status, "delete", owner: owner, key: key)
    }

    // MARK: - Owner scoping

    /// The `SecretStore` for one owner: a module id (`context.secrets`) or `adapter.<adapter id>`
    /// (`AdapterContext.secrets`). The owner must be non-empty and contain no `/`.
    public nonisolated func scoped(to owner: String) -> any SecretStore {
        precondition(Self.isValidOwner(owner), "invalid secret owner id")
        return OwnerSecretStore(store: self, owner: owner)
    }

    /// The owner id an agent or terminal adapter's secrets use.
    public nonisolated static func adapterOwner(_ adapterID: String) -> String { "adapter.\(adapterID)" }

    nonisolated static func isValidOwner(_ owner: String) -> Bool { !owner.isEmpty && !owner.contains("/") }

    /// `<owner id>/<key>`.
    nonisolated static func account(owner: String, key: String) -> String { "\(owner)/\(key)" }

    /// The attributes every item query carries (AD-9).
    nonisolated static func itemQuery(identity: SecretStoreIdentity, accessGroup: String, account: String)
        -> [CFString: Any]
    {
        [
            kSecClass: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain: true,
            kSecAttrAccessGroup: accessGroup,
            kSecAttrSynchronizable: false,
            kSecAttrService: identity.service,
            kSecAttrAccount: account,
        ]
    }

    private func query(owner: String, key: String) throws(SecretStoreError) -> [CFString: Any] {
        guard case .available = availability(), let group = identity.accessGroup else {
            throw .unavailable(status: errSecMissingEntitlement)
        }
        precondition(Self.isValidOwner(owner), "invalid secret owner id")
        return Self.itemQuery(identity: identity, accessGroup: group, account: Self.account(owner: owner, key: key))
    }

    private func check(_ status: OSStatus, _ operation: StaticString, owner: String, key: String)
        throws(SecretStoreError)
    {
        switch status {
        case errSecSuccess: return
        case errSecItemNotFound: throw .notFound
        case errSecMissingEntitlement:
            log.error("Secret \(operation): missing keychain entitlement")
            throw .unavailable(status: status)
        default:
            log.error(
                "Secret \(operation) failed for \(owner, privacy: .public)/\(key, privacy: .public): \(status, privacy: .public)"
            )
            throw .failed(status: status)
        }
    }

    // MARK: - Setup problem

    static func unavailableEvent() -> NotifierEvent {
        NotifierEvent(
            kind: SetupProblemReporter.alertKind, severity: .warn,
            title: text("vigiecore.setup.title.secretsUnavailable"),
            body: text("vigiecore.setup.body.secretsUnavailable"), action: nil, dedupeKey: unavailableDedupeKey,
            category: text("vigiecore.setup.category.secrets"))
    }

    private static func text(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }
}

/// `context.secrets` / `AdapterContext.secrets`: one owner's view of ``KeychainSecretStore``.
struct OwnerSecretStore: SecretStore {
    let store: KeychainSecretStore
    let owner: String

    func read(_ key: String) async throws -> String? {
        do {
            return try await store.get(owner: owner, key: key)
        } catch .notFound {
            return nil
        }
    }

    func write(_ value: String?, for key: String) async throws {
        guard let value else {
            do {
                try await store.remove(owner: owner, key: key)
            } catch .notFound {
                // Already gone.
            }
            return
        }
        try await store.set(value, owner: owner, key: key)
    }
}
