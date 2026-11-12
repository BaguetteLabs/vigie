import Foundation

/// One usage window, e.g. `5h` or `weekly` (SPEC §7.2).
public struct UsageWindow: Hashable, Sendable, Codable {
    /// Window name: `5h`, `weekly`, `daily`.
    public let name: String
    /// Amount used, in the unit of `limit` (or a percentage when `limit` is nil).
    public let used: Double
    public let limit: Double?
    public let resetsAt: Date?

    public init(name: String, used: Double, limit: Double?, resetsAt: Date?) {
        self.name = name
        self.used = used
        self.limit = limit
        self.resetsAt = resetsAt
    }
}

/// What a provider returns on each refresh. A failed fetch throws; the module shows it as stale, never a wrong
/// number (SPEC §7.2).
public struct UsageSnapshot: Hashable, Sendable, Codable {
    public let windows: [UsageWindow]
    public let fetchedAt: Date

    public init(windows: [UsageWindow], fetchedAt: Date) {
        self.windows = windows
        self.fetchedAt = fetchedAt
    }
}

/// An adapter's usage source for `agents.usage` (SPEC §7.2, AD-23). `id` equals the adapter id. One provider
/// serves every Account of the adapter (Story 7.10): `agents.usage` calls ``fetch(context:account:)`` once per
/// Account with plan limits on.
public protocol UsageProvider: Sendable {
    var id: AgentID { get }
    var name: LocalizedStringResource { get }
    /// How often `agents.usage` calls `fetch`.
    var refreshInterval: Duration { get }

    func fetch(context: any AdapterContext) async throws -> UsageSnapshot

    /// Another app's credential `fetch` may read through `SecretStore.readExternal` (AD-9 amended, Story 7.3),
    /// shown in the consent text by the module's Settings block. Default: nil.
    var externalCredential: ExternalCredentialDescriptor? { get }

    /// Plan windows of one Account (Story 7.10): its own settings keys (``AgentAccount/settingKey(_:)``), its
    /// own secret (``AgentAccount/secretKey(_:)``) and credential. Default: ``fetch(context:)`` for the default
    /// Account; other Accounts throw `PlanUsageError.credentialMissing`.
    func fetch(context: any AdapterContext, account: AgentAccount) async throws -> UsageSnapshot

    /// The external credential of one Account (its consent is recorded per Account, AD-9). Default:
    /// ``externalCredential`` for the default Account, nil for the others.
    func externalCredential(for account: AgentAccount) -> ExternalCredentialDescriptor?

    /// The user granted or revoked consent for the Account's external credential in Settings: forget anything
    /// the provider holds for it in memory (a held login, a refused-prompt back-off), so the next fetch reads
    /// the credential again. Default: nothing.
    func resetExternalCredential(for account: AgentAccount) async
}

extension UsageProvider {
    public var externalCredential: ExternalCredentialDescriptor? { nil }

    public func fetch(context: any AdapterContext, account: AgentAccount) async throws -> UsageSnapshot {
        guard account.isDefault else { throw PlanUsageError.credentialMissing }
        return try await fetch(context: context)
    }

    public func externalCredential(for account: AgentAccount) -> ExternalCredentialDescriptor? {
        account.isDefault ? externalCredential : nil
    }

    public func resetExternalCredential(for account: AgentAccount) async {}
}

/// Why a remote plan-limit fetch failed (Story 7.3, SPEC §14.2). `agents.usage` keeps the last good windows,
/// shows them stale and raises one setup problem; it never shows a wrong number.
public enum PlanUsageError: Error, Hashable, Sendable {
    /// Network failure or a non-success HTTP status other than 401/403 (`status` nil for transport errors).
    case unavailable(status: Int?)
    /// The endpoint refused the credential (401/403).
    case unauthorized
    /// The response is not the shape the adapter knows (the unofficial endpoint changed).
    case formatChanged
    /// The other app's stored login has expired. Vigie never renews it.
    case credentialExpired
    /// No credential: no token pasted, or the other app's login is missing or unreadable.
    case credentialMissing
    /// The user has not allowed Vigie to read the other app's login on this Mac.
    case consentRequired
    /// The user refused the Keychain prompt for the other app's login (or macOS could not show it). The provider
    /// waits before asking again; signing in or pasting a token is the fix.
    case credentialDenied
}

extension PlanUsageError {
    /// True when signing in again (or pasting a token) is the fix.
    public var needsSignIn: Bool {
        switch self {
        case .unauthorized, .credentialExpired, .credentialMissing, .consentRequired, .credentialDenied: true
        case .unavailable, .formatChanged: false
        }
    }
}
