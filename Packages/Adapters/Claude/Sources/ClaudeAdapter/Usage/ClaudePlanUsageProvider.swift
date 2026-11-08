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

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public var id: AgentID { ClaudeAdapter.agentID }
    /// "Claude": the plan, not the CLI ("Claude plan usage unavailable").
    public var name: LocalizedStringResource { L10n.resource("claude.plan.name") }
    public var refreshInterval: Duration { Self.refreshInterval }
    public var externalCredential: ExternalCredentialDescriptor? { ClaudeCodeCredential.descriptor }

    public func fetch(context: any AdapterContext) async throws -> UsageSnapshot {
        let token = try await credential(context: context)
        return try await ClaudePlanUsageClient(http: context.http).fetch(token: token, now: now())
    }

    func credential(context: any AdapterContext) async throws(PlanUsageError) -> String {
        let raw = context.settings.value(ClaudeAdapter.SettingKey.planAuth, as: String.self)
        switch ClaudeAdapter.PlanAuth(rawValue: raw ?? "") ?? .token {
        case .token:
            let token: String?
            do {
                token = try await context.secrets.read(ClaudeAdapter.SettingKey.planToken)
            } catch {
                throw .credentialMissing
            }
            guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
                throw .credentialMissing
            }
            return token
        case .claudeCode:
            let text: String
            do {
                text = try await context.secrets.readExternal(ClaudeCodeCredential.descriptor)
            } catch SecretStoreError.consentRequired {
                throw .consentRequired
            } catch {
                throw .credentialMissing
            }
            return try ClaudeCodeCredential.accessToken(fromJSON: text, now: now())
        }
    }
}
