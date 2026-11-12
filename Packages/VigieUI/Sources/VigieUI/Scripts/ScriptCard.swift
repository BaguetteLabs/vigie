import SwiftUI

/// A script's Home card (DESIGN "Script widget", UX-DR86): the shared card frame at `components.script-card`
/// (222 × 138), header `NAME · TARGET` left and the cadence right, the body per type and state, the meta line in
/// `ink-3` (the WARN triangle first while the latest run failed). Relative times count from `now`, else from a
/// minute timeline.
///
/// A click on the body runs the output's action (`onActivate`); `NOT CONFIRMED` runs `onReview`.
public struct ScriptCard: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    @Environment(\.timeZone) private var timeZone
    private let model: ScriptCardModel
    private let now: Date?
    private let onActivate: (@MainActor () -> Void)?
    private let onReview: @MainActor () -> Void

    public init(
        model: ScriptCardModel, now: Date? = nil, onActivate: (@MainActor () -> Void)? = nil,
        onReview: @escaping @MainActor () -> Void = {}
    ) {
        self.model = model
        self.now = now
        self.onActivate = onActivate
        self.onReview = onReview
    }

    public var body: some View {
        if let now {
            card(now: now)
        } else {
            TimelineView(.everyMinute) { context in card(now: context.date) }
        }
    }

    private func card(now: Date) -> some View {
        let shown = model.privacy(privacyActive)
        let size = ScriptCardMetrics.size(theme)
        return WidgetCard(title: Text(verbatim: shown.title), meta: Text(verbatim: shown.cadence)) {
            ScriptCardContent(shown: shown, now: now, onActivate: onActivate, onReview: onReview)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: shown.accessibilityLabel(now: now, timeZone: timeZone)))
    }
}

/// A script card's body and meta line, shared by the Home card and the page hero (Story 12.11). `interactive`
/// false draws the body without its own buttons (the page hero is the one control).
struct ScriptCardContent: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.timeZone) private var timeZone
    let shown: ScriptCardModel
    let now: Date
    var interactive = true
    var onActivate: (@MainActor () -> Void)?
    var onReview: @MainActor () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.rowGap)) {
            content
            Spacer(minLength: 0)
            metaLine
        }
    }

    @ViewBuilder private var content: some View {
        switch shown.body {
        case .output(let content):
            if interactive, let onActivate, let action = shown.action {
                Button(action: onActivate) {
                    ScriptWidgetBody(content).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(verbatim: action.hint))
            } else {
                ScriptWidgetBody(content)
            }
        case .notConfirmed:
            if interactive {
                ScriptStateLabel(action: onReview)
            } else {
                stateText(ScriptStateLabel.notConfirmedText)
            }
        case .state(let text):
            stateText(text)
        }
    }

    private func stateText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(theme.font(.rowStatus))
            .tracking(theme.tracking(.rowStatus))
            .foregroundStyle(theme.color(.ink3))
            .lineLimit(1)
    }

    @ViewBuilder private var metaLine: some View {
        if shown.meta != nil || shown.warningBadge {
            HStack(spacing: theme.spacing(.glyphGap) / 2) {
                if shown.warningBadge {
                    StatusMarkGlyph(level: .warn, size: .small)
                }
                if let meta = shown.meta {
                    Text(verbatim: meta.text(now: now, timeZone: timeZone))
                        .font(theme.font(.cardTitle))
                        .tracking(theme.tracking(.cardTitle))
                        .foregroundStyle(theme.color(.ink3))
                        .lineLimit(1)
                }
            }
        }
    }
}

/// The script card's size from the theme (`components.script-card`); DESIGN values when a theme lacks it.
public enum ScriptCardMetrics {
    public static func size(_ theme: Theme) -> CGSize {
        CGSize(
            width: theme.componentLength("script-card", "width") ?? 222,
            height: theme.componentLength("script-card", "height") ?? 138)
    }
}

#Preview("Script cards · dark") {
    ScriptCardPreview(look: .dark)
}

#Preview("Script cards · light") {
    ScriptCardPreview(look: .light)
}

private struct ScriptCardPreview: View {
    let look: Look

    var body: some View {
        let theme = PreviewThemes.theme(look)
        let now = Date.now
        HStack(spacing: theme.spacing(.gridGap)) {
            ScriptCard(
                model: ScriptCardModel(
                    name: "Site", target: "vigie.app", cadence: "EVERY 1M",
                    body: .output(.status(level: .ok, qualifier: "UP", value: "200 · 142 ms")),
                    meta: .checked(now)), now: now)
            ScriptCard(
                model: ScriptCardModel(
                    name: "GitHub PRs", cadence: "EVERY 5M",
                    body: .output(
                        .number(
                            value: "3", label: "open", detail: "2 awaiting review",
                            bar: ScriptNumberBar(value: 3), level: nil)),
                    meta: .updated(now), warningBadge: true), now: now)
            ScriptCard(model: ScriptCardModel(name: "Release", cadence: "EVERY 1H", body: .notConfirmed), now: now)
        }
        .padding(theme.spacing(.gridPaddingX))
        .background(theme.color(.surfacePanel))
        .vigieTheme(theme)
    }
}
