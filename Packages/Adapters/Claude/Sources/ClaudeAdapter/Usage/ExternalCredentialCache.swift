import Foundation

/// The external logins `ClaudePlanUsageProvider` holds in process memory for the session (SPEC §7.2, AD-9 amended
/// 2026-11-12), keyed by `ExternalCredentialDescriptor.id`: the Keychain is read once per launch (so macOS shows
/// its prompt at most once), then again only when the held token has expired or the endpoint rejected it.
///
/// It also remembers a refused Keychain prompt until a time, so the provider does not ask again at each refresh.
/// Only the access token and its expiry are kept, never the refresh token; nothing is written to disk, renewed or
/// logged. One instance lives in ``ClaudeAdapter`` for the life of the process: relaunching forgets everything.
public actor ExternalCredentialCache {
    /// An access token read from the external item.
    struct Login: Sendable, Equatable {
        let accessToken: String
        let expiresAt: Date?
    }

    private var logins: [String: Login] = [:]
    /// Descriptor id → the time before which the Keychain is not asked again.
    private var denials: [String: Date] = [:]

    public init() {}

    func login(for id: String) -> Login? { logins[id] }

    func hold(_ login: Login, for id: String) { logins[id] = login }

    /// Forgets the held login: the next fetch reads the Keychain again.
    func drop(_ id: String) { logins[id] = nil }

    func deniedUntil(_ id: String) -> Date? { denials[id] }

    func deny(_ id: String, until: Date) {
        logins[id] = nil
        denials[id] = until
    }

    func clearDenial(_ id: String) { denials[id] = nil }

    /// Forgets the held login and the back-off (consent granted or revoked in Settings).
    func reset(_ id: String) {
        logins[id] = nil
        denials[id] = nil
    }
}
