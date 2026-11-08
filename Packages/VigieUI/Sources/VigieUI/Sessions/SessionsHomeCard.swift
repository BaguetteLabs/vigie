import SwiftUI

/// The `agents.sessions` Home card (Story 11.2, FR90, UX-DR30 Home row grid, UX-DR97): a ``WidgetCard`` titled
/// `AGENTS` with the session count as meta, then the same urgency-ordered rows as the Agents tab on the compact
/// `18 | 92 | 1fr | 64` grid (glyph, agent, project, `STATUS · T+`). Content taller than the cell scrolls and
/// fades under the bottom mask; the card keeps its size. A row press is Focus and does not reach the grid's
/// "open the tab" button around the card. The empty states are the tab's, without the Settings button (a button
/// cannot nest in the card's own button).
public struct SessionsHomeCardView: View {
    @Environment(\.vigieTheme) private var theme
    private let fixedNow: Date?
    private let snapshot: @MainActor (Date) -> SessionsSnapshot
    private let onFocus: @MainActor (String) -> Void
    /// False draws the rows in a plain stack (`ImageRenderer` draws no `ScrollView` content).
    var scrolls = true

    /// - Parameters:
    ///   - now: a fixed time (tests, previews); nil ticks every second.
    ///   - snapshot: the rows (or the empty state) at a given time, as for ``SessionsTabView``.
    ///   - onFocus: Focus on a row id (the session key).
    public init(
        now: Date? = nil,
        snapshot: @escaping @MainActor (Date) -> SessionsSnapshot,
        onFocus: @escaping @MainActor (String) -> Void
    ) {
        self.fixedNow = now
        self.snapshot = snapshot
        self.onFocus = onFocus
    }

    /// A card over fixed rows.
    public init(
        rows: [SessionRowModel], emptyState: SessionsEmptyState? = nil,
        onFocus: @escaping @MainActor (String) -> Void
    ) {
        let fixed = SessionsSnapshot(rows: rows, empty: rows.isEmpty ? emptyState : nil)
        self.init(now: Date(timeIntervalSince1970: 0), snapshot: { _ in fixed }, onFocus: onFocus)
    }

    /// The snapshot at `now`, for tests.
    func snapshotValue(_ now: Date) -> SessionsSnapshot { snapshot(now) }

    public var body: some View {
        if let fixedNow {
            card(snapshot(fixedNow))
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                card(snapshot(context.date))
            }
        }
    }

    @ViewBuilder private func card(_ snapshot: SessionsSnapshot) -> some View {
        if let empty = snapshot.empty, snapshot.rows.isEmpty {
            WidgetCard(title: L10n.resource("sessions.home.title")) {
                EmptyStateBlock(empty.copy)
            }
        } else {
            WidgetCard(
                title: Text(L10n.resource("sessions.home.title")),
                meta: Text(verbatim: L10n.format("sessions.home.meta", snapshot.rows.count))
            ) {
                rowList {
                    VStack(spacing: 0) {
                        ForEach(snapshot.rows) { row in
                            SessionsHomeRow(row: row) { onFocus(row.id) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func rowList(@ViewBuilder _ rows: () -> some View) -> some View {
        if scrolls {
            ScrollFadeList(showsHint: false, content: rows)
        } else {
            rows().frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// One compact Home row: a button, so its press is Focus and the surrounding card button stays quiet.
struct SessionsHomeRow: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    let row: SessionRowModel
    let onFocus: @MainActor () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius(.row), style: .continuous)
        Button(action: onFocus) {
            HStack(spacing: theme.spacing(.glyphGap) / 2) {
                SessionGlyphView(row.glyphStatus).frame(width: SessionsHomeCardMetrics.glyph)
                Text(verbatim: row.agentName)
                    .font(theme.font(.code))
                    .foregroundStyle(theme.color(.ink2))
                    .lineLimit(1)
                    .minimumScaleFactor(SessionsHomeCardMetrics.agentMinScale)
                    .frame(maxWidth: SessionsHomeCardMetrics.agent, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                Text(verbatim: row.project)
                    .font(theme.font(.rowPrimary))
                    .foregroundStyle(theme.color(.ink1))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .sensitive()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: row.statusLabel)
                    .font(theme.font(.rowStatus))
                    .tracking(theme.tracking(.rowStatus))
                    .foregroundStyle(theme.color(row.glyphStatus.colorRole))
                    .lineLimit(1)
                    .minimumScaleFactor(SessionsHomeCardMetrics.statusMinScale)
                    .frame(width: SessionsHomeCardMetrics.status, alignment: .trailing)
            }
            .frame(height: SessionsHomeCardMetrics.rowHeight)
            .background { SessionAlertTint(status: row.glyphStatus, isAlert: row.isAlert) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(Text(verbatim: row.privacy(privacyActive).accessibilityLabel))
    }
}

/// The Home row grid `18 | 92 | 1fr | 64` (DESIGN "Home cards", UX-DR30). DESIGN gives these in prose only (no
/// `components.*` token), so they live here. The 222pt card leaves 196pt inside its padding, so `92` is the
/// agent column's maximum (small mono face, usually narrower) and the project keeps the rest.
enum SessionsHomeCardMetrics {
    static let glyph: CGFloat = 18
    static let agent: CGFloat = 92
    static let status: CGFloat = 64
    /// Compact row: four rows plus the header fit the 138pt cell before the fade.
    static let rowHeight: CGFloat = 22
    /// `BLOCKED · 12M` is wider than 64pt in the status face; it shrinks rather than truncates.
    static let statusMinScale: CGFloat = 0.5
    static let agentMinScale: CGFloat = 0.7
}
