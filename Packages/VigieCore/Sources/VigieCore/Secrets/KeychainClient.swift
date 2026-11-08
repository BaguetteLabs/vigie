import Foundation
import Security

/// The four Keychain calls ``KeychainSecretStore`` makes, so tests can use an in-memory fake (Story 7.2).
/// Dictionaries are `SecItem` queries and attributes; results are `OSStatus`.
public protocol KeychainClient: Sendable {
    func add(_ attributes: [CFString: Any]) -> OSStatus
    func update(_ query: [CFString: Any], _ attributes: [CFString: Any]) -> OSStatus
    /// `SecItemCopyMatching`; the data is returned when the query asks for `kSecReturnData`.
    func copyMatching(_ query: [CFString: Any]) -> (OSStatus, Data?)
    func delete(_ query: [CFString: Any]) -> OSStatus
}

/// The real Keychain (`SecItem*`). The only Keychain caller in Vigie (AD-9).
public struct SystemKeychainClient: KeychainClient {
    public init() {}

    public func add(_ attributes: [CFString: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func update(_ query: [CFString: Any], _ attributes: [CFString: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    public func copyMatching(_ query: [CFString: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    public func delete(_ query: [CFString: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
