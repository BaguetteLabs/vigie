import SwiftUI

/// The Usage tab (FR54; DESIGN "Usage provider card, meter and pace bar"; UX-DR31, UX-DR41 Usage 50/50; mockup
/// `key-usage-tab.html`): provider cards in the user's order on the left half, scrolling beyond two with the
/// fade, a 3 px track and the footer `DRAG TO REORDER · ALSO IN SETTINGS` · `SCROLL ↓`; `HISTORY · 7D` and
/// `COST · TODAY` stacked on the right half. No provider at all: `NO USAGE PROVIDER`, one sentence and
/// `Open settings ⌘,` across the whole body (UX-DR44).
///
/// `snapshot` is read in `body`, so an `@Observable` source re-renders the tab when it changes.
public struct UsageTabView: View {
    @Environment(\.vigieTheme) private var theme
    /// False draws the cards in a plain stack (offscreen renders: `ImageRenderer` draws no `ScrollView` content).
    var scrolls = true
    private let snapshot: @MainActor () -> UsageTabSnapshot
    private let onOpenSettings: (@MainActor () -> Void)?
    private let onReorder: @MainActor ([String]) -> Void

    /// - Parameters:
    ///   - snapshot: what the tab shows now.
    ///   - onOpenSettings: opens Settings › Usage (`Open settings ⌘,`); nil hides the button.
    ///   - onReorder: the provider ids in their new order after a drag (Story 7.9).
    public init(
        snapshot: @escaping @MainActor () -> UsageTabSnapshot,
        onOpenSettings: (@MainActor () -> Void)? = nil,
        onReorder: @escaping @MainActor ([String]) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.onOpenSettings = onOpenSettings
        self.onReorder = onReorder
    }

    public var body: some View {
        let snapshot = snapshot()
        Group {
            if snapshot.isEmpty {
                WidgetCard(
                    title: Text(L10n.resource("usage.tab.title")), meta: Text(L10n.resource("usage.tab.noProviders"))
                ) {
                    EmptyStateBlock(
                        VigieCopy.noUsageProvider, settingsShortcut: L10n.string("usage.tab.settingsShortcut"),
                        settingsAction: onOpenSettings)
                }
            } else {
                HStack(alignment: .top, spacing: theme.spacing(.gridGap)) {
                    providerList(snapshot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    VStack(spacing: theme.spacing(.gridGap)) {
                        // Filled by Story 7.8.
                        WidgetCard(title: Text(L10n.resource("usage.history.title"))) { Color.clear }
                        WidgetCard(title: Text(L10n.resource("usage.cost.title"))) { Color.clear }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, theme.spacing(.gridPaddingX))
        .padding(.top, theme.spacing(.cardPaddingY))
        .padding(.bottom, theme.spacing(.gridPaddingX))
    }

    @ViewBuilder private func providerList(_ snapshot: UsageTabSnapshot) -> some View {
        let cards = VStack(spacing: theme.spacing(.gridGap)) {
            ForEach(snapshot.providers) { provider in
                UsageProviderCard(model: provider)
            }
        }
        if snapshot.overflows {
            VStack(spacing: UsageTabMetrics.footerSpacing) {
                if scrolls {
                    ScrollFadeList(thumbWidth: UsageTabMetrics.thumbWidth, showsHint: false, showsTrack: true) {
                        cards.padding(.trailing, UsageTabMetrics.scrollInset)
                    }
                } else {
                    cards.padding(.trailing, UsageTabMetrics.scrollInset)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                        .clipped()
                }
                UsageListFooter()
            }
        } else {
            cards
        }
    }
}

/// `⠿ DRAG TO REORDER · ALSO IN SETTINGS` on the left, `SCROLL ↓` on the right (`.phint`), with `SETTINGS` in
/// `ink-2`.
struct UsageListFooter: View {
    @Environment(\.vigieTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing(.glyphGap)) {
            GripGlyph().accessibilityHidden(true)
            (Text(L10n.resource("usage.footer.reorder")) + Text(verbatim: " ")
                + Text(L10n.resource("usage.footer.settings")).foregroundStyle(theme.color(.ink2)))
            Spacer(minLength: theme.spacing(.glyphGap))
            Text(VigieCopy.scrollHint)
        }
        .font(theme.font(.readoutLabel))
        .tracking(theme.tracking(.readoutLabel))
        .foregroundStyle(theme.color(.ink3))
        .lineLimit(1)
        .frame(height: UsageTabMetrics.footerHeight)
    }
}
