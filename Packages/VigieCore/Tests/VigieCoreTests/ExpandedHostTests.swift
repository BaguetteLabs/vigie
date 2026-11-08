import AppKit
import ModuleKit
import Observation
import SwiftUI
import Testing
import VigieUI

@testable import VigieCore

@MainActor
final class FakeExpandedPanel: ExpandedPanelHosting {
    private(set) var panelFrame: CGRect?
    private(set) var isKey = false
    private(set) var isVisible = false
    private(set) var log: [String] = []

    func show(panelFrame: CGRect) {
        self.panelFrame = panelFrame
        isVisible = true
        log.append("show")
    }

    func hide() {
        panelFrame = nil
        isVisible = false
        isKey = false
        log.append("hide")
    }

    func takeKey() {
        isKey = true
        log.append("takeKey")
    }

    func dropKey() {
        isKey = false
        log.append("dropKey")
    }
}

@MainActor @Observable
final class TabModule: NotchModule {
    let manifest: ModuleManifest
    var state: ModuleState = .ambient
    @ObservationIgnored let hasTab: Bool
    @ObservationIgnored var hasCard: Bool

    init(_ id: ModuleID, hasTab: Bool = true, hasCard: Bool = false) {
        manifest = ModuleManifest(id: id, name: "Tab", icon: "circle")
        self.hasTab = hasTab
        self.hasCard = hasCard
    }

    func expandedView() -> AnyView? { hasTab ? AnyView(Color.clear) : nil }
    func homeCard() -> AnyView? { hasCard ? AnyView(Color.clear) : nil }
    func start(context: any ModuleContext) async throws {}
    func stop() async {}
}

@MainActor
final class ExpandedFixture {
    let modules: [ModuleID: TabModule]
    let registry: ModuleRegistry
    let focus = FocusPolicy()
    let enablement: TestEnablement
    let panel = FakeExpandedPanel()
    var openOnHover = false
    var closeOnLeave = false
    var tabOrder: [String] = []
    var homeCards: [String] = []
    var openedPanes: [String] = []
    var pointer = CGPoint(x: 700, y: 980)
    var host: NotchHost!

    static let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    static let island = CGRect(x: 536, y: 950, width: 440, height: 32)
    static let notch = CGRect(x: 656, y: 950, width: 200, height: 32)

    init(
        ids: [ModuleID] = ["agents.sessions", "agents.usage", "shelf"], withoutTab: Set<ModuleID> = [],
        withCard: Set<ModuleID> = []
    ) {
        var modules: [ModuleID: TabModule] = [:]
        for id in ids {
            modules[id] = TabModule(id, hasTab: !withoutTab.contains(id), hasCard: withCard.contains(id))
        }
        let made = modules
        self.modules = modules
        let enablement = TestEnablement()
        self.enablement = enablement
        registry = ModuleRegistry(
            descriptors: ids.map { id in
                ModuleDescriptor(manifest: ModuleManifest(id: id, name: "Tab", icon: "circle")) { made[id]! }
            },
            enablement: enablement,
            contextFactory: CoreModuleContextFactory(
                environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus()),
            logger: testLogger)
        let library = try! ThemeLoader.loadBundled()
        let panel = panel
        host = NotchHost(
            themeController: ThemeController(library: library, accessibility: .init(reduceMotion: true)),
            registry: registry, contextMenu: NotchContextMenu(), displays: { [] },
            focusPolicy: focus,
            openOnHover: { [unowned self] in self.openOnHover },
            hoverDelay: { .milliseconds(20) },
            closeOnLeave: { [unowned self] in self.closeOnLeave },
            tabOrder: { [unowned self] in self.tabOrder },
            openSettingsPane: { [unowned self] in self.openedPanes.append($0) },
            homeCardOrder: { [unowned self] in self.homeCards },
            pointerLocation: { [unowned self] in self.pointer },
            makeExpandedPanel: { _ in panel },
            logger: testLogger)
        host.anchorsOverride = [
            IslandAnchor(screenFrame: Self.screen, islandFrame: Self.island, notchRect: Self.notch)
        ]
    }

    func start() async { await registry.start() }
    var intent: UserIntent { UserIntentMinter.mint(source: .hotkey(CoreHotkeys.expandName)) }
}

@MainActor @Suite struct ExpandedHostTests {
    @Test func expandWithoutIntentPresentsWithoutFocus() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: nil)
        #expect(f.host.isExpanded)
        #expect(f.panel.isVisible)
        #expect(!f.panel.isKey)
        #expect(!f.host.isExpandedKey)
        #expect(f.focus.keySurfaceID == nil)
        #expect(f.focus.presentedSurfaceIDs == [ExpandedSurface.id])
    }

    @Test func expandWithIntentMakesThePanelKeyThroughTheFocusPolicy() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: f.intent)
        #expect(f.panel.isKey)
        #expect(f.focus.keySurfaceID == ExpandedSurface.id)
        #expect(f.host.isExpandedKey)
    }

    @Test func islandClickExpandsWithFocus() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.islandClicked()
        #expect(f.host.isExpanded)
        #expect(f.panel.isKey)
    }

    @Test func panelGrowsOutOfTheNotchOnTheDisplayUnderThePointer() async throws {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: nil)
        let frame = try #require(f.panel.panelFrame)
        #expect(frame.size == CGSize(width: 720, height: 420))
        #expect(frame.maxY == ExpandedFixture.screen.maxY)
        #expect(frame.midX == ExpandedFixture.notch.midX)
        #expect(f.host.expansionOrigin == ExpandedFixture.island.size)
    }

    @Test func escapeCollapsesTheKeyExpandedView() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: f.intent)
        #expect(f.host.handleEscape())
        #expect(!f.host.isExpanded)
        #expect(f.focus.keySurfaceID == nil)
        #expect(f.focus.presentedSurfaceIDs.isEmpty)
        #expect(await eventually { !f.panel.isVisible })
    }

    @Test func escapeClosesOnlyTheKeySurface() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: nil)
        // Without focus, Esc is not for the expanded view.
        #expect(!f.host.handleEscape())
        #expect(f.host.isExpanded)
        // Another surface holds focus: Esc closes it, not the expanded view.
        let notes = FakeSurface("notes")
        f.focus.present(notes, focus: UserIntentMinter.mint(source: .menu("new-note")))
        #expect(f.host.handleEscape())
        #expect(notes.isClosed)
        #expect(f.host.isExpanded)
    }

    @Test func anotherSurfaceTakingFocusResignsTheExpandedView() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: f.intent)
        f.focus.present(FakeSurface("notes"), focus: UserIntentMinter.mint(source: .menu("new-note")))
        #expect(!f.panel.isKey)
        #expect(f.host.isExpanded)
    }

    @Test func toggleTwiceReturnsToCollapsed() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.toggleExpanded(focus: f.intent)
        #expect(f.host.isExpanded && f.panel.isKey)
        f.host.toggleExpanded(focus: f.intent)
        #expect(!f.host.isExpanded)
        #expect(f.focus.keySurfaceID == nil)
        #expect(await eventually { !f.panel.isVisible })
    }

    @Test func hotkeyOnAViewOpenedWithoutFocusTakesFocus() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: nil)
        f.host.toggleExpanded(focus: f.intent)
        #expect(f.host.isExpanded)
        #expect(f.panel.isKey)
    }

    @Test func reexpandingDuringTheExitKeepsThePanelOnScreen() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: f.intent)
        f.host.collapse()
        f.host.expand(focus: f.intent)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(f.panel.isVisible)
        #expect(f.host.isExpanded)
    }

    @Test func opensOnHomeAndOpenTabSelectsATab() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.selectedTabID = "shelf"
        f.host.expand(focus: f.intent)
        #expect(f.host.selectedTabID == ExpandedTab.homeID)
        f.host.collapse()
        f.host.openTab("shelf", focus: f.intent)
        #expect(f.host.selectedTabID == "shelf")
    }

    @Test func tabsFollowTabOrderAndCarryTheAttentionMarker() async {
        let f = ExpandedFixture(ids: ["agents.sessions", "agents.usage", "shelf", "time"], withoutTab: ["time"])
        await f.start()
        #expect(f.host.expandedTabs.map(\.id) == ["home", "agents.sessions", "agents.usage", "shelf"])
        f.tabOrder = ["shelf", "calendar", "agents.sessions"]
        #expect(f.host.expandedTabs.map(\.id) == ["home", "shelf", "agents.sessions", "agents.usage"])
        #expect(f.host.expandedTabs.allSatisfy { !$0.needsAttention })
        f.modules["agents.sessions"]!.state = .alert
        #expect(f.host.expandedTabs.first { $0.id == "agents.sessions" }?.needsAttention == true)
        #expect(f.host.expandedContent(for: "shelf") != nil)
        #expect(f.host.expandedContent(for: "time") == nil)
    }

    @Test func tabOrderPutsListedIdsFirstAndAppendsTheRest() {
        let tabs = ["a", "b", "c", "d"].map { ExpandedTab(id: $0, title: $0, icon: "circle") }
        #expect(ExpandedTabOrder.ordered(tabs, by: []).map(\.id) == ["a", "b", "c", "d"])
        #expect(ExpandedTabOrder.ordered(tabs, by: ["c", "x", "a", "c"]).map(\.id) == ["c", "a", "b", "d"])
    }

    @Test func hoverDoesNotOpenUnlessOptedIn() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.islandHoverChanged(true)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(!f.host.isExpanded)
    }

    @Test func hoverOpensWithoutFocusAfterTheDelayWhenOptedIn() async {
        let f = ExpandedFixture()
        f.openOnHover = true
        await f.start()
        f.host.islandHoverChanged(true)
        #expect(!f.host.isExpanded)
        #expect(await eventually { f.host.isExpanded })
        #expect(!f.panel.isKey)
        #expect(f.focus.keySurfaceID == nil)
    }

    @Test func leavingBeforeTheHoverDelayCancelsTheOpen() async {
        let f = ExpandedFixture()
        f.openOnHover = true
        await f.start()
        f.host.islandHoverChanged(true)
        f.host.islandHoverChanged(false)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(!f.host.isExpanded)
    }

    @Test func closeOnLeaveCollapsesWhenThePointerLeavesPanelAndIsland() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: f.intent)
        f.host.pointerMoved(to: CGPoint(x: 700, y: 700))  // inside the panel
        f.host.pointerMoved(to: CGPoint(x: 100, y: 100))
        #expect(f.host.isExpanded)  // off by default

        f.closeOnLeave = true
        f.host.pointerMoved(to: CGPoint(x: 700, y: 700))
        f.host.pointerMoved(to: CGPoint(x: 700, y: 981))  // over the island, still inside
        #expect(f.host.isExpanded)
        f.host.pointerMoved(to: CGPoint(x: 100, y: 100))
        #expect(!f.host.isExpanded)
    }

    @Test func clickOutsideCollapses() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: f.intent)
        f.host.mouseDownOutsideExpanded()
        #expect(!f.host.isExpanded)
    }

    @Test func clickOnTheShadowMarginCollapsesAndClickOnAPanelOpenedByHoverTakesFocus() async throws {
        let f = ExpandedFixture()
        await f.start()
        f.host.expand(focus: nil)
        let frame = try #require(f.panel.panelFrame)
        f.host.expandedPanelMouseDown(at: CGPoint(x: frame.midX, y: frame.midY))
        #expect(f.panel.isKey)
        f.host.expandedPanelMouseDown(at: CGPoint(x: frame.midX, y: frame.minY - 10))
        #expect(!f.host.isExpanded)
    }

    @Test func noIslandMeansNoExpandedView() async {
        let f = ExpandedFixture()
        await f.start()
        f.host.anchorsOverride = []
        f.host.expand(focus: f.intent)
        #expect(!f.host.isExpanded)
        #expect(f.panel.log.isEmpty)
    }

    @Test func anchorIsTheDisplayUnderThePointerElseTheMainVigieDisplay() {
        let main = IslandAnchor(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            islandFrame: CGRect(x: 536, y: 950, width: 440, height: 32),
            notchRect: CGRect(x: 656, y: 950, width: 200, height: 32))
        let side = IslandAnchor(
            screenFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
            islandFrame: CGRect(x: 2252, y: 1048, width: 440, height: 32),
            notchRect: CGRect(x: 2372, y: 1048, width: 200, height: 32))
        #expect(IslandAnchor.select([main, side], pointer: CGPoint(x: 2000, y: 1080)) == side)
        #expect(IslandAnchor.select([main, side], pointer: CGPoint(x: 100, y: 982)) == main)
        #expect(IslandAnchor.select([main, side], pointer: CGPoint(x: -500, y: 300)) == main)
        #expect(IslandAnchor.select([], pointer: .zero) == nil)
    }

    @Test func panelFrameStaysOnScreen() {
        let anchor = IslandAnchor(
            screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            islandFrame: CGRect(x: 0, y: 568, width: 300, height: 32),
            notchRect: CGRect(x: 50, y: 568, width: 200, height: 32))
        let frame = anchor.panelFrame(size: CGSize(width: 720, height: 420))
        #expect(frame == CGRect(x: 0, y: 180, width: 720, height: 420))
    }

    @Test func hostControlExpandsOnlyWithAnIntent() async {
        let f = ExpandedFixture()
        await f.start()
        let control = CoreHostControl(moduleID: "shelf", link: NotchHostLink(host: f.host))
        control.expand(focus: nil)
        control.openOwnTab(focus: nil)
        #expect(!f.host.isExpanded)
        control.openOwnTab(focus: f.intent)
        #expect(f.host.isExpanded)
        #expect(f.host.selectedTabID == "shelf")
        #expect(throws: ModuleServiceError.self) { try control.registerDynamicModule(TabModule("x")) }
        // Unbound link: nothing happens.
        CoreHostControl(moduleID: "shelf", link: NotchHostLink()).expand(focus: f.intent)
    }

    @Test func contextFactoryUsesTheInjectedHostControl() {
        let link = NotchHostLink()
        let factory = CoreModuleContextFactory(
            environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus(),
            hostControl: { CoreHostControl(moduleID: $0, link: link) })
        let manifest = ModuleManifest(id: "shelf", name: "Shelf", icon: "tray")
        let context = factory.makeContext(for: manifest, tracker: RegistrationTracker())
        let control = context.host as? CoreHostControl
        #expect(control?.moduleID == "shelf")
        #expect(control?.link === link)
    }
}

@MainActor @Suite struct ExpandedPanelTests {
    @Test func appKitPanelBecomesKeyOnlyWhenAllowed() throws {
        _ = NSApplication.shared
        let f = ExpandedFixture()
        let panel = ExpandedPanel(host: f.host, rootView: Color.clear)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.level.rawValue > NotchPanel.islandLevel.rawValue)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        let outline = CGRect(x: 396, y: 562, width: 720, height: 420)
        panel.show(panelFrame: outline)
        #expect(panel.panelFrame == outline)
        let margin = ExpandedMetrics.shadowMargin
        #expect(panel.frame == CGRect(x: 396 - margin, y: 562 - margin, width: 720 + 2 * margin, height: 420 + margin))
        panel.allowsKey = true
        #expect(panel.canBecomeKey)
        panel.hide()
        #expect(!panel.canBecomeKey)
        #expect(panel.panelFrame == nil)
        #expect(!panel.isVisible)
    }
}
