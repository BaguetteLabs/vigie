import AgentKit
import Foundation

/// The remote half of the single `claude` usage provider (Story 7.3, AD-23): plan windows from the endpoint in
/// ``ClaudePlanUsageClient``, through `AdapterContext.http` only (AD-16). `agents.usage` calls it only while the
/// adapter's `usage_providers` contains `plan`, and merges the windows with the local log data.
///
/// The credential comes from `plan_auth` (local): `token` reads the pasted `plan_token` from the adapter's
/// SecretStore; `claude_code` reads Claude Code's login through `readExternal` (consent required) and uses its
/// access token for this request only. Nothing is logged, stored or renewed.
public struct ClaudePlanUsageProvider: UsageProvider {
    public static let refreshInterval: Duration = .seconds(300)

    let now: @Sendable () -> Date
    /// Expands `~` in Account locations (the credential of a non-default Account).
    let homeDirectory: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.homeDirectory = homeDirectory
        self.now = now
    }

    public var id: AgentID { ClaudeAdapter.agentID }
    /// "Claude": the plan, not the CLI ("Claude plan usage unavailable").
    public var name: LocalizedStringResource { L10n.resource("claude.plan.name") }
    public var refreshInterval: Duration { Self.refreshInterval }
    public var externalCredential: ExternalCredentialDescriptor? { ClaudeCodeCredential.descriptor }

    /// The default Account's login item, or the one Claude Code keeps for the Account's `CLAUDE_CONFIG_DIR`.
    public func externalCredential(for account: AgentAccount) -> ExternalCredentialDescriptor? {
        ClaudeCodeCredential.descriptor(for: account, home: homeDirectory)
    }

    public func fetch(context: any AdapterContext) async throws -> UsageSnapshot {
        try await fetch(context: context, account: AgentAccount(id: .default, label: "", location: nil))
    }

    /// One Account: its `plan_auth` (`account.<id>.plan_auth` past the default), its pasted token
    /// (`plan_token.<id>`) or its Claude Code login.
    public func fetch(context: any AdapterContext, account: AgentAccount) async throws -> UsageSnapshot {
        let token = try await credential(context: context, account: account)
        return try await ClaudePlanUsageClient(http: context.http).fetch(token: token, now: now())
    }

    func credential(context: any AdapterContext) async throws(PlanUsageError) -> String {
        try await credential(context: context, account: AgentAccount(id: .default, label: "", location: nil))
    }

    func credential(context: any AdapterContext, account: AgentAccount) async throws(PlanUsageError) -> String {
        let raw = context.settings.value(account.settingKey(ClaudeAdapter.SettingKey.planAuth), as: String.self)
        switch ClaudeAdapter.PlanAuth(rawValue: raw ?? "") ?? .token {
        case .token:
            let token: String?
            do {
                token = try await context.secrets.read(account.secretKey(ClaudeAdapter.SettingKey.planToken))
            } catch {
                throw .credentialMissing
            }
            guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
                throw .credentialMissing
            }
            return token
        case .claudeCode:
            guard let descriptor = externalCredential(for: account) else { throw .credentialMissing }
            let text: String
            do {
                text = try await context.secrets.readExternal(descriptor)
            } catch SecretStoreError.consentRequired {
                throw .consentRequired
            } catch {
                throw .credentialMissing
            }
            return try ClaudeCodeCredential.accessToken(fromJSON: text, now: now())
        }
    }
}
