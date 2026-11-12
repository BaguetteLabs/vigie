import Foundation

/// The external logins `ClaudePlanUsageProvider` holds in process memory for the session (SPEC §7.2, AD-9 amended
/// 2026-11-12), keyed by `ExternalCredentialDescriptor.id`: the Keychain is read once per launch (so macOS shows
/// its prompt at most once), then again only when the held token has expired or the endpoint rejected it.
///
/// Only the access token and its expiry are kept, never the refresh token; nothing is written to disk, renewed or
/// logged. One instance lives in ``ClaudeAdapter`` for the life of the process.
public actor ExternalCredentialCache {
    /// An access token read from the external item.
    struct Login: Sendable, Equatable {
        let accessToken: String
        let expiresAt: Date?
    }

    private var logins: [String: Login] = [:]

    public init() {}

    func login(for id: String) -> Login? { logins[id] }

    func hold(_ login: Login, for id: String) { logins[id] = login }

    /// Forgets the held login: the next fetch reads the Keychain again.
    func drop(_ id: String) { logins[id] = nil }
}
