import AgentKit
import Foundation
import VigieUI

/// The right half of the Usage tab as loaded from the database (Story 7.8): each local provider's tokens per
/// day for the last seven local days, and today's usage by project. Loaded off the main actor (the store is
/// an actor) after each ingest and when the tab appears; views never touch the database.
public struct UsageOverview: Hashable, Sendable {
    public struct ProviderSeries: Hashable, Sendable {
        public var id: AgentID
        /// The Account of this series when the provider has several (history split by Account, Story 7.10);
        /// nil: all of the provider's Accounts.
        public var account: AccountID?
        /// `Claude Code`, or `Claude Code · Work`.
        public var name: String
        /// Seven day buckets, oldest first; the last one is today.
        public var series: UsageSeries

        public init(id: AgentID, account: AccountID? = nil, name: String, series: UsageSeries) {
            self.id = id
            self.account = account
            self.name = name
            self.series = series
        }

        /// The chart series id: `claude`, `claude.work`.
        var seriesID: String { account.map { UsageAccountKey(provider: id, account: $0).description } ?? id.rawValue }
    }

    /// Start of the local day the overview was loaded on.
    public var day: Date
    public var providers: [ProviderSeries]
    /// Today, every provider.
    public var today: UsageSeries
    /// Names of the Accounts of providers with several (`Claude Code · Work`), for the cost split; empty when
    /// every provider has one Account.
    public var accountNames: [UsageAccountKey: String]

    public init(
        day: Date, providers: [ProviderSeries], today: UsageSeries, accountNames: [UsageAccountKey: String] = [:]
    ) {
        self.day = day
        self.providers = providers
        self.today = today
        self.accountNames = accountNames
    }
}

extension AgentsUsageModule {
    /// Days in `HISTORY · 7D`, today included.
    nonisolated static let historyDays = 7
    /// Cost rows before the rest are summed into `N MORE`.
    nonisolated static let costRows = 3

    /// Reloads the history and today's cost (after each ingest, when the tab appears, at the day change).
    func refreshOverview() async {
        guard let history, lastIngest != nil else { return }
        let now = now()
        let calendar = calendar
        let day = calendar.startOfDay(for: now)
        let since = calendar.date(byAdding: .day, value: -(Self.historyDays - 1), to: day) ?? day
        let local = currentRegistry
        // One series per provider; per Account when the provider has several (Story 7.10).
        var wanted: [(id: AgentID, account: AccountID?, name: String)] = []
        var accountNames: [UsageAccountKey: String] = [:]
        for adapter in tabProviders where local.source(for: adapter.id) != nil {
            let name = String(localized: adapter.name)
            let all = accounts(adapter)
            guard all.count > 1 else {
                wanted.append((adapter.id, nil, name))
                continue
            }
            let short = String(localized: adapter.usageProvider?.name ?? adapter.name)
            for account in all where local.source(for: adapter.id, account: account.id) != nil {
                let label = Self.displayName(short, account: account, several: true)
                wanted.append((adapter.id, account.id, label))
                accountNames[UsageAccountKey(provider: adapter.id, account: account.id)] = label
            }
        }
        do {
            var loaded: [UsageOverview.ProviderSeries] = []
            for item in wanted {
                let series = try await history.usage(
                    since: since, until: now, bucket: .day, provider: item.id, account: item.account)
                loaded.append(
                    UsageOverview.ProviderSeries(id: item.id, account: item.account, name: item.name, series: series))
            }
            let today = try await history.today(now: now)
            overview = UsageOverview(day: day, providers: loaded, today: today, accountNames: accountNames)
        } catch {
            log?.error("Usage overview failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Reloads when the dial clock crossed into a new local day.
    func refreshOverviewIfDayChanged() {
        guard let overview, overview.day != calendar.startOfDay(for: clock) else { return }
        Task { await refreshOverview() }
    }

    /// `HISTORY · 7D`: `READING LOGS…` until the first ingest and load, `NO HISTORY YET` without a token.
    var historyPanel: UsageHistoryPanel {
        guard lastIngest != nil, let overview else { return .readingLogs }
        return Self.historyPanel(overview, calendar: calendar)
    }

    /// `COST · TODAY`: `READING LOGS…` until the first ingest and load, `—` + `NO COST DATA` without a record.
    var costPanel: UsageCostPanel {
        guard lastIngest != nil, let overview else { return .readingLogs }
        return Self.costPanel(today: overview.today, accountNames: overview.accountNames)
    }

    /// One series per provider, the last seven local days with empty days kept, weekday initials from the
    /// calendar's locale (`veryShortWeekdaySymbols`), today last.
    nonisolated static func historyPanel(_ overview: UsageOverview, calendar: Calendar) -> UsageHistoryPanel {
        let symbols = calendar.veryShortWeekdaySymbols
        let locale = calendar.locale ?? .current
        let days = (0..<historyDays).compactMap { offset -> UsageHistoryChart.Day? in
            guard let start = calendar.date(byAdding: .day, value: offset - (historyDays - 1), to: overview.day)
            else { return nil }
            let tokens = overview.providers.map { provider in
                provider.series.buckets.first { calendar.isDate($0.start, inSameDayAs: start) }?.totals.tokens.total
                    ?? 0
            }
            let weekday = calendar.component(.weekday, from: start)
            let label = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1].uppercased(with: locale) : ""
            return UsageHistoryChart.Day(start: start, label: label, isToday: offset == historyDays - 1, tokens: tokens)
        }
        let chart = UsageHistoryChart(
            series: overview.providers.map { .init(id: $0.seriesID, name: $0.name) }, days: days)
        return chart.total > 0 ? .chart(chart) : .empty
    }

    /// Estimated cost per project (the last path component of `cwd`), most expensive first, the rest past
    /// `costRows` summed into `N MORE`; the total and whether every record was priced.
    ///
    /// With `accountNames` (some provider has several Accounts), the same total split per named Account, most
    /// expensive first, for the `ACCOUNTS` switch (Story 7.10).
    nonisolated static func costPanel(today: UsageSeries, accountNames: [UsageAccountKey: String] = [:])
        -> UsageCostPanel
    {
        guard today.total.records > 0 else { return .empty }
        let sorted = today.byProject.sorted {
            ($0.value.estimatedCost, $0.value.tokens.total, $1.key) > (
                $1.value.estimatedCost, $1.value.tokens.total, $0.key
            )
        }
        let top = sorted.first?.value.estimatedCost ?? 0
        func fraction(_ cost: Double) -> Double { top > 0 ? cost / top : 0 }
        var rows = sorted.prefix(sorted.count > costRows ? costRows - 1 : costRows).map { project, totals in
            UsageCostList.Row(
                name: projectName(project), path: project, cost: totals.estimatedCost,
                fraction: fraction(totals.estimatedCost))
        }
        if sorted.count > costRows {
            let rest = sorted.dropFirst(costRows - 1)
            let cost = rest.reduce(0) { $0 + $1.value.estimatedCost }
            rows.append(
                UsageCostList.Row(
                    name: UsageText.format("agentsUsage.cost.more", rest.count), path: nil, cost: cost,
                    fraction: fraction(cost)))
        }
        var accountRows: [UsageCostList.Row] = []
        if !accountNames.isEmpty {
            let named = today.byAccount.compactMap { key, totals in
                accountNames[key].map { (key: key, name: $0, totals: totals) }
            }
            .sorted { ($0.totals.estimatedCost, $1.key) > ($1.totals.estimatedCost, $0.key) }
            let topAccount = named.first?.totals.estimatedCost ?? 0
            accountRows = named.map { item in
                UsageCostList.Row(
                    name: item.name.uppercased(with: UsageText.locale), path: nil,
                    cost: item.totals.estimatedCost,
                    fraction: topAccount > 0 ? item.totals.estimatedCost / topAccount : 0)
            }
        }
        return .list(
            UsageCostList(
                rows: rows, total: today.total.estimatedCost, isApproximate: !today.total.isFullyPriced,
                accountRows: accountRows))
    }

    /// `vigie` for `/Users/me/www/vigie`; a value that is not a path is kept as is.
    nonisolated static func projectName(_ cwd: String) -> String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? cwd : name
    }
}
