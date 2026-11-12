import AppKit
import ModuleKit
import Observation
import SwiftUI
import Testing
import VigieUI

@testable import VigieCore

@Suite struct VirtualNotchGeometryTests {
    static let plain1080 = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
    static let menuBar = MenuBarMetrics(height: 24, statusItemsMinX: 1500)

    func geometry(
        _ settings: VirtualNotchSettings = .default, screen: ScreenMetrics = Self.plain1080,
        menuBar: MenuBarMetrics = Self.menuBar, idle: Bool = false, overlap: CGFloat = 0
    ) -> NotchGeometry {
        NotchGeometry.virtual(
            screen: screen, settings: settings, menuBar: menuBar, maxSideWidth: 120, cornerRadius: 14,
            isIdle: idle, overlap: overlap)
    }

    @Test func plainDisplayGetsAMenuBarTallPillCentredOverTheMenuBar() {
        let g = geometry()
        #expect(g.isVirtual)
        #expect(!g.isFloating)
        #expect(g.notchRect == CGRect(x: 860, y: 1056, width: 200, height: 24))
        #expect(g.islandFrame == CGRect(x: 740, y: 1056, width: 440, height: 24))
        #expect(g.islandFrame.maxY == 1080)  // over the menu bar, top edge on the screen edge
        #expect(g.wings == IslandWings(leading: 120, notch: 200, trailing: 120))
        #expect(g.cornerRadius == 14)
    }

    // Story 2.16: the virtual notch is exactly as tall as the measured menu bar, plus `notch_overlap`.
    @Test(arguments: [CGFloat(24), 37])
    func heightIsTheMenuBarHeightOverTheMenuBar(menuBarHeight: CGFloat) {
        let g = geometry(menuBar: MenuBarMetrics(height: menuBarHeight))
        #expect(g.height == menuBarHeight)
        #expect(g.islandFrame.maxY == 1080)
        #expect(g.islandFrame.minY == 1080 - menuBarHeight)
        #expect(g.notchSlot.height == menuBarHeight)
        #expect(g.leadingWing.height == menuBarHeight && g.trailingWing.height == menuBarHeight)
        let overlapped = geometry(menuBar: MenuBarMetrics(height: menuBarHeight), overlap: 2)
        #expect(overlapped.height == menuBarHeight + 2)
        #expect(overlapped.islandFrame.maxY == 1080)  // the overlap hangs below the menu bar
        #expect(overlapped.notchRect.height == menuBarHeight + 2)
    }

    @Test(arguments: [CGFloat(24), 37])
    func belowPlacementIsMenuBarTallUnderTheMenuBar(menuBarHeight: CGFloat) {
        let g = geometry(
            VirtualNotchSettings(placement: .below), menuBar: MenuBarMetrics(height: menuBarHeight), overlap: 2)
        #expect(g.isFloating)
        #expect(g.islandFrame.maxY == 1080 - menuBarHeight)
        #expect(g.height == menuBarHeight + 2)
    }

    @Test func negativeOverlapIsIgnored() {
        #expect(geometry(overlap: -5).height == 24)
    }

    @Test func widthComesFromTheSettings() {
        let g = geometry(VirtualNotchSettings(width: 260))
        #expect(g.notchRect.width == 260)
        #expect(g.islandFrame.midX == 960)
    }

    @Test func idleShrinksToTheNotchKeepsOrHides() {
        let shrunk = geometry(VirtualNotchSettings(idle: .shrink), idle: true)
        #expect(shrunk.islandFrame.width == 200)
        #expect(shrunk.wings == IslandWings(leading: 0, notch: 200, trailing: 0))
        let kept = geometry(VirtualNotchSettings(idle: .keep), idle: true)
        #expect(kept.islandFrame.width == 440)
        let hidden = geometry(VirtualNotchSettings(idle: .hide), idle: true)
        #expect(hidden.islandFrame.width == 200)  // the host orders it out; the anchor stays
    }

    @Test func belowPlacementHangsJustUnderTheMenuBar() {
        let g = geometry(VirtualNotchSettings(placement: .below))
        #expect(g.isFloating)
        #expect(g.islandFrame.maxY == CGFloat(1056))
        #expect(g.hoverStrip?.maxY == 1080)  // the hover strip stays on the top edge
    }

    @Test func rightPositionSitsJustLeftOfTheStatusItems() {
        let g = geometry(VirtualNotchSettings(position: .right))
        #expect(g.islandFrame.maxX == 1500 - NotchGeometry.statusItemsGap)
        let idle = geometry(VirtualNotchSettings(position: .right), idle: true)
        #expect(idle.islandFrame.maxX == g.islandFrame.maxX)  // shrinks towards the left
        let unknown = geometry(VirtualNotchSettings(position: .right), menuBar: MenuBarMetrics(height: 24))
        #expect(unknown.islandFrame.midX == 960)
    }

    @Test func pillStaysOnScreen() {
        var screen = Self.plain1080
        screen.frame.origin = CGPoint(x: -1920, y: 300)
        let g = geometry(
            VirtualNotchSettings(position: .right), screen: screen,
            menuBar: MenuBarMetrics(height: 24, statusItemsMinX: -1900))
        #expect(g.islandFrame.minX == -1920)
        #expect(g.islandFrame.maxY == 1380)
        let wide = geometry(VirtualNotchSettings(width: 5000))
        #expect(wide.islandFrame.width <= 1920)
        #expect(wide.islandFrame.minX >= 0)
    }

    @Test func hoverStripIsWiderThanThePillAndAFewPointsTall() throws {
        let g = geometry()
        let strip = try #require(g.hoverStrip)
        #expect(strip.width > g.islandFrame.width)
        #expect(strip.midX == g.islandFrame.midX)
        #expect(strip.height == NotchGeometry.hoverStripHeight)
        #expect(strip.height <= 6)
        #expect(strip.maxY == 1080)
    }

    @Test func physicalNotchHasNoHoverStrip() throws {
        let g = try #require(
            NotchGeometry.physical(
                screen: NotchGeometryTests.macBookPro14, bandHeight: 34, maxSideWidth: 120, cornerRadius: 14))
        #expect(g.hoverStrip == nil)
        #expect(!g.isVirtual)
    }

    @Test func settingsParseRawConfigValuesWithDefaults() {
        let parsed = VirtualNotchSettings(
            width: 240, idle: "hide", position: "right", placement: "below", style: "menu_bar")
        #expect(
            parsed
                == VirtualNotchSettings(width: 240, idle: .hide, position: .right, placement: .below, style: .menuBar))
        let fallback = VirtualNotchSettings(width: nil, idle: "bogus", position: nil, placement: nil, style: nil)
        #expect(fallback == .default)
        #expect(VirtualNotchSettings.default.width == 200)
    }

    @Test func classifiesDisplays() {
        #expect(DisplayInfo.classify(Self.plain1080) == .plain)
        #expect(DisplayInfo.classify(NotchGeometryTests.macBookPro14) == .physical)
        #expect(DisplayInfo.Kind.island.usesVirtualNotch)
        #expect(DisplayInfo.Kind.plain.usesVirtualNotch)
        #expect(!DisplayInfo.Kind.physical.usesVirtualNotch)
    }
}

// MARK: Host

@MainActor
final class FakeIslandPanel: IslandPanelHosting {
    let displayID: CGDirectDisplayID
    private(set) var frame: CGRect?
    private(set) var isShown = false
    private(set) var placements = 0

    init(displayID: CGDirectDisplayID) { self.displayID = displayID }

    func place(frame: CGRect) {
        self.frame = frame
        placements += 1
    }

    private(set) var hidesInFullScreen: Bool?

    func show() { isShown = true }
    func hide() { isShown = false }
    func setHidesInFullScreen(_ hides: Bool) { hidesInFullScreen = hides }
}

@MainActor
final class FakeMenuBarProbe: MenuBarProbing {
    var autoHidesMenuBar = false
    var visible = true
    var height: CGFloat = 24
    func menuBar(on screenFrame: CGRect) -> MenuBarMetrics { MenuBarMetrics(height: height) }
    func isMenuBarVisible(on screenFrame: CGRect) -> Bool { visible }
}

@MainActor @Observable
final class WingModule: NotchModule {
    let manifest: ModuleManifest
    var state: ModuleState = .hidden
    var items: [LeftWingItem] = []

    init(_ id: ModuleID) { manifest = ModuleManifest(id: id, name: "Wing", icon: "circle") }

    func leftWingItems() -> [LeftWingItem] { items }
    func start(context: any ModuleContext) async throws {}
    func stop() async {}
}

extension DisplayInfo {
    static func plain(_ id: CGDirectDisplayID, x: CGFloat = 0, main: Bool = false, name: String? = nil) -> DisplayInfo {
        DisplayInfo(
            id: id, name: name ?? "Plain \(id)", kind: .plain, isMain: main, isBuiltIn: false,
            metrics: ScreenMetrics(
                frame: CGRect(x: x, y: 0, width: 1920, height: 1080), safeAreaTop: 0, auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil))
    }

    static func notched(_ id: CGDirectDisplayID, x: CGFloat = 0, main: Bool = false) -> DisplayInfo {
        var metrics = NotchGeometryTests.macBookPro14
        metrics.frame.origin.x = x
        metrics.auxiliaryTopLeftArea?.origin.x += x
        metrics.auxiliaryTopRightArea?.origin.x += x
        return DisplayInfo(
            id: id, name: "Built-in Retina Display", kind: .physical, isMain: main, isBuiltIn: true, metrics: metrics)
    }
}

@MainActor
final class DisplayHostFixture {
    var displays: [DisplayInfo]
    var settings = VirtualNotchSettings.default
    var selection = DisplaySelection.notched
    var hideInFullScreen = true
    var notchOverlap: CGFloat = 0
    var notchSideInset: CGFloat = 0
    var promptPending = false
    var answers: [DisplayPromptAnswer] = []
    var pointer = CGPoint.zero
    let probe = FakeMenuBarProbe()
    var panels: [FakeIslandPanel] = []
    let module = WingModule("time")
    let registry: ModuleRegistry
    let themeController: ThemeController
    var host: NotchHost!

    init(_ displays: [DisplayInfo], look: AppearanceMode = .dark, accessibility: AccessibilityAdjustments = .none) {
        self.displays = displays
        let module = module
        registry = ModuleRegistry(
            descriptors: [ModuleDescriptor(manifest: module.manifest) { module }],
            enablement: TestEnablement(),
            contextFactory: CoreModuleContextFactory(
                environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus()),
            logger: testLogger)
        themeController = ThemeController(
            library: try! ThemeLoader.loadBundled(), mode: look, accessibility: accessibility)
        host = NotchHost(
            themeController: themeController, registry: registry, contextMenu: NotchContextMenu(),
            notchOverlap: { [unowned self] in self.notchOverlap },
            notchSideInset: { [unowned self] in self.notchSideInset },
            virtualNotch: { [unowned self] in self.settings },
            displaySelection: { [unowned self] in self.selection },
            hideInFullScreen: { [unowned self] in self.hideInFullScreen },
            displayPromptPending: { [unowned self] in self.promptPending },
            onDisplayPromptAnswer: { [unowned self] in self.answers.append($0) },
            displays: { [unowned self] in self.displays },
            menuBarProbe: probe,
            makeIslandPanel: { [unowned self] _, id in
                let panel = FakeIslandPanel(displayID: id)
                self.panels.append(panel)
                return panel
            },
            pointerLocation: { [unowned self] in self.pointer },
            logger: testLogger)
    }

    func panel(_ id: CGDirectDisplayID) -> FakeIslandPanel? {
        host.panels[id] as? FakeIslandPanel
    }

    /// Gives the left wing an item, so the island is not idle.
    func makeBusy() async {
        await registry.start()
        module.items = [LeftWingItem(id: "clock", priority: 10) { _ in AnyView(Color.clear) }]
        module.state = .ambient
        host.rearbitrate()
    }
}

@MainActor @Suite struct VirtualNotchHostTests {
    @Test func plainDisplayShowsAVirtualNotch() throws {
        let f = DisplayHostFixture([.plain(1, main: true)])
        f.host.start()
        defer { f.host.stop() }
        let island = try #require(f.host.islands.first)
        #expect(island.geometry.isVirtual)
        #expect(f.host.displayMode == .virtual(.plain(1, main: true)))
        #expect(island.surface == .black)
        #expect(f.panel(1)?.isShown == true)
        #expect(f.panel(1)?.frame == island.geometry.islandFrame)
        #expect(f.host.anchor(forDisplayUnder: CGPoint(x: 10, y: 10))?.notchRect == island.geometry.notchRect)
    }

    @Test func hardwareNotchWinsOverAPlainDisplay() throws {
        let f = DisplayHostFixture([.plain(1, x: 1512, main: true), .notched(2)])
        f.host.start()
        defer { f.host.stop() }
        let island = try #require(f.host.islands.first)
        #expect(!island.geometry.isVirtual)
        #expect(f.host.activeDisplayID == 2)
    }

    @Test func idleHideOrdersThePanelOutButKeepsTheAnchor() async throws {
        let f = DisplayHostFixture([.plain(1, main: true)])
        f.settings.idle = .hide
        f.host.start()
        defer { f.host.stop() }
        #expect(f.host.isIdle)
        #expect(f.host.islands.first?.isHidden == true)
        #expect(f.panel(1)?.isShown == false)
        #expect(f.host.islandAnchors.count == 1)  // a peek can still appear

        await f.makeBusy()
        #expect(!f.host.isIdle)
        #expect(f.host.islands.first?.isHidden == false)
        #expect(f.panel(1)?.isShown == true)
        #expect(f.host.geometry?.islandFrame.width == 440)
    }

    @Test func idleShrinkResizesTheSamePanel() async throws {
        let f = DisplayHostFixture([.plain(1, main: true)])
        f.host.start()
        defer { f.host.stop() }
        let panel = try #require(f.panel(1))
        #expect(panel.frame?.width == 200)
        await f.makeBusy()
        #expect(f.panel(1) === panel)
        #expect(panel.frame?.width == 440)
    }

    @Test func hoverStripShowsAHiddenPillAndPlaysTheReaction() throws {
        let f = DisplayHostFixture([.plain(1, main: true)])
        f.settings.idle = .hide
        f.host.start()
        defer { f.host.stop() }
        let strip = try #require(f.host.islands.first?.geometry.hoverStrip)
        f.host.stripPointerMoved(to: CGPoint(x: strip.minX + 2, y: 1080))
        #expect(f.host.hoverStripDisplayID == 1)
        #expect(f.panel(1)?.isShown == true)
        f.host.stripPointerMoved(to: CGPoint(x: 960, y: 1060))  // down onto the pill
        #expect(f.host.hoverStripDisplayID == 1)
        f.host.stripPointerMoved(to: CGPoint(x: 960, y: 500))
        #expect(f.host.hoverStripDisplayID == nil)
        #expect(f.panel(1)?.isShown == false)
    }

    @Test func autoHiddenMenuBarHidesTheVirtualNotchWithIt() {
        let f = DisplayHostFixture([.plain(1, main: true)])
        f.probe.autoHidesMenuBar = true
        f.probe.visible = false
        f.host.start()
        defer { f.host.stop() }
        #expect(f.panel(1)?.isShown == false)
        #expect(f.host.islandAnchors.count == 1)  // alerts still peek
        f.probe.visible = true
        f.host.refreshMenuBarVisibility()
        #expect(f.panel(1)?.isShown == true)
        f.probe.visible = false
        f.host.refreshMenuBarVisibility()
        #expect(f.panel(1)?.isShown == false)
    }

    @Test func autoHideNeverHidesAHardwareNotch() {
        let f = DisplayHostFixture([.notched(1, main: true)])
        f.probe.autoHidesMenuBar = true
        f.probe.visible = false
        f.host.start()
        defer { f.host.stop() }
        #expect(f.panel(1)?.isShown == true)
    }

    @Test func menuBarStyleUsesTheLightRoleSetInLightAppearance() throws {
        let f = DisplayHostFixture([.plain(1, main: true)], look: .light)
        f.settings.style = .menuBar
        f.host.start()
        defer { f.host.stop() }
        let island = try #require(f.host.islands.first)
        #expect(island.surface == .menuBar)
        let theme = f.host.theme(for: island)
        #expect(theme.look == .light)
        #expect(theme.defines(.surfaceVNTop) && theme.defines(.surfaceVNBottom))
        #expect(island.surface.roles(theme) == [.surfaceVNTop, .surfaceVNBottom])
    }

    @Test func menuBarStyleFallsBackToTheBlackIslandInDarkAppearance() throws {
        let f = DisplayHostFixture([.plain(1, main: true)], look: .dark)
        f.settings.style = .menuBar
        f.host.start()
        defer { f.host.stop() }
        let island = try #require(f.host.islands.first)
        let theme = f.host.theme(for: island)
        #expect(theme.look == .dark)
        #expect(theme.themeColor(.surfaceVNTop) == theme.themeColor(.island))
        #expect(theme.themeColor(.surfaceVNBottom) == theme.themeColor(.island))
    }

    @Test func reduceTransparencyFlattensTheMenuBarStyle() throws {
        let f = DisplayHostFixture(
            [.plain(1, main: true)], look: .light, accessibility: AccessibilityAdjustments(reduceTransparency: true))
        f.settings.style = .menuBar
        f.host.start()
        defer { f.host.stop() }
        let island = try #require(f.host.islands.first)
        #expect(island.surface.roles(f.host.theme(for: island)) == [.surfaceVNBottom])
    }

    @Test func blackStyleUsesTheIslandThemeInLightAppearance() throws {
        let f = DisplayHostFixture([.plain(1, main: true)], look: .light)
        f.host.start()
        defer { f.host.stop() }
        let island = try #require(f.host.islands.first)
        #expect(f.host.theme(for: island).look == .dark)
        #expect(island.surface.roles(f.host.theme(for: island)) == [.island])
    }

    @Test func reloadAppliesNewSettings() {
        let f = DisplayHostFixture([.plain(1, main: true)])
        f.host.start()
        defer { f.host.stop() }
        f.settings.placement = .below
        f.host.reloadDisplayConfiguration()
        #expect(f.host.geometry?.islandFrame.maxY == CGFloat(1056))
        #expect(f.host.geometry?.isFloating == true)
    }

    // Story 2.16: the theme band (34 px) never sets a virtual notch's height.
    @Test func themeBandHeightIsIgnoredForAVirtualNotch() throws {
        let f = DisplayHostFixture([.plain(1, main: true)])
        #expect(f.themeController.islandTheme.spacing(.bandHeight) == 34)
        f.notchOverlap = 2
        f.host.start()
        defer { f.host.stop() }
        let island = try #require(f.host.islands.first)
        #expect(island.geometry.height == 26)
        #expect(island.geometry.islandFrame.maxY == 1080)
        #expect(f.panel(1)?.frame == island.geometry.islandFrame)
    }

    @Test func menuBarHeightChangeIsFollowedOnReplace() throws {
        let f = DisplayHostFixture([.plain(1, main: true)])
        f.probe.height = 24
        f.host.start()
        defer { f.host.stop() }
        #expect(f.host.islands.first?.geometry.height == 24)
        #expect(f.panel(1)?.frame?.height == 24)

        f.probe.height = 37  // display scaling changed
        f.host.reloadDisplayConfiguration()
        #expect(f.host.islands.first?.geometry.height == 37)
        #expect(f.panel(1)?.frame?.height == 37)
        #expect(f.panel(1)?.frame?.maxY == 1080)
        let island = try #require(f.host.islands.first)
        #expect(f.host.theme(for: island).spacing(.bandHeight) == 37)
    }

    @Test func virtualIslandContentGetsTheIslandHeightAsItsBand() throws {
        let f = DisplayHostFixture([.plain(1, main: true)])
        f.host.start()
        defer { f.host.stop() }
        let island = try #require(f.host.islands.first)
        let theme = f.host.theme(for: island)
        #expect(theme.spacing(.bandHeight) == 24)
        #expect(theme.closedBand.isCompact)
        #expect(theme.look == f.themeController.islandTheme.look)
    }

    @Test func physicalIslandKeepsTheThemeBand() throws {
        let f = DisplayHostFixture([.notched(1, main: true)])
        f.notchOverlap = 2
        f.host.start()
        defer { f.host.stop() }
        let island = try #require(f.host.islands.first)
        #expect(!island.geometry.isVirtual)
        let expected = try #require(
            NotchGeometry.physical(
                screen: NotchGeometryTests.macBookPro14, bandHeight: 34, maxSideWidth: 120, cornerRadius: 14,
                overlap: 2))
        #expect(island.geometry.islandFrame == expected.islandFrame)  // max(band 34, notch 32) + overlap
        #expect(f.host.theme(for: island) == f.themeController.islandTheme)
    }

    @Test func geometryLogRecordsTheMenuBarHeightForAVirtualIsland() throws {
        let f = DisplayHostFixture([.plain(1, main: true), .notched(2, x: 1920)])
        f.selection = .all
        f.notchOverlap = 2
        f.probe.height = 24
        f.host.start()
        defer { f.host.stop() }
        let line = try #require(f.host.lastNotchGeometryLines[1])
        #expect(line.contains("virtual"))
        #expect(line.contains("menuBarHeight=24.0"))
        #expect(line.contains("overlap=2.0"))
        let frame = try #require(f.host.islands.first { $0.display.id == 1 }?.geometry.islandFrame)
        #expect(line.contains("island=\(NSStringFromRect(frame))"))
        #expect(f.host.lastNotchGeometryLines[2]?.contains("safeAreaTop=") == true)
    }

    @Test func noDisplayNoIsland() {
        let f = DisplayHostFixture([])
        f.host.start()
        defer { f.host.stop() }
        #expect(f.host.islands.isEmpty)
        #expect(f.host.displayMode == .none)
        #expect(f.host.anchor(forDisplayUnder: .zero) == nil)
    }
}
