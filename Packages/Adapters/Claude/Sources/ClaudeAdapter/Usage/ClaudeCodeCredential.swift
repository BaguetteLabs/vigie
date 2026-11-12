import AgentKit
import CryptoKit
import Foundation

/// Claude Code's stored login (Story 7.3, A57): a generic password in the login keychain, service
/// `Claude Code-credentials`, account = the macOS user name, value = JSON with `claudeAiOauth.accessToken`,
/// `refreshToken`, `expiresAt` (ms since 1970), `scopes`, `subscriptionType`. Vigie reads it through
/// `SecretStore.readExternal` with the user's consent, once per launch, keeps `accessToken` and `expiresAt` in
/// process memory for the session (``ExternalCredentialCache``), and never writes it to disk, renews or logs it
/// (AD-9 amended 2026-11-12).
public enum ClaudeCodeCredential {
    /// Keychain service of the item Claude Code writes.
    public static let service = "Claude Code-credentials"

    /// The descriptor shown in the consent text. No account hint: the first item of the service is read
    /// (Claude Code writes one, under the macOS user name).
    public static let descriptor = ExternalCredentialDescriptor(
        id: "claude.claude_code_login", displayName: "Claude Code", service: service, accountHint: nil,
        explanation: L10n.resource("claude.plan.consent.explanation"))

    /// The login of one Account (Story 7.10): the default Account's is ``descriptor``; an Account bound to
    /// another `CLAUDE_CONFIG_DIR` has Claude Code's item for that folder, service
    /// `Claude Code-credentials-<first 8 hex of SHA-256(config dir)>`, and its own consent
    /// (`claude.claude_code_login.<account id>`). nil for a non-default Account without a location.
    ///
    /// The suffix follows Claude Code's own naming for a custom config folder (not documented by Anthropic;
    /// checked against no live item yet): the folder as the shell expands it, `~` resolved, no trailing slash.
    public static func descriptor(for account: AgentAccount, home: URL) -> ExternalCredentialDescriptor? {
        if account.isDefault { return descriptor }
        guard let location = account.location else { return nil }
        return ExternalCredentialDescriptor(
            id: account.credentialID(descriptor.id), displayName: descriptor.displayName,
            service: service(configDirectory: expanded(location.path, home: home)), accountHint: nil,
            explanation: descriptor.explanation)
    }

    /// `Claude Code-credentials-<8 hex>` for a custom config folder.
    public static func service(configDirectory path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(service)-\(hex.prefix(8))"
    }

    static func expanded(_ raw: String, home: URL) -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if path == "~" {
            path = home.path
        } else if path.hasPrefix("~/") {
            path = home.path + "/" + path.dropFirst(2)
        }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// Pure: the access token in the item's JSON. Throws `.credentialMissing` when there is none (or the JSON is
    /// not the known shape), `.credentialExpired` when `expiresAt` is at or before `now`. Never logs.
    public static func accessToken(fromJSON text: String, now: Date) throws(PlanUsageError) -> String {
        try accessToken(of: login(fromJSON: text), now: now)
    }

    /// Pure: `accessToken` and `expiresAt` of the item's JSON (the refresh token is not kept). Throws
    /// `.credentialMissing` when there is no access token.
    static func login(fromJSON text: String) throws(PlanUsageError) -> ExternalCredentialCache.Login {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            let oauth = object["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw .credentialMissing }
        let expires = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return ExternalCredentialCache.Login(accessToken: token, expiresAt: expires)
    }

    /// The login's token, or `.credentialExpired` when `expiresAt` is at or before `now`.
    static func accessToken(of login: ExternalCredentialCache.Login, now: Date) throws(PlanUsageError) -> String {
        if let expires = login.expiresAt, expires <= now { throw .credentialExpired }
        return login.accessToken
    }
}
