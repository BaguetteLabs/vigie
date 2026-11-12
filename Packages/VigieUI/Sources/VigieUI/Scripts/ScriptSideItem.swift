import SwiftUI

/// A script's item on the closed notch's left-wing lane (DESIGN "Side-slot item", A22, UX-DR86): the 16px
/// status-vocabulary glyph, then the level (in its hue) over the target (`ink-3`); number and text scripts show
/// their value over their label, no glyph. Static. Value and label scale with the band (``ClosedBandMetrics``);
/// VoiceOver reads "<name>, <level>". Script text is masked under Privacy mode.
public struct ScriptSideItem: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    private let model: ScriptSideItemModel

    public init(model: ScriptSideItemModel) {
        self.model = model
    }

    public var body: some View {
        let shown = model.privacy(privacyActive)
        let band = theme.closedBand
        HStack(spacing: theme.spacing(.glyphGap)) {
            switch shown.content {
            case .level(let level, let target):
                StatusMarkGlyph(
                    level: level, size: .medium, length: band.rowLength(StatusMarkSize.medium.length(in: theme)))
                readout(
                    top: StatusLabelFormatter().label(for: level),
                    topRole: StatusMarkStyle(level: level, look: theme.look).labelRole, bottom: target)
            case .value(let value, let label, _):
                readout(top: value, topRole: .ink1, bottom: label)
            case .state(let text):
                readout(top: shown.name, topRole: .ink2, bottom: text)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: shown.accessibilityLabel))
    }

    private func readout(top: String, topRole: ColorRole, bottom: String) -> some View {
        let band = theme.closedBand
        let valueFont = band.fontSpec(.readoutValue, in: theme)
        let labelFont = band.fontSpec(.readoutLabel, in: theme)
        return VStack(alignment: .leading, spacing: band.stackedLength(theme.spacing(.glyphGap) / 2)) {
            Text(verbatim: top)
                .font(valueFont.font)
                .tracking(valueFont.tracking)
                .foregroundStyle(theme.color(topRole))
            Text(verbatim: bottom)
                .font(labelFont.font)
                .tracking(labelFont.tracking)
                .textCase(.uppercase)
                .foregroundStyle(theme.color(.ink3))
        }
        .lineLimit(1)
        .fixedSize()
    }
}

#Preview("Side-slot items") {
    let theme = PreviewThemes.theme(.dark)
    HStack(spacing: theme.spacing(.gridGap)) {
        ScriptSideItem(model: ScriptSideItemModel(name: "vigie.app", content: .level(.ok, target: "vigie.app")))
        ScriptSideItem(model: ScriptSideItemModel(name: "Site", content: .level(.warn, target: "api")))
        ScriptSideItem(
            model: ScriptSideItemModel(name: "GitHub PRs", content: .value("3", label: "open", valueIsText: false)))
    }
    .padding(theme.spacing(.gridPaddingX))
    .background(theme.color(.band))
    .vigieTheme(theme)
}
