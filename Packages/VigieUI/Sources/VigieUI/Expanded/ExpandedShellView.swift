import SwiftUI

/// The expanded panel's content (DESIGN "Expanded panel", "Tab bar", "Settings gear"; UX-DR26, UX-DR27,
/// UX-DR80, UX-DR104): the 34px black band (wordmark left, `● Online · HH:MM · Ddd DD Mon` right), the tab
/// row (tab bar, then the settings gear at the far right) and the active tab's body.
///
/// The host passes the tabs in `[general] tab_order` and owns the selection; with no selection the first tab
/// is active (Home arrives in Epic 11, A12). `⌘1…9` switch tabs while the panel is key; Tab and `←→` move
/// keyboard focus along the tabs and then the gear; `↵` / Space activates. The panel body follows the
/// environment theme; the band uses `bandTheme` (the island's dark look) when given.
public struct ExpandedShellView: View {
    @Environment(\.vigieTheme) private var theme
    @Binding private var selection: String?
    @FocusState private var rowFocus: ExpandedRowFocus?
    /// Focus rings show only once the keyboard moves focus, not for the focus AppKit gives on open.
    @State private var showsFocusRing = false

    private let tabs: [ExpandedTab]
    private let bandTheme: Theme?
    private let now: Date?
    private let openSettings: (@MainActor () -> Void)?
    private let content: @MainActor (String) -> AnyView?

    /// - Parameters:
    ///   - tabs: module tabs in display order.
    ///   - selection: the active tab id; nil (or an unknown id) shows the first tab.
    ///   - bandTheme: the theme for the black band (the island's dark look); nil uses the environment theme.
    ///   - now: a fixed time for the status line (tests, previews); nil follows the clock every minute.
    ///   - openSettings: opens the Settings window; nil keeps the gear focusable but inert (until Story 2.14).
    ///   - content: the body of a tab (`expandedView()`); nil shows the empty state.
    public init(
        tabs: [ExpandedTab],
        selection: Binding<String?>,
        bandTheme: Theme? = nil,
        now: Date? = nil,
        openSettings: (@MainActor () -> Void)? = nil,
        content: @escaping @MainActor (String) -> AnyView?
    ) {
        self.tabs = tabs
        self._selection = selection
        self.bandTheme = bandTheme
        self.now = now
        self.openSettings = openSettings
        self.content = content
    }

    /// The active tab: the selection when it names a tab, else the first tab.
    public static func activeTabID(selection: String?, tabs: [ExpandedTab]) -> String? {
        if let selection, tabs.contains(where: { $0.id == selection }) { return selection }
        return tabs.first?.id
    }

    private var activeID: String? { Self.activeTabID(selection: selection, tabs: tabs) }

    public var body: some View {
        VStack(spacing: 0) {
            ExpandedBand(now: now)
                .vigieTheme(bandTheme ?? theme)
            tabRow
            body(for: activeID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.color(.surfacePanel))
        .clipShape(IslandShape(radius: theme.radius(.expanded)))
        .background(shortcutButtons)
        .focusEffectDisabled()
        .onChange(of: rowFocus) { old, new in
            if old != nil, new != nil { showsFocusRing = true }
        }
    }

    // MARK: Tab row

    private var tabRow: some View {
        HStack(spacing: theme.spacing(.tabRowGap)) {
            ExpandedTabBar(
                tabs: tabs, activeID: activeID, focus: $rowFocus, showsFocusRing: showsFocusRing, select: select)
            Spacer(minLength: 0)
            SettingsGear(isFocused: showsFocusRing && rowFocus == .gear, action: openSettings)
                .focusable()
                .focused($rowFocus, equals: .gear)
                .focusEffectDisabled()
        }
        .frame(height: theme.tabBarHeight)
        .overlay(alignment: .bottom) {
            if theme.usesCornerMarks {
                // C: a 1px `line` underline across the whole tab row.
                Rectangle().fill(theme.color(.line)).frame(height: ComponentMetrics.hairline)
            }
        }
        .padding(.horizontal, theme.spacing(.tabsMarginX))
        .padding(.top, ExpandedMetrics.tabRowTop)
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            showsFocusRing = true
            rowFocus = ExpandedRowFocus.moved(from: rowFocus, forward: press.key == .rightArrow, tabs: tabs)
            return .handled
        }
    }

    @ViewBuilder
    private func body(for id: String?) -> some View {
        if let id, let view = content(id) {
            view
        } else {
            EmptyStateBlock(VigieCopy.noTabs)
                .padding(theme.spacing(.gridPaddingX))
        }
    }

    private func select(_ id: String) {
        selection = id
    }

    /// `⌘1…9`: invisible buttons whose key equivalents fire only while the panel is key.
    private var shortcutButtons: some View {
        ZStack {
            ForEach(1...ExpandedShortcuts.maxSlots, id: \.self) { digit in
                Button {
                    if let id = ExpandedShortcuts.tabID(forDigit: digit, in: tabs) { select(id) }
                } label: {
                    EmptyView()
                }
                .keyboardShortcut(KeyEquivalent(Character(String(digit))), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

// MARK: - Band

/// The black band: wordmark `VIGIE` left, status and clock right (always the dark role set).
struct ExpandedBand: View {
    @Environment(\.vigieTheme) private var theme
    let now: Date?

    var body: some View {
        HStack(spacing: 0) {
            wordmark
            Spacer(minLength: theme.spacing(.wingGap))
            if let now {
                status(at: now)
            } else {
                TimelineView(.everyMinute) { context in status(at: context.date) }
            }
        }
        .padding(.horizontal, theme.spacing(.expandedBarPaddingX))
        .frame(maxWidth: .infinity)
        .frame(height: theme.spacing(.bandHeight))
        .background(theme.color(.band))
    }

    @ViewBuilder
    private var wordmark: some View {
        let word = Text(L10n.resource("expanded.wordmark")).font(theme.font(.kicker))
        if theme.usesCornerMarks {
            // C: condensed caps with a gold `·`.
            HStack(spacing: 0) {
                word.tracking(theme.tracking(.kicker)).foregroundStyle(theme.color(.ink1))
                Text(verbatim: " ·").font(theme.font(.kicker)).foregroundStyle(theme.color(.gold))
            }
            .accessibilityElement(children: .combine)
        } else {
            // A: iris-gradient text, letter-spacing 0.5em.
            word
                .tracking(theme.fontSpec(.kicker).size * ExpandedMetrics.wordmarkTrackingEm)
                .foregroundStyle(
                    LinearGradient(
                        colors: [theme.color(.iris1), theme.color(.iris2), theme.color(.iris3)],
                        startPoint: .leading, endPoint: .trailing))
        }
    }

    private func status(at date: Date) -> some View {
        HStack(spacing: theme.spacing(.glyphGap) / 2) {
            Circle()
                .fill(theme.color(.statusIdle))
                .frame(width: ExpandedMetrics.statusDot, height: ExpandedMetrics.statusDot)
                .accessibilityHidden(true)
            Text(verbatim: ExpandedStatusLine.text(at: date))
                .font(theme.font(.tab))
                .tracking(theme.tracking(.tab))
                .textCase(theme.usesCornerMarks ? .uppercase : nil)
                .foregroundStyle(theme.color(.ink2))
        }
        .lineLimit(1)
    }
}

// MARK: - Tab bar

/// The tabs: A, a pill container with the active tab raised; C, gold text with a 2px gold underline.
struct ExpandedTabBar: View {
    @Environment(\.vigieTheme) private var theme
    let tabs: [ExpandedTab]
    let activeID: String?
    var focus: FocusState<ExpandedRowFocus?>.Binding
    let showsFocusRing: Bool
    let select: (String) -> Void

    var body: some View {
        let look = theme.look
        HStack(spacing: ExpandedMetrics.tabGap) {
            ForEach(tabs) { tab in
                ExpandedTabLabel(
                    tab: tab, isActive: tab.id == activeID,
                    isFocused: showsFocusRing && focus.wrappedValue == .tab(tab.id)
                )
                .contentShape(Rectangle())
                .onTapGesture { select(tab.id) }
                .focusable()
                .focused(focus, equals: .tab(tab.id))
                .focusEffectDisabled()
                .onKeyPress(keys: [.return, .space]) { _ in
                    select(tab.id)
                    return .handled
                }
                .accessibilityAction { select(tab.id) }
            }
        }
        .padding(.horizontal, theme.usesCornerMarks ? 0 : ExpandedMetrics.pillInset)
        .frame(height: theme.tabBarHeight)
        .background {
            if !theme.usesCornerMarks {
                let pill = RoundedRectangle(cornerRadius: theme.radius(.full), style: .continuous)
                pill.fill(theme.color(.ink1).opacity(ExpandedMetrics.pillFill(look)))
                    .overlay(
                        pill.strokeBorder(
                            theme.borderColor(.ink1, opacity: ExpandedMetrics.pillHairline(look)),
                            lineWidth: theme.a11y.hairlineWidth))
            }
        }
        .fixedSize()
    }
}

struct ExpandedTabLabel: View {
    @Environment(\.vigieTheme) private var theme
    let tab: ExpandedTab
    let isActive: Bool
    let isFocused: Bool

    var body: some View {
        HStack(spacing: theme.spacing(.glyphGap)) {
            Text(verbatim: tab.title)
                .font(theme.font(.tab))
                .tracking(theme.tracking(.tab))
                .textCase(theme.usesCornerMarks ? .uppercase : nil)
                .foregroundStyle(theme.color(labelRole))
                .lineLimit(1)
            if tab.needsAttention {
                AttentionMarker()
            }
        }
        .padding(.horizontal, theme.spacing(.tabPaddingX))
        .frame(height: theme.usesCornerMarks ? theme.tabBarHeight : ExpandedMetrics.tabHeight)
        .background { activeBackground }
        .overlay { focusRing }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tab.accessibilityLabel))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private var labelRole: ColorRole {
        if theme.usesCornerMarks { return isActive ? .goldText : .ink3 }
        return isActive ? .ink1 : .ink3
    }

    @ViewBuilder
    private var activeBackground: some View {
        if isActive {
            if theme.usesCornerMarks {
                VStack {
                    Spacer(minLength: 0)
                    Rectangle().fill(theme.color(.gold)).frame(height: ExpandedMetrics.activeUnderline)
                }
            } else {
                RaisedPill()
            }
        }
    }

    @ViewBuilder
    private var focusRing: some View {
        if isFocused {
            let ring = theme.color(.ink1).opacity(
                theme.isLight && !theme.usesCornerMarks ? 1 : ExpandedMetrics.focusRing)
            if theme.usesCornerMarks {
                Rectangle().strokeBorder(ring, lineWidth: theme.a11y.focusRingWidth)
            } else {
                Capsule().strokeBorder(ring, lineWidth: theme.a11y.focusRingWidth)
            }
        }
    }
}

/// The A raised pill: the active tab and the hovered settings gear.
struct RaisedPill: View {
    @Environment(\.vigieTheme) private var theme

    var body: some View {
        let pill = Capsule()
        if theme.isLight {
            pill.fill(theme.color(.surfaceCard))
                .overlay(
                    pill.strokeBorder(
                        theme.borderColor(.ink1, opacity: ExpandedMetrics.raisedHairline(.light)),
                        lineWidth: theme.a11y.hairlineWidth))
        } else {
            pill.fill(
                theme.glassFill(
                    LinearGradient(
                        colors: [
                            theme.color(.ink1).opacity(ExpandedMetrics.raisedTop),
                            theme.color(.ink1).opacity(ExpandedMetrics.raisedBottom),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    flat: .surfaceCard)
            )
            .overlay(
                pill.strokeBorder(
                    theme.borderColor(.ink1, opacity: ExpandedMetrics.raisedHairline(.dark)),
                    lineWidth: theme.a11y.hairlineWidth))
        }
    }
}

/// The 5px attention marker in the blocked hue: a diamond in A, a square in C. A shape, so color is never the
/// only cue (UX-DR104); the tab's accessibility label says "needs attention".
public struct AttentionMarker: View {
    @Environment(\.vigieTheme) private var theme

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(theme.color(.statusBlocked))
            .frame(width: ExpandedMetrics.attentionMarker, height: ExpandedMetrics.attentionMarker)
            .rotationEffect(theme.usesCornerMarks ? .zero : .degrees(45))
            .accessibilityHidden(true)
    }
}

// MARK: - Settings gear

/// The settings gear (DESIGN "Settings gear", Story 1.7a): a detached 24px round (C: 26px square) button with
/// a 14px outline gear in `ink-3`. Hover raises it (A pill; C struct border at 30%) with the macOS tooltip
/// `Settings (⌘,)`; keyboard focus draws the per-look ring. It is never a tab and has no `⌘1–9` slot.
struct SettingsGear: View {
    @Environment(\.vigieTheme) private var theme
    @State private var isHovered = false
    let isFocused: Bool
    let action: (@MainActor () -> Void)?

    var body: some View {
        let size = theme.gearSize
        Image(systemName: "gearshape")
            .font(.system(size: ExpandedMetrics.gearIcon, weight: .light))
            .foregroundStyle(theme.color(isHovered || isFocused ? .ink1 : .ink3))
            .frame(width: size, height: size)
            .background { hoverBackground }
            .overlay { focusRing }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture { action?() }
            .onKeyPress(keys: [.return, .space]) { _ in
                action?()
                return .handled
            }
            .help(Text(L10n.resource("expanded.settings.tooltip")))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L10n.resource("expanded.settings")))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action?() }
    }

    @ViewBuilder
    private var hoverBackground: some View {
        if isHovered {
            if theme.usesCornerMarks {
                Rectangle().strokeBorder(
                    theme.borderColor(.structure, opacity: ExpandedMetrics.structBorder),
                    lineWidth: theme.a11y.hairlineWidth)
            } else {
                RaisedPill()
            }
        }
    }

    @ViewBuilder
    private var focusRing: some View {
        if isFocused {
            let ring = GearFocusRing(theme: theme)
            let stroke = theme.color(.ink1).opacity(ring.opacity)
            if ring.isSquare {
                Rectangle().strokeBorder(stroke, lineWidth: ring.width)
            } else {
                Circle()
                    .strokeBorder(stroke, lineWidth: ring.width)
                    .background {
                        if ring.hasHalo {
                            Circle()
                                .stroke(
                                    theme.color(.iris1).opacity(ExpandedMetrics.focusHalo),
                                    lineWidth: ExpandedMetrics.focusHaloWidth
                                )
                                .padding(-ExpandedMetrics.focusHaloWidth / 2)
                        }
                    }
            }
        }
    }
}

/// The settings gear's keyboard focus ring per look (DESIGN "Settings gear", accessibility floor): A dark a
/// 1px platinum ring at 55% plus a 3px cyan halo at 14%; A light the solid graphite selection ring, no halo;
/// C the C selection ring (square, `ink-1` at 55%). Under Increase contrast the ring is 2px and the halo is
/// dropped (`theme.a11y`).
struct GearFocusRing: Equatable {
    var isSquare: Bool
    var width: CGFloat
    var opacity: Double
    var hasHalo: Bool

    init(theme: Theme) {
        isSquare = theme.usesCornerMarks
        width = theme.a11y.focusRingWidth
        let solidLight = theme.isLight && !isSquare
        opacity = solidLight ? 1 : ExpandedMetrics.focusRing
        hasHalo = !isSquare && !theme.isLight && theme.a11y.haloEnabled
    }
}

#Preview("Expanded · A dark") {
    ExpandedShellPreview(look: .dark)
}

#Preview("Expanded · C light") {
    ExpandedShellPreview(look: .light, variant: "twin-metal-tactical")
}

private struct ExpandedShellPreview: View {
    let look: Look
    var variant = ThemeLibrary.defaultVariantID
    @State private var selection: String? = "agents.sessions"

    var body: some View {
        let theme = PreviewThemes.theme(look, variant: variant)
        ExpandedShellView(
            tabs: [
                ExpandedTab(id: "agents.sessions", title: "Agents", icon: "terminal", needsAttention: true),
                ExpandedTab(id: "agents.usage", title: "Usage", icon: "gauge"),
                ExpandedTab(id: "shelf", title: "Shelf", icon: "tray"),
            ],
            selection: $selection,
            bandTheme: PreviewThemes.theme(.dark, variant: variant),
            content: { _ in nil }
        )
        .frame(width: theme.expandedPanelSize.width, height: theme.expandedPanelSize.height)
        .vigieTheme(theme)
    }
}
