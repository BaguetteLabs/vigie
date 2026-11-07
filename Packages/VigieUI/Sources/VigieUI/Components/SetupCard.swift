import SwiftUI

/// In-tab setup card (DESIGN "Setup card", UX-DR23) for a module that cannot work, e.g. calendar access not
/// granted: centred, at most 380px wide, neutral 1px inner outline (platinum 16% dark, graphite 14% light),
/// 2.5% fill, an `i`-in-square mark, a `SETUP · <topic>` kicker, a title, one sentence and two buttons
/// (System Settings and the module's pane). No status glyph or hue.
public struct SetupCard: View {
    @Environment(\.vigieTheme) private var theme
    private let topic: LocalizedStringResource
    private let title: LocalizedStringResource
    private let sentence: LocalizedStringResource
    private let primary: ActionButton
    private let secondary: ActionButton

    public init(
        topic: LocalizedStringResource,
        title: LocalizedStringResource,
        sentence: LocalizedStringResource,
        primary: ActionButton,
        secondary: ActionButton
    ) {
        self.topic = topic
        self.title = title
        self.sentence = sentence
        self.primary = primary
        self.secondary = secondary
    }

    /// A setup card from ``VigieCopy`` (topic, title, sentence and button labels).
    public init(
        _ copy: VigieCopy.Setup,
        primaryShortcut: String? = nil,
        secondaryShortcut: String? = nil,
        primaryAction: @escaping @MainActor () -> Void,
        secondaryAction: @escaping @MainActor () -> Void
    ) {
        self.init(
            topic: copy.topic, title: copy.title, sentence: copy.sentence,
            primary: ActionButton(
                label: copy.primaryAction, shortcut: primaryShortcut, role: .primary, action: primaryAction),
            secondary: ActionButton(label: copy.secondaryAction, shortcut: secondaryShortcut, action: secondaryAction))
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius(.setupCard), style: .continuous)
        let maxWidth = theme.componentLength("setup-card", "max-width") ?? ComponentMetrics.setupMaxWidth
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.spacing(.actionGap)) {
                Image(systemName: "info.square")
                    .resizable()
                    .scaledToFit()
                    .frame(width: ComponentMetrics.infoMark, height: ComponentMetrics.infoMark)
                    .accessibilityHidden(true)
                Text(verbatim: VigieCopy.setupKicker(topic: String(localized: topic)))
                    .font(theme.font(.kicker))
                    .tracking(theme.tracking(.kicker))
            }
            .foregroundStyle(theme.color(.ink2))
            Text(title)
                .font(theme.font(.peekTitle))
                .foregroundStyle(theme.color(.ink1))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, theme.spacing(.cardPaddingY))
                .accessibilityAddTraits(.isHeader)
            Text(sentence)
                .font(theme.font(.prose))
                .foregroundStyle(theme.color(.ink2))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, theme.spacing(.actionGap))
            HStack(spacing: theme.spacing(.actionGap)) {
                primary
                secondary
            }
            .fixedSize()
            .padding(.top, theme.spacing(.gridPaddingX))
        }
        .padding(theme.componentInsets("setup-card", "padding") ?? EdgeInsets())
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(theme.color(.ink1).opacity(ComponentMetrics.setupFill), in: shape)
        .overlay {
            if theme.usesCornerMarks {
                CornerMarks()
                    .stroke(
                        theme.color(.structure).opacity(ComponentMetrics.cornerMarkOpacity),
                        lineWidth: ComponentMetrics.hairline)
            } else {
                shape.strokeBorder(
                    theme.accessibility.increaseContrast
                        ? theme.color(.ink3)
                        : theme.color(.ink1).opacity(ComponentMetrics.setupOutline(theme.look)),
                    lineWidth: ComponentMetrics.hairline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Setup card · dark") {
    SetupCardPreview(look: .dark)
}

#Preview("Setup card · light") {
    SetupCardPreview(look: .light)
}

private struct SetupCardPreview: View {
    let look: Look

    var body: some View {
        let theme = PreviewThemes.theme(look)
        SetupCard(VigieCopy.calendarAccess, primaryAction: {}, secondaryAction: {})
            .frame(
                width: theme.componentLength("expanded-panel", "width"),
                height: theme.componentLength("home-grid", "card-height").map { $0 * 2 }
            )
            .background(theme.color(.surfacePanel))
            .vigieTheme(theme)
    }
}
