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

    /// Ids must be unique: a duplicate is a programming error in assembly.
    public init(_ adapters: [any TerminalAdapter]) {
        precondition(Set(adapters.map(\.id)).count == adapters.count, "Duplicate terminal adapter id")
        self.adapters = adapters
    }

    public var ids: [TerminalID] { adapters.map(\.id) }

    public func adapter(for id: TerminalID) -> (any TerminalAdapter)? {
        adapters.first { $0.id == id }
    }

    /// The first adapter whose `matches(env:)` accepts `env` (AD-23), in assembly order.
    public func matching(env: [String: String]) -> (any TerminalAdapter)? {
        adapters.first { $0.matches(env: env) }
    }
}
