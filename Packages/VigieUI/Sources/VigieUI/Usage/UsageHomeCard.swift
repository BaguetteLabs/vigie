import SwiftUI

/// One compact row of the Usage Home card: the provider's main window (5h, else the only window).
struct UsageHomeRowModel: Hashable, Identifiable {
    enum Value: Hashable {
        case readingLogs
        case noPlanWindows
        case window(dial: QuotaDialModel, percent: Int, reset: UsageReset?)
    }

    let id: String
    let name: String
    let value: Value
    /// `STALE · 14:02`, when the last refresh failed.
    let stale: String?
    let isWarning: Bool
    let warnThreshold: Int?

    init(_ provider: UsageProviderCardModel) {
        id = provider.id
        name = provider.name
        stale = provider.meta.stale
        switch provider.content {
        case .readingLogs:
            value = .readingLogs
            isWarning = false
            warnThreshold = nil
        case .noPlanWindows:
            value = .noPlanWindows
            isWarning = false
            warnThreshold = nil
        case .windows(let dial, let bars):
            let main = bars.first { $0.window.kind == dial.primary?.kind } ?? bars.first
            value = .window(dial: dial, percent: dial.primary?.percent ?? main?.window.percent ?? 0, reset: main?.reset)
            let warning = bars.first { $0.window.isWarning }
            isWarning = warning != nil
            warnThreshold = warning?.warnThreshold
        }
    }

    /// "Claude Code, 5 hour window 62 percent, reset 16:40 in 1H52".
    var accessibilityLabel: String {
        var parts = [name]
        switch value {
        case .readingLogs: parts.append(L10n.string("empty.usage.readingLogs.label"))
        case .noPlanWindows: parts.append(L10n.string("usage.card.noPlanWindows"))
        case .window(let dial, let percent, let reset):
            parts.append(L10n.format("usage.dial.a11y.window", dial.primary?.kind.spokenName ?? "", percent))
            if let reset { parts.append(L10n.format("usage.bar.a11y.reset", reset.time, reset.remaining)) }
        }
        if isWarning, let warnThreshold { parts.append(L10n.format("usage.bar.pace.warning", warnThreshold)) }
        if let stale { parts.append(stale) }
        return parts.joined(separator: ", ")
    }
}

/// The `agents.usage` Home card (Story 11.2, FR90, UX-DR97): a ``WidgetCard`` titled `USAGE` with the
/// `WARN · ≥ 80%` marker (UX-DR78) when any provider is in warning, else the first provider's meta; one compact row
/// per provider (24 px dial, name, main window value, `RESET 16:40 · IN 1H52`, `STALE · HH:MM`). Overflow
/// scrolls and fades under the bottom mask; the card keeps its size. No Settings button (the Home grid wraps the
/// card in a button).
public struct UsageHomeCardView: View {
    @Environment(\.vigieTheme) private var theme
    private let snapshot: @MainActor () -> UsageTabSnapshot
    /// False draws the rows in a plain stack (`ImageRenderer` draws no `ScrollView` content).
    var scrolls = true

    public init(snapshot: @escaping @MainActor () -> UsageTabSnapshot) {
        self.snapshot = snapshot
    }

    /// The rows now, for tests.
    func rowsValue() -> [UsageHomeRowModel] { snapshot().providers.map(UsageHomeRowModel.init) }

    /// The card meta now, for tests.
    func metaValue() -> String? { Self.meta(snapshot().providers.map(UsageHomeRowModel.init), snapshot().providers) }

    static func meta(_ rows: [UsageHomeRowModel], _ providers: [UsageProviderCardModel]) -> String? {
        if let threshold = rows.first(where: \.isWarning)?.warnThreshold {
            return L10n.format("usage.bar.pace.warning", threshold)
        }
        return providers.first?.meta.text
    }

    public var body: some View {
        let providers = snapshot().providers
        let rows = providers.map(UsageHomeRowModel.init)
        Group {
            if rows.isEmpty {
                WidgetCard(title: Text(L10n.resource("usage.home.title"))) {
                    EmptyStateBlock(VigieCopy.noUsageProvider)
                }
            } else {
                WidgetCard(
                    title: Text(L10n.resource("usage.home.title")),
                    meta: Self.meta(rows, providers).map { Text(verbatim: $0) }
                ) {
                    rowList {
                        VStack(spacing: 0) {
                            ForEach(rows) { UsageHomeRow(row: $0) }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                verbatim: rows.isEmpty
                    ? L10n.string("empty.usage.label")
                    : L10n.string("usage.home.title") + ", " + rows.map(\.accessibilityLabel).joined(separator: "; ")))
    }

    @ViewBuilder private func rowList(@ViewBuilder _ rows: () -> some View) -> some View {
        if scrolls {
            ScrollFadeList(showsHint: false, content: rows)
        } else {
            rows().frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

struct UsageHomeRow: View {
    @Environment(\.vigieTheme) private var theme
    let row: UsageHomeRowModel

    var body: some View {
        HStack(spacing: theme.spacing(.glyphGap)) {
            dial.frame(width: QuotaDialSize.wing.length(in: theme))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.glyphGap)) {
                    Text(verbatim: row.name)
                        .font(theme.font(.code))
                        .foregroundStyle(theme.color(.ink2))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    valueText
                }
                detail
            }
        }
        .frame(height: UsageHomeCardMetrics.rowHeight)
    }

    @ViewBuilder private var dial: some View {
        if case .window(let model, _, _) = row.value {
            QuotaDialView(model: model, size: .wing, showsName: false, showsValue: false)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private var valueText: some View {
        switch row.value {
        case .window(_, let percent, _):
            Text(verbatim: L10n.format("usage.bar.value", percent))
                .font(theme.font(.readoutValue))
                .tracking(theme.tracking(.readoutValue))
                .foregroundStyle(
                    theme.color(
                        row.isWarning
                            ? (theme.look == .light ? .quotaWarningText : .quotaWarning)
                            : (theme.defines(.structure) ? .goldText : .ink1)
                    )
                )
                .monospacedDigit()
                .lineLimit(1)
        case .readingLogs, .noPlanWindows:
            EmptyView()
        }
    }

    @ViewBuilder private var detail: some View {
        Group {
            switch row.value {
            case .readingLogs:
                Text(VigieCopy.readingLogs.label)
            case .noPlanWindows:
                Text(L10n.resource("usage.card.noPlanWindows"))
            case .window(_, _, let reset):
                if let stale = row.stale {
                    Text(verbatim: stale)
                } else if let reset {
                    Text(L10n.resource("usage.bar.reset")) + Text(verbatim: " ")
                        + Text(verbatim: reset.time).foregroundStyle(theme.color(.ink2))
                        + Text(verbatim: UsageTabMetrics.separator)
                        + Text(verbatim: L10n.format("usage.bar.in", reset.remaining))
                }
            }
        }
        .font(theme.font(.readoutLabel))
        .tracking(theme.tracking(.readoutLabel) * UsageTabMetrics.resetTrackingScale)
        .foregroundStyle(theme.color(.ink3))
        .lineLimit(1)
        .minimumScaleFactor(UsageHomeCardMetrics.detailMinScale)
    }
}

enum UsageHomeCardMetrics {
    /// Two text lines beside the 24 px dial; two and a half rows fit the 138 pt cell before the fade.
    static let rowHeight: CGFloat = 32
    static let detailMinScale: CGFloat = 0.7
}
