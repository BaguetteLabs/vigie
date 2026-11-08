import SwiftUI

/// A 38px mini drop zone at the bottom of the Shelf tab's `SEND TO` card (DESIGN "Shelf tab", Stories 9.7–9.9):
/// glyph and label on the left, meta on the right (`SHARE`, `COPY`, `LAST · 3 LINES · 14:48`).
///
/// A: `rounded.mini-zone`, 2% fill, 1px hairline at 8%, label tracked caps in `ink-2`, meta in `ink-3`. C: square,
/// struct inner border at 22%, label in `card-title` style, meta in `row-status` (SF Mono). Drag-hover follows
/// the drop-zone rule: lit (solid accent border, inner tint, release line in place of the meta) when it takes
/// the item; `disabled` (dimmed, no accent) when it does not. A zone whose setting is off is not drawn at all:
/// the caller leaves it out.
public struct DropMiniZone: View {
    /// What the zone shows during (or outside) a drag.
    public enum Phase: Hashable, Sendable {
        /// No drag over the zone.
        case idle
        /// A drag over the card that the zone takes (lit, meta kept).
        case lit
        /// A drag hovering the zone that it takes (lit, release line).
        case hovered
        /// A drag the zone does not take: dimmed.
        case disabled
    }

    @Environment(\.vigieTheme) private var theme
    let zone: DropDisplayZone
    let phase: Phase

    public init(zone: DropDisplayZone, phase: Phase = .idle) {
        self.zone = zone
        self.phase = phase
    }

    /// `components.send-to-card.mini-zone-height` (38px).
    public static func height(_ theme: Theme) -> CGFloat {
        theme.componentLength("send-to-card", "mini-zone-height") ?? fallbackHeight
    }

    static let fallbackHeight: CGFloat = 38
    /// Glyph size in the mini zone.
    static let glyph: CGFloat = 12
    /// A fill and hairline (DESIGN: 2% fill, 8% hairline); dimmed opacity of a disabled zone.
    static let fill = 0.02
    static let hairline = 0.08
    static let disabledOpacity = 0.4
    /// Lit inner tint (accent).
    static let litFill = 0.12

    var isLit: Bool { phase == .lit || phase == .hovered }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        HStack(spacing: theme.spacing(.glyphGap)) {
            DropGlyph(name: zone.glyph, size: Self.glyph)
                .foregroundStyle(theme.color(isLit ? .ink1 : .ink2))
            Text(zone.label)
                .font(theme.font(labelRole))
                .tracking(theme.tracking(labelRole))
                .textCase(.uppercase)
                .foregroundStyle(theme.color(isLit ? .ink1 : .ink2))
            Spacer(minLength: theme.spacing(.glyphGap))
            if let line = trailingLine {
                Text(line)
                    .font(theme.font(metaRole))
                    .tracking(theme.tracking(metaRole))
                    .textCase(.uppercase)
                    .foregroundStyle(phase == .hovered ? accentText : theme.color(.ink3))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, theme.spacing(.cardPaddingX))
        .frame(height: Self.height(theme))
        .frame(maxWidth: .infinity)
        .background(shape.fill(fillStyle))
        .overlay(border(shape))
        .opacity(phase == .disabled ? Self.disabledOpacity : 1)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(zone.accessibilityLabel))
        .accessibilityValue(zone.meta.map { Text($0) } ?? Text(verbatim: ""))
        .accessibilityHint(phase == .disabled ? Text(L10n.resource("drop.mini.disabled")) : Text(verbatim: ""))
        .accessibilityAddTraits(isLit ? .isSelected : [])
    }

    /// The meta, or the release line while hovered.
    var trailingLine: LocalizedStringResource? {
        if phase == .hovered, let release = zone.releaseLine { return release }
        return zone.meta
    }

    private var radius: CGFloat { theme.usesCornerMarks ? 0 : theme.radius(.miniZone) }
    private var labelRole: TypographyRole { theme.usesCornerMarks ? .cardTitle : .readoutLabel }
    private var metaRole: TypographyRole { theme.usesCornerMarks ? .rowStatus : .readoutLabel }
    private var accent: Color { theme.color(theme.usesCornerMarks ? .gold : zone.accent) }
    private var accentText: Color { theme.color(theme.usesCornerMarks ? .goldText : zone.accent) }

    private var fillStyle: AnyShapeStyle {
        if isLit {
            return AnyShapeStyle(accent.opacity(Self.litFill))
        }
        if theme.usesCornerMarks { return AnyShapeStyle(Color.clear) }
        return AnyShapeStyle(theme.color(.ink1).opacity(Self.fill))
    }

    @ViewBuilder
    private func border(_ shape: RoundedRectangle) -> some View {
        let width = theme.a11y.hairlineWidth
        if isLit {
            shape.strokeBorder(accent, lineWidth: width)
        } else if theme.usesCornerMarks {
            shape.strokeBorder(theme.borderColor(.structure, opacity: DropMetrics.structBorder), lineWidth: width)
        } else {
            shape.strokeBorder(theme.borderColor(.ink1, opacity: Self.hairline), lineWidth: width)
        }
    }
}

/// The `SEND TO` card's mini zones, top to bottom, `spacing.mini-zone-gap` apart (AirDrop, then Image to Text).
/// Zones left out (setting off, module off) are simply not passed.
public struct DropMiniZoneStack: View {
    @Environment(\.vigieTheme) private var theme
    let zones: [DropDisplayZone]
    let phase: (String) -> DropMiniZone.Phase

    public init(zones: [DropDisplayZone], phase: @escaping (String) -> DropMiniZone.Phase = { _ in .idle }) {
        self.zones = zones
        self.phase = phase
    }

    public var body: some View {
        VStack(spacing: theme.spacing(.miniZoneGap)) {
            ForEach(zones) { zone in
                DropMiniZone(zone: zone, phase: phase(zone.id))
            }
        }
    }
}

#Preview("Mini zones") {
    let theme = PreviewThemes.theme(.dark)
    let airdrop = DropDisplayZone(
        id: "airdrop", label: "AirDrop", glyph: "drop.airdrop", accent: .iris2, style: .standard, isPrimary: false,
        meta: "SHARE", releaseLine: "RELEASE TO SHARE", accessibilityLabel: "AirDrop")
    let image = DropDisplayZone(
        id: "image", label: "Image to Text", glyph: "drop.image-to-text", accent: .iris2, style: .standard,
        isPrimary: false, meta: "COPY", releaseLine: "RELEASE TO COPY TEXT", accessibilityLabel: "Image to Text")
    DropMiniZoneStack(zones: [airdrop, image]) { $0 == "airdrop" ? .hovered : .disabled }
        .frame(width: 212)
        .padding(theme.spacing(.gridPaddingX))
        .background(theme.color(.surfaceCard))
        .vigieTheme(theme)
}
