import AgentKit
import Foundation

/// One local usage source: one Account's log reader of an adapter, keyed by the provider id (= adapter id,
/// AD-23) and the Account (Story 7.10).
public struct UsageSource: Sendable {
    public let id: AgentID
    public let account: AccountID
    public let reader: any AgentLogReader

    public init(id: AgentID, account: AccountID = .default, reader: any AgentLogReader) {
        self.id = id
        self.account = account
        self.reader = reader
    }
}

/// The usage providers `agents.usage` ingests, by provider id (AD-23: one provider per adapter, `id` = adapter
/// id) and Account. Built from the same `AgentAdapters` value as `agents.sessions`. An Account takes part when
/// its adapter has a log reader for its location and its `usage_providers` (the default Account's
/// `[modules."agents.sessions".adapter.<id>] usage_providers`, another's `account.<id>.usage_providers`, read
/// through the adapter's read-only settings view) includes `local`; an unset setting means the default, `local`
/// on.
public struct UsageProviderRegistry: Sendable {
    /// Setting key at `[modules."agents.sessions".adapter.<id>]` (SPEC §11).
    public static let usageProvidersKey = "usage_providers"
    /// The `usage_providers` entry for tokens and cost from local logs.
    public static let localSource = "local"

    public let sources: [UsageSource]

    public init(sources: [UsageSource]) {
        self.sources = sources
    }

    public init(adapters: AgentAdapters, settings: (any AgentAdapter) -> any ReadOnlySettings) {
        self.init(
            sources: adapters.adapters.flatMap { adapter -> [UsageSource] in
                let view = settings(adapter)
                return adapter.accounts(settings: view).compactMap { account in
                    guard let reader = adapter.logReader(for: account) else { return nil }
                    let enabled = view.value(account.settingKey(Self.usageProvidersKey), as: [String].self)
                    guard enabled?.contains(Self.localSource) ?? true else { return nil }
                    return UsageSource(id: adapter.id, account: account.id, reader: reader)
                }
            })
    }

    /// Provider ids with at least one source, in registration order, once.
    public var ids: [AgentID] {
        var seen: Set<AgentID> = []
        return sources.map(\.id).filter { seen.insert($0).inserted }
    }

    /// The first source of `id` (any Account).
    public func source(for id: AgentID) -> UsageSource? {
        sources.first { $0.id == id }
    }

    /// The source of one Account.
    public func source(for id: AgentID, account: AccountID) -> UsageSource? {
        sources.first { $0.id == id && $0.account == account }
    }
}
