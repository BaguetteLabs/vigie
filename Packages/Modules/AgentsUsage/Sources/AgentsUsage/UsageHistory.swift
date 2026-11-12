import AgentKit
import Foundation

/// The query side of the usage history (Stories 7.4, 11.x read it): tokens and estimated cost over time, per
/// model and per project, in the shared `UsageSeries` shape.
public struct UsageHistory: Sendable {
    public let store: UsageStore
    public let estimator: CostEstimator
    public let calendar: Calendar

    public init(store: UsageStore, estimator: CostEstimator, calendar: Calendar = .current) {
        self.store = store
        self.estimator = estimator
        self.calendar = calendar
    }

    /// Usage in `[since, until)` by `bucket` (empty buckets included), for one provider or all (nil), one of its
    /// Accounts or all (nil).
    public func usage(
        since: Date, until: Date, bucket: UsageBucket, provider: AgentID? = nil, account: AccountID? = nil
    ) async throws -> UsageSeries {
        let rows = try await store.aggregates(since: since, until: until, provider: provider, account: account)
        var starts: [Date] = []
        if let first = calendar.dateInterval(of: bucket.component, for: since)?.start {
            var start = first
            while start < until {
                starts.append(start)
                guard let next = calendar.date(byAdding: bucket.component, value: 1, to: start), next > start
                else { break }
                start = next
            }
        }
        var buckets = starts.map { UsageSeriesBucket(start: $0) }
        var total = UsageTotals.zero
        var byModel: [String: UsageTotals] = [:]
        var byProject: [String: UsageTotals] = [:]
        var byAccount: [UsageAccountKey: UsageTotals] = [:]
        for row in rows {
            let cost = estimator.cost(of: row.tokens, model: row.model, provider: row.provider)
            let totals = UsageTotals(
                tokens: row.tokens, estimatedCost: cost ?? 0, records: row.records,
                unpricedRecords: cost == nil ? row.records : 0)
            total = total + totals
            byModel[row.model, default: .zero] = byModel[row.model, default: .zero] + totals
            byProject[row.project, default: .zero] = byProject[row.project, default: .zero] + totals
            let key = UsageAccountKey(provider: row.provider, account: row.account)
            byAccount[key, default: .zero] = byAccount[key, default: .zero] + totals
            // Last bucket whose start is at or before the slot.
            if let index = buckets.lastIndex(where: { $0.start <= row.slotStart }) ?? buckets.indices.first {
                buckets[index].totals = buckets[index].totals + totals
                buckets[index].byModel[row.model, default: .zero] =
                    buckets[index].byModel[row.model, default: .zero] + totals
            }
        }
        return UsageSeries(
            provider: provider, since: since, until: until, bucket: bucket, buckets: buckets, total: total,
            byModel: byModel, byProject: byProject, windows: [], account: account, byAccount: byAccount)
    }

    /// Today so far (local calendar day of `now`), by hour.
    public func today(now: Date = Date(), provider: AgentID? = nil, account: AccountID? = nil) async throws
        -> UsageSeries
    {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        return try await usage(since: start, until: end, bucket: .hour, provider: provider, account: account)
    }
}
