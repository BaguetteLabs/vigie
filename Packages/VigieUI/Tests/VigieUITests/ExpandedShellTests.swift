import AppKit
import SwiftUI
import Testing

@testable import VigieUI

@MainActor
@Suite struct ExpandedShellTests {
    static let tabs = [
        ExpandedTab(id: "agents.sessions", title: "Agents", icon: "terminal", needsAttention: true),
        ExpandedTab(id: "agents.usage", title: "Usage", icon: "gauge"),
        ExpandedTab(id: "shelf", title: "Shelf", icon: "tray"),
    ]

    static func theme(_ look: Look, variant: String = ThemeLibrary.defaultVariantID) -> Theme {
        Fixtures.library.resolve(themeID: variant, look: look).theme
    }

    @Test(arguments: [
        (ThemeLibrary.defaultVariantID, Look.dark), (ThemeLibrary.defaultVariantID, .light),
        ("twin-metal-tactical", .dark), ("twin-metal-tactical", .light),
    ])
    func rendersWithTheBundledTheme(variant: String, look: Look) throws {
        let theme = Self.theme(look, variant: variant)
        let size = theme.expandedPanelSize
        let view = ExpandedShellView(
            tabs: Self.tabs, selection: .constant(nil), bandTheme: Self.theme(.dark, variant: variant),
            now: Date(timeIntervalSince1970: 1_793_803_680), content: { _ in nil }
        )
        .frame(width: size.width, height: size.height)
        .vigieTheme(theme)
        let renderer = ImageRenderer(content: view)
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(size.width) && image.height == Int(size.height))
    }

    @Test func panelMetricsComeFromTheTheme() {
        let a = Self.theme(.dark)
        #expect(a.expandedPanelSize == CGSize(width: 720, height: 420))
        #expect(a.radius(.expanded) == 24)
        #expect(a.spacing(.bandHeight) == 34)
        #expect(a.tabBarHeight == 30)
        #expect(a.gearSize == 24)
        #expect(Self.theme(.dark, variant: "twin-metal-tactical").gearSize == 26)
        #expect(a.spacing(.tabsMarginX) == 16)
        #expect(a.spacing(.tabRowGap) == 8)
        #expect(ExpandedMetrics.attentionMarker == 5)
    }

    @Test func gearAndCopyComeFromTheCatalog() {
        #expect(L10n.string("expanded.settings") == "Settings")
        #expect(L10n.string("expanded.settings.tooltip") == "Settings (⌘,)")
        #expect(L10n.string("expanded.wordmark") == "VIGIE")
        #expect(L10n.string("empty.expanded.label") == "NO TABS")
    }

    @Test func attentionTabReadsNeedsAttention() {
        #expect(Self.tabs[0].accessibilityLabel == "Agents, needs attention")
        #expect(Self.tabs[1].accessibilityLabel == "Usage")
    }

    @Test func commandDigitsMapToTabsInOrderAndNeverToTheGear() {
        #expect(ExpandedShortcuts.tabID(forDigit: 1, in: Self.tabs) == "agents.sessions")
        #expect(ExpandedShortcuts.tabID(forDigit: 3, in: Self.tabs) == "shelf")
        #expect(ExpandedShortcuts.tabID(forDigit: 4, in: Self.tabs) == nil)
        #expect(ExpandedShortcuts.tabID(forDigit: 0, in: Self.tabs) == nil)
        let many = (1...12).map { ExpandedTab(id: "t\($0)", title: "T\($0)", icon: "circle") }
        #expect(ExpandedShortcuts.tabID(forDigit: 9, in: many) == "t9")
        #expect(ExpandedShortcuts.tabID(forDigit: 10, in: many) == nil)
        #expect(ExpandedShortcuts.digit(for: "t9", in: many) == 9)
        #expect(ExpandedShortcuts.digit(for: "t10", in: many) == nil)
    }

    @Test func arrowsMoveAlongTheTabsThenTheGear() {
        let tabs = Self.tabs
        #expect(ExpandedRowFocus.moved(from: nil, forward: true, tabs: tabs) == .tab("agents.sessions"))
        #expect(
            ExpandedRowFocus.moved(from: .tab("agents.sessions"), forward: true, tabs: tabs) == .tab("agents.usage"))
        #expect(ExpandedRowFocus.moved(from: .tab("shelf"), forward: true, tabs: tabs) == .gear)
        #expect(ExpandedRowFocus.moved(from: .gear, forward: true, tabs: tabs) == .gear)
        #expect(ExpandedRowFocus.moved(from: .gear, forward: false, tabs: tabs) == .tab("shelf"))
        #expect(
            ExpandedRowFocus.moved(from: .tab("agents.sessions"), forward: false, tabs: tabs) == .tab("agents.sessions")
        )
        #expect(ExpandedRowFocus.moved(from: nil, forward: true, tabs: []) == .gear)
    }

    @Test func opensOnTheFirstTabUnlessTheSelectionNamesOne() {
        #expect(ExpandedShellView.activeTabID(selection: nil, tabs: Self.tabs) == "agents.sessions")
        #expect(ExpandedShellView.activeTabID(selection: "shelf", tabs: Self.tabs) == "shelf")
        #expect(ExpandedShellView.activeTabID(selection: "gone", tabs: Self.tabs) == "agents.sessions")
        #expect(ExpandedShellView.activeTabID(selection: nil, tabs: []) == nil)
    }

    @Test func statusLineFormatsTimeAndDateInTheLocale() {
        let date = Date(timeIntervalSince1970: 1_793_803_680)  // 2026-11-04 14:48 UTC
        let utc = TimeZone(identifier: "UTC")!
        #expect(
            ExpandedStatusLine.text(at: date, locale: Locale(identifier: "en_GB"), timeZone: utc)
                == "Online · 14:48 · Wed 04 Nov")
        #expect(
            ExpandedStatusLine.text(at: date, locale: Locale(identifier: "en_US"), timeZone: utc)
                .hasPrefix("Online · 2:48"))
        // By default: the user's region and hour cycle, in the catalog's language.
        #expect(
            ExpandedStatusLine.displayLocale.language.languageCode == L10n.catalogLocale.language.languageCode)
    }

    @Test func expansionStyleFollowsPresenceAndReduceMotion() {
        var theme = Self.theme(.dark)
        #expect(ExpansionStyle(theme: theme) == .grow)
        #expect(ExpansionStyle(theme: theme).collapseDuration(theme) == .milliseconds(200))
        theme.presence = .calm
        #expect(ExpansionStyle(theme: theme) == .fade)
        theme.accessibility = AccessibilityAdjustments(reduceMotion: true)
        #expect(ExpansionStyle(theme: theme) == .instant)
        #expect(ExpansionStyle(theme: theme).collapseDuration(theme) == .zero)
    }

    @Test func gearFocusRingFollowsTheLookAndIncreaseContrast() {
        let aDark = GearFocusRing(theme: Self.theme(.dark))
        #expect(aDark.isSquare == false && aDark.width == 1 && aDark.opacity == 0.55 && aDark.hasHalo == true)
        let aLight = GearFocusRing(theme: Self.theme(.light))
        #expect(aLight.isSquare == false && aLight.width == 1 && aLight.opacity == 1 && aLight.hasHalo == false)
        let c = GearFocusRing(theme: Self.theme(.dark, variant: "twin-metal-tactical"))
        #expect(c.isSquare == true && c.width == 1 && c.opacity == 0.55 && c.hasHalo == false)
        var contrast = Self.theme(.dark)
        contrast.accessibility = AccessibilityAdjustments(increaseContrast: true)
        let ring = GearFocusRing(theme: contrast)
        #expect(ring.width == 2)
        #expect(!ring.hasHalo)
    }

    @Test func expansionMaskGrowsFromTheIslandAtTheTopCentre() {
        let rect = CGRect(x: 0, y: 0, width: 720, height: 420)
        let closed = ExpansionMaskShape(width: 440, height: 34, radius: 14).path(in: rect).boundingRect
        #expect(closed == CGRect(x: 140, y: 0, width: 440, height: 34))
        let open = ExpansionMaskShape(width: 720, height: 420, radius: 24).path(in: rect).boundingRect
        #expect(open == rect)
    }
}
