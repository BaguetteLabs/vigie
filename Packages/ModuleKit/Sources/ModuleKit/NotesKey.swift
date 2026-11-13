import CryptoKit
import Foundation

// MARK: - Notes key (Story 15.1, AD-9, AD-10)

/// The notes encryption key: 32 random bytes (AES-256), the single synchronizable iCloud Keychain item of AD-9.
///
/// Its ``keyID`` (the first 8 bytes of SHA-256 of the key, 16 lowercase hex characters) is the `key_id` every note
/// file's plaintext header carries (Story 15.2). The key bytes never appear in `description`, logs or files.
public struct SyncedKey: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// Key length in bytes.
    public static let byteCount = 32
    /// Bytes of SHA-256 kept for ``keyID``.
    public static let keyIDByteCount = 8

    /// The raw key. Hold it in memory only.
    public let data: Data
    /// `key_id`: hex of the first 8 bytes of SHA-256(``data``).
    public let keyID: String

    /// nil unless `data` is exactly ``byteCount`` bytes.
    public init?(data: Data) {
        guard data.count == Self.byteCount else { return nil }
        self.data = data
        self.keyID = Self.keyID(for: data)
    }

    /// A new key from the system's secure random generator (CryptoKit, `SecRandomCopyBytes` underneath).
    public static func random() -> SyncedKey {
        let bytes = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return SyncedKey(data: bytes)!
    }

    /// The `key_id` of raw key bytes.
    public static func keyID(for data: Data) -> String {
        SHA256.hash(data: data).prefix(keyIDByteCount).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `text` has the shape of a `key_id` (16 lowercase hex characters).
    public static func isValidKeyID(_ text: String) -> Bool {
        text.utf8.count == keyIDByteCount * 2
            && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    /// The CryptoKit key (Story 15.2 encrypts with it).
    public var symmetricKey: SymmetricKey { SymmetricKey(data: data) }

    public var description: String { "SyncedKey(\(keyID))" }
    public var debugDescription: String { description }
}

/// Why the notes key store cannot be used.
public enum SyncedKeyUnavailableReason: Hashable, Sendable {
    /// The build has no signing team (ad-hoc dev builds): there is no access group to use.
    case noSigningTeam
    /// The build is signed but lacks the keychain access group (`errSecMissingEntitlement`).
    case missingEntitlement
    /// Any other Keychain failure while probing (the `OSStatus`).
    case keychainError(status: Int32)
    /// The context belongs to a module other than `notes` (only Notes holds the notes key).
    case notOwner
}

public enum SyncedKeyAvailability: Hashable, Sendable {
    case available
    case unavailable(SyncedKeyUnavailableReason)
}

/// Which key and folder this build uses (AD-10).
public enum SyncedKeyScope: Hashable, Sendable {
    /// The release key in `<TeamID>.<release bundle id>.notes`, shared by Vigie and Vigie Dev; the configured
    /// notes folder.
    case shared
    /// Vigie Dev cannot read the release key: it keeps its own key (its own access group) and uses its own notes
    /// folder, `folderName` (the app's display name, `Vigie Dev`) next to the default one.
    case ownBuild(folderName: String)
}

/// Whether iCloud Keychain syncs the key. macOS has no public API to ask, so the production store reports
/// ``unknown``; Settings then states that the recovery key is the only sure way to read notes on another Mac.
public enum ICloudKeychainStatus: Hashable, Sendable {
    case on
    case off
    case unknown
}

/// Why a ``SyncedKeyStore`` call failed. Never carries key bytes.
public enum SyncedKeyError: Error, Hashable, Sendable {
    case unavailable(SyncedKeyUnavailableReason)
    /// ``SyncedKeyStore/createKey()`` found a key already stored: adopt it, never create a second one.
    case alreadyExists
    /// The stored item is not a 32-byte key.
    case corrupt
    /// Any other Keychain failure (the `OSStatus`).
    case failed(status: Int32)
}

/// `context.notesKey` (Story 15.1): the one notes encryption key, beside the owner-scoped ``SecretStore``
/// (AD-9). VigieCore implements it on the data protection keychain as a synchronizable generic password, account
/// `notes`, in `<TeamID>.<release bundle id>.notes`. Only the `notes` module's context carries a working store;
/// every other module gets ``UnavailableSyncedKeyStore`` (`.notOwner`).
///
/// AD-10: call ``createKey()`` only from an explicit user action ("Set up notes"), never while the notes folder
/// holds note files.
public protocol SyncedKeyStore: Sendable {
    /// Whether the store can be used in this build. Probed once, then cached.
    func availability() async -> SyncedKeyAvailability
    /// Which key and folder this build uses.
    func scope() async -> SyncedKeyScope
    /// Whether iCloud Keychain syncs the item, when it can be told.
    func iCloudKeychainStatus() async -> ICloudKeychainStatus
    /// The stored key, or nil when there is none (yet: it may still arrive through iCloud Keychain).
    func readKey() async throws -> SyncedKey?
    /// Creates and stores a new random key. Throws ``SyncedKeyError/alreadyExists`` when one is stored; it never
    /// replaces a key.
    func createKey() async throws -> SyncedKey
    /// Stores `key` (from a recovery key), replacing what is stored.
    func importKey(_ key: SyncedKey) async throws
    /// Deletes the stored key (and its synced copies). Not used by any surface in v0.4.
    func delete() async throws
    /// Yields when the stored key may have changed: a write through this store, or a synced item that arrived
    /// or left (polled while someone listens). Each call returns a new stream; stop iterating to end it.
    func changes() -> AsyncStream<Void>
}

/// The store of a context that holds no notes key: always unavailable.
public struct UnavailableSyncedKeyStore: SyncedKeyStore {
    public let reason: SyncedKeyUnavailableReason

    public init(reason: SyncedKeyUnavailableReason = .notOwner) {
        self.reason = reason
    }

    public func availability() async -> SyncedKeyAvailability { .unavailable(reason) }
    public func scope() async -> SyncedKeyScope { .shared }
    public func iCloudKeychainStatus() async -> ICloudKeychainStatus { .unknown }
    public func readKey() async throws -> SyncedKey? { throw SyncedKeyError.unavailable(reason) }
    public func createKey() async throws -> SyncedKey { throw SyncedKeyError.unavailable(reason) }
    public func importKey(_ key: SyncedKey) async throws { throw SyncedKeyError.unavailable(reason) }
    public func delete() async throws { throw SyncedKeyError.unavailable(reason) }
    public func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
