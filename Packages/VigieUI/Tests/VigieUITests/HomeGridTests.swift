import AppKit
import SwiftUI
import Testing

@testable import VigieUI

@MainActor
@Suite struct HomeGridTests {
    static func theme(_ look: Look, variant: String = ThemeLibrary.defaultVariantID) -> Theme {
        Fixtures.library.resolve(themeID: variant, look: look).theme
    }

    static let names = ["Agents", "Usage", "Shelf", "Calendar", "Time"]

    static func cards(_ count: Int) -> [HomeCardModel] {
        (0..<count).map { index in
            let name = names[index % names.count]
            return HomeCardModel(
                id: "module.\(index)", title: name,
                content: AnyView(
                    WidgetCard(title: Text(verbatim: name), meta: Text(verbatim: "Meta \(index + 1)")) {
                        VStack(alignment: .leading) {
                            StatusLabel(.working, elapsed: .seconds(60 * (index + 1)))
                            StatusLabel(.idle)
                        }
                    }))
        }
    }

    @Test func cardIsTheFixedScriptCardCell() {
        for variant in [ThemeLibrary.defaultVariantID, "twin-metal-tactical"] {
            #expect(HomeMetrics.cardSize(Self.theme(.dark, variant: variant)) == CGSize(width: 222, height: 138))
        }
        #expect(HomeGridView.columnCount == 3)
        // Three cells and two gaps fit inside the panel's grid padding.
        let theme = Self.theme(.dark)
        let row = 3 * 222 + 2 * theme.spacing(.gridGap)
        #expect(row <= theme.expandedPanelSize.width - 2 * theme.spacing(.gridPaddingX))
    }

    @Test func homeTabIsNamedFromTheCatalog() {
        #expect(ExpandedTab.home.id == ExpandedTab.homeID)
        #expect(ExpandedTab.home.title == "Home")
        #expect(L10n.format("home.card.open", "Usage") == "Open Usage")
        #expect(L10n.string("empty.home.label") == "NO WIDGETS")
        #expect(L10n.string("empty.home.sentence") == "Pick Home widgets in Settings.")
    }

    @Test(arguments: [0, 2, 5], [Look.dark, .light])
    func rendersInsideTheExpandedShell(count: Int, look: Look) throws {
        let theme = Self.theme(look)
        let size = theme.expandedPanelSize
        let cards = Self.cards(count)
        let view = ExpandedShellView(
            tabs: [.home, ExpandedTab(id: "module.0", title: "Agents", icon: "terminal")],
            selection: .constant(ExpandedTab.homeID), bandTheme: Self.theme(.dark),
            now: Date(timeIntervalSince1970: 1_793_803_680),
            content: { _ in AnyView(HomeTabView(cards: cards, onOpen: { _ in }, onOpenSettings: {})) }
        )
        .frame(width: size.width, height: size.height)
        .padding(20)
        .background(look == .dark ? Color(white: 0.22) : Color(white: 0.85))
        .vigieTheme(theme)
        // ImageRenderer leaves scroll views blank: draw through a hosting view instead.
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: size.width + 40, height: size.height + 40)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = try #require(rep.cgImage)
        #expect(image.width >= Int(size.width + 40))
        if let dir = ProcessInfo.processInfo.environment["VIGIE_HOME_RENDER_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("home-\(count)-\(look.rawValue).png")
            try rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}
