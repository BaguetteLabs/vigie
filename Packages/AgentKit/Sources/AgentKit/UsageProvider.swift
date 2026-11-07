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

/// An adapter's usage source for `agents.usage` (SPEC §7.2, AD-23). `id` equals the adapter id. Multiple
/// Accounts are added with Epic 7.
public protocol UsageProvider: Sendable {
    var id: AgentID { get }
    var name: LocalizedStringResource { get }
    /// How often `agents.usage` calls `fetch`.
    var refreshInterval: Duration { get }

    func fetch(context: any AdapterContext) async throws -> UsageSnapshot
}
