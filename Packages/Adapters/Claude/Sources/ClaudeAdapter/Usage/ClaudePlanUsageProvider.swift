import AgentKit
import Foundation
import Security

/// The remote half of the single `claude` usage provider (Story 7.3, AD-23): plan windows from the endpoint in
/// ``ClaudePlanUsageClient``, through `AdapterContext.http` only (AD-16). `agents.usage` calls it only while the
/// adapter's `usage_providers` contains `plan`, and merges the windows with the local log data.
///
/// The credential comes from `plan_auth` (local): `token` reads the pasted `plan_token` from the adapter's
/// SecretStore at each fetch; `claude_code` reads Claude Code's login through `readExternal` (consent required)
/// once and holds its access token in ``ExternalCredentialCache`` for the session (SPEC §7.2): the Keychain is
/// read again only when the held token has expired, or on the fetch after the endpoint rejected it (401/403).
/// A refused Keychain prompt throws `.credentialDenied` and the Keychain is not asked again for
/// ``denialBackoff`` (or until consent is granted again, or the next launch). Nothing is logged, written to disk
/// or renewed.
public struct ClaudePlanUsageProvider: UsageProvider {
    public static let refreshInterval: Duration = .seconds(300)
    /// How long a refused Keychain prompt keeps the provider from asking again.
    public static let denialBackoff: Duration = .seconds(3600)
    /// `readExternal` failures that mean the user (or macOS) refused the read: user cancel, authorization
    /// failed, no UI allowed.
    static let denialStatuses: Set<Int32> = [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed]

    let now: @Sendable () -> Date
    /// Expands `~` in Account locations (the credential of a non-default Account).
    let homeDirectory: URL
    /// Shared by every provider ``ClaudeAdapter/usageProvider`` returns.
    let credentials: ExternalCredentialCache

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        credentialCache: ExternalCredentialCache = ExternalCredentialCache(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.homeDirectory = homeDirectory
        self.credentials = credentialCache
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

    /// Consent granted or revoked in Settings: forget the held login and the back-off.
    public func resetExternalCredential(for account: AgentAccount) async {
        guard let descriptor = externalCredential(for: account) else { return }
        await credentials.reset(descriptor.id)
    }

    public func fetch(context: any AdapterContext) async throws -> UsageSnapshot {
        try await fetch(context: context, account: AgentAccount(id: .default, label: "", location: nil))
    }

    /// One Account: its `plan_auth` (`account.<id>.plan_auth` past the default), its pasted token
    /// (`plan_token.<id>`) or its Claude Code login.
    public func fetch(context: any AdapterContext, account: AgentAccount) async throws -> UsageSnapshot {
        let (token, held) = try await credential(context: context, account: account)
        do {
            return try await ClaudePlanUsageClient(http: context.http).fetch(token: token, now: now())
        } catch PlanUsageError.unauthorized {
            // The held login was rejected: forget it, the next fetch reads the Keychain again (not this one, so
            // a refresh reads it at most once).
            if let held { await credentials.drop(held.id) }
            throw PlanUsageError.unauthorized
        }
    }

    func credential(context: any AdapterContext) async throws(PlanUsageError) -> String {
        try await credential(context: context, account: AgentAccount(id: .default, label: "", location: nil)).token
    }

    /// The token, and the external descriptor it came from (nil for a pasted token).
    func credential(context: any AdapterContext, account: AgentAccount) async throws(PlanUsageError) -> (
        token: String, held: ExternalCredentialDescriptor?
    ) {
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
            return (token, nil)
        case .claudeCode:
            guard let descriptor = externalCredential(for: account) else { throw .credentialMissing }
            return (try await externalToken(context: context, descriptor: descriptor), descriptor)
        }
    }

    /// The held login's token while it is valid and consent still stands; else one Keychain read, held when it
    /// carries a valid token.
    func externalToken(context: any AdapterContext, descriptor: ExternalCredentialDescriptor)
        async throws(PlanUsageError) -> String
    {
        if let login = await credentials.login(for: descriptor.id) {
            if await context.secrets.hasConsent(for: descriptor),
                let token = try? ClaudeCodeCredential.accessToken(of: login, now: now())
            {
                return token
            }
            // Expired, or consent revoked: never reuse it.
            await credentials.drop(descriptor.id)
        }
        let current = now()
        if let until = await credentials.deniedUntil(descriptor.id) {
            guard current >= until else { throw .credentialDenied }
            await credentials.clearDenial(descriptor.id)
        }
        let text: String
        do {
            text = try await context.secrets.readExternal(descriptor)
        } catch SecretStoreError.consentRequired {
            throw .consentRequired
        } catch SecretStoreError.failed(let status) where Self.denialStatuses.contains(status) {
            let backoff = Double(Self.denialBackoff.components.seconds)
            await credentials.deny(descriptor.id, until: current.addingTimeInterval(backoff))
            throw .credentialDenied
        } catch {
            throw .credentialMissing
        }
        let login = try ClaudeCodeCredential.login(fromJSON: text)
        let token = try ClaudeCodeCredential.accessToken(of: login, now: current)
        await credentials.hold(login, for: descriptor.id)
        return token
    }
}
