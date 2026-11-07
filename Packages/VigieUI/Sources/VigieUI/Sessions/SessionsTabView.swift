import SwiftUI

/// The Agents tab (DESIGN "Session row", "Widget card"; EXPERIENCE "Session row"; FR39, FR92; mockup
/// `key-agents-tab.html`): one full-width card titled `SESSIONS · N · M ALERTS` with the keyboard hints and
/// `SORTED BY URGENCY`, column headers, then the urgency-sorted rows in a scroll-fade list.
///
/// The only action is Focus: a click anywhere on a row, or `↵` on the keyboard selection (`↑↓`). A selected
/// failed row whose process ended also offers `DISMISS` (`⌫`). The rows are rebuilt every second from
/// `snapshot`, so `T+` and `STALE · 18M` keep counting.
public struct SessionsTabView: View {
    @Environment(\.vigieTheme) private var theme
    @State private var selection: String?
    @State private var hovered: String?

    private let fixedNow: Date?
    /// False draws the rows in a plain stack (offscreen renders: `ImageRenderer` draws no `ScrollView` content).
    var scrolls = true
    private let snapshot: @MainActor (Date) -> SessionsSnapshot
    private let onFocus: @MainActor (String) -> Void
    private let onDismiss: @MainActor (String) -> Void
    private let openSettings: (@MainActor () -> Void)?

    /// - Parameters:
    ///   - now: a fixed time (tests, previews); nil ticks every second.
    ///   - selection: the initial keyboard selection (tests, previews).
    ///   - snapshot: the rows (or the empty state) at a given time.
    ///   - onFocus: Focus on a row id (the session key).
    ///   - onDismiss: removes a dismissable failed row.
    ///   - openSettings: opens Settings › Agents from the `NO AGENT CONNECTED` state; nil hides the button.
    public init(
        now: Date? = nil,
        selection: String? = nil,
        snapshot: @escaping @MainActor (Date) -> SessionsSnapshot,
        onFocus: @escaping @MainActor (String) -> Void,
        onDismiss: @escaping @MainActor (String) -> Void = { _ in },
        openSettings: (@MainActor () -> Void)? = nil
    ) {
        self.fixedNow = now
        self.snapshot = snapshot
        self.onFocus = onFocus
        self.onDismiss = onDismiss
        self.openSettings = openSettings
        self._selection = State(initialValue: selection)
    }

    public var body: some View {
        Group {
            if let fixedNow {
                content(snapshot(fixedNow))
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(snapshot(context.date))
                }
            }
        }
        .padding(.horizontal, theme.spacing(.gridPaddingX))
        .padding(.top, theme.spacing(.cardPaddingY))
        .padding(.bottom, theme.spacing(.gridPaddingX))
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .return, .delete]) { press in
            handle(press.key)
        }
    }

    @ViewBuilder private func content(_ snapshot: SessionsSnapshot) -> some View {
        if let empty = snapshot.empty, snapshot.rows.isEmpty {
            WidgetCard(title: Text(verbatim: snapshot.header)) {
                EmptyStateBlock(
                    empty.copy, settingsAction: empty.offersSettings ? openSettings : nil)
            }
        } else {
            let showsTerminal = snapshot.showsTerminalColumn
            let selected = SessionsSelection.valid(selection, in: snapshot.rows.map(\.id))
            WidgetCard(title: Text(verbatim: snapshot.header), meta: meta) {
                VStack(alignment: .leading, spacing: 0) {
                    SessionColumnHeaders(showsTerminal: showsTerminal)
                    rowList {
                        VStack(spacing: 0) {
                            ForEach(Array(snapshot.rows.enumerated()), id: \.element.id) { index, row in
                                SessionRowView(
                                    row: row,
                                    showsTerminal: showsTerminal,
                                    isFirst: index == 0,
                                    isSelected: row.id == selected,
                                    isHovered: row.id == hovered,
                                    onHover: { hovering in
                                        if hovering { hovered = row.id } else if hovered == row.id { hovered = nil }
                                    },
                                    onFocus: {
                                        selection = row.id
                                        onFocus(row.id)
                                    },
                                    onDismiss: { onDismiss(row.id) })
                            }
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

    /// `↑↓ SELECT · ↵ FOCUS · ⌘1–9 TABS · ESC` then `SORTED BY URGENCY`.
    private var meta: Text {
        Text(L10n.resource("sessions.hints")) + Text(verbatim: SessionsMetrics.metaSeparator)
            + Text(L10n.resource("sessions.sorted"))
    }

    private func handle(_ key: KeyEquivalent) -> KeyPress.Result {
        let rows = snapshot(fixedNow ?? Date()).rows
        let ids = rows.map(\.id)
        switch key {
        case .upArrow, .downArrow:
            guard !ids.isEmpty else { return .ignored }
            selection = SessionsSelection.move(selection, by: key == .upArrow ? -1 : 1, in: ids)
            return .handled
        case .return:
            guard let id = SessionsSelection.valid(selection, in: ids) else { return .ignored }
            onFocus(id)
            return .handled
        case .delete:
            guard let id = SessionsSelection.valid(selection, in: ids),
                rows.first(where: { $0.id == id })?.canDismiss == true
            else { return .ignored }
            onDismiss(id)
            return .handled
        default:
            return .ignored
        }
    }
}

/// `AGENT · PROJECT · LAST ACTION · TERMINAL · STATUS · T+`, aligned on the row grid, in the 7.5px tracked
/// label type of the mockup (`.cols`), so `TERMINAL` fits its 62px column.
struct SessionColumnHeaders: View {
    @Environment(\.vigieTheme) private var theme
    let showsTerminal: Bool

    var body: some View {
        let columns = SessionColumns(theme: theme)
        HStack(spacing: theme.spacing(.rowGap)) {
            Color.clear.frame(width: columns.glyph)
            header("sessions.column.agent").frame(width: columns.agent, alignment: .leading)
            header("sessions.column.project").frame(maxWidth: .infinity, alignment: .leading)
            if showsTerminal {
                header("sessions.column.terminal").frame(width: columns.terminal, alignment: .leading)
            }
            header("sessions.column.status").frame(width: columns.status, alignment: .trailing)
            Color.clear.frame(width: columns.action)
        }
        .padding(.horizontal, theme.spacing(.actionGap))
        .frame(height: SessionsMetrics.columnHeaderHeight)
        .accessibilityHidden(true)
    }

    private func header(_ key: String) -> some View {
        Text(L10n.resource(key))
            .font(theme.font(.readoutLabel))
            .tracking(theme.tracking(.readoutLabel))
            .foregroundStyle(theme.color(.ink3))
            .lineLimit(1)
    }
}
