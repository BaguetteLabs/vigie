import AgentKit
import Foundation

/// Token counts by kind.
public struct TokenCounts: Hashable, Sendable, Codable {
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
    }

    public static let zero = TokenCounts()

    public var total: Int { input + output + cacheCreation + cacheRead }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input, output: lhs.output + rhs.output,
            cacheCreation: lhs.cacheCreation + rhs.cacheCreation, cacheRead: lhs.cacheRead + rhs.cacheRead)
    }
}

/// Tokens and estimated cost for a group of records.
public struct UsageTotals: Hashable, Sendable {
    public var tokens: TokenCounts
    /// USD over the records whose model has a price (A56). An estimate, never a bill.
    public var estimatedCost: Double
    public var records: Int
    /// Records whose model has no price: not in `estimatedCost`.
    public var unpricedRecords: Int

    public init(tokens: TokenCounts = .zero, estimatedCost: Double = 0, records: Int = 0, unpricedRecords: Int = 0) {
        self.tokens = tokens
        self.estimatedCost = estimatedCost
        self.records = records
        self.unpricedRecords = unpricedRecords
    }

    public static let zero = UsageTotals()

    /// True when every record was priced.
    public var isFullyPriced: Bool { unpricedRecords == 0 }

    public static func + (lhs: UsageTotals, rhs: UsageTotals) -> UsageTotals {
        UsageTotals(
            tokens: lhs.tokens + rhs.tokens, estimatedCost: lhs.estimatedCost + rhs.estimatedCost,
            records: lhs.records + rhs.records, unpricedRecords: lhs.unpricedRecords + rhs.unpricedRecords)
    }
}

/// Time bucket of a `UsageSeries`, in the query's calendar (local time by default).
public enum UsageBucket: String, Hashable, Sendable, CaseIterable {
    case hour
    case day

    var component: Calendar.Component {
        switch self {
        case .hour: .hour
        case .day: .day
        }
    }
}

/// One bucket of a `UsageSeries`.
public struct UsageSeriesBucket: Hashable, Sendable {
    public let start: Date
    public var totals: UsageTotals
    public var byModel: [String: UsageTotals]

    public init(start: Date, totals: UsageTotals = .zero, byModel: [String: UsageTotals] = [:]) {
        self.start = start
        self.totals = totals
        self.byModel = byModel
    }
}

/// The shared usage shape every provider answers with (SPEC §7.2, AD-23): token counts and estimated cost over
/// time, per model and per project, plus optional plan windows. Read by the Usage tab (7.4) and Home (11.x).
public struct UsageSeries: Hashable, Sendable {
    /// nil = every provider.
    public let provider: AgentID?
    /// nil = every Account of `provider` (Story 7.10).
    public let account: AccountID?
    public let since: Date
    public let until: Date
    public let bucket: UsageBucket
    /// Every bucket from the one containing `since` to the one containing `until`, empty ones included.
    public var buckets: [UsageSeriesBucket]
    public var total: UsageTotals
    public var byModel: [String: UsageTotals]
    public var byProject: [String: UsageTotals]
    /// Plan windows (5h, weekly). Local logs have none; Story 7.3 adds them.
    public var windows: [UsageWindow]
    /// Totals per provider Account (Story 7.10): history and cost split by Account.
    public var byAccount: [UsageAccountKey: UsageTotals]

    public init(
        provider: AgentID?, since: Date, until: Date, bucket: UsageBucket, buckets: [UsageSeriesBucket],
        total: UsageTotals, byModel: [String: UsageTotals], byProject: [String: UsageTotals],
        windows: [UsageWindow] = [], account: AccountID? = nil, byAccount: [UsageAccountKey: UsageTotals] = [:]
    ) {
        self.provider = provider
        self.account = account
        self.byAccount = byAccount
        self.since = since
        self.until = until
        self.bucket = bucket
        self.buckets = buckets
        self.total = total
        self.byModel = byModel
        self.byProject = byProject
        self.windows = windows
    }
}

/// A provider Account: the usage identity (AD-23 amended: adapter id + Account, Story 7.10).
public struct UsageAccountKey: Hashable, Sendable, Comparable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let provider: AgentID
    public let account: AccountID

    public init(provider: AgentID, account: AccountID = .default) {
        self.provider = provider
        self.account = account
    }

    /// `"claude"` (the default Account) or `"claude.work"`, for literals in code and tests. Traps on an
    /// invalid literal: that is a programming error.
    public init(stringLiteral value: String) {
        let parts = value.split(separator: ".", maxSplits: 1).map(String.init)
        guard let first = parts.first, let provider = AgentID(first),
            let account = parts.count > 1 ? AccountID(parts[1]) : AccountID.default
        else { preconditionFailure("Invalid usage account literal: \(value)") }
        self.init(provider: provider, account: account)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.provider.rawValue, lhs.account.rawValue) < (rhs.provider.rawValue, rhs.account.rawValue)
    }

    /// `claude` for the default Account, `claude.work` for another (dedupe keys, card ids).
    public var description: String {
        account.isDefault ? provider.rawValue : "\(provider.rawValue).\(account.rawValue)"
    }
}
