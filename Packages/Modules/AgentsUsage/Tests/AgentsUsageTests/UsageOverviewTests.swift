import AgentKit
import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import AgentsUsage

/// Story 7.8: history and today's cost on the Usage tab (FR54, UX-DR31, UX-DR100).
@MainActor @Suite struct UsageOverviewTests {
    /// Wednesday 2026-11-04 00:00 UTC.
    nonisolated static let wednesday = Date(timeIntervalSince1970: 1_793_750_400)
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    static func totals(_ tokens: Int, cost: Double = 0, unpriced: Int = 0) -> UsageTotals {
        UsageTotals(
            tokens: TokenCounts(input: tokens), estimatedCost: cost, records: 1 + unpriced, unpricedRecords: unpriced)
    }

    /// Seven day buckets ending today with the given tokens (nil = no bucket, as a short series would be).
    static func week(_ tokens: [Int]) -> UsageSeries {
        let start = wednesday - 6 * 86400
        let buckets = tokens.enumerated().map { index, count in
            UsageSeriesBucket(start: start + Double(index) * 86400, totals: count == 0 ? .zero : totals(count))
        }
        return UsageSeries(
            provider: nil, since: start, until: wednesday + 3600, bucket: .day, buckets: buckets,
            total: buckets.reduce(.zero) { $0 + $1.totals }, byModel: [:], byProject: [:])
    }

    static func today(_ projects: [String: UsageTotals]) -> UsageSeries {
        UsageSeries(
            provider: nil, since: wednesday, until: wednesday + 86400, bucket: .hour, buckets: [],
            total: projects.values.reduce(.zero, +), byModel: [:], byProject: projects)
    }

    @Test func historyHasSevenDaysPerProviderWithEmptyDays() throws {
        let overview = UsageOverview(
            day: Self.wednesday,
            providers: [
                .init(id: "claude", name: "Claude Code", series: Self.week([500, 0, 190, 0, 810, 690, 480])),
                .init(id: "codex", name: "Codex", series: Self.week([120, 140, 0, 50, 0, 0, 120])),
            ], today: Self.today([:]))
        guard case .chart(let chart) = AgentsUsageModule.historyPanel(overview, calendar: Self.calendar) else {
            Issue.record("no chart")
            return
        }
        #expect(chart.series.map(\.name) == ["Claude Code", "Codex"])
        #expect(chart.days.count == 7)
        #expect(chart.days.map(\.label) == ["T", "F", "S", "S", "M", "T", "W"])
        #expect(chart.days.map(\.isToday) == [false, false, false, false, false, false, true])
        #expect(chart.days[1].tokens == [0, 140])
        #expect(chart.days[3].tokens == [0, 50])
        #expect(chart.total == 3100)
        #expect(chart.totalText == UsageFormat.tokens(3100))
    }

    @Test func aProviderWithoutBucketsCountsZero() throws {
        var short = Self.week([0, 0, 0, 0, 0, 0, 0])
        short.buckets = []
        let overview = UsageOverview(
            day: Self.wednesday,
            providers: [
                .init(id: "claude", name: "Claude Code", series: Self.week([0, 0, 0, 0, 0, 0, 10])),
                .init(id: "codex", name: "Codex", series: short),
            ], today: Self.today([:]))
        guard case .chart(let chart) = AgentsUsageModule.historyPanel(overview, calendar: Self.calendar) else {
            Issue.record("no chart")
            return
        }
        #expect(chart.days.last?.tokens == [10, 0])
    }

    @Test func noTokensIsNoHistoryYet() {
        let overview = UsageOverview(
            day: Self.wednesday,
            providers: [.init(id: "claude", name: "Claude", series: Self.week([0, 0, 0, 0, 0, 0, 0]))],
            today: Self.today([:]))
        #expect(AgentsUsageModule.historyPanel(overview, calendar: Self.calendar) == .empty)
        let none = UsageOverview(day: Self.wednesday, providers: [], today: Self.today([:]))
        #expect(AgentsUsageModule.historyPanel(none, calendar: Self.calendar) == .empty)
    }

    @Test func costPerProjectSortedWithTotal() throws {
        let panel = AgentsUsageModule.costPanel(
            today: Self.today([
                "/Users/me/www/infra": Self.totals(10, cost: 1.02),
                "/Users/me/www/vigie": Self.totals(10, cost: 2.31),
                "/Users/me/blog": Self.totals(10, cost: 0.79),
            ]))
        guard case .list(let list) = panel else {
            Issue.record("no list")
            return
        }
        #expect(list.rows.map(\.name) == ["vigie", "infra", "blog"])
        #expect(list.rows.map(\.path) == ["/Users/me/www/vigie", "/Users/me/www/infra", "/Users/me/blog"])
        #expect(list.rows[0].fraction == 1)
        #expect(abs(list.rows[1].fraction - 1.02 / 2.31) < 1e-9)
        #expect(abs(list.total - 4.12) < 1e-9)
        #expect(!list.isApproximate)
    }

    @Test func extraProjectsAreSummedAndUnpricedIsFlagged() throws {
        let panel = AgentsUsageModule.costPanel(
            today: Self.today([
                "/a/one": Self.totals(10, cost: 4), "/a/two": Self.totals(10, cost: 3),
                "/a/three": Self.totals(10, cost: 2), "/a/four": Self.totals(10, cost: 1, unpriced: 2),
            ]))
        guard case .list(let list) = panel else {
            Issue.record("no list")
            return
        }
        #expect(list.rows.map(\.name) == ["one", "two", "2 MORE"])
        #expect(list.rows[2].cost == 3 && list.rows[2].path == nil)
        #expect(list.isApproximate)
        #expect(list.totalText.hasPrefix("≈ "))
    }

    @Test func noRecordTodayIsNoCostData() {
        #expect(AgentsUsageModule.costPanel(today: Self.today([:])) == .empty)
        #expect(AgentsUsageModule.projectName("/Users/me/www/vigie") == "vigie")
        #expect(AgentsUsageModule.projectName("?") == "?")
    }

    @Test func loadsAfterTheIngestFromTheDatabase() async throws {
        let sandbox = try Sandbox()
        let context = FakeModuleContext(directory: sandbox.storage)
        // Friday 2026-11-06 18:00 UTC: alpha has records on Thursday and today (a subagent), beta today.
        let now = Date(timeIntervalSince1970: 1_793_988_000)
        let module = AgentsUsageModule(
            adapters: AgentAdapters([LogAdapter(reader: sandbox.reader)]), calendar: Self.calendar, now: { now })
        #expect(module.usageTabSnapshot().history == .readingLogs)
        #expect(module.usageTabSnapshot().cost == .readingLogs)
        try await module.start(context: context)
        await module.waitForInitialIngest()
        await module.refreshOverview()
        let snapshot = module.usageTabSnapshot()
        guard case .chart(let chart) = snapshot.history, case .list(let cost) = snapshot.cost else {
            Issue.record("no data: \(snapshot.history) \(snapshot.cost)")
            await module.stop()
            return
        }
        #expect(chart.series.map(\.id) == ["claude"])
        #expect(chart.days.last?.isToday == true && chart.days.last?.label == "F")
        #expect(chart.days[5].total > 0 && chart.days[6].total > 0)
        #expect(chart.days[5].total + chart.days[6].total == chart.total)
        #expect(cost.rows.map(\.name).sorted() == ["alpha", "beta"])
        #expect(cost.rows.contains { $0.path == "/Users/me/beta" })
        await module.stop()
    }
}
