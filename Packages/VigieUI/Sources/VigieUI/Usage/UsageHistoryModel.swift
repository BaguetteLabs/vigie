import Foundation

/// `HISTORY · 7D` (Story 7.8; FR54, UX-DR31): tokens per local day for the last seven days, one series per agent
/// (stacked), weekday initials on the axis, today last.
public struct UsageHistoryChart: Hashable, Sendable {
    /// One agent's series (`Claude Code`).
    public struct Series: Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// One day: its weekday initial (`W`) and the tokens of each series, in `series` order.
    public struct Day: Hashable, Sendable, Identifiable {
        public var start: Date
        public var label: String
        public var isToday: Bool
        public var tokens: [Int]

        public init(start: Date, label: String, isToday: Bool, tokens: [Int]) {
            self.start = start
            self.label = label
            self.isToday = isToday
            self.tokens = tokens
        }

        public var id: Date { start }
        public var total: Int { tokens.reduce(0, +) }
    }

    public var series: [Series]
    public var days: [Day]

    public init(series: [Series], days: [Day]) {
        self.series = series
        self.days = days
    }

    /// Every token of the seven days.
    public var total: Int { days.reduce(0) { $0 + $1.total } }

    /// The tallest day, the chart's full height.
    public var maxDayTotal: Int { days.map(\.total).max() ?? 0 }

    /// `1.84M`.
    public var totalText: String { UsageFormat.tokens(total) }

    /// Each series' share of the tallest day on `day`, bottom first.
    public func heights(of day: Day) -> [Double] {
        let top = maxDayTotal
        guard top > 0 else { return day.tokens.map { _ in 0 } }
        return day.tokens.map { Double($0) / Double(top) }
    }
}

/// What `HISTORY · 7D` shows.
public enum UsageHistoryPanel: Hashable, Sendable {
    /// Before the first log read: `READING LOGS…` (UX-DR100).
    case readingLogs
    /// No token in the seven days: `NO HISTORY YET`.
    case empty
    case chart(UsageHistoryChart)
}

/// `COST · TODAY` (Story 7.8; FR54, UX-DR31): today's estimated cost per project (from `cwd`), most expensive
/// first, the total, and the source line `FROM LOCAL LOGS · OFFLINE`.
public struct UsageCostList: Hashable, Sendable {
    public struct Row: Hashable, Sendable, Identifiable {
        /// The project folder name (`vigie`), or `2 MORE` for the rest.
        public var name: String
        /// The full `cwd` (tooltip, VoiceOver); nil for the `MORE` row.
        public var path: String?
        public var cost: Double
        /// The bar: this row's cost against the first row's.
        public var fraction: Double

        public init(name: String, path: String?, cost: Double, fraction: Double) {
            self.name = name
            self.path = path
            self.cost = cost
            self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
        }

        public var id: String { path ?? name }
        public var costText: String { UsageFormat.cost(cost) }
    }

    public var rows: [Row]
    public var total: Double
    /// Some records have no price: the total is a floor, shown `≈ $4.12` with a footnote.
    public var isApproximate: Bool
    /// The same total split by provider Account (`CLAUDE · WORK`), when some provider has several Accounts
    /// (Story 7.10); empty otherwise. The card then offers a `PROJECTS` / `ACCOUNTS` switch.
    public var accountRows: [Row]

    public init(rows: [Row], total: Double, isApproximate: Bool, accountRows: [Row] = []) {
        self.rows = rows
        self.total = total
        self.isApproximate = isApproximate
        self.accountRows = accountRows
    }

    /// `$4.12`, or `≈ $4.12` when some records are unpriced.
    public var totalText: String {
        let amount = UsageFormat.cost(total)
        return isApproximate ? L10n.format("usage.cost.approximate", amount) : amount
    }
}

/// What `COST · TODAY` shows.
public enum UsageCostPanel: Hashable, Sendable {
    /// Before the first log read: `READING LOGS…`.
    case readingLogs
    /// No record today: `—` with `NO COST DATA` (UX-DR100).
    case empty
    case list(UsageCostList)
}

/// Number formats of the Usage tab.
public enum UsageFormat {
    /// Tokens, compact and locale-aware: `842`, `12.3K`, `1.84M`.
    public static func tokens(_ count: Int, locale: Locale = .current) -> String {
        count.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)).locale(locale))
    }

    /// An estimate in US dollars (the price table's currency), in the locale's currency style: `$4.12`.
    public static func cost(_ amount: Double, locale: Locale = .current) -> String {
        amount.formatted(.currency(code: "USD").locale(locale))
    }
}
