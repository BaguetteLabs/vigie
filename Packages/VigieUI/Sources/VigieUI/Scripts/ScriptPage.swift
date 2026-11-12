import SwiftUI

/// What the page's buttons do; the integrations module supplies them (Story 12.11).
public struct ScriptPageActions {
    /// The hero's output action (`open`, `run`, `copy`).
    public var activate: @MainActor () -> Void
    /// `NOT CONFIRMED`: opens the Script Confirmation.
    public var review: @MainActor () -> Void
    /// `REVEAL`: shows the script file in Finder.
    public var reveal: @MainActor () -> Void
    /// `OPEN SOURCE`: opens the file in the default editor for its type.
    public var openSource: @MainActor () -> Void

    public init(
        activate: @escaping @MainActor () -> Void = {}, review: @escaping @MainActor () -> Void = {},
        reveal: @escaping @MainActor () -> Void = {}, openSource: @escaping @MainActor () -> Void = {}
    ) {
        self.activate = activate
        self.review = review
        self.reveal = reveal
        self.openSource = openSource
    }
}

/// Where keyboard focus is in the page. Tab moves through ``order``: hero → About → runs list → chips (UX-DR86,
/// PRD FR-8); each stop is focusable and `↵` / Space activates it.
public enum ScriptPageFocus: String, Hashable, Sendable, CaseIterable {
    case hero
    case about
    case runs
    case reveal
    case openSource

    /// The Tab order, top to bottom, leading to trailing (the order the views are laid out in).
    public static let order: [ScriptPageFocus] = [.hero, .about, .runs, .reveal, .openSource]

    /// The accessibility identifier of the stop (tests read the order back from the accessibility tree).
    public var accessibilityID: String { "script.page.\(rawValue)" }
}

/// A script's tab (Story 12.11, DESIGN "Script page", UX-DR86, UX-DR87): the `components.script-page` grid
/// (`1fr 212px` × `118px 1fr`) with the hero (the widget at large size) across the top, the Markdown
/// documentation under `ABOUT · FROM <file>` on the left, and the 212px runs card on the right with `REVEAL`
/// and `OPEN SOURCE`. Relative times and the next-run countdown count from `now`, else from a one-second
/// timeline.
public struct ScriptPage: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    @FocusState private var focus: ScriptPageFocus?
    private let model: ScriptPageModel
    private let now: Date?
    private let actions: ScriptPageActions

    public init(model: ScriptPageModel, now: Date? = nil, actions: ScriptPageActions = ScriptPageActions()) {
        self.model = model
        self.now = now
        self.actions = actions
    }

    public var body: some View {
        let shown = model.privacy(privacyActive)
        let grid = ScriptPageMetrics.grid(theme)
        VStack(spacing: theme.spacing(.gridGap)) {
            timed { now in hero(shown, now: now) }
                .frame(height: grid.heroHeight)
            HStack(alignment: .top, spacing: theme.spacing(.gridGap)) {
                about(shown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                timed { now in ScriptRunsCard(model: shown.runs, now: now, focus: $focus, actions: actions) }
                    .frame(width: grid.runsWidth)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, theme.spacing(.gridPaddingX))
        .padding(.top, theme.spacing(.cardPaddingY))
        .padding(.bottom, theme.spacing(.gridPaddingX))
    }

    @ViewBuilder private func timed(@ViewBuilder _ content: @escaping (Date) -> some View) -> some View {
        if let now {
            content(now)
        } else {
            TimelineView(.periodic(from: .now, by: ScriptPageMetrics.tick)) { context in content(context.date) }
        }
    }

    // MARK: Hero

    private func hero(_ shown: ScriptPageModel, now: Date) -> some View {
        let card = shown.hero
        return WidgetCard(title: Text(verbatim: card.title), meta: Text(verbatim: shown.heroMeta)) {
            ScriptCardContent(shown: card, now: now, interactive: false)
        }
        .contentShape(Rectangle())
        .onTapGesture { activateHero(shown) }
        .keyboardSelectionRing(isSelected: focus == .hero)
        .focusable(interactions: .activate)
        .focused($focus, equals: .hero)
        .focusEffectDisabled()
        .onKeyPress(keys: [.return, .space]) { _ in
            guard shown.heroIsActionable else { return .ignored }
            activateHero(shown)
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: shown.heroAccessibilityLabel(now: now)))
        .accessibilityAddTraits(shown.heroIsActionable ? .isButton : [])
        .accessibilityHint(Text(verbatim: heroHint(shown)))
        .accessibilityAction { activateHero(shown) }
        .accessibilityIdentifier(ScriptPageFocus.hero.accessibilityID)
    }

    private func activateHero(_ shown: ScriptPageModel) {
        switch shown.hero.body {
        case .notConfirmed: actions.review()
        case .output where shown.hero.action != nil: actions.activate()
        default: break
        }
    }

    private func heroHint(_ shown: ScriptPageModel) -> String {
        switch shown.hero.body {
        case .notConfirmed: L10n.string("script.state.notConfirmed.hint")
        case .output: shown.hero.action?.hint ?? ""
        case .state: ""
        }
    }

    // MARK: About

    private func about(_ shown: ScriptPageModel) -> some View {
        let blocks = ScriptDocumentationBlock.parse(shown.documentation)
        return WidgetCard(
            title: Text(verbatim: ScriptPageModel.aboutTitle), meta: Text(verbatim: shown.aboutMeta)
        ) {
            ScrollView(.vertical) {
                Group {
                    if blocks.isEmpty {
                        Text(L10n.resource("script.page.about.empty"))
                            .font(theme.font(.cardTitle))
                            .tracking(theme.tracking(.cardTitle))
                            .foregroundStyle(theme.color(.ink3))
                    } else {
                        VStack(alignment: .leading, spacing: theme.spacing(.rowGap)) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                ScriptPageDocumentationBlock(block: block)
                            }
                        }
                        .sensitive()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .keyboardSelectionRing(isSelected: focus == .about)
        .focusable()
        .focused($focus, equals: .about)
        .focusEffectDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: L10n.format("script.page.a11y.about", shown.runs.fileName)))
        .accessibilityIdentifier(ScriptPageFocus.about.accessibilityID)
    }
}

/// One documentation block in the island's prose style (DESIGN "Script page" › About): headings in peek-title
/// style, paragraphs in prose style in `ink-2`, inline Markdown (emphasis, code spans, links) applied.
struct ScriptPageDocumentationBlock: View {
    @Environment(\.vigieTheme) private var theme
    let block: ScriptDocumentationBlock

    var body: some View {
        switch block {
        case .heading(_, let text):
            Text(ScriptDocumentationBlock.attributed(text))
                .font(theme.font(.peekTitle))
                .tracking(theme.tracking(.peekTitle))
                .foregroundStyle(theme.color(.ink1))
        case .paragraph(let text):
            Text(ScriptDocumentationBlock.attributed(text))
                .font(theme.font(.prose))
                .foregroundStyle(theme.color(.ink2))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The 212px runs card (DESIGN "Script page" › Runs): label/value pairs (labels in card-title style, `ink-3`;
/// values in `ink-1` over a mono sub-line in `ink-3`), the runs list (time, duration, result per run), then the
/// `REVEAL` and `OPEN SOURCE` chips.
struct ScriptRunsCard: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.timeZone) private var timeZone
    let model: ScriptRunsCardModel
    let now: Date
    var focus: FocusState<ScriptPageFocus?>.Binding
    let actions: ScriptPageActions

    var body: some View {
        WidgetCard(title: Text(L10n.resource("script.page.runs")), meta: Text(verbatim: model.runtime)) {
            VStack(alignment: .leading, spacing: theme.spacing(.rowGap)) {
                pair(
                    "script.page.lastRun", value: model.lastRun?.timeText(timeZone: timeZone), sub: model.lastRunDetail)
                pair(
                    "script.page.nextRun", value: model.nextRunText(timeZone: timeZone),
                    sub: model.nextRunDetail(now: now))
                pair("script.page.timeout", value: model.timeoutText, sub: nil)
                pair("script.page.source", value: model.fileName, sub: model.folder)
                runsList
                    .frame(maxHeight: .infinity, alignment: .top)
                chips
            }
        }
        .keepingTitle()
    }

    private func pair(_ key: String, value: String?, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.resource(key))
                .font(theme.font(.cardTitle))
                .tracking(theme.tracking(.cardTitle))
                .foregroundStyle(theme.color(.ink3))
            Text(verbatim: value ?? L10n.string("script.page.never"))
                .font(theme.font(.rowPrimary))
                .monospacedDigit()
                .foregroundStyle(theme.color(value == nil ? .ink3 : .ink1))
            if let sub {
                Text(verbatim: sub)
                    .font(theme.font(.code))
                    .foregroundStyle(theme.color(.ink3))
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var runsList: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                if model.runs.isEmpty {
                    Text(L10n.resource("script.page.runs.empty"))
                        .font(theme.font(.cardTitle))
                        .tracking(theme.tracking(.cardTitle))
                        .foregroundStyle(theme.color(.ink3))
                }
                ForEach(Array(model.runs.enumerated()), id: \.offset) { _, run in
                    row(run)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .keyboardSelectionRing(isSelected: focus.wrappedValue == .runs)
        .focusable()
        .focused(focus, equals: .runs)
        .focusEffectDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(L10n.resource("script.page.a11y.runs")))
        .accessibilityIdentifier(ScriptPageFocus.runs.accessibilityID)
    }

    private func row(_ run: ScriptRunRow) -> some View {
        HStack(spacing: theme.spacing(.glyphGap)) {
            Text(verbatim: run.timeText(timeZone: timeZone))
                .foregroundStyle(theme.color(.ink2))
            Text(verbatim: run.durationText)
                .foregroundStyle(theme.color(.ink3))
            Spacer(minLength: 0)
            Text(verbatim: run.result.label)
                .foregroundStyle(theme.color(run.result.isFailure ? .quotaWarning : .ink2))
        }
        .font(theme.font(.code))
        .monospacedDigit()
        .lineLimit(1)
        .padding(.vertical, theme.spacing(.glyphGap) / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: run.accessibilityLabel(timeZone: timeZone)))
    }

    private var chips: some View {
        HStack(spacing: theme.spacing(.glyphGap)) {
            chip(.reveal, key: "script.page.reveal", action: actions.reveal)
            chip(.openSource, key: "script.page.openSource", action: actions.openSource)
        }
    }

    private func chip(_ stop: ScriptPageFocus, key: String, action: @escaping @MainActor () -> Void) -> some View {
        TimeChip(label: L10n.resource(key), action: action)
            .focused(focus, equals: stop)
            .onKeyPress(keys: [.return, .space]) { _ in
                action()
                return .handled
            }
            .accessibilityHint(Text(L10n.resource("\(key).hint")))
            .accessibilityIdentifier(stop.accessibilityID)
    }
}

/// The page grid from `components.script-page` (`1fr 212px` × `118px 1fr`): the fixed runs column width and hero
/// height. DESIGN values when a theme lacks them.
public enum ScriptPageMetrics {
    public struct Grid: Sendable, Equatable {
        public var runsWidth: CGFloat
        public var heroHeight: CGFloat
    }

    /// The countdown's refresh step, in seconds (`in 38 s`).
    static let tick: TimeInterval = 1

    public static func grid(_ theme: Theme) -> Grid {
        Grid(
            runsWidth: fixed(theme.component("script-page", "columns")) ?? 212,
            heroHeight: fixed(theme.component("script-page", "rows")) ?? 118)
    }

    /// The one fixed track of a two-track CSS grid value (`1fr 212px` → 212, `118px 1fr` → 118).
    static func fixed(_ tracks: String?) -> CGFloat? {
        tracks?.split(separator: " ").lazy.compactMap { ThemeValue.length(String($0)) }.first
    }
}
