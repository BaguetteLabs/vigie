import SwiftUI

/// The drag-only drop display (DESIGN "Drop display", UX-DR83, Story 9.1): `components.drop-display`
/// (700 × 196), flush top with `rounded.peek` bottom corners, the 34px black band (`DROP · 1 ITEM` left,
/// `ESC · CANCEL` right), then the zone grid laid out by the Notch Host (layout B: Stash 2 × 2, Ask AI 1 × 2,
/// AirDrop and Image to Text 1 × 1 stacked; hidden zones reflow).
///
/// The view only draws: the host owns the drag, the hovered zone and the drop. `model.isRevealed` grows the
/// display out of the band over `motion.drop-display-grow` and retracts it over `motion.exit`; both are instant
/// under Reduce motion. The rim is static (no shimmer), so Calm and Reduce motion need no change.
public struct DropDisplayView: View {
    @Environment(\.vigieTheme) private var theme
    private let model: DropDisplayModel
    private let bandTheme: Theme?

    /// - Parameter bandTheme: the theme for the black band (the island's dark look); nil uses the environment.
    public init(model: DropDisplayModel, bandTheme: Theme? = nil) {
        self.model = model
        self.bandTheme = bandTheme
    }

    public var body: some View {
        let size = theme.dropDisplaySize
        let band = theme.spacing(.bandHeight)
        let shape = IslandShape(radius: theme.radius(.peek))
        let shadow = theme.dropDisplayShadow
        let frames = DropDisplayGeometry.zoneFrames(model.layout, theme: theme)
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                theme.color(.band).frame(height: band)
                theme.color(.surfacePanel)
            }
            DropDisplayRim()
            DropBand(itemCount: model.itemCount)
                .vigieTheme(bandTheme ?? theme)
            ForEach(model.zones) { zone in
                if let frame = frames[zone.id] {
                    DropZoneCell(
                        zone: zone, isLit: model.isLit(zone.id), isHovered: model.hoveredZoneID == zone.id,
                        optionHeld: model.optionHeld
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(shape)
        .mask(alignment: .top) {
            Rectangle().frame(height: !theme.a11y.motionEnabled || model.isRevealed ? size.height : band)
        }
        .opacity(!theme.a11y.motionEnabled && !model.isRevealed ? 0 : 1)
        .animation(revealAnimation, value: model.isRevealed)
        .shadow(color: theme.color(.shadow).opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
        .accessibilityElement(children: .contain)
    }

    /// Grow over `motion.drop-display-grow`, retract over `motion.exit`; instant under Reduce motion.
    private var revealAnimation: Animation? {
        model.isRevealed
            ? theme.animation(.dropDisplayGrow, curve: .easeOut)
            : theme.animation(.exit, curve: .easeIn)
    }
}

/// The black band: `DROP · <N> ITEM(S)` (count in `ink-2`, the rest `ink-3`) and `ESC · CANCEL`, readout-label
/// style, `drop-band-padding-x` from the edges.
struct DropBand: View {
    @Environment(\.vigieTheme) private var theme
    let itemCount: Int

    var body: some View {
        HStack(spacing: 0) {
            (Text(verbatim: DropDisplayModel.bandPrefix() + " ").foregroundStyle(theme.color(.ink3))
                + Text(verbatim: DropDisplayModel.bandCount(itemCount)).foregroundStyle(theme.color(.ink2)))
            Spacer(minLength: theme.spacing(.wingGap))
            Text(verbatim: DropDisplayModel.bandCancel()).foregroundStyle(theme.color(.ink3))
        }
        .font(theme.font(.readoutLabel))
        .tracking(theme.tracking(.readoutLabel))
        .textCase(.uppercase)
        .lineLimit(1)
        .padding(.horizontal, theme.spacing(.dropBandPaddingX))
        .frame(height: theme.spacing(.bandHeight))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The edge: A, the iris rim at half strength (static, no shimmer); C, a struct hairline and corner marks.
struct DropDisplayRim: View {
    @Environment(\.vigieTheme) private var theme

    var body: some View {
        let radius = theme.radius(.peek)
        Group {
            if theme.usesCornerMarks {
                ZStack {
                    IslandRimShape(radius: radius, lineWidth: ComponentMetrics.hairline)
                        .fill(theme.color(.structure).opacity(DropMetrics.structBorder), style: FillStyle(eoFill: true))
                    CornerMarks()
                        .stroke(theme.color(.structure), lineWidth: ComponentMetrics.hairline)
                        .padding(.top, theme.spacing(.bandHeight))
                }
            } else {
                LinearGradient(
                    colors: [theme.color(.iris1), theme.color(.iris2), theme.color(.iris3)],
                    startPoint: .leading, endPoint: .trailing
                )
                .opacity(DropMetrics.rimStrength)
                .mask(
                    IslandRimShape(radius: radius, lineWidth: ComponentMetrics.hairline)
                        .fill(style: FillStyle(eoFill: true)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// One zone: glyph (or the round `+` target), label, then the meta line, the release line while lit, and the
/// modifier hint. Lit = solid accent border + inner tint (A also a 3px inner halo in dark looks).
public struct DropZoneCell: View {
    @Environment(\.vigieTheme) private var theme
    @State private var breathing = false
    let zone: DropDisplayZone
    let isLit: Bool
    let isHovered: Bool
    let optionHeld: Bool

    public init(zone: DropDisplayZone, isLit: Bool, isHovered: Bool = false, optionHeld: Bool = false) {
        self.zone = zone
        self.isLit = isLit
        self.isHovered = isHovered
        self.optionHeld = optionHeld
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: zoneRadius, style: .continuous)
        ZStack {
            shape.fill(fill)
            border(shape)
            VStack(spacing: DropMetrics.glyphGap) {
                mark
                VStack(spacing: DropMetrics.lineGap) {
                    label
                    lines
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, theme.spacing(.glyphGap))
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(zone.accessibilityLabel))
        .accessibilityAddTraits(isLit ? .isSelected : [])
    }

    // MARK: Frame

    private var zoneRadius: CGFloat { theme.usesCornerMarks ? 0 : theme.radius(.zone) }

    /// The accent for borders and tint: A the zone's accent, C gold.
    private var accent: Color { theme.color(theme.usesCornerMarks ? .gold : zone.accent) }
    /// The accent for text: A the zone's accent, C gold text.
    private var accentText: Color { theme.color(theme.usesCornerMarks ? .goldText : zone.accent) }

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
                    center: .center, startRadius: 0, endRadius: DropMetrics.litTintRadius))
        }
        if theme.usesCornerMarks { return AnyShapeStyle(Color.clear) }
        switch zone.style {
        case .target:
            return AnyShapeStyle(
                RadialGradient(
                    colors: [accent.opacity(DropMetrics.targetTint), accent.opacity(0)], center: .center,
                    startRadius: 0, endRadius: DropMetrics.targetTintRadius))
        case .standard:
            let opacity = zone.isPrimary ? DropMetrics.primaryFill : DropMetrics.secondaryFill
            return AnyShapeStyle(theme.color(.ink1).opacity(opacity))
        }
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
        } else if zone.style == .target {
            let opacity = theme.usesCornerMarks ? DropMetrics.targetBorderC : DropMetrics.targetBorderA
            shape.strokeBorder(
                theme.accentBorderColor(theme.usesCornerMarks ? .gold : zone.accent, opacity: opacity),
                style: StrokeStyle(lineWidth: width, dash: DropMetrics.dash))
        } else if theme.usesCornerMarks {
            shape.strokeBorder(theme.borderColor(.structure, opacity: DropMetrics.structBorder), lineWidth: width)
        } else {
            let opacity = zone.isPrimary ? DropMetrics.primaryHairline : DropMetrics.secondaryHairline
            shape.strokeBorder(theme.borderColor(.ink1, opacity: opacity), lineWidth: width)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var mark: some View {
        switch zone.style {
        case .target:
            let side = DropMetrics.plusTarget
            ZStack {
                if isLit { Circle().fill(accent.opacity(DropMetrics.plusLitFill)) }
                Circle().strokeBorder(
                    isLit ? accent : accent.opacity(DropMetrics.plusRing), lineWidth: theme.a11y.hairlineWidth)
                PlusMark().stroke(accentText, style: StrokeStyle(lineWidth: theme.a11y.hairlineWidth, lineCap: .round))
            }
            .frame(width: side, height: side)
            .opacity(breathes && breathing ? DropMetrics.plusRing + DropMetrics.plusLitFill : 1)
            .onAppear {
                guard breathes else { return }
                withAnimation(theme.loopAnimation(.calmPulse, autoreverses: true)) { breathing = true }
            }
            .accessibilityHidden(true)
        case .standard:
            DropGlyph(name: zone.glyph, size: zone.isPrimary ? DropMetrics.primaryGlyph : DropMetrics.secondaryGlyph)
                .foregroundStyle(theme.color(isLit ? .ink1 : .ink2))
        }
    }

    /// The `+` breathes on `calm-pulse` in A dark looks while loops run; static when lit, in light looks, in C,
    /// in Calm presence and under Reduce motion (UX-DR96).
    private var breathes: Bool {
        !isLit && !theme.usesCornerMarks && !theme.isLight && theme.loopsEnabled
    }

    private var label: some View {
        let role: TypographyRole = zone.isPrimary && !theme.usesCornerMarks ? .tab : .cardTitle
        let color: Color =
            isLit
            ? theme.color(.ink1) : zone.style == .target ? accentText : theme.color(zone.isPrimary ? .ink1 : .ink2)
        return Text(zone.label)
            .font(theme.font(role))
            .tracking(theme.tracking(.cardTitle))
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var lines: some View {
        if isLit, let release = zone.releaseLine {
            line(release, role: .cardTitle, color: accentText)
        } else if let meta = zone.meta {
            line(meta, role: metaRole, color: theme.color(.ink3))
        }
        if let hint = zone.hint {
            if isHovered && optionHeld, let active = zone.hintActive {
                line(active, role: metaRole, color: accentText)
            } else {
                line(hint, role: metaRole, color: theme.color(.ink3))
            }
        }
    }

    private var metaRole: TypographyRole { theme.usesCornerMarks ? .rowStatus : .readoutLabel }

    private func line(_ text: LocalizedStringResource, role: TypographyRole, color: Color) -> some View {
        Text(text)
            .font(theme.font(role))
            .tracking(theme.tracking(role))
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
