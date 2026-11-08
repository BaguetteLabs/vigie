import AgentKit
import Foundation

/// Claude Code's stored login (Story 7.3, A57): a generic password in the login keychain, service
/// `Claude Code-credentials`, account = the macOS user name, value = JSON with `claudeAiOauth.accessToken`,
/// `refreshToken`, `expiresAt` (ms since 1970), `scopes`, `subscriptionType`. Vigie reads it through
/// `SecretStore.readExternal` with the user's consent, uses `accessToken` for one request, and never writes,
/// renews or keeps it (AD-9 amended).
public enum ClaudeCodeCredential {
    /// Keychain service of the item Claude Code writes.
    public static let service = "Claude Code-credentials"

    /// The descriptor shown in the consent text. No account hint: the first item of the service is read
    /// (Claude Code writes one, under the macOS user name).
    public static let descriptor = ExternalCredentialDescriptor(
        id: "claude.claude_code_login", displayName: "Claude Code", service: service, accountHint: nil,
        explanation: L10n.resource("claude.plan.consent.explanation"))

    /// Pure: the access token in the item's JSON. Throws `.credentialMissing` when there is none (or the JSON is
    /// not the known shape), `.credentialExpired` when `expiresAt` is at or before `now`. Never logs.
    public static func accessToken(fromJSON text: String, now: Date) throws(PlanUsageError) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            let oauth = object["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw .credentialMissing }
        if let expires = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
            Date(timeIntervalSince1970: expires / 1000) <= now
        {
            throw .credentialExpired
        }
        return token
    }
}
