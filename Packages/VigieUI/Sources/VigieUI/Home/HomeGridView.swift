import SwiftUI

/// One card on the Home tab, as the Notch Host passes it: a provider's `homeCard()` (a module today, a script
/// with the `home` surface from Epic 12).
public struct HomeCardModel: Identifiable {
    /// The provider id (the module id), as `[home] cards` lists it.
    public let id: String
    /// Localized provider name, for the "Open <name>" accessibility label.
    public let title: String
    /// True when clicking the card opens a tab (the provider has an `expandedView()`, A34).
    public let opensTab: Bool
    /// The card itself; the provider draws its own ``WidgetCard`` frame inside the 222 × 138 cell.
    public let content: AnyView

    public init(id: String, title: String, opensTab: Bool = true, content: AnyView) {
        self.id = id
        self.title = title
        self.opensTab = opensTab
        self.content = content
    }
}

extension ExpandedTab {
    /// The Home tab's id. Home is not a module: it is always first and never in `[general] tab_order`.
    public static let homeID = "home"

    /// The Home tab (FR89): first, always present.
    public static var home: ExpandedTab {
        ExpandedTab(id: homeID, title: L10n.string("expanded.tab.home"), icon: "square.grid.3x2")
    }
}

/// The Home tab body (FR90, UX-DR97 as amended 2026-11-07): the grid when cards are chosen, else the empty
/// state leading to Settings › Home.
public struct HomeTabView: View {
    private let cards: [HomeCardModel]
    private let onOpen: @MainActor (String) -> Void
    private let onOpenSettings: (@MainActor () -> Void)?

    public init(
        cards: [HomeCardModel],
        onOpen: @escaping @MainActor (String) -> Void,
        onOpenSettings: (@MainActor () -> Void)?
    ) {
        self.cards = cards
        self.onOpen = onOpen
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        if cards.isEmpty {
            HomeEmptyView(onOpenSettings: onOpenSettings)
        } else {
            HomeGridView(cards: cards, onOpen: onOpen)
        }
    }
}

/// The Home grid (`components.home-grid`, UX-DR41 / UX-DR97 as amended 2026-11-07): three equal columns of
/// one fixed card size, 222 × 138, no spans; cards fill left to right in the order set in Settings › Home and
/// the grid scrolls inside the panel beyond two rows. Home has no edit mode: a click on a card opens its tab.
public struct HomeGridView: View {
    @Environment(\.vigieTheme) private var theme
    private let cards: [HomeCardModel]
    private let onOpen: @MainActor (String) -> Void

    /// Three columns (`components.home-grid.columns`).
    public static let columnCount = 3

    public init(cards: [HomeCardModel], onOpen: @escaping @MainActor (String) -> Void) {
        self.cards = cards
        self.onOpen = onOpen
    }

    public var body: some View {
        let size = HomeMetrics.cardSize(theme)
        let gap = theme.spacing(.gridGap)
        let columns = Array(repeating: GridItem(.fixed(size.width), spacing: gap), count: Self.columnCount)
        ScrollFadeList(showsHint: false) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: gap) {
                ForEach(cards) { card in
                    HomeCardCell(card: card, size: size, onOpen: onOpen)
                }
            }
            .padding(theme.spacing(.gridPaddingX))
        }
    }
}

/// Home sizes from the theme: the card is the script card cell (`components.script-card`, 222 × 138), the row
/// height `components.home-grid.card-height`.
public enum HomeMetrics {
    public static func cardSize(_ theme: Theme) -> CGSize {
        CGSize(
            width: theme.componentLength("script-card", "width") ?? 0,
            height: theme.componentLength("home-grid", "card-height") ?? 0)
    }
}

/// One cell: the provider's card at the fixed size, clipped, as a button that opens its tab.
struct HomeCardCell: View {
    @Environment(\.vigieTheme) private var theme
    let card: HomeCardModel
    let size: CGSize
    let onOpen: @MainActor (String) -> Void

    var body: some View {
        let content = card.content
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        if card.opensTab {
            Button {
                onOpen(card.id)
            } label: {
                content
            }
            .buttonStyle(HomeCardButtonStyle())
            .accessibilityLabel(Text(L10n.format("home.card.open", card.title)))
        } else {
            content
        }
    }
}

/// Hover lifts the card like a row (UX-DR40: `ink-1` lift in Chrome Hologram, `struct` tint in Twin Metal),
/// press dims it.
struct HomeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HomeCardButtonBody(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct HomeCardButtonBody<Label: View>: View {
    @Environment(\.vigieTheme) private var theme
    @State private var isHovered = false
    let label: Label
    let isPressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
        label
            .overlay {
                if isHovered {
                    shape.fill(hoverTint).allowsHitTesting(false)
                }
            }
            .opacity(isPressed ? ComponentMetrics.pressedOpacity : 1)
            .contentShape(shape)
            .onHover { hovering in
                withAnimation(theme.animation(.enter)) { isHovered = hovering }
            }
    }

    private var hoverTint: Color {
        theme.usesCornerMarks
            ? theme.color(.structure).opacity(ComponentMetrics.hoverLiftStruct)
            : theme.color(.ink1).opacity(ComponentMetrics.hoverLift)
    }
}

/// Home with no card chosen (UX-DR97, UX-DR100): `NO WIDGETS` + "Pick Home widgets in Settings." with
/// `Open settings` leading to Settings › Home.
public struct HomeEmptyView: View {
    @Environment(\.vigieTheme) private var theme
    private let onOpenSettings: (@MainActor () -> Void)?

    public init(onOpenSettings: (@MainActor () -> Void)?) {
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        EmptyStateBlock(VigieCopy.noWidgets, settingsAction: onOpenSettings)
            .padding(theme.spacing(.gridPaddingX))
    }
}
