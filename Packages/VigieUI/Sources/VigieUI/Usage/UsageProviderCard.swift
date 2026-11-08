import SwiftUI

/// A Usage tab provider card (DESIGN "Usage provider card, meter and pace bar"; UX-DR31; mockup
/// `key-usage-tab.html`): header with the 6-dot grip, the provider name and its meta; then the 58 px dial
/// next to one bar per window, or `READING LOGS…` before the first log read, or `NO PLAN WINDOWS` for a
/// local-logs provider.
struct UsageProviderCard: View {
    @Environment(\.vigieTheme) private var theme
    let model: UsageProviderCardModel
    /// Moves the card one place (-1 up, 1 down); the VoiceOver alternative to dragging the grip. Nil: no drag.
    var onMove: (@MainActor (Int) -> Void)?
    /// Called with the dragged provider id when it is dropped on this card.
    var onDrop: (@MainActor (String) -> Void)?
    @State private var isTargeted = false

    var body: some View {
        card
            .opacity(isTargeted ? UsageTabMetrics.dropOpacity : 1)
            .dropDestination(
                for: String.self,
                action: { items, _ in
                    guard let id = items.first, let onDrop else { return false }
                    onDrop(id)
                    return true
                }, isTargeted: { isTargeted = $0 }
            )
            .accessibilityAction(named: Text(L10n.resource("usage.card.moveUp"))) { onMove?(-1) }
            .accessibilityAction(named: Text(L10n.resource("usage.card.moveDown"))) { onMove?(1) }
    }

    @ViewBuilder private var grip: some View {
        if onDrop != nil {
            GripGlyph().draggable(model.id)
        } else {
            GripGlyph()
        }
    }

    private var card: some View {
        WidgetCard(title: Text(verbatim: model.name), meta: meta, leading: grip) {
            switch model.content {
            case .readingLogs:
                placeholder(VigieCopy.readingLogs.label)
            case .noPlanWindows:
                placeholder(L10n.resource("usage.card.noPlanWindows"))
            case .windows(let dial, let bars):
                HStack(alignment: .center, spacing: UsageTabMetrics.dialGap) {
                    QuotaDialView(model: dial, size: .tab)
                    VStack(alignment: .leading, spacing: UsageTabMetrics.windowGap) {
                        ForEach(bars) { bar in
                            UsageBarRow(model: bar)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    /// `MAX · WARN 80%` with the threshold value in `ink-2`.
    private var meta: Text {
        var text = Text(verbatim: "")
        for (index, part) in model.meta.parts.enumerated() {
            if index > 0 { text = text + Text(verbatim: UsageTabMetrics.separator) }
            text = text + Text(verbatim: part.text)
            if let highlight = part.highlight {
                text = text + Text(verbatim: " ") + Text(verbatim: highlight).foregroundStyle(theme.color(.ink2))
            }
        }
        return text
    }

    private func placeholder(_ label: LocalizedStringResource) -> some View {
        Text(label)
            .font(theme.font(.cardTitle))
            .tracking(theme.tracking(.cardTitle))
            .foregroundStyle(theme.color(.ink3))
            .frame(maxWidth: .infinity, minHeight: QuotaDialSize.tab.length(in: theme))
    }
}

/// One window: `5H  62%  RESET 16:40 · IN 1H52`, the bar, then `ELAPSED 63%` and the pace label.
struct UsageBarRow: View {
    @Environment(\.vigieTheme) private var theme
    let model: UsageBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.actionGap)) {
                Text(verbatim: model.label)
                    .font(theme.font(.rowStatus))
                    .tracking(theme.tracking(.rowStatus))
                    .foregroundStyle(theme.color(.ink2))
                    .frame(width: UsageTabMetrics.windowLabelWidth, alignment: .leading)
                Text(verbatim: L10n.format("usage.bar.value", model.window.percent))
                    .font(theme.font(.readoutValue))
                    .tracking(theme.tracking(.readoutValue))
                    .foregroundStyle(theme.color(theme.defines(.structure) ? .goldText : .ink1))
                    .monospacedDigit()
                Spacer(minLength: theme.spacing(.glyphGap))
                if let reset = model.reset {
                    (Text(L10n.resource("usage.bar.reset")) + Text(verbatim: " ")
                        + Text(verbatim: reset.time).foregroundStyle(theme.color(.ink2))
                        + Text(verbatim: UsageTabMetrics.separator)
                        + Text(verbatim: L10n.format("usage.bar.in", reset.remaining)))
                        .font(theme.font(.readoutLabel))
                        .tracking(theme.tracking(.readoutLabel) * UsageTabMetrics.resetTrackingScale)
                        .foregroundStyle(theme.color(.ink3))
                        .layoutPriority(1)
                }
            }
            .lineLimit(1)
            UsagePaceBar(model: model)
                .padding(.top, UsageTabMetrics.barSpacing)
            HStack(spacing: theme.spacing(.glyphGap)) {
                if let elapsed = model.elapsedText {
                    Text(verbatim: elapsed).foregroundStyle(theme.color(.ink3))
                }
                Spacer(minLength: theme.spacing(.glyphGap))
                if let label = model.paceLabel {
                    paceLabel(label)
                }
            }
            .font(theme.font(.readoutLabel))
            .tracking(theme.tracking(.readoutLabel))
            .lineLimit(1)
            .padding(.top, UsageTabMetrics.paceLineSpacing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: model.accessibilityLabel))
    }

    @ViewBuilder private func paceLabel(_ label: UsagePaceLabel) -> some View {
        switch label {
        case .warning:
            let hue = theme.color(theme.look == .light ? .quotaWarningText : .quotaWarning)
            HStack(spacing: theme.spacing(.glyphGap) / 2) {
                WarningTriangle().fill(theme.color(.quotaWarning))
                    .frame(width: UsageTabMetrics.triangle, height: UsageTabMetrics.triangle)
                Text(verbatim: label.text).foregroundStyle(hue)
            }
        case .ahead:
            Text(verbatim: label.text).foregroundStyle(theme.color(.paceAhead))
        case .within:
            Text(verbatim: label.text).foregroundStyle(theme.color(.ink2))
        }
    }
}

/// The bar (`.pb`): a 4 px `line` track, the fill per state, the dashed threshold tick in `ink-2` and the 2 px
/// pace marker (A `ink-1`, C `gold-text`) with a keyline in the card colour.
struct UsagePaceBar: View {
    @Environment(\.vigieTheme) private var theme
    let model: UsageBarModel

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let track = Capsule()
            ZStack(alignment: .topLeading) {
                track.fill(theme.trackColor())
                    .frame(height: UsageTabMetrics.barHeight)
                    .offset(y: UsageTabMetrics.barTop)
                fill
                    .frame(width: max(0, width * model.window.fraction), height: UsageTabMetrics.barHeight)
                    .clipShape(track)
                    .offset(y: UsageTabMetrics.barTop)
                thresholdTick
                    .offset(
                        x: width * model.thresholdFraction - UsageTabMetrics.thresholdWidth / 2,
                        y: UsageTabMetrics.thresholdTop)
                if let marker = model.markerFraction {
                    RoundedRectangle(cornerRadius: UsageTabMetrics.markerWidth / 2)
                        .fill(theme.color(theme.defines(.structure) ? .goldText : .ink1))
                        .frame(width: UsageTabMetrics.markerWidth, height: UsageTabMetrics.barBoxHeight)
                        .background(
                            RoundedRectangle(cornerRadius: UsageTabMetrics.markerWidth)
                                .fill(theme.color(.surfaceCard))
                                .padding(-UsageTabMetrics.markerKeyline)
                        )
                        .offset(x: width * marker - UsageTabMetrics.markerWidth / 2)
                }
            }
        }
        .frame(height: UsageTabMetrics.barBoxHeight)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var fill: some View {
        switch model.fill {
        case .warning:
            let pattern = HatchPattern(theme: theme)
            let hue = theme.color(.quotaWarning)
            ZStack {
                Rectangle().fill(hue.opacity(pattern.lightAlpha))
                HatchStripes(pattern: pattern).fill(hue)
            }
        case .ahead:
            Rectangle().fill(theme.color(.paceAhead))
        case .metal(let secondary):
            Rectangle().fill(UsageFills.metal(theme, secondary: secondary))
        }
    }

    private var thresholdTick: some View {
        Path { path in
            path.move(to: CGPoint(x: UsageTabMetrics.thresholdWidth / 2, y: 0))
            path.addLine(to: CGPoint(x: UsageTabMetrics.thresholdWidth / 2, y: UsageTabMetrics.thresholdHeight))
        }
        .stroke(
            theme.color(.ink2),
            style: StrokeStyle(lineWidth: UsageTabMetrics.thresholdWidth, dash: UsageTabMetrics.thresholdDash)
        )
        .frame(width: UsageTabMetrics.thresholdWidth, height: UsageTabMetrics.thresholdHeight)
    }
}

/// The usage metal fills shared by bars and the history chart (DESIGN "Pace and quota-warning colors"): A
/// within pace = `line-silver → pace-on` (platinum on bars), the secondary series `ink-3 → line-silver`; C
/// `pace-on` Volt (the secondary dimmed); Calm flat `ink-2` (C `struct`); flat under Reduce transparency /
/// Increase contrast.
enum UsageFills {
    static func metal(_ theme: Theme, secondary: Bool) -> AnyShapeStyle {
        let tactical = theme.defines(.structure)
        if theme.presence == .calm { return AnyShapeStyle(theme.color(tactical ? .structure : .ink2)) }
        if tactical {
            return AnyShapeStyle(
                theme.color(.paceOn).opacity(secondary ? UsageTabMetrics.secondarySeriesOpacity : 1))
        }
        let colors: [ColorRole] = secondary ? [.ink3, .lineSilver] : [.lineSilver, .paceOn]
        return theme.glassFill(
            LinearGradient(colors: colors.map(theme.color), startPoint: .leading, endPoint: .trailing),
            flat: secondary ? .lineSilver : .paceOn)
    }
}
