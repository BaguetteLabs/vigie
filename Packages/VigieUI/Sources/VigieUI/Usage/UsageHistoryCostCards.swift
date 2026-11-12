import SwiftUI

/// `HISTORY · 7D` (mockup `.hist`): the seven-day total in the big numeral with `ALL AGENTS`, stacked day bars
/// (first series at the bottom in the primary metal, the next in the darker silver; today outlined, C gold),
/// weekday initials (today in `ink-1`) and the legend.
struct UsageHistoryCard: View {
    @Environment(\.vigieTheme) private var theme
    let panel: UsageHistoryPanel

    var body: some View {
        WidgetCard(title: Text(L10n.resource("usage.history.title")), meta: Text(L10n.resource("usage.history.meta"))) {
            switch panel {
            case .readingLogs: UsagePanelLabel(label: VigieCopy.readingLogs.label)
            case .empty: UsagePanelLabel(label: VigieCopy.noHistoryYet.label)
            case .chart(let chart): content(chart)
            }
        }
    }

    private func content(_ chart: UsageHistoryChart) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            UsageBigValue(value: chart.totalText, label: Text(L10n.resource("usage.history.allAgents")))
            HStack(alignment: .bottom, spacing: UsageTabMetrics.historyGap) {
                ForEach(chart.days) { day in
                    column(day, heights: chart.heights(of: day))
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.top, UsageTabMetrics.historyTop)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: accessibilityLabel(chart)))
            HStack(spacing: UsageTabMetrics.historyGap) {
                ForEach(chart.days) { day in
                    Text(verbatim: day.label)
                        .foregroundStyle(theme.color(day.isToday ? .ink1 : .ink3))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, UsageTabMetrics.historyAxisTop)
            .accessibilityHidden(true)
            HStack(spacing: theme.spacing(.rowGap)) {
                ForEach(Array(chart.series.enumerated()), id: \.element.id) { index, series in
                    HStack(spacing: UsageTabMetrics.legendGap) {
                        RoundedRectangle(cornerRadius: UsageTabMetrics.legendSwatchHeight / 2)
                            .fill(UsageFills.series(theme, index: index))
                            .frame(width: UsageTabMetrics.legendSwatchWidth, height: UsageTabMetrics.legendSwatchHeight)
                        Text(verbatim: series.name.uppercased(with: L10n.catalogLocale))
                    }
                }
            }
            .padding(.top, UsageTabMetrics.legendTop)
            .accessibilityHidden(true)
        }
        .font(theme.font(.readoutLabel))
        .tracking(theme.tracking(.readoutLabel))
        .foregroundStyle(theme.color(.ink3))
        .lineLimit(1)
    }

    private func column(_ day: UsageHistoryChart.Day, heights: [Double]) -> some View {
        GeometryReader { proxy in
            VStack(spacing: UsageTabMetrics.historyStackGap) {
                Spacer(minLength: 0)
                // The first series sits at the bottom.
                ForEach(Array(heights.enumerated().reversed()), id: \.offset) { index, height in
                    if height > 0 {
                        segment(index: index, isToday: day.isToday)
                            .frame(height: max(UsageTabMetrics.historyMinimumBar, proxy.size.height * height))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func segment(index: Int, isToday: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: UsageTabMetrics.historyRadius)
        if isToday && index == 0 && theme.defines(.structure) {
            shape.fill(theme.color(.gold))
        } else {
            shape.fill(UsageFills.series(theme, index: index))
                .overlay {
                    if isToday && index == 0 {
                        shape.strokeBorder(theme.color(.ink1), lineWidth: theme.a11y.hairlineWidth)
                    }
                }
        }
    }

    /// "Tokens, last 7 days: 1.84M. Wednesday 420K, …".
    private func accessibilityLabel(_ chart: UsageHistoryChart) -> String {
        let days = chart.days.map { day in
            L10n.format(
                "usage.history.a11y.day", day.start.formatted(.dateTime.weekday(.wide)), UsageFormat.tokens(day.total))
        }
        return ([L10n.format("usage.history.a11y.total", chart.totalText)] + days).joined(separator: ", ")
    }
}

/// `COST · TODAY` (mockup `.cost`): the total in the big numeral with `API RATE`, one row per project (name,
/// amount, a 2 px bar against the first), and `FROM LOCAL LOGS · OFFLINE` with the price line under it
/// (`PRICES <date> · BUNDLED` / `UPDATED`, Story 6.5). No record today: `—` and `NO COST DATA`.
struct UsageCostCard: View {
    @Environment(\.vigieTheme) private var theme
    let panel: UsageCostPanel
    /// The price table line; nil hides it.
    var prices: String?
    /// `ACCOUNTS` selected in the split switch (only offered when the list has Account rows).
    @State var byAccount = false

    var body: some View {
        WidgetCard(title: Text(L10n.resource("usage.cost.title")), meta: Text(L10n.resource("usage.cost.meta"))) {
            switch panel {
            case .readingLogs:
                UsagePanelLabel(label: VigieCopy.readingLogs.label)
            case .empty:
                VStack(alignment: .leading, spacing: 0) {
                    UsageBigValue(value: L10n.string("usage.cost.none"), label: Text(VigieCopy.noCostData.label))
                    Spacer(minLength: 0)
                    source
                }
            case .list(let list):
                content(list)
            }
        }
    }

    private func content(_ list: UsageCostList) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            UsageBigValue(
                value: list.totalText,
                label: Text(L10n.resource(list.isApproximate ? "usage.cost.apiRate.partial" : "usage.cost.apiRate")))
            if !list.accountRows.isEmpty { splitSwitch }
            VStack(spacing: UsageTabMetrics.costRowGap) {
                ForEach(byAccount && !list.accountRows.isEmpty ? list.accountRows : list.rows) { row in
                    VStack(spacing: UsageTabMetrics.costBarTop) {
                        HStack(spacing: theme.spacing(.actionGap)) {
                            Text(verbatim: row.name)
                                .font(theme.font(.body))
                                .foregroundStyle(theme.color(.ink1))
                                .truncationMode(.middle)
                                .sensitive()
                            Spacer(minLength: theme.spacing(.glyphGap))
                            Text(verbatim: row.costText)
                                .font(theme.font(.body))
                                .monospacedDigit()
                                .foregroundStyle(theme.color(.ink2))
                        }
                        .lineLimit(1)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(theme.trackColor())
                                Capsule().fill(UsageFills.metal(theme, secondary: false))
                                    .frame(width: proxy.size.width * row.fraction)
                            }
                        }
                        .frame(height: UsageTabMetrics.costBarHeight)
                    }
                    .help(row.path ?? row.name)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(row.path ?? row.name), \(row.costText)"))
                }
            }
            .padding(.top, UsageTabMetrics.costTop)
            Spacer(minLength: 0)
            source
        }
    }

    /// `PROJECTS · ACCOUNTS`: the selected one in `ink-1`, the other in `ink-3` (Story 7.10).
    private var splitSwitch: some View {
        HStack(spacing: theme.spacing(.glyphGap)) {
            splitButton(L10n.resource("usage.cost.split.projects"), selected: !byAccount) { byAccount = false }
            Text(verbatim: UsageTabMetrics.separator.trimmingCharacters(in: .whitespaces))
            splitButton(L10n.resource("usage.cost.split.accounts"), selected: byAccount) { byAccount = true }
        }
        .font(theme.font(.readoutLabel))
        .tracking(theme.tracking(.readoutLabel))
        .foregroundStyle(theme.color(.ink3))
        .lineLimit(1)
        .padding(.top, UsageTabMetrics.costTop)
    }

    private func splitButton(
        _ label: LocalizedStringResource, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label).foregroundStyle(theme.color(selected ? .ink1 : .ink3))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.resource("usage.cost.source"))
            if let prices {
                Text(verbatim: prices)
            }
        }
        .font(theme.font(.readoutLabel))
        .tracking(theme.tracking(.readoutLabel))
        .foregroundStyle(theme.color(.ink3))
        .lineLimit(1)
    }
}

/// The big numeral of the right-half cards (`.big`, 26 px) with its small label (`ALL AGENTS`, `API RATE`).
struct UsageBigValue: View {
    @Environment(\.vigieTheme) private var theme
    let value: String
    let label: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: UsageTabMetrics.bigLabelGap) {
            Text(verbatim: value)
                .font(theme.font(.timeValue))
                .tracking(theme.tracking(.timeValue))
                .monospacedDigit()
                .foregroundStyle(theme.color(theme.defines(.structure) ? .goldText : .ink1))
            label
                .font(theme.font(.readoutLabel))
                .tracking(theme.tracking(.readoutLabel))
                .foregroundStyle(theme.color(.ink3))
        }
        .lineLimit(1)
    }
}

/// A centred status label in a right-half card (`READING LOGS…`, `NO HISTORY YET`).
struct UsagePanelLabel: View {
    @Environment(\.vigieTheme) private var theme
    let label: LocalizedStringResource

    var body: some View {
        Text(label)
            .font(theme.font(.cardTitle))
            .tracking(theme.tracking(.cardTitle))
            .foregroundStyle(theme.color(.ink3))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension UsageFills {
    /// History series: the primary metal, then the darker silver at 85 %, then `ink-3`.
    static func series(_ theme: Theme, index: Int) -> AnyShapeStyle {
        switch index {
        case 0: metal(theme, secondary: false)
        case 1: AnyShapeStyle(metal(theme, secondary: true).opacity(UsageTabMetrics.secondarySeriesOpacity))
        default: AnyShapeStyle(theme.color(.ink3))
        }
    }
}
