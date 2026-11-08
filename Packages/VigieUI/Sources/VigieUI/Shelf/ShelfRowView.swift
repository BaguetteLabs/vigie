import SwiftUI

/// One 42px Stash row on the mockup grid `20px 1fr 50px 64px 92px 12px` (gap 10): file tile, name over
/// `size · mode`, source app (`—` when unknown), added time over its day, time left over the TTL bar, grip.
/// Hover: `QUICK LOOK · REVEAL · PIN` replace source and added, the grip brightens and shows the
/// `DRAG · MOVE  ⌥ DRAG · COPY` tip. The selection carries the keyboard ring. A click selects; the grip drags.
struct ShelfRowView: View {
    @Environment(\.vigieTheme) private var theme
    let row: ShelfRowModel
    let isFirst: Bool
    let isSelected: Bool
    let isHovered: Bool
    let interactive: Bool
    let actions: ShelfTabActions
    /// Changes when ↵ asks for this row's `Send to` menu.
    var menuToken: Int? = nil
    let onHover: (Bool) -> Void

    /// The `Send to` menu and VoiceOver actions (Story 9.10).
    private var menuEntries: [ShelfMenuEntry] {
        ShelfMenuEntry.entries(sendTo: actions.sendToEntries(row.id), isPinned: row.isPinned)
    }

    var body: some View {
        let columns = ShelfColumns.standard
        let shape = RoundedRectangle(cornerRadius: theme.radius(.row), style: .continuous)
        HStack(spacing: columns.gap) {
            ShelfFileTile(kind: row.kind).frame(width: columns.tile)
            nameColumn.frame(maxWidth: .infinity, alignment: .leading)
            if isHovered {
                chips.fixedSize()
            } else {
                sourceColumn.frame(width: columns.source, alignment: .leading)
                addedColumn.frame(width: columns.added, alignment: .trailing)
            }
            ShelfExpiryView(expiry: row.expiry).frame(width: columns.expires, alignment: .leading)
            grip.frame(width: columns.grip, height: columns.height)
        }
        .padding(.horizontal, columns.paddingX)
        .frame(height: columns.height)
        .background {
            if isHovered {
                shape.fill(hoverTint)
                    .overlay {
                        shape.strokeBorder(
                            theme.borderColor(.ink1, opacity: ShelfTabMetrics.hoverOutline),
                            lineWidth: theme.a11y.hairlineWidth)
                    }
            }
        }
        .keyboardSelectionRing(isSelected: isSelected)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(theme.color(.ink1).opacity(ShelfTabMetrics.rowRule(theme.look)))
                    .frame(height: theme.a11y.hairlineWidth)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isHovered {
                ShelfDragTip().offset(y: ShelfTabMetrics.tipOverhang).allowsHitTesting(false)
            }
        }
        .contentShape(shape)
        .onHover(perform: onHover)
        .onTapGesture { actions.select(row.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.accessibilityLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { actions.select(row.id) }
        .accessibilityActions {
            ForEach(menuEntries) { entry in
                Button(entry.title) { entry.perform(on: row.id, actions) }
            }
        }
        .contextMenu {
            if interactive {
                ForEach(menuEntries) { entry in
                    Button(entry.title) { entry.perform(on: row.id, actions) }
                }
            }
        }
        .background {
            if interactive {
                ShelfMenuAnchor(
                    token: menuToken, entries: { menuEntries },
                    run: { entry in entry.perform(on: row.id, actions) })
            }
        }
    }

    private var pinKey: String { row.isPinned ? "shelf.action.unpin" : "shelf.action.pin" }

    private var hoverTint: Color {
        theme.usesCornerMarks
            ? theme.color(.structure).opacity(ComponentMetrics.hoverLiftStruct)
            : theme.color(.ink1).opacity(ComponentMetrics.hoverLift)
    }

    private var nameColumn: some View {
        VStack(alignment: .leading, spacing: ShelfTabMetrics.nameGap) {
            Text(verbatim: row.name)
                .font(ShelfTabMetrics.font(theme, .rowPrimary, size: ShelfTabMetrics.nameSize))
                .foregroundStyle(theme.color(.ink1))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: row.sizeMode)
                .font(ShelfTabMetrics.font(theme, .code, size: ShelfTabMetrics.metaSize, weight: 400))
                .foregroundStyle(theme.color(.ink3))
                .lineLimit(1)
        }
    }

    private var sourceColumn: some View {
        Text(verbatim: row.sourceApp ?? ShelfTabMetrics.noSource)
            .font(ShelfTabMetrics.font(theme, .body, size: ShelfTabMetrics.sourceSize))
            .foregroundStyle(theme.color(.ink2))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var addedColumn: some View {
        VStack(alignment: .trailing, spacing: ShelfTabMetrics.addedGap) {
            Text(verbatim: row.addedTime)
                .font(ShelfTabMetrics.font(theme, .readoutValue, size: ShelfTabMetrics.addedSize, weight: 300))
                .monospacedDigit()
                .foregroundStyle(theme.color(.ink1))
            // `FRI 30 OCT` may run into the source column's slack rather than truncate.
            Text(verbatim: row.addedDay)
                .font(theme.font(.readoutLabel))
                .tracking(theme.tracking(.readoutLabel))
                .foregroundStyle(theme.color(.ink3))
                .fixedSize()
        }
        .lineLimit(1)
    }

    private var chips: some View {
        HStack(spacing: ShelfTabMetrics.chipGap) {
            ShelfMiniChip(label: L10n.resource("shelf.action.quickLook")) { actions.quickLook(row.id) }
            ShelfMiniChip(label: L10n.resource("shelf.action.reveal")) { actions.reveal(row.id) }
            ShelfMiniChip(label: L10n.resource(pinKey)) { actions.togglePin(row.id) }
        }
    }

    @ViewBuilder private var grip: some View {
        let glyph = GripGlyph(isActive: isHovered).accessibilityHidden(true)
        if interactive {
            glyph.overlay {
                ShelfDragHandle(
                    beginDrag: { actions.beginDrag(row.id) },
                    endDrag: { operation in actions.endDrag(row.id, operation) },
                    badgeColor: theme.nsColor(theme.usesCornerMarks ? .gold : .iris2)
                )
                .frame(width: ShelfTabMetrics.dragHandleWidth)
                .frame(maxHeight: .infinity)
            }
        } else {
            glyph
        }
    }
}

/// The expires column: time left over the TTL bar; the warning hue and triangle in the last 24 h; `PINNED`
/// over the dashed line.
struct ShelfExpiryView: View {
    @Environment(\.vigieTheme) private var theme
    let expiry: ShelfRowModel.Expiry

    var body: some View {
        VStack(alignment: .leading, spacing: ShelfTabMetrics.barGap) {
            label
                .font(ShelfTabMetrics.font(theme, .rowStatus, size: ShelfTabMetrics.ttlSize))
                // Mockup `.ttl b`: .14em, the action tracking (`EXPIRES IN 5H` fits the 92px column).
                .tracking(theme.tracking(.action))
                .lineLimit(1)
                .fixedSize()
            bar.frame(height: ShelfTabMetrics.barHeight)
        }
    }

    @ViewBuilder private var label: some View {
        switch expiry {
        case .timeLeft(let text, _):
            Text(verbatim: text).foregroundStyle(theme.color(.ink2))
        case .expiring(let text, _):
            HStack(spacing: ShelfTabMetrics.triangleGap) {
                WarningTriangle()
                    .fill(theme.color(.quotaWarning))
                    .frame(width: ShelfTabMetrics.triangleSide, height: ShelfTabMetrics.triangleSide)
                    .accessibilityHidden(true)
                Text(verbatim: text).foregroundStyle(theme.color(ShelfTabMetrics.warningTextRole(theme)))
            }
        case .pinned:
            Text(L10n.resource("shelf.row.pinned"))
                .foregroundStyle(theme.color(theme.usesCornerMarks ? .ink1 : ShelfTabMetrics.pinnedRole(theme)))
        }
    }

    @ViewBuilder private var bar: some View {
        switch expiry {
        case .timeLeft(_, let fraction):
            ShelfTTLBar(
                fraction: fraction,
                fill: AnyShapeStyle(
                    LinearGradient(
                        colors: [theme.color(.ink2), theme.color(.ink1)], startPoint: .leading, endPoint: .trailing)))
        case .expiring(_, let fraction):
            ShelfTTLBar(fraction: fraction, fill: AnyShapeStyle(theme.color(.quotaWarning)))
        case .pinned:
            GeometryReader { proxy in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
                }
                .stroke(
                    theme.color(ShelfTabMetrics.pinnedRole(theme)),
                    style: StrokeStyle(lineWidth: theme.a11y.hairlineWidth, dash: ShelfTabMetrics.dash))
            }
        }
    }
}

/// The 2px TTL bar: a track in `ink-1` at 10% (12% light) and the fraction of the ttl left.
struct ShelfTTLBar: View {
    @Environment(\.vigieTheme) private var theme
    let fraction: Double
    let fill: AnyShapeStyle

    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: ShelfTabMetrics.barHeight / 2, style: .continuous)
            ZStack(alignment: .leading) {
                shape.fill(theme.color(.ink1).opacity(ShelfTabMetrics.track(theme.look)))
                shape.fill(fill).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The 18 × 22 glass file tile with the extension at its foot (mockup `.tile`).
struct ShelfFileTile: View {
    @Environment(\.vigieTheme) private var theme
    let kind: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShelfTabMetrics.tileRadius, style: .continuous)
        shape
            .fill(
                LinearGradient(
                    colors: [theme.color(.ink1).opacity(ShelfTabMetrics.tileGlass), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay {
                shape.strokeBorder(
                    theme.borderColor(.ink1, opacity: ShelfTabMetrics.tileBorder), lineWidth: theme.a11y.hairlineWidth)
            }
            .overlay(alignment: .bottom) {
                Text(verbatim: kind)
                    .font(ShelfTabMetrics.font(theme, .readoutLabel, size: ShelfTabMetrics.tileLabelSize, weight: 600))
                    .foregroundStyle(theme.color(.ink2))
                    .lineLimit(1)
                    .minimumScaleFactor(ShelfTabMetrics.tileLabelMinScale)
                    .padding(.bottom, ShelfTabMetrics.tileLabelInset)
                    .padding(.horizontal, ShelfTabMetrics.tileLabelInset / 2)
            }
            .frame(width: ShelfTabMetrics.tileWidth, height: ShelfTabMetrics.tileHeight)
            .accessibilityHidden(true)
    }
}

/// A hover chip (`QUICK LOOK`, `REVEAL`, `PIN`): 8px tracked caps in `ink-1`, a pill with an inner hairline
/// (C: square).
struct ShelfMiniChip: View {
    @Environment(\.vigieTheme) private var theme
    let label: LocalizedStringResource
    let action: @MainActor () -> Void

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: theme.usesCornerMarks ? 0 : ShelfTabMetrics.chipHeight / 2, style: .continuous)
        Button(action: action) {
            Text(label)
                .font(ShelfTabMetrics.font(theme, .action, size: ShelfTabMetrics.chipSize))
                .tracking(theme.tracking(.action))
                .textCase(.uppercase)
                .foregroundStyle(theme.color(.ink1))
                .lineLimit(1)
                .padding(.horizontal, ShelfTabMetrics.chipPaddingX)
                .frame(height: ShelfTabMetrics.chipHeight)
                .overlay {
                    shape.strokeBorder(
                        theme.usesCornerMarks
                            ? theme.borderColor(.structure, opacity: ComponentMetrics.structBorder)
                            : theme.borderColor(.ink1, opacity: ShelfTabMetrics.chipBorder),
                        lineWidth: theme.a11y.hairlineWidth)
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityHidden(true)
    }
}

/// `DRAG · MOVE  ⌥ DRAG · COPY` under the hovered row's grip (mockup `.tip`).
struct ShelfDragTip: View {
    @Environment(\.vigieTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShelfTabMetrics.tipRadius, style: .continuous)
        Text(L10n.resource("shelf.tip.drag"))
            .font(ShelfTabMetrics.font(theme, .readoutLabel, size: ShelfTabMetrics.chipSize))
            .tracking(theme.tracking(.readoutLabel))
            .foregroundStyle(theme.color(.ink1))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, ShelfTabMetrics.chipPaddingX)
            .frame(height: ShelfTabMetrics.tipHeight)
            .background(theme.color(.surfaceCard), in: shape)
            .overlay {
                shape.strokeBorder(
                    theme.borderColor(.ink1, opacity: ShelfTabMetrics.tipBorder), lineWidth: theme.a11y.hairlineWidth)
            }
            .shadow(
                color: theme.color(.shadow).opacity(ShelfTabMetrics.tipShadow(theme.look)),
                radius: ShelfTabMetrics.tipShadowRadius, y: ShelfTabMetrics.tipShadowY
            )
            .accessibilityHidden(true)
    }
}

/// The row grid of the mockup (`.it`): `20px 1fr 50px 64px 92px 12px`, gap 10, 42px high, 8px inset.
struct ShelfColumns: Equatable {
    var tile: CGFloat = 20
    var source: CGFloat = 50
    var added: CGFloat = 64
    var expires: CGFloat = 92
    var grip: CGFloat = 12
    var gap: CGFloat = 10
    var height: CGFloat = 42
    var paddingX: CGFloat = 8

    static let standard = ShelfColumns()
}

/// Sizes and proportions the Shelf mockup states (no DESIGN token covers the row).
enum ShelfTabMetrics {
    static let sendToWidth: CGFloat = 212
    static let askZoneHeight: CGFloat = 84
    static let headerHeight: CGFloat = 12
    static let headerTop: CGFloat = 4
    static let nameSize: CGFloat = 12.5
    static let metaSize: CGFloat = 10
    static let sourceSize: CGFloat = 10.5
    static let addedSize: CGFloat = 12
    static let ttlSize: CGFloat = 9
    static let chipSize: CGFloat = 8
    static let ruleSize: CGFloat = 9.5
    static let nameGap: CGFloat = 4
    static let addedGap: CGFloat = 3
    static let barGap: CGFloat = 5
    static let barHeight: CGFloat = 2
    static let triangleSide: CGFloat = 8
    static let triangleGap: CGFloat = 4
    static let tileWidth: CGFloat = 18
    static let tileHeight: CGFloat = 22
    static let tileRadius: CGFloat = 3
    static let tileGlass = 0.12
    static let tileBorder = 0.30
    static let tileLabelSize: CGFloat = 5.5
    static let tileLabelMinScale: CGFloat = 0.7
    static let tileLabelInset: CGFloat = 2
    static let chipHeight: CGFloat = 18
    static let chipPaddingX: CGFloat = 7
    static let chipGap: CGFloat = 5
    static let chipBorder = 0.18
    static let hoverOutline = 0.10
    static let tipHeight: CGFloat = 18
    static let tipRadius: CGFloat = 7
    static let tipBorder = 0.16
    static let tipShadowRadius: CGFloat = 5
    static let tipShadowY: CGFloat = 4
    static func tipShadow(_ look: Look) -> Double { look == .dark ? 0.35 : 0.12 }
    /// How far the drag tip hangs below its row (mockup: `bottom: -21px`).
    static let tipOverhang: CGFloat = 21
    /// The grip's drag area: wider than the 8px glyph so it is easy to grab.
    static let dragHandleWidth: CGFloat = 22
    static let footerGap: CGFloat = 6
    static let plusTarget: CGFloat = 30
    static let plusSize: CGFloat = 21
    static let plusRing = 0.45
    static let plusGlyph = "+"
    static let dash: [CGFloat] = [3, 3]
    static let noSource = "—"
    static let metaSeparator = " · "
    /// `⌘V` on the tab.
    static let pasteKey = KeyEquivalent("v")
    static let previewBodyHeight: CGFloat = 350

    /// Row rule (`--hair2`): 4% dark, 7% light.
    static func rowRule(_ look: Look) -> Double { look == .dark ? 0.04 : 0.07 }
    /// TTL bar track (`--track`): 10% dark, 12% light.
    static func track(_ look: Look) -> Double { look == .dark ? 0.10 : 0.12 }
    /// Ask AI dashed border: A lilac 35%, C gold 55%.
    static func askDash(_ theme: Theme) -> Double { theme.usesCornerMarks ? 0.55 : 0.35 }

    /// Lilac (`iris-2`) marks pinned items and the Ask AI target in A; C has no lilac: `struct`.
    static func pinnedRole(_ theme: Theme) -> ColorRole { theme.usesCornerMarks ? .structure : .iris2 }

    /// Warning text: `quota-warning-text` on light looks (contrast), `quota-warning` on dark.
    static func warningTextRole(_ theme: Theme) -> ColorRole { theme.isLight ? .quotaWarningText : .quotaWarning }

    /// A role's family at a mockup size (the role's weight unless given).
    static func font(_ theme: Theme, _ role: TypographyRole, size: CGFloat, weight: Int? = nil) -> Font {
        let spec = theme.fontSpec(role)
        return FontSpec(
            family: spec.family, size: size, weight: weight ?? spec.weight, tabularDigits: spec.tabularDigits
        ).font
    }
}
