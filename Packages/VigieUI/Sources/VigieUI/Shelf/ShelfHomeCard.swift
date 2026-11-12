import AppKit
import ModuleKit
import SwiftUI
import UniformTypeIdentifiers

/// One stash item in the Home shelf widget: its Shelf row, plus the `5H` tag in its last 24 h.
public struct ShelfHomeItem: Identifiable, Equatable, Sendable {
    public var row: ShelfRowModel
    /// `5H`, in the item's last 24 h; nil otherwise.
    public var tag: String?

    public var id: UUID { row.id }
    public var isExpiring: Bool { tag != nil }

    public init(row: ShelfRowModel, tag: String? = nil) {
        self.row = row
        self.tag = tag
    }
}

/// What the Home shelf widget shows (Story 11.3, FR57, FR60, UX-DR33, UX-DR97), every text already formatted
/// by the Shelf module from its catalog.
public struct ShelfHomeCardModel: Sendable {
    /// `Shelf`.
    public var title: String
    /// `2 items`.
    public var meta: String
    /// Items in their last 24 h first (soonest first), then the others newest first.
    public var items: [ShelfHomeItem]
    /// `1 EXPIRES IN 5H` along the Stash zone's bottom; nil when nothing is in its last 24 h.
    public var warning: String?
    /// The Shelf's Stash zone.
    public var stashZone: SendToTarget?
    /// The Ask AI zone of `agents.sessions` (nil while that module is off).
    public var askZone: SendToTarget?

    public init(
        title: String, meta: String, items: [ShelfHomeItem], warning: String? = nil, stashZone: SendToTarget?,
        askZone: SendToTarget?
    ) {
        self.title = title
        self.meta = meta
        self.items = items
        self.warning = warning
        self.stashZone = stashZone
        self.askZone = askZone
    }

    /// The zones, Stash first. The widget shows only these two (FR57): AirDrop and Image to Text stay on the
    /// drop display and the Shelf tab.
    public var targets: [SendToTarget] { [stashZone, askZone].compactMap { $0 } }

    public func target(_ id: String) -> SendToTarget? { targets.first { $0.id == id } }

    /// The model as Privacy mode shows it (AD-24): file names masked.
    public func privacy(_ privacyActive: Bool) -> ShelfHomeCardModel {
        guard privacyActive else { return self }
        var copy = self
        copy.items = items.map { ShelfHomeItem(row: $0.row.redacted(), tag: $0.tag) }
        return copy
    }

    /// True when `target` takes the drag: a stash item dragged from the widget's own list never goes back to
    /// the Stash (the primary zone); otherwise the zone's own `accepts`.
    public static func accepts(_ target: SendToTarget, contentTypes: [UTType], isStashItem: Bool) -> Bool {
        if isStashItem && target.summary.role == .primary { return false }
        return target.accepts(contentTypes)
    }
}

/// What the widget asks of its module. Every closure runs on the main actor.
public struct ShelfHomeCardActions {
    /// The content types of the stash item being dragged from the widget's list, nil when the drag came from
    /// another app.
    public var internalDragTypes: @MainActor () -> [UTType]?
    /// A release on an accepting zone: the zone, what was dropped, and the modifiers held.
    public var drop: @MainActor (String, SendToDrop, EventModifiers) -> Void
    /// A drag from an item's tile starts: the file, its access held until ``endDrag``; nil refuses the drag.
    public var beginDrag: @MainActor (UUID) -> URL?
    /// The drag ended with this operation (a move takes the item off the shelf).
    public var endDrag: @MainActor (UUID, ShelfDragOperation) -> Void

    public init(
        internalDragTypes: @escaping @MainActor () -> [UTType]? = { nil },
        drop: @escaping @MainActor (String, SendToDrop, EventModifiers) -> Void = { _, _, _ in },
        beginDrag: @escaping @MainActor (UUID) -> URL? = { _ in nil },
        endDrag: @escaping @MainActor (UUID, ShelfDragOperation) -> Void = { _, _ in }
    ) {
        self.internalDragTypes = internalDragTypes
        self.drop = drop
        self.beginDrag = beginDrag
        self.endDrag = endDrag
    }
}

/// The drag over the widget, as its zones draw it.
public struct ShelfHomeHover: Equatable, Sendable {
    /// The zone under the drag.
    public var zoneID: String?
    /// True when that zone takes the drag.
    public var accepts: Bool
    /// ⌥ held.
    public var optionHeld: Bool

    public init(zoneID: String? = nil, accepts: Bool = false, optionHeld: Bool = false) {
        self.zoneID = zoneID
        self.accepts = accepts
        self.optionHeld = optionHeld
    }

    public var modifiers: EventModifiers { optionHeld ? .option : [] }

    /// Lit with its release line when hovered and it takes the drag, dimmed when it does not, else idle.
    public func phase(of id: String) -> DropMiniZone.Phase {
        guard zoneID == id else { return .idle }
        return accepts ? .hovered : .disabled
    }
}

/// The Shelf Home card (Story 11.3; DESIGN "Shelf row" › Home shelf widget, mockup `compare-a-vs-c-v3.html`
/// Home): a ``WidgetCard`` titled `Shelf` with the item count, then the Stash zone (`1fr`, the stash list
/// inside it) and the Ask AI zone (70px, compact) side by side. An item in its last 24 h comes first with its
/// `5H` tag, and the warning line `1 EXPIRES IN 5H` runs along the Stash zone's bottom (FR60, UX-DR33).
///
/// The card keeps its 222 × 138 cell: a list longer than the zone is clipped under the bottom fade mask, with
/// no scrolling (UX-DR97). Files from Finder dropped on a zone, and stash items dragged from an item's tile
/// onto Ask AI, go to the module, which runs the zone with `source = .homeWidget` (AD-19). A stash item is not
/// taken back by the Stash.
public struct ShelfHomeCardView: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    @State private var hover: ShelfHomeHover

    private let model: @MainActor () -> ShelfHomeCardModel
    private let actions: ShelfHomeCardActions
    /// False drops the drop targets and the AppKit drag sources (offscreen renders).
    var interactive = true

    /// - Parameters:
    ///   - hover: the drag drawn over the card (tests, previews).
    ///   - model: what the card shows now (read in `body`).
    public init(
        hover: ShelfHomeHover = ShelfHomeHover(), model: @escaping @MainActor () -> ShelfHomeCardModel,
        actions: ShelfHomeCardActions = ShelfHomeCardActions()
    ) {
        self.model = model
        self.actions = actions
        self._hover = State(initialValue: hover)
    }

    /// The model now, for tests.
    func modelValue() -> ShelfHomeCardModel { model() }

    public var body: some View {
        let model = model().privacy(privacyActive)
        WidgetCard(title: Text(verbatim: model.title), meta: Text(verbatim: model.meta)) {
            HStack(spacing: ShelfHomeCardMetrics.zoneGap) {
                if let stash = model.stashZone {
                    dropTarget(stash) {
                        ShelfHomeStashZone(
                            target: stash, items: model.items, warning: model.warning,
                            phase: hover.phase(of: stash.id), interactive: interactive, actions: actions)
                    }
                }
                if let ask = model.askZone {
                    dropTarget(ask) {
                        SendToAskZone(
                            target: ask, isLit: hover.phase(of: ask.id) == .hovered,
                            isRefused: hover.phase(of: ask.id) == .disabled, modifiers: hover.modifiers,
                            compact: true)
                    }
                    .frame(width: ShelfHomeCardMetrics.askWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func dropTarget(_ target: SendToTarget, @ViewBuilder content: () -> some View) -> some View {
        if interactive {
            content().onDrop(
                of: [.fileURL], delegate: ShelfHomeDropDelegate(target: target, hover: $hover, actions: actions))
        } else {
            content()
        }
    }
}

/// The Stash zone of the widget: the zone label (the release line while a drag it takes hovers it), the
/// stash list (or the zone's meta when empty) and the warning line at its bottom.
struct ShelfHomeStashZone: View {
    @Environment(\.vigieTheme) private var theme
    let target: SendToTarget
    let items: [ShelfHomeItem]
    let warning: String?
    let phase: DropMiniZone.Phase
    let interactive: Bool
    let actions: ShelfHomeCardActions

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text(phase == .hovered ? (target.zone.releaseLine ?? target.zone.label) : target.zone.label)
                .font(theme.font(.readoutLabel))
                .tracking(theme.tracking(.readoutLabel))
                .textCase(.uppercase)
                .foregroundStyle(phase == .hovered ? accentText : theme.color(.ink3))
                .lineLimit(1)
                .minimumScaleFactor(ShelfHomeCardMetrics.minScale)
                .padding(.bottom, ShelfHomeCardMetrics.labelGap)
            if items.isEmpty {
                if let meta = target.zone.meta {
                    Text(meta)
                        .font(theme.font(.readoutLabel))
                        .tracking(theme.tracking(.readoutLabel))
                        .foregroundStyle(theme.color(.ink3))
                        .lineLimit(2)
                        .minimumScaleFactor(ShelfHomeCardMetrics.minScale)
                }
                Spacer(minLength: 0)
            } else {
                ShelfHomeList(items: items, interactive: interactive, actions: actions)
            }
            if let warning {
                ShelfHomeWarningLine(text: warning)
                    .padding(.top, ShelfHomeCardMetrics.warningGap)
            }
        }
        .padding(.horizontal, ShelfHomeCardMetrics.zonePaddingX)
        .padding(.vertical, ShelfHomeCardMetrics.zonePaddingY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(fill))
        .overlay(border(shape))
        .opacity(phase == .disabled ? DropMiniZone.disabledOpacity : 1)
        .contentShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(target.zone.accessibilityLabel))
        .accessibilityAddTraits(phase == .hovered ? .isSelected : [])
    }

    private var isLit: Bool { phase == .hovered }
    private var radius: CGFloat { theme.usesCornerMarks ? 0 : theme.radius(.zone) }
    private var accent: Color { theme.color(theme.usesCornerMarks ? .gold : target.zone.accent) }
    private var accentText: Color { theme.color(theme.usesCornerMarks ? .goldText : target.zone.accent) }

    private var fill: AnyShapeStyle {
        if isLit { return AnyShapeStyle(accent.opacity(DropMiniZone.litFill)) }
        if theme.usesCornerMarks { return AnyShapeStyle(Color.clear) }
        return AnyShapeStyle(theme.color(.ink1).opacity(DropMetrics.primaryFill))
    }

    @ViewBuilder
    private func border(_ shape: RoundedRectangle) -> some View {
        let width = theme.a11y.hairlineWidth
        if isLit {
            shape.strokeBorder(accent, lineWidth: width)
        } else if theme.usesCornerMarks {
            shape.strokeBorder(theme.borderColor(.structure, opacity: DropMetrics.structBorder), lineWidth: width)
        } else {
            shape.strokeBorder(theme.borderColor(.ink1, opacity: DropMetrics.primaryHairline), lineWidth: width)
        }
    }
}

/// The stash list: fixed-height rows from the top, clipped to the zone; when they do not all fit, the last
/// visible rows fade under the bottom mask (UX-DR97). Never scrolls.
struct ShelfHomeList: View {
    @Environment(\.vigieTheme) private var theme
    let items: [ShelfHomeItem]
    let interactive: Bool
    let actions: ShelfHomeCardActions

    var body: some View {
        GeometryReader { proxy in
            let masked = ShelfHomeCardMetrics.overflows(count: items.count, height: proxy.size.height)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    ShelfHomeRow(item: item, interactive: interactive, actions: actions)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .mask { ShelfHomeFadeMask(isOn: masked) }
        }
    }
}

/// The bottom mask: opaque, then a fade over `ComponentMetrics.scrollFade` at the bottom when on.
struct ShelfHomeFadeMask: View {
    let isOn: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
            if isOn {
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: ComponentMetrics.scrollFade)
            }
        }
    }
}

/// One item: the file tile (its drag-out handle), the name, and the `5H` tag in its last 24 h.
struct ShelfHomeRow: View {
    @Environment(\.vigieTheme) private var theme
    let item: ShelfHomeItem
    let interactive: Bool
    let actions: ShelfHomeCardActions

    var body: some View {
        HStack(spacing: ShelfHomeCardMetrics.rowGap) {
            tile
            Text(verbatim: item.row.name)
                .font(ShelfTabMetrics.font(theme, .body, size: ShelfHomeCardMetrics.nameSize))
                .foregroundStyle(theme.color(.ink1))
                .lineLimit(1)
                .truncationMode(.middle)
                .sensitive()
            Spacer(minLength: 0)
            if let tag = item.tag {
                HStack(spacing: ShelfHomeCardMetrics.tagGap) {
                    WarningTriangle()
                        .fill(theme.color(.quotaWarning))
                        .frame(width: ShelfHomeCardMetrics.triangleSide, height: ShelfHomeCardMetrics.triangleSide)
                        .accessibilityHidden(true)
                    Text(verbatim: tag)
                        .font(ShelfTabMetrics.font(theme, .rowStatus, size: ShelfHomeCardMetrics.tagSize))
                        .tracking(theme.tracking(.action))
                        .foregroundStyle(theme.color(ShelfTabMetrics.warningTextRole(theme)))
                }
                .fixedSize()
            }
        }
        .frame(height: ShelfHomeCardMetrics.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.row.accessibilityLabel))
    }

    @ViewBuilder private var tile: some View {
        let tile = ShelfHomeTile()
        if interactive {
            tile.overlay {
                ShelfDragHandle(
                    beginDrag: { actions.beginDrag(item.id) },
                    endDrag: { operation in actions.endDrag(item.id, operation) },
                    badgeColor: theme.nsColor(theme.usesCornerMarks ? .gold : .iris2))
            }
        } else {
            tile
        }
    }
}

/// The small glass file tile of a widget row (mockup `.file i`, 13 × 16 scaled to the row): no label.
struct ShelfHomeTile: View {
    @Environment(\.vigieTheme) private var theme

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
            .frame(width: ShelfHomeCardMetrics.tileWidth, height: ShelfHomeCardMetrics.tileHeight)
            .accessibilityHidden(true)
    }
}

/// `▲ 1 EXPIRES IN 5H` in the warning hue (quota-warning, `quota-warning-text` on light looks; A43: never
/// color only, the triangle carries it too).
struct ShelfHomeWarningLine: View {
    @Environment(\.vigieTheme) private var theme
    let text: String

    var body: some View {
        HStack(spacing: ShelfTabMetrics.triangleGap) {
            WarningTriangle()
                .fill(theme.color(.quotaWarning))
                .frame(width: ShelfHomeCardMetrics.triangleSide, height: ShelfHomeCardMetrics.triangleSide)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(ShelfTabMetrics.font(theme, .rowStatus, size: ShelfHomeCardMetrics.tagSize))
                .tracking(theme.tracking(.action))
                .foregroundStyle(theme.color(ShelfTabMetrics.warningTextRole(theme)))
                .lineLimit(1)
                .minimumScaleFactor(ShelfHomeCardMetrics.minScale)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hover, ⌥ and release on one zone of the widget. A stash item from the widget's list carries its type
/// through ``ShelfHomeCardActions/internalDragTypes``; a Finder drag counts as plain data unless it declares an
/// image or PDF.
struct ShelfHomeDropDelegate: DropDelegate {
    let target: SendToTarget
    @Binding var hover: ShelfHomeHover
    let actions: ShelfHomeCardActions

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: hover.accepts ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) {
        if hover.zoneID == target.id { hover = ShelfHomeHover() }
    }

    func performDrop(info: DropInfo) -> Bool {
        let modifiers: EventModifiers = NSEvent.modifierFlags.contains(.option) ? .option : []
        hover = ShelfHomeHover()
        let internalTypes = actions.internalDragTypes()
        guard accepts(info, internalTypes: internalTypes) else { return false }
        if internalTypes != nil {
            actions.drop(target.id, .stashItem, modifiers)
            return true
        }
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        let zoneID = target.id
        let drop = actions.drop
        Task { @MainActor in
            let urls = await SendToDropDelegate.fileURLs(providers)
            guard !urls.isEmpty else { return }
            drop(zoneID, .files(urls), modifiers)
        }
        return true
    }

    private func update(_ info: DropInfo) {
        let next = ShelfHomeHover(
            zoneID: target.id, accepts: accepts(info, internalTypes: actions.internalDragTypes()),
            optionHeld: NSEvent.modifierFlags.contains(.option))
        if hover != next { hover = next }
    }

    private func accepts(_ info: DropInfo, internalTypes: [UTType]?) -> Bool {
        let types = internalTypes ?? Self.finderTypes(info)
        return ShelfHomeCardModel.accepts(target, contentTypes: types, isStashItem: internalTypes != nil)
    }

    private static func finderTypes(_ info: DropInfo) -> [UTType] {
        for type in [UTType.image, .pdf] where info.hasItemsConforming(to: [type]) { return [type] }
        return [.data]
    }
}

/// Layout numbers of the Home shelf widget (mockup `compare-a-vs-c-v3.html`: `.zones` `1fr 70px`, gap 8;
/// `.zone` padding 9 × 10; `.zl` 6px under; `.file` rows 22px, 10px names). Rows, tile and vertical padding
/// are tightened so three rows fit beside the warning line in the 138 pt cell.
enum ShelfHomeCardMetrics {
    static let zoneGap: CGFloat = 8
    static let askWidth: CGFloat = 70
    static let zonePaddingX: CGFloat = 10
    static let zonePaddingY: CGFloat = 7
    static let labelGap: CGFloat = 4
    static let rowHeight: CGFloat = 16
    static let rowGap: CGFloat = 6
    static let tileWidth: CGFloat = 10
    static let tileHeight: CGFloat = 13
    static let nameSize: CGFloat = 10
    static let tagSize: CGFloat = 8.5
    static let tagGap: CGFloat = 3
    static let triangleSide: CGFloat = 7
    static let warningGap: CGFloat = 4
    static let minScale: CGFloat = 0.8

    /// True when `count` rows do not all fit `height`: the list fades under the bottom mask.
    static func overflows(count: Int, height: CGFloat) -> Bool {
        CGFloat(count) * rowHeight > height + ScrollMetrics.tolerance
    }
}
