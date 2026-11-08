import SwiftUI

/// The Shelf tab (FR59, UX-DR33, UX-DR41 Shelf `1fr` + 212; mockup `key-shelf-tab.html`): the Stash table card
/// on the left (title `STASH · N`, meta `1 EXPIRING · TTL 7D`, column headers, the rows newest first, the
/// footer `DRAG OUT MOVE · ⌥ DRAG COPY` · `␣ QUICK LOOK` and the expiry rule) and the `SEND TO` card on the
/// right (`sendTo`, filled by Story 9.7; a placeholder Ask AI zone until then). An empty stash shows
/// `STASH EMPTY` and the sentence naming the ttl (UX-DR44); the right card stays.
///
/// One row is selected (click, or ↑↓ once the tab has keyboard focus: the panel takes it on a click,
/// UX-DR45); Space opens Quick Look on it. Hover shows `QUICK LOOK · REVEAL · PIN` over the source and added
/// columns and the `DRAG · MOVE  ⌥ DRAG · COPY` tip under the grip; the grip is the drag-out handle.
///
/// `snapshot` is read in `body`, so an `@Observable` source re-renders the tab when it changes.
public struct ShelfTabView: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    @State private var hovered: UUID?
    /// ↵ on the selection: which row pops its `Send to` menu, and a counter that changes per request.
    @State private var menuRequest: (id: UUID, token: Int)?

    /// False draws the rows in a plain stack and the grip without its AppKit drag source (offscreen
    /// renders: `ImageRenderer` draws neither `ScrollView` content nor AppKit views).
    var interactive = true
    private let snapshot: @MainActor () -> ShelfTabSnapshot
    private let actions: ShelfTabActions
    private let sendTo: AnyView?

    /// - Parameters:
    ///   - hovered: the row drawn hovered (tests, previews).
    ///   - snapshot: what the tab shows now.
    ///   - actions: the module's handlers.
    ///   - sendTo: the right card (Story 9.7); nil draws the placeholder.
    public init(
        hovered: UUID? = nil,
        snapshot: @escaping @MainActor () -> ShelfTabSnapshot,
        actions: ShelfTabActions,
        sendTo: AnyView? = nil
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.sendTo = sendTo
        self._hovered = State(initialValue: hovered)
    }

    public var body: some View {
        // Privacy mode (AD-24): file names masked in the rows and their VoiceOver labels.
        let snapshot = snapshot().privacy(privacyActive)
        HStack(alignment: .top, spacing: theme.spacing(.gridGap)) {
            stashCard(snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Group {
                if let sendTo { sendTo } else { ShelfSendToPlaceholder() }
            }
            .frame(width: theme.componentLength("send-to-card", "width") ?? ShelfTabMetrics.sendToWidth)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, theme.spacing(.gridPaddingX))
        .padding(.top, theme.spacing(.cardPaddingY))
        .padding(.bottom, theme.spacing(.gridPaddingX))
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .space, .return]) { press in
            handle(press.key)
        }
        .onKeyPress(keys: [ShelfTabMetrics.pasteKey]) { press in
            guard press.modifiers == .command else { return .ignored }
            actions.paste()
            return .handled
        }
        // ⌘V usually arrives as the Edit › Paste command; the host reads the clipboard, not this view.
        .onPasteCommand(of: [.item]) { _ in actions.paste() }
    }

    @ViewBuilder private func stashCard(_ snapshot: ShelfTabSnapshot) -> some View {
        WidgetCard(title: Text(verbatim: snapshot.title), meta: meta(snapshot)) {
            if snapshot.rows.isEmpty {
                EmptyStateBlock(label: L10n.resource("shelf.empty.label"), sentence: snapshot.emptySentence)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ShelfColumnHeaders()
                    rowList(snapshot)
                        .frame(maxHeight: .infinity, alignment: .top)
                    ShelfFooter(notice: snapshot.notice)
                }
            }
        }
    }

    /// `1 EXPIRING` in the warning hue, then `· TTL 7D`.
    private func meta(_ snapshot: ShelfTabSnapshot) -> Text {
        let ttl = Text(verbatim: snapshot.ttlMeta)
        guard let expiring = snapshot.expiringMeta else { return ttl }
        return Text(verbatim: expiring).foregroundStyle(theme.color(ShelfTabMetrics.warningTextRole(theme)))
            + Text(verbatim: ShelfTabMetrics.metaSeparator) + ttl
    }

    @ViewBuilder private func rowList(_ snapshot: ShelfTabSnapshot) -> some View {
        let selected = ShelfSelection.valid(snapshot.selectedID, in: snapshot.rows.map(\.id))
        let rows = VStack(spacing: 0) {
            ForEach(Array(snapshot.rows.enumerated()), id: \.element.id) { index, row in
                ShelfRowView(
                    row: row,
                    isFirst: index == 0,
                    isSelected: row.id == selected,
                    isHovered: row.id == hovered,
                    interactive: interactive,
                    actions: actions,
                    menuToken: menuRequest?.id == row.id ? menuRequest?.token : nil,
                    onHover: { hovering in
                        if hovering { hovered = row.id } else if hovered == row.id { hovered = nil }
                    }
                )
                .zIndex(row.id == hovered ? 1 : 0)
            }
        }
        if interactive {
            ScrollFadeList(showsHint: false) { rows.padding(.bottom, ShelfTabMetrics.tipOverhang) }
        } else {
            rows
        }
    }

    private func handle(_ key: KeyEquivalent) -> KeyPress.Result {
        let snapshot = snapshot()
        let ids = snapshot.rows.map(\.id)
        switch key {
        case .upArrow, .downArrow:
            guard !ids.isEmpty else { return .ignored }
            actions.select(ShelfSelection.move(snapshot.selectedID, by: key == .upArrow ? -1 : 1, in: ids))
            return .handled
        case .space:
            guard let id = ShelfSelection.valid(snapshot.selectedID, in: ids) else { return .ignored }
            actions.quickLook(id)
            return .handled
        case .return:
            guard let id = ShelfSelection.valid(snapshot.selectedID, in: ids) else { return .ignored }
            menuRequest = (id, (menuRequest?.token ?? 0) + 1)
            return .handled
        default:
            return .ignored
        }
    }
}

/// `ITEM · SOURCE · ADDED · EXPIRES` on the row grid (mockup `.sh-h`).
struct ShelfColumnHeaders: View {
    @Environment(\.vigieTheme) private var theme

    var body: some View {
        let columns = ShelfColumns.standard
        HStack(spacing: columns.gap) {
            Color.clear.frame(width: columns.tile)
            header("shelf.column.item").frame(maxWidth: .infinity, alignment: .leading)
            header("shelf.column.source").frame(width: columns.source, alignment: .leading)
            header("shelf.column.added").frame(width: columns.added, alignment: .trailing)
            header("shelf.column.expires").frame(width: columns.expires, alignment: .leading)
            Color.clear.frame(width: columns.grip)
        }
        .padding(.horizontal, columns.paddingX)
        .frame(height: ShelfTabMetrics.headerHeight)
        .padding(.top, ShelfTabMetrics.headerTop)
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

/// `DRAG OUT MOVE · ⌥ DRAG COPY` (verbs in `ink-2`) and `␣ QUICK LOOK` (or the last notice), then the expiry
/// rule under a hairline (mockup `.foot`).
struct ShelfFooter: View {
    @Environment(\.vigieTheme) private var theme
    let notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ShelfTabMetrics.footerGap) {
            HStack(spacing: theme.spacing(.glyphGap)) {
                (Text(L10n.resource("shelf.footer.dragOut")) + Text(verbatim: " ")
                    + Text(L10n.resource("shelf.footer.move")).foregroundStyle(theme.color(.ink2))
                    + Text(verbatim: ShelfTabMetrics.metaSeparator) + Text(L10n.resource("shelf.footer.optionDrag"))
                    + Text(verbatim: " ")
                    + Text(L10n.resource("shelf.footer.copy")).foregroundStyle(theme.color(.ink2)))
                Spacer(minLength: theme.spacing(.glyphGap))
                if let notice {
                    Text(verbatim: notice).foregroundStyle(theme.color(.ink2))
                } else {
                    Text(L10n.resource("shelf.footer.quickLook"))
                }
            }
            .font(theme.font(.readoutLabel))
            .tracking(theme.tracking(.readoutLabel))
            .textCase(.uppercase)
            .foregroundStyle(theme.color(.ink3))
            .lineLimit(1)
            Text(L10n.resource("shelf.footer.rule"))
                .font(ShelfTabMetrics.font(theme, .prose, size: ShelfTabMetrics.ruleSize))
                .foregroundStyle(theme.color(.ink3))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, ShelfTabMetrics.footerGap)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(theme.color(.ink1).opacity(ComponentMetrics.cardHairline(theme.look)))
                        .frame(height: theme.a11y.hairlineWidth)
                }
        }
        .padding(.top, ShelfTabMetrics.footerGap)
    }
}

/// The right card until Story 9.7 builds `SEND TO`: the header and the dashed lilac Ask AI zone (`+`,
/// `ASK AI`, `Drop a file to start a session`). It takes no drop yet.
struct ShelfSendToPlaceholder: View {
    @Environment(\.vigieTheme) private var theme

    var body: some View {
        WidgetCard(title: Text(L10n.resource("shelf.sendTo.title"))) {
            let accent = theme.color(ShelfTabMetrics.pinnedRole(theme))
            let shape = RoundedRectangle(cornerRadius: theme.radius(.zone), style: .continuous)
            VStack(spacing: theme.spacing(.glyphGap)) {
                Text(verbatim: ShelfTabMetrics.plusGlyph)
                    .font(ShelfTabMetrics.font(theme, .readoutValue, size: ShelfTabMetrics.plusSize))
                    .foregroundStyle(accent)
                    .frame(width: ShelfTabMetrics.plusTarget, height: ShelfTabMetrics.plusTarget)
                    .overlay {
                        Circle().strokeBorder(
                            theme.borderColor(ShelfTabMetrics.pinnedRole(theme), opacity: ShelfTabMetrics.plusRing),
                            lineWidth: theme.a11y.hairlineWidth)
                    }
                Text(L10n.resource("shelf.sendTo.askAI"))
                    .font(theme.font(.kicker))
                    .tracking(theme.tracking(.kicker))
                    .foregroundStyle(accent)
                Text(L10n.resource("shelf.sendTo.askAI.sentence"))
                    .font(ShelfTabMetrics.font(theme, .prose, size: ShelfTabMetrics.sourceSize))
                    .foregroundStyle(theme.color(.ink3))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: theme.componentLength("send-to-card", "ask-zone-height") ?? ShelfTabMetrics.askZoneHeight)
            .overlay {
                shape.strokeBorder(
                    theme.borderColor(
                        theme.usesCornerMarks ? .gold : ShelfTabMetrics.pinnedRole(theme),
                        opacity: ShelfTabMetrics.askDash(theme)),
                    style: StrokeStyle(lineWidth: theme.a11y.hairlineWidth, dash: ShelfTabMetrics.dash))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview("Shelf tab · dark") {
    ShelfTabPreview(look: .dark)
}

#Preview("Shelf tab · light") {
    ShelfTabPreview(look: .light)
}

private struct ShelfTabPreview: View {
    let look: Look

    var body: some View {
        let theme = PreviewThemes.theme(look)
        let rows = ShelfPreviewSamples.rows
        ShelfTabView(
            hovered: rows.last?.id,
            snapshot: {
                ShelfTabSnapshot(
                    title: "STASH · 3", expiringMeta: "1 EXPIRING", ttlMeta: "TTL 7D", rows: rows,
                    selectedID: rows.first?.id, emptySentence: L10n.resource("shelf.empty.label"))
            },
            actions: ShelfTabActions()
        )
        .frame(
            width: theme.componentLength("expanded-panel", "width"),
            height: ShelfTabMetrics.previewBodyHeight
        )
        .background(theme.color(.surfacePanel))
        .vigieTheme(theme)
    }
}

enum ShelfPreviewSamples {
    static let rows: [ShelfRowModel] = [
        ShelfRowModel(
            id: UUID(), name: "build-log-2026-11-04.txt", kind: "TXT", sizeMode: "184 KB · REF", sourceApp: nil,
            addedTime: "14:31", addedDay: "TODAY", expiry: .timeLeft("6D LEFT", fraction: 0.97),
            accessibilityLabel: "build-log-2026-11-04.txt"),
        ShelfRowModel(
            id: UUID(), name: "mock-usage-tab.png", kind: "PNG", sizeMode: "1.2 MB · SAVED", sourceApp: nil,
            addedTime: "19:50", addedDay: "WED 28 OCT", expiry: .expiring("EXPIRES IN 5H", fraction: 0.03),
            accessibilityLabel: "mock-usage-tab.png"),
        ShelfRowModel(
            id: UUID(), name: "deploy-checklist.md", kind: "MD", sizeMode: "3 KB · REF", sourceApp: nil,
            addedTime: "10:05", addedDay: "MON 26 OCT", expiry: .pinned, accessibilityLabel: "deploy-checklist.md"),
    ]
}
