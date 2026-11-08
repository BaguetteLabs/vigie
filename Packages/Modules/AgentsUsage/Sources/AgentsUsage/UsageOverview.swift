import AgentKit
import Foundation
import VigieUI

/// The right half of the Usage tab as loaded from the database (Story 7.8): each local provider's tokens per
/// day for the last seven local days, and today's usage by project. Loaded off the main actor (the store is
/// an actor) after each ingest and when the tab appears; views never touch the database.
public struct UsageOverview: Hashable, Sendable {
    public struct ProviderSeries: Hashable, Sendable {
        public var id: AgentID
        public var name: String
        /// Seven day buckets, oldest first; the last one is today.
        public var series: UsageSeries

        public init(id: AgentID, name: String, series: UsageSeries) {
            self.id = id
            self.name = name
            self.series = series
        }
    }

    /// Start of the local day the overview was loaded on.
    public var day: Date
    public var providers: [ProviderSeries]
    /// Today, every provider.
    public var today: UsageSeries

    public init(day: Date, providers: [ProviderSeries], today: UsageSeries) {
        self.day = day
        self.providers = providers
        self.today = today
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
        let local = registry?.ids ?? []
        let providers = tabProviders.filter { local.contains($0.id) }.map { ($0.id, String(localized: $0.name)) }
        do {
            var loaded: [UsageOverview.ProviderSeries] = []
            for (id, name) in providers {
                let series = try await history.usage(since: since, until: now, bucket: .day, provider: id)
                loaded.append(UsageOverview.ProviderSeries(id: id, name: name, series: series))
            }
            let today = try await history.today(now: now)
            overview = UsageOverview(day: day, providers: loaded, today: today)
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
        return Self.costPanel(today: overview.today)
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
            series: overview.providers.map { .init(id: $0.id.rawValue, name: $0.name) }, days: days)
        return chart.total > 0 ? .chart(chart) : .empty
    }

    /// Estimated cost per project (the last path component of `cwd`), most expensive first, the rest past
    /// `costRows` summed into `N MORE`; the total and whether every record was priced.
    nonisolated static func costPanel(today: UsageSeries) -> UsageCostPanel {
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
        return .list(
            UsageCostList(rows: rows, total: today.total.estimatedCost, isApproximate: !today.total.isFullyPriced))
    }

    /// `vigie` for `/Users/me/www/vigie`; a value that is not a path is kept as is.
    nonisolated static func projectName(_ cwd: String) -> String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? cwd : name
    }
}
