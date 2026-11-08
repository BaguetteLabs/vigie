import AgentKit
import Foundation

/// One local usage source: an adapter's `logReader`, keyed by the provider id (= adapter id, AD-23).
public struct UsageSource: Sendable {
    public let id: AgentID
    public let reader: any AgentLogReader

    public init(id: AgentID, reader: any AgentLogReader) {
        self.id = id
        self.reader = reader
    }
}

/// The usage providers `agents.usage` ingests, by provider id (AD-23: one provider per adapter, `id` = adapter
/// id). Built from the same `AgentAdapters` value as `agents.sessions`. An adapter takes part when it has a
/// `logReader` and its `usage_providers` setting (`[modules."agents.sessions".adapters.<id>]`, read through the
/// adapter's read-only settings view) includes `local`; an unset setting means the default, `local` on.
public struct UsageProviderRegistry: Sendable {
    /// Setting key at `[modules."agents.sessions".adapters.<id>]` (SPEC §11).
    public static let usageProvidersKey = "usage_providers"
    /// The `usage_providers` entry for tokens and cost from local logs.
    public static let localSource = "local"

    public let sources: [UsageSource]

    public init(sources: [UsageSource]) {
        self.sources = sources
    }

    public init(adapters: AgentAdapters, settings: (any AgentAdapter) -> any ReadOnlySettings) {
        self.init(
            sources: adapters.adapters.compactMap { adapter in
                guard let reader = adapter.logReader else { return nil }
                let enabled = settings(adapter).value(Self.usageProvidersKey, as: [String].self)
                guard enabled?.contains(Self.localSource) ?? true else { return nil }
                return UsageSource(id: adapter.id, reader: reader)
            })
    }

    public var ids: [AgentID] { sources.map(\.id) }

    public func source(for id: AgentID) -> UsageSource? {
        sources.first { $0.id == id }
    }
}
