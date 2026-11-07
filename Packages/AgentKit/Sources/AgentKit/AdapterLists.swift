import Foundation

/// The agent adapters App assembly builds once and hands to `agents.sessions` and `agents.usage` (AD-4). Both
/// modules receive this same value, so they always agree on the adapter list.
public struct AgentAdapters: Sendable {
    public let adapters: [any AgentAdapter]

    /// Ids must be unique: a duplicate is a programming error in assembly.
    public init(_ adapters: [any AgentAdapter]) {
        precondition(Set(adapters.map(\.id)).count == adapters.count, "Duplicate agent adapter id")
        self.adapters = adapters
    }

    public var ids: [AgentID] { adapters.map(\.id) }

    public func adapter(for id: AgentID) -> (any AgentAdapter)? {
        adapters.first { $0.id == id }
    }
}

/// The terminal adapters App assembly builds once (AD-4).
public struct TerminalAdapters: Sendable {
    public let adapters: [any TerminalAdapter]
    /// Used when no adapter matches a session's env (SPEC §7.1.1 fallback): activates the terminal app without
    /// selecting a tab (A16). App assembly passes the generic adapter; modules never import a Terminals package
    /// (AD-1).
    public let fallback: (any TerminalAdapter)?

    /// Ids must be unique: a duplicate is a programming error in assembly.
    public init(_ adapters: [any TerminalAdapter], fallback: (any TerminalAdapter)? = nil) {
        precondition(Set(adapters.map(\.id)).count == adapters.count, "Duplicate terminal adapter id")
        self.adapters = adapters
        self.fallback = fallback
    }

    public var ids: [TerminalID] { adapters.map(\.id) }

    public func adapter(for id: TerminalID) -> (any TerminalAdapter)? {
        adapters.first { $0.id == id }
    }

    /// The first adapter whose `matches(env:)` accepts `env` (AD-23), in assembly order.
    public func matching(env: [String: String]) -> (any TerminalAdapter)? {
        adapters.first { $0.matches(env: env) }
    }

    /// The adapter that focuses a session with this env: the first match, else ``fallback``.
    public func resolve(env: [String: String]) -> (any TerminalAdapter)? {
        matching(env: env) ?? fallback
    }
}
