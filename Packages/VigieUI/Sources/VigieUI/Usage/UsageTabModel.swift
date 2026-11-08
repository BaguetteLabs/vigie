import Foundation
import ModuleKit

/// The reset line of a usage bar: the local reset time (`16:40`, `MON 09:00`) and the time left (`1H52`,
/// `4D18`). Formatted by the module, which owns the calendar; the bar adds `RESET … · IN …`.
public struct UsageReset: Hashable, Sendable {
    public var time: String
    public var remaining: String

    public init(time: String, remaining: String) {
        self.time = time
        self.remaining = remaining
    }
}

/// The pace label at the right of a bar's pace line (UX-DR31, UX-DR78). A quota warning wins.
public enum UsagePaceLabel: Hashable, Sendable {
    /// `WITHIN PACE`, or `WITHIN PACE · +3` when usage leads the elapsed time by at least one point (within
    /// the tolerance).
    case within(lead: Int)
    /// `AHEAD OF PACE · +9`.
    case ahead(lead: Int)
    /// `WARN · ≥ 80%` with a triangle.
    case warning(threshold: Int)

    public var text: String {
        switch self {
        case .within(let lead):
            lead >= 1 ? L10n.format("usage.bar.pace.withinLead", lead) : L10n.string("usage.bar.pace.within")
        case .ahead(let lead): L10n.format("usage.bar.pace.aheadLead", lead)
        case .warning(let threshold): L10n.format("usage.bar.pace.warning", threshold)
        }
    }
}

/// One plan window on a provider card (DESIGN "Usage provider card, meter and pace bar"): value, reset line,
/// the bar with its pace marker and dashed threshold tick, and the pace line (`ELAPSED 63%` + label).
public struct UsageBarModel: Hashable, Sendable, Identifiable {
    /// How the bar is filled.
    public enum Fill: Hashable, Sendable {
        /// Within pace (or not paced): metal, 5h platinum, weekly and daily darker silver (A); C `pace-on`.
        case metal(secondary: Bool)
        /// Ahead of pace: solid `pace-ahead`.
        case ahead
        /// At or over the threshold: hatched `quota-warning`.
        case warning
    }

    /// The window: share used, `elapsedFraction` set when `pace` is on (marker and label), `isWarning`.
    public var window: QuotaDialModel.Window
    /// The provider's `warn_threshold`, in %.
    public var warnThreshold: Int
    /// The window's elapsed share (shown as `ELAPSED 63%` even with `pace` off); nil without a reset time.
    public var elapsed: Double?
    public var reset: UsageReset?

    public init(window: QuotaDialModel.Window, warnThreshold: Int, elapsed: Double?, reset: UsageReset?) {
        self.window = window
        self.warnThreshold = min(100, max(1, warnThreshold))
        self.elapsed = elapsed.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        self.reset = reset
    }

    public var id: QuotaWindowKind { window.kind }

    /// `5H`, `WEEK`, `DAY`.
    public var label: String { window.label }

    /// The pace marker position: the elapsed share while `pace` is on.
    public var markerFraction: Double? { window.elapsedFraction }

    /// The threshold tick position.
    public var thresholdFraction: Double { Double(warnThreshold) / 100 }

    public var fill: Fill {
        if window.isWarning { return .warning }
        if window.pace == .ahead { return .ahead }
        return .metal(secondary: window.kind != .fiveHour)
    }

    /// `ELAPSED 63%`, or nil without a reset time.
    public var elapsedText: String? {
        elapsed.map { L10n.format("usage.bar.elapsed", Int(($0 * 100).rounded())) }
    }

    /// The warning label always; the pace label only while the window is paced.
    public var paceLabel: UsagePaceLabel? {
        if window.isWarning { return .warning(threshold: warnThreshold) }
        guard let pace = window.pace, let elapsed = window.elapsedFraction else { return nil }
        let lead = Int((window.fraction * 100 - elapsed * 100).rounded())
        return pace == .ahead ? .ahead(lead: lead) : .within(lead: lead)
    }

    /// "5 hour window 62 percent, reset 16:40 in 1H52, elapsed 63 percent, within pace".
    public var accessibilityLabel: String {
        var parts = [L10n.format("usage.dial.a11y.window", window.kind.spokenName, window.percent)]
        if let reset { parts.append(L10n.format("usage.bar.a11y.reset", reset.time, reset.remaining)) }
        if let elapsed { parts.append(L10n.format("usage.bar.a11y.elapsed", Int((elapsed * 100).rounded()))) }
        if let paceLabel { parts.append(paceLabel.text.lowercased(with: L10n.catalogLocale)) }
        return parts.joined(separator: ", ")
    }
}

/// The meta at the right of a provider card header (UX-DR31): `MAX · WARN 80%`, `ULTRA · WEEKLY ONLY`,
/// `DAILY QUOTA ONLY`, `LOCAL LOGS ONLY`, plus `STALE · 14:02` after a failed refresh.
public struct UsageCardMeta: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The plan has a 5h window: `WARN 80%`.
        case warn(threshold: Int)
        /// No 5h window, weekly only.
        case weeklyOnly
        /// Daily quota only (Gemini CLI).
        case dailyOnly
        /// No plan windows: tokens and cost from local logs only.
        case localOnly
    }

    /// The plan's name (`MAX`), when the provider reports it. Plan endpoints do not yet.
    public var planName: String?
    public var kind: Kind
    /// `STALE · 14:02`, already formatted by the module.
    public var stale: String?

    public init(planName: String? = nil, kind: Kind, stale: String? = nil) {
        self.planName = planName
        self.kind = kind
        self.stale = stale
    }

    /// The parts in order; `highlight` is drawn brighter (the threshold value).
    public var parts: [(text: String, highlight: String?)] {
        var parts: [(String, String?)] = []
        if let planName { parts.append((planName.uppercased(with: L10n.catalogLocale), nil)) }
        switch kind {
        case .warn(let threshold):
            parts.append((L10n.string("usage.card.meta.warn"), L10n.format("usage.card.meta.percent", threshold)))
        case .weeklyOnly: parts.append((L10n.string("usage.card.meta.weeklyOnly"), nil))
        case .dailyOnly: parts.append((L10n.string("usage.card.meta.dailyOnly"), nil))
        case .localOnly: parts.append((L10n.string("usage.card.meta.localOnly"), nil))
        }
        if let stale { parts.append((stale, nil)) }
        return parts
    }

    /// The whole meta as plain text: `MAX · WARN 80%`.
    public var text: String {
        parts.map { part in part.highlight.map { "\(part.text) \($0)" } ?? part.text }
            .joined(separator: UsageTabMetrics.separator)
    }
}

/// One provider card on the Usage tab.
public struct UsageProviderCardModel: Hashable, Sendable, Identifiable {
    public enum Content: Hashable, Sendable {
        /// Before the first log read: `READING LOGS…` in place of the values (UX-DR100), never zeros.
        case readingLogs
        /// A local-logs provider (no plan windows): `NO PLAN WINDOWS`.
        case noPlanWindows
        /// The 58 px dial and one bar per window.
        case windows(dial: QuotaDialModel, bars: [UsageBarModel])
    }

    /// The card id: the provider id (`claude`) for its default Account, `claude.work` for another (Story 7.10).
    public var id: String
    /// `Claude Code`; shown uppercase.
    public var name: String
    public var meta: UsageCardMeta
    public var content: Content
    /// The provider id, the unit of `order` (drag and Move up / down move the provider with all its Accounts).
    public var providerID: String
    /// The Account label (`Work`), set only when the provider has several Accounts (UX-DR99). Sensitive.
    @Sensitive public var account: String?

    public init(
        id: String, name: String, meta: UsageCardMeta, content: Content, providerID: String? = nil,
        account: String? = nil
    ) {
        self.id = id
        self.name = name
        self.meta = meta
        self.content = content
        self.providerID = providerID ?? id
        self.account = account.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The header: `CLAUDE CODE`, or `CLAUDE CODE · WORK` with several Accounts (UX-DR99); uppercased by the
    /// card title style.
    public var title: String {
        account.map { L10n.format("usage.readout.label", name, $0) } ?? name
    }
}

extension UsageProviderCardModel: PrivacyRedactable {
    /// The Account masked in the header and the dial (`CLAUDE CODE · ••••••`).
    public func redacted() -> UsageProviderCardModel {
        var copy = self
        copy.account = $account.masked
        if case .windows(let dial, let bars) = content { copy.content = .windows(dial: dial.redacted(), bars: bars) }
        return copy
    }
}

/// What the Usage tab shows (Stories 7.7, 7.8): the provider cards in user order on the left half, the history
/// and today's cost on the right.
public struct UsageTabSnapshot: Hashable, Sendable {
    public var providers: [UsageProviderCardModel]
    /// `HISTORY · 7D` on the right half (Story 7.8).
    public var history: UsageHistoryPanel
    /// `COST · TODAY` under it (Story 7.8).
    public var cost: UsageCostPanel

    public init(
        providers: [UsageProviderCardModel], history: UsageHistoryPanel = .readingLogs,
        cost: UsageCostPanel = .readingLogs
    ) {
        self.providers = providers
        self.history = history
        self.cost = cost
    }

    /// No usage provider at all: `NO USAGE PROVIDER`, its sentence and `Open settings ⌘,` (UX-DR44).
    public var isEmpty: Bool { providers.isEmpty }

    /// More than two cards: the list scrolls, with the fade, the 3 px track and the footer (UX-DR29).
    public var overflows: Bool { providers.count > UsageTabMetrics.visibleProviders }

    /// The snapshot as Privacy mode shows it (AD-24): Account labels and project names masked; providers,
    /// windows, values and costs stay.
    public func privacy(_ privacyActive: Bool) -> UsageTabSnapshot {
        guard privacyActive else { return self }
        var copy = self
        copy.providers = providers.map { $0.redacted() }
        if case .list(let list) = cost { copy.cost = .list(list.redacted()) }
        return copy
    }

    /// Provider ids in card order, once each (the unit of `order`).
    public var providerOrder: [String] {
        var seen: Set<String> = []
        return providers.map(\.providerID).filter { seen.insert($0).inserted }
    }
}

/// Usage tab proportions from the mockup (`key-usage-tab.html`) that DESIGN states in prose, not tokens.
enum UsageTabMetrics {
    static let separator = " · "
    /// A card under a dragged provider.
    static let dropOpacity = 0.6
    /// Providers shown before the list scrolls.
    static let visibleProviders = 2
    /// `.prov`: dial column gap.
    static let dialGap: CGFloat = 12
    /// `.wins`: gap between windows.
    static let windowGap: CGFloat = 13
    /// `.win .wl`: the window label column.
    static let windowLabelWidth: CGFloat = 32
    /// `.win .wr`: the reset line is tracked .08em against the label type's .24em.
    static let resetTrackingScale: CGFloat = 1 / 3
    /// `.pb`: the bar box, its 4 px track 4 px from the top.
    static let barBoxHeight: CGFloat = 12
    static let barHeight: CGFloat = 4
    static let barTop: CGFloat = 4
    /// Gaps above the bar and the pace line.
    static let barSpacing: CGFloat = 5
    static let paceLineSpacing: CGFloat = 4
    /// `.pb .el`: 2 px marker, 1.5 px keyline in the card colour.
    static let markerWidth: CGFloat = 2
    static let markerKeyline: CGFloat = 1.5
    /// `.pb .th`: 1 px dashed tick, 10 px tall from y 1, 2 px dashes every 3.3 px.
    static let thresholdWidth: CGFloat = 1
    static let thresholdHeight: CGFloat = 10
    static let thresholdTop: CGFloat = 1
    static let thresholdDash: [CGFloat] = [2, 1.3]
    /// `.wtri`: the label triangle.
    static let triangle: CGFloat = 8
    /// `.plist.more .pscroll`: right padding beside the 3 px track.
    static let scrollInset: CGFloat = 8
    static let thumbWidth: CGFloat = 3
    /// `.phint`: footer height and gap above it.
    static let footerHeight: CGFloat = 14
    static let footerSpacing: CGFloat = 6
    /// `.big small`: gap after the big numeral.
    static let bigLabelGap: CGFloat = 6
    /// `.hist`: column gap, gap between stacked series, bar radius, top margin and the least visible bar.
    static let historyGap: CGFloat = 6
    static let historyStackGap: CGFloat = 1
    static let historyRadius: CGFloat = 1.5
    static let historyTop: CGFloat = 8
    static let historyMinimumBar: CGFloat = 1
    /// `.days`, `.lg`: axis and legend.
    static let historyAxisTop: CGFloat = 5
    static let legendTop: CGFloat = 7
    static let legendGap: CGFloat = 5
    static let legendSwatchWidth: CGFloat = 8
    static let legendSwatchHeight: CGFloat = 3
    /// `.cost`: rows and their 2 px bars.
    static let costTop: CGFloat = 4
    static let costRowGap: CGFloat = 3
    static let costBarTop: CGFloat = 2
    static let costBarHeight: CGFloat = 2
    /// Weekly / daily bars in A: the darker silver at this opacity of the history's second series.
    static let secondarySeriesOpacity = 0.85
}
