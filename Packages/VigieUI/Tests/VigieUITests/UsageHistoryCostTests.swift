import Foundation
import SwiftUI
import Testing

@testable import VigieUI

/// Story 7.8: `HISTORY · 7D` and `COST · TODAY` (FR54, UX-DR31, UX-DR100).
@MainActor @Suite struct UsageHistoryCostTests {
    static let en = Locale(identifier: "en_US")
    static let monday = Date(timeIntervalSince1970: 1_793_664_000)  // 2026-11-02 00:00 UTC

    static func chart(_ tokens: [[Int]]) -> UsageHistoryChart {
        let labels = ["M", "T", "W", "T", "F", "S", "S"]
        return UsageHistoryChart(
            series: [.init(id: "claude", name: "Claude Code"), .init(id: "codex", name: "Codex")],
            days: tokens.enumerated().map { index, values in
                .init(
                    start: monday + Double(index) * 86400, label: labels[index], isToday: index == tokens.count - 1,
                    tokens: values)
            })
    }

    static let week = chart([
        [500_000, 120_000], [710_000, 140_000], [190_000, 0], [290_000, 50_000], [810_000, 170_000],
        [690_000, 120_000], [480_000, 120_000],
    ])
    static let cost = UsageCostList(
        rows: [
            .init(name: "vigie", path: "/Users/me/www/vigie", cost: 2.31, fraction: 1),
            .init(name: "infra", path: "/Users/me/www/infra", cost: 1.02, fraction: 0.44),
            .init(name: "blog", path: "/Users/me/blog", cost: 0.79, fraction: 0.34),
        ], total: 4.12, isApproximate: false)

    @Test func compactTokens() {
        #expect(UsageFormat.tokens(842, locale: Self.en) == "842")
        #expect(UsageFormat.tokens(12_340, locale: Self.en) == "12.3K")
        #expect(UsageFormat.tokens(1_843_000, locale: Self.en) == "1.84M")
        #expect(UsageFormat.tokens(1_200_000, locale: Self.en) == "1.2M")
        #expect(UsageFormat.tokens(0, locale: Self.en) == "0")
    }

    @Test func dollarsInTheLocaleStyle() {
        #expect(UsageFormat.cost(4.12, locale: Self.en) == "$4.12")
        #expect(UsageFormat.cost(4.12, locale: Locale(identifier: "fr_FR")).contains("4,12"))
    }

    @Test func chartScalesToTheTallestDay() {
        let chart = Self.week
        #expect(chart.total == 4_390_000)
        #expect(chart.maxDayTotal == 980_000)
        let expected: [Double] = [810_000.0 / 980_000.0, 170_000.0 / 980_000.0]
        #expect(chart.heights(of: chart.days[4]) == expected)
        #expect(chart.days.last?.isToday == true)
        let empty = Self.chart([[0, 0]])
        #expect(empty.heights(of: empty.days[0]) == [0, 0])
    }

    @Test func costTotalIsApproximateWhenSomeRecordsAreUnpriced() {
        #expect(Self.cost.totalText == UsageFormat.cost(4.12))
        var partial = Self.cost
        partial.isApproximate = true
        #expect(partial.totalText == "≈ \(UsageFormat.cost(4.12))")
        #expect(Self.cost.rows[0].costText == UsageFormat.cost(2.31))
        #expect(UsageCostList.Row(name: "x", path: nil, cost: 1, fraction: .nan).fraction == 0)
    }

    @Test func copy() {
        for (key, value) in [
            "usage.history.meta": "TOKENS", "usage.history.allAgents": "ALL AGENTS", "usage.cost.meta": "ESTIMATE",
            "usage.cost.apiRate": "API RATE", "usage.cost.none": "—", "usage.cost.source": "FROM LOCAL LOGS · OFFLINE",
        ] {
            #expect(L10n.string(key) == value, "\(key)")
        }
        #expect(String(localized: VigieCopy.noHistoryYet.label) == "NO HISTORY YET")
        #expect(String(localized: VigieCopy.noCostData.label) == "NO COST DATA")
    }

    /// The main state with history and cost, and both empty states, in A dark, A light and C dark.
    @Test(arguments: [
        (Look.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID),
        (.dark, "twin-metal-tactical"),
    ])
    func rendersTheRightHalf(look: Look, variant: String) throws {
        let theme = SessionsTabTests.theme(look, variant: variant)
        let suffix = "\(variant)-\(look.rawValue)"
        var partial = Self.cost
        partial.isApproximate = true
        let states: [(String, UsageTabSnapshot)] = [
            (
                "history",
                UsageTabSnapshot(
                    providers: [UsageTabTests.claude, UsageTabTests.codex], history: .chart(Self.week),
                    cost: .list(Self.cost))
            ),
            (
                "history-partial",
                UsageTabSnapshot(
                    providers: [UsageTabTests.claude],
                    history: .chart(Self.chart([[0], [0], [0], [0], [0], [0], [42]])),
                    cost: .list(partial))
            ),
            ("history-empty", UsageTabSnapshot(providers: [UsageTabTests.claude], history: .empty, cost: .empty)),
        ]
        for (name, snapshot) in states {
            var tab = UsageTabView(snapshot: { snapshot })
            tab.scrolls = false
            let image = try SessionsTabTests.render(tab, theme: theme, name: "usage-\(name)-\(suffix)")
            #expect(SessionGlyphTests.inkedPixels(image) > 3000, "\(name) \(suffix)")
        }
    }
}
