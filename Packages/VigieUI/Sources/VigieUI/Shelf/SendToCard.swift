import AppKit
import ModuleKit
import SwiftUI
import UniformTypeIdentifiers

/// One zone the `SEND TO` card offers: how it is drawn and what it takes (AD-19 zone summary).
public struct SendToTarget: Identifiable, Sendable {
    public let zone: DropDisplayZone
    public let summary: DropZoneSummary

    public var id: String { zone.id }

    public init(zone: DropDisplayZone, summary: DropZoneSummary) {
        self.zone = zone
        self.summary = summary
    }

    /// The Ask AI zone as the card draws it, from its summary.
    public init(summary: DropZoneSummary) {
        self.init(zone: DropDisplayZone(summary: summary), summary: summary)
    }

    /// True when the zone takes a drag of these types (files only: the card never receives loose content).
    public func accepts(_ contentTypes: [UTType]) -> Bool {
        summary.isEnabled && summary.accepts(contentTypes: contentTypes, loose: nil)
    }
}

extension DropDisplayZone {
    /// A zone summary as the display draws it (accent token → role; unknown tokens fall back to `iris-2`).
    public init(summary: DropZoneSummary, meta: LocalizedStringResource? = nil) {
        self.init(
            id: summary.id, label: summary.label, glyph: summary.glyph,
            accent: ColorRole(rawValue: summary.accentToken) ?? .iris2,
            style: summary.style == .target ? .target : .standard, isPrimary: summary.role == .primary,
            meta: meta ?? summary.meta, releaseLine: summary.releaseLine,
            accessibilityLabel: summary.accessibilityLabel ?? summary.label, hint: summary.modifierHint?.idle,
            hintActive: summary.modifierHint?.active)
    }
}

/// What the `SEND TO` card shows (UX-DR84, DESIGN "SEND TO card"): the header meta, the Ask AI zone of
/// `agents.sessions` (nil while that module is off) and the Shelf's mini zones (AirDrop, Image to Text), only
/// the enabled ones.
public struct SendToCardModel: Sendable {
    /// `DEFAULTS`, or `LAST · 3 LINES · 14:48` after an Image to Text copy.
    public var meta: String
    public var askZone: SendToTarget?
    public var miniZones: [SendToTarget]

    public init(meta: String, askZone: SendToTarget?, miniZones: [SendToTarget]) {
        self.meta = meta
        self.askZone = askZone
        self.miniZones = miniZones
    }

    /// No zone to draw: the card says `NO TARGETS`.
    public var isEmpty: Bool { askZone == nil && miniZones.isEmpty }

    /// Every zone, Ask AI first.
    public var targets: [SendToTarget] { (askZone.map { [$0] } ?? []) + miniZones }

    public func target(_ id: String) -> SendToTarget? { targets.first { $0.id == id } }

    /// The lit line under `RELEASE TO ASK`: the rows that name the target for `modifiers` (`Claude Code in
    /// File's folder`; with ⌥ the alternate folder), nil without rows.
    public static func releaseTarget(_ details: [DropZoneDetail], modifiers: EventModifiers) -> String? {
        let values = details.filter { $0.isActive(modifiers: modifiers) }.map(\.value)
        switch values.count {
        case 0: return nil
        case 2: return L10n.format("shelf.sendTo.releaseTarget", values[0], values[1])
        default: return values.joined(separator: ShelfTabMetrics.metaSeparator)
        }
    }
}

/// What a drop on the card carries.
public enum SendToDrop: Sendable, Equatable {
    /// The stash item being dragged out of the Stash rows (the module knows which: its drag is in flight).
    case stashItem
    /// Files dragged in from another app (Finder).
    case files([URL])
}

/// What the card asks of its module. Every closure runs on the main actor.
public struct SendToCardActions {
    /// The content types of the stash item being dragged from the rows, nil when no internal drag is in flight
    /// (the drag came from another app).
    public var internalDragTypes: @MainActor () -> [UTType]?
    /// A release on an accepting zone: the zone, what was dropped, and the modifiers held.
    public var drop: @MainActor (String, SendToDrop, EventModifiers) -> Void

    public init(
        internalDragTypes: @escaping @MainActor () -> [UTType]? = { nil },
        drop: @escaping @MainActor (String, SendToDrop, EventModifiers) -> Void = { _, _, _ in }
    ) {
        self.internalDragTypes = internalDragTypes
        self.drop = drop
    }
}

/// The drag over the card, as the zones draw it.
public struct SendToHover: Equatable, Sendable {
    /// The zone under the drag.
    public var zoneID: String?
    /// The dragged content types (gating).
    public var contentTypes: [UTType]
    /// ⌥ held.
    public var optionHeld: Bool

    public init(zoneID: String? = nil, contentTypes: [UTType] = [], optionHeld: Bool = false) {
        self.zoneID = zoneID
        self.contentTypes = contentTypes
        self.optionHeld = optionHeld
    }

    public var modifiers: EventModifiers { optionHeld ? .option : [] }

    /// How `target` draws under this drag: lit with its release line when hovered and it takes the item,
    /// dimmed (`disabled`) when hovered and it does not, else idle.
    public func phase(of target: SendToTarget) -> DropMiniZone.Phase {
        guard zoneID == target.id else { return .idle }
        return target.accepts(contentTypes) ? .hovered : .disabled
    }
}

/// The Shelf tab's right card (Story 9.7, UX-DR84, UX-DR32, UX-DR70; mockup `key-shelf-tab.html`,
/// `key-design-pass-1-7.html` 1.7c): header `SEND TO` and its meta, the 84px Ask AI zone (dashed lilac border,
/// C gold; the round `+` breathes on `calm-pulse` in A dark only, static in light, C, Calm and Reduce motion;
/// `ASK AI`, `Drop a file to start a session`), its rows `AGENT` / `FOLDER` / `⌥ FOLDER`, then the 38px mini
/// zones at the bottom. Zones that are off are not in the model and not drawn.
///
/// Every zone is a drop target for a stash item dragged from the rows and for files from Finder. Hovered and
/// accepting: solid border, inner tint, `RELEASE TO ASK` naming agent and folder; with ⌥ the `FOLDER` row dims
/// and `⌥ FOLDER` lights.
public struct SendToCardView: View {
    @Environment(\.vigieTheme) private var theme
    @State private var hover: SendToHover

    private let model: @MainActor () -> SendToCardModel
    private let actions: SendToCardActions
    /// False drops the drop targets (offscreen renders).
    var interactive = true

    /// - Parameters:
    ///   - hover: the drag drawn over the card (tests, previews).
    ///   - model: what the card shows now (read in `body`).
    public init(
        hover: SendToHover = SendToHover(), model: @escaping @MainActor () -> SendToCardModel,
        actions: SendToCardActions = SendToCardActions()
    ) {
        self.model = model
        self.actions = actions
        self._hover = State(initialValue: hover)
    }

    public var body: some View {
        let model = model()
        WidgetCard(title: Text(L10n.resource("shelf.sendTo.title")), meta: Text(verbatim: model.meta)) {
            if model.isEmpty {
                Text(L10n.resource("shelf.sendTo.noTargets"))
                    .font(theme.font(.readoutLabel))
                    .tracking(theme.tracking(.readoutLabel))
                    .foregroundStyle(theme.color(.ink3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let ask = model.askZone {
                        dropTarget(ask) {
                            SendToAskZone(
                                target: ask, isLit: hover.phase(of: ask) == .hovered,
                                isRefused: hover.phase(of: ask) == .disabled, modifiers: hover.modifiers)
                        }
                        SendToDetailRows(
                            details: ask.summary.details, modifiers: hover.modifiers,
                            reactsToModifiers: hover.zoneID == ask.id && ask.accepts(hover.contentTypes)
                        )
                        .padding(.top, SendToMetrics.rowsTop)
                    }
                    Spacer(minLength: theme.spacing(.miniZoneGap))
                    VStack(spacing: theme.spacing(.miniZoneGap)) {
                        ForEach(model.miniZones) { target in
                            dropTarget(target) { DropMiniZone(zone: target.zone, phase: hover.phase(of: target)) }
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .keepingTitle()
    }

    @ViewBuilder
    private func dropTarget(_ target: SendToTarget, @ViewBuilder content: () -> some View) -> some View {
        if interactive {
            content().onDrop(
                of: [.fileURL],
                delegate: SendToDropDelegate(target: target, hover: $hover, actions: actions))
        } else {
            content()
        }
    }
}

/// The 84px Ask AI zone of the card.
struct SendToAskZone: View {
    @Environment(\.vigieTheme) private var theme
    @State private var breathing = false
    let target: SendToTarget
    let isLit: Bool
    /// Hovered by a drag it does not take: dimmed.
    let isRefused: Bool
    let modifiers: EventModifiers

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        VStack(spacing: SendToMetrics.askGap) {
            plus
            if isLit {
                Text(target.zone.releaseLine ?? target.zone.label)
                    .font(theme.font(.kicker))
                    .tracking(theme.tracking(.kicker))
                    .textCase(.uppercase)
                    .foregroundStyle(accentText)
                if let line = SendToCardModel.releaseTarget(target.summary.details, modifiers: modifiers) {
                    Text(verbatim: line)
                        .font(ShelfTabMetrics.font(theme, .prose, size: SendToMetrics.sentenceSize))
                        .foregroundStyle(theme.color(.ink1))
                }
            } else {
                Text(target.zone.label)
                    .font(theme.font(.kicker))
                    .tracking(theme.tracking(.kicker))
                    .textCase(.uppercase)
                    .foregroundStyle(accentText)
                Text(L10n.resource("shelf.sendTo.askAI.sentence"))
                    .font(ShelfTabMetrics.font(theme, .prose, size: SendToMetrics.sentenceSize))
                    .foregroundStyle(theme.color(.ink3))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(SendToMetrics.minScale)
        .multilineTextAlignment(.center)
        .padding(.horizontal, theme.spacing(.glyphGap))
        .frame(maxWidth: .infinity)
        .frame(height: theme.componentLength("send-to-card", "ask-zone-height") ?? ShelfTabMetrics.askZoneHeight)
        .background(shape.fill(fill))
        .overlay(border(shape))
        .opacity(isRefused ? DropMiniZone.disabledOpacity : 1)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(target.zone.accessibilityLabel))
        .accessibilityAddTraits(isLit ? .isSelected : [])
    }

    private var radius: CGFloat { theme.usesCornerMarks ? 0 : theme.radius(.zone) }
    private var accent: Color { theme.color(theme.usesCornerMarks ? .gold : target.zone.accent) }
    private var accentText: Color { theme.color(theme.usesCornerMarks ? .goldText : target.zone.accent) }

    /// Breathes on `calm-pulse` in A dark looks while loops run; static when lit, in light, in C, in Calm and
    /// under Reduce motion (UX-DR32, UX-DR96).
    private var breathes: Bool { !isLit && !theme.usesCornerMarks && !theme.isLight && theme.loopsEnabled }

    private var plus: some View {
        let side = ShelfTabMetrics.plusTarget
        return ZStack {
            if isLit { Circle().fill(accent.opacity(DropMetrics.plusLitFill)) }
            Circle().strokeBorder(
                isLit ? accent : accent.opacity(DropMetrics.plusRing), lineWidth: theme.a11y.hairlineWidth)
            PlusMark()
                .stroke(accentText, style: StrokeStyle(lineWidth: theme.a11y.hairlineWidth, lineCap: .round))
                .frame(width: SendToMetrics.plusMark, height: SendToMetrics.plusMark)
        }
        .frame(width: side, height: side)
        .opacity(breathes && breathing ? DropMetrics.plusRing + DropMetrics.plusLitFill : 1)
        .onAppear {
            guard breathes else { return }
            withAnimation(theme.loopAnimation(.calmPulse, autoreverses: true)) { breathing = true }
        }
        .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        if isLit {
            if theme.usesCornerMarks {
                return AnyShapeStyle(
                    LinearGradient(
                        colors: [accent.opacity(DropMetrics.litGoldStart), accent.opacity(DropMetrics.litGoldEnd)],
                        startPoint: .leading, endPoint: .trailing))
            }
            return AnyShapeStyle(
                RadialGradient(
                    colors: [accent.opacity(DropMetrics.litTintCenter), accent.opacity(DropMetrics.litTintEdge)],
                    center: .center, startRadius: 0, endRadius: SendToMetrics.tintRadius))
        }
        if theme.usesCornerMarks { return AnyShapeStyle(Color.clear) }
        return AnyShapeStyle(
            RadialGradient(
                colors: [accent.opacity(DropMetrics.targetTint), accent.opacity(0)], center: .center, startRadius: 0,
                endRadius: SendToMetrics.tintRadius))
    }

    @ViewBuilder
    private func border(_ shape: RoundedRectangle) -> some View {
        let width = theme.a11y.hairlineWidth
        if isLit {
            ZStack {
                if !theme.usesCornerMarks && !theme.isLight && theme.a11y.haloEnabled {
                    shape.strokeBorder(accent.opacity(DropMetrics.litHalo), lineWidth: DropMetrics.litHaloWidth)
                }
                shape.strokeBorder(accent, lineWidth: width)
            }
        } else {
            shape.strokeBorder(
                theme.accentBorderColor(
                    theme.usesCornerMarks ? .gold : target.zone.accent,
                    opacity: theme.usesCornerMarks ? DropMetrics.targetBorderC : DropMetrics.targetBorderA),
                style: StrokeStyle(lineWidth: width, dash: DropMetrics.dash))
        }
    }
}

/// `AGENT Claude Code` / `FOLDER File's folder` / `⌥ FOLDER ~/Code` on a 58px label column. While a drag the
/// zone takes hovers it, rows follow the modifiers: a `dimmedWhile` row dims, a `litWhile` row lights.
struct SendToDetailRows: View {
    @Environment(\.vigieTheme) private var theme
    let details: [DropZoneDetail]
    let modifiers: EventModifiers
    let reactsToModifiers: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SendToMetrics.rowGap) {
            ForEach(details) { detail in
                HStack(alignment: .firstTextBaseline, spacing: SendToMetrics.rowGap) {
                    Text(detail.label)
                        .font(theme.font(.readoutLabel))
                        .tracking(theme.tracking(.readoutLabel))
                        .textCase(.uppercase)
                        .foregroundStyle(isLit(detail) ? accentText : theme.color(.ink3))
                        .frame(width: SendToMetrics.labelColumn, alignment: .leading)
                    Text(verbatim: detail.value)
                        .font(ShelfTabMetrics.font(theme, .prose, size: SendToMetrics.valueSize))
                        .foregroundStyle(isLit(detail) ? accentText : theme.color(.ink1))
                        .truncationMode(.middle)
                }
                .lineLimit(1)
                .opacity(isDimmed(detail) ? SendToMetrics.dimmedRow : 1)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SendToMetrics.rowInset)
    }

    private var accentText: Color { theme.color(theme.usesCornerMarks ? .goldText : .iris2) }

    private func isLit(_ detail: DropZoneDetail) -> Bool {
        guard reactsToModifiers, case .litWhile = detail.emphasis else { return false }
        return detail.isActive(modifiers: modifiers)
    }

    private func isDimmed(_ detail: DropZoneDetail) -> Bool {
        guard reactsToModifiers, case .dimmedWhile = detail.emphasis else { return false }
        return !detail.isActive(modifiers: modifiers)
    }
}

/// Hover, ⌥ and release on one zone of the card. A stash item from the rows carries its type through
/// ``SendToCardActions/internalDragTypes``; a Finder drag counts as plain data unless it declares an image or
/// PDF.
struct SendToDropDelegate: DropDelegate {
    let target: SendToTarget
    @Binding var hover: SendToHover
    let actions: SendToCardActions

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: target.accepts(hover.contentTypes) ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) {
        if hover.zoneID == target.id { hover = SendToHover() }
    }

    func performDrop(info: DropInfo) -> Bool {
        let types = contentTypes(info)
        let modifiers: EventModifiers = NSEvent.modifierFlags.contains(.option) ? .option : []
        hover = SendToHover()
        guard target.accepts(types) else { return false }
        if actions.internalDragTypes() != nil {
            actions.drop(target.id, .stashItem, modifiers)
            return true
        }
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        let zoneID = target.id
        let drop = actions.drop
        Task { @MainActor in
            let urls = await Self.fileURLs(providers)
            guard !urls.isEmpty else { return }
            drop(zoneID, .files(urls), modifiers)
        }
        return true
    }

    private func update(_ info: DropInfo) {
        let next = SendToHover(
            zoneID: target.id, contentTypes: contentTypes(info),
            optionHeld: NSEvent.modifierFlags.contains(.option))
        if hover != next { hover = next }
    }

    private func contentTypes(_ info: DropInfo) -> [UTType] {
        if let types = actions.internalDragTypes() { return types }
        for type in [UTType.image, .pdf] where info.hasItemsConforming(to: [type]) { return [type] }
        return [.data]
    }

    /// The file URLs of the providers, in order.
    static func fileURLs(_ providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
            if let url, url.isFileURL { urls.append(url) }
        }
        return urls
    }
}

/// Layout numbers of the `SEND TO` card not carried by `components.send-to-card` (mockup `.cfg`, `.az`).
enum SendToMetrics {
    /// The Ask AI zone: gap between `+`, label and sentence; sentence 10px; the `+` stroke 12px.
    static let askGap: CGFloat = 7
    static let sentenceSize: CGFloat = 10
    static let plusMark: CGFloat = 11
    static let minScale: CGFloat = 0.8
    static let tintRadius: CGFloat = 90
    /// Rows: 12px under the zone, 58px label column, 8px gaps, value 11px; a dimmed row at 45%.
    static let rowsTop: CGFloat = 12
    static let labelColumn: CGFloat = 58
    static let rowGap: CGFloat = 8
    static let valueSize: CGFloat = 11
    static let rowInset: CGFloat = 2
    static let dimmedRow = 0.45
}
