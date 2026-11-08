import AppKit
import ModuleKit
import Observation
import SwiftUI
import VigieUI
import os

/// Where the main Vigie island lives.
public enum NotchDisplayMode: Equatable, Sendable {
    /// Around the hardware notch of this display.
    case physical(DisplayInfo)
    /// A virtual notch drawn by Vigie on this plain display (SPEC §5.5).
    case virtual(DisplayInfo)
    /// Nowhere: no display shows Vigie.
    case none
}

/// One placed island: its display, geometry and how it is drawn.
public struct PlacedIsland: Sendable, Equatable {
    public var display: DisplayInfo
    public var geometry: NotchGeometry
    /// The fill: black on a hardware notch and for `virtual_notch.style = "black"`.
    public var surface: IslandSurface
    /// True while the island is placed but not drawn: an idle virtual notch with `idle = hide`, or a virtual
    /// notch whose auto-hidden menu bar is hidden (FR11, FR26). Peeks still anchor on it.
    public var isHidden: Bool

    public var anchor: IslandAnchor {
        IslandAnchor(screenFrame: display.frame, islandFrame: geometry.islandFrame, notchRect: geometry.notchRect)
    }
}

/// The island window as the host drives it. ``NotchPanel`` in production; tests use a fake.
@MainActor
public protocol IslandPanelHosting: AnyObject {
    /// Moves the window to `frame` (global AppKit coordinates) without animation.
    func place(frame: CGRect)
    /// Orders the window front without taking focus.
    func show()
    func hide()
    var isShown: Bool { get }
    /// `general.hide_in_fullscreen` (FR20): true keeps the window out of full-screen spaces, so it disappears
    /// on a display that has a full-screen app open.
    func setHidesInFullScreen(_ hides: Bool)
}

/// Owns the island panels and their placement (AD-2): classifies the displays, lays out the island around the
/// hardware notch or draws a virtual notch on a plain display (SPEC §5.3–5.5), follows screen changes, and fills
/// the wings.
///
/// The wings come from ``ClosedNotchArbiter`` (SPEC §5): ``leadingLayout`` and ``trailingLayout`` are
/// recomputed on the main actor whenever a running module's `state` (or anything its `leftWingItems()` reads)
/// changes, a module starts or stops, or a transient readout comes or goes. Call ``rearbitrate()`` when
/// `closed.slots` changes, and ``reloadDisplayConfiguration()`` when `[display]`, `[virtual_notch]`,
/// `closed.max_side_width` or `general.hide_in_fullscreen` change.
///
/// The expanded view (Story 2.10, SPEC §10) opens only on a click on the island, the expand hotkey or, when
/// `open_on_hover` is on, a hover longer than `hover_delay`; see `NotchHost+Expanded.swift`.
@MainActor @Observable
public final class NotchHost {
    /// The connected displays at the last placement.
    public private(set) var displays: [DisplayInfo] = []
    /// The placed islands, main Vigie display first.
    public private(set) var islands: [PlacedIsland] = []
    /// The display whose island fades in on hover from the top-center strip (FR27), while the pointer is there.
    public private(set) var hoverStripDisplayID: CGDirectDisplayID?
    /// True while the one-time display prompt waits in the expanded view (Story 2.7, A60): the App reports it
    /// pending and a display without a notch is connected. The island carries a marker meanwhile.
    public private(set) var showsDisplayPrompt = false

    /// The main Vigie display: where peeks go when the display under the pointer shows no island.
    public var activeDisplayID: CGDirectDisplayID? { islands.first?.display.id }
    public var displayMode: NotchDisplayMode {
        guard let island = islands.first else { return .none }
        return island.geometry.isVirtual ? .virtual(island.display) : .physical(island.display)
    }
    /// The main Vigie display's island geometry.
    public var geometry: NotchGeometry? { islands.first?.geometry }
    public var isPresented: Bool { panels.values.contains { $0.isShown } }
    /// The main island frame in global AppKit coordinates, when placed.
    public var frame: CGRect? { geometry?.islandFrame }
    /// The left wing: the shared item lane.
    public private(set) var leadingLayout = SideLayout.empty
    /// The right wing: `agents.sessions` only.
    public private(set) var trailingLayout = SideLayout.empty
    /// The transient readout on the left wing, while it lasts.
    public private(set) var transient: TransientReadout?
    /// The drain line under ``transient`` (readouts that drain only), held full while the pointer is over the
    /// notch.
    public private(set) var transientDrain: TransientDrain?
    /// True while the pointer is over a closed island (hover holds a transient readout).
    public private(set) var isPointerOverIsland = false
    /// True from `expand` until `collapse` (the panel stays on screen for the exit motion after that).
    public internal(set) var isExpanded = false
    /// The active tab of the expanded view; nil shows the first tab.
    public var selectedTabID: String?
    /// The closed island's size when the expanded view opened: where it grows from.
    public internal(set) var expansionOrigin: CGSize = .zero

    @ObservationIgnored let themeController: ThemeController
    /// Privacy mode (AD-24): read by every surface root (`privacyActive`). Nothing is added to the closed notch.
    @ObservationIgnored public let privacy: CorePrivacyService
    @ObservationIgnored let registry: ModuleRegistry
    @ObservationIgnored private let contextMenu: NotchContextMenu
    @ObservationIgnored private let maxSideWidth: @MainActor () -> CGFloat
    @ObservationIgnored private let closedSlots: @MainActor () -> Int
    @ObservationIgnored private let virtualNotch: @MainActor () -> VirtualNotchSettings
    @ObservationIgnored private let displaySelection: @MainActor () -> DisplaySelection
    @ObservationIgnored private let hideInFullScreen: @MainActor () -> Bool
    @ObservationIgnored private let displayPromptPending: @MainActor () -> Bool
    @ObservationIgnored private let onDisplayPromptAnswer: (@MainActor (DisplayPromptAnswer) -> Void)?
    @ObservationIgnored private var displayPromptAnswered = false
    @ObservationIgnored private let menuBarProbe: any MenuBarProbing
    @ObservationIgnored private var arbitrationGeneration = 0
    @ObservationIgnored private var transientTask: Task<Void, Never>?
    /// The current readout's duration (nil: a progress readout, shown until replaced or cleared).
    @ObservationIgnored private var transientDuration: Duration?
    @ObservationIgnored private var transientTrigger = 0
    /// Posts a VoiceOver announcement; `NSAccessibility.post(.announcementRequested)` by default.
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let readDisplays: @MainActor () -> [DisplayInfo]
    @ObservationIgnored let logger: Logger
    @ObservationIgnored private let makeIslandPanel: @MainActor (NotchHost, CGDirectDisplayID) -> any IslandPanelHosting
    @ObservationIgnored private(set) var panels: [CGDirectDisplayID: any IslandPanelHosting] = [:]
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var layoutScheduled = false
    @ObservationIgnored private var lastIdle: Bool?
    @ObservationIgnored private(set) var hiddenMenuBars: Set<CGDirectDisplayID> = []
    @ObservationIgnored private var menuBarTimer: Timer?
    @ObservationIgnored private var stripMonitors: [Any] = []

    // Expanded view (NotchHost+Expanded.swift).
    @ObservationIgnored let focusPolicy: FocusPolicy
    @ObservationIgnored let openOnHover: @MainActor () -> Bool
    @ObservationIgnored let hoverDelay: @MainActor () -> Duration
    @ObservationIgnored let closeOnLeave: @MainActor () -> Bool
    @ObservationIgnored let tabOrder: @MainActor () -> [String]
    @ObservationIgnored let pointerLocation: @MainActor () -> CGPoint
    @ObservationIgnored let makeExpandedPanel: @MainActor (NotchHost) -> any ExpandedPanelHosting
    /// Opens the Settings window from the gear; nil keeps the gear inert (until Story 2.14).
    @ObservationIgnored public let openSettings: (@MainActor () -> Void)?
    /// Opens Settings on a pane (the Home empty state's `Open settings` → Settings › Home).
    @ObservationIgnored let openSettingsPane: (@MainActor (String) -> Void)?
    /// `[home] cards`: provider ids in Home order (Story 11.1).
    @ObservationIgnored let homeCardOrder: @MainActor () -> [String]
    /// Home cards from providers that are not modules (scripts with the `home` surface, Epic 12).
    @ObservationIgnored let additionalHomeCards: @MainActor () -> [HomeCardModel]
    /// `[home] cards` ids already logged as offering no card, so each is logged once.
    @ObservationIgnored var loggedMissingHomeCards: Set<String> = []
    @ObservationIgnored let expandedSurface = ExpandedSurface()
    @ObservationIgnored var expandedPanel: (any ExpandedPanelHosting)?
    @ObservationIgnored var expansionGeneration = 0
    @ObservationIgnored var hoverTask: Task<Void, Never>?
    @ObservationIgnored var hideTask: Task<Void, Never>?
    @ObservationIgnored var eventMonitors: [Any] = []
    @ObservationIgnored var pointerWasInside = false
    /// Test seam: anchors used instead of the laid-out island.
    @ObservationIgnored var anchorsOverride: [IslandAnchor]?
    /// The drag-only drop display (Story 9.1): file drags over an island open it with the running modules'
    /// `dropZones`. Peeks wait while it is open.
    @ObservationIgnored public let dropDisplay: DropDisplayController

    /// - Parameters:
    ///   - maxSideWidth: `closed.max_side_width` (SPEC §5.3, default 120).
    ///   - closedSlots: `closed.slots` (SPEC §5, default 3, clamped 1…4).
    ///   - virtualNotch: `[virtual_notch]` (SPEC §5.5); `VirtualNotchSettings(configStore:)` in production.
    ///   - displaySelection: `[display] display` (SPEC §5.4); `DisplaySelection(configStore:)` in production.
    ///   - hideInFullScreen: `[general] hide_in_fullscreen` (default true).
    ///   - displayPromptPending: true until the one-time display prompt was answered or dismissed (A60); the App
    ///     persists that.
    ///   - onDisplayPromptAnswer: the App writes `[display] display` for `.choose` and records the prompt as done.
    ///   - displays: the connected displays; ``DisplayInfo/current(_:)`` in production.
    ///   - menuBarProbe: menu bar height, status items and auto-hide; ``SystemMenuBarProbe`` in production.
    ///   - makeIslandPanel: builds an island window for a display; a ``NotchPanel`` in production.
    ///   - focusPolicy: the app-wide focus arbiter (AD-13); the expanded view is one of its surfaces.
    ///   - openOnHover: `[general] open_on_hover` (default false).
    ///   - hoverDelay: `[general] hover_delay` (default 150 ms).
    ///   - closeOnLeave: `[general] close_on_leave` (default false).
    ///   - tabOrder: `[general] tab_order`, module ids (default empty: registry order).
    ///   - openSettings: opens the Settings window from the gear; nil until Story 2.14.
    ///   - openSettingsPane: opens Settings on a pane id (`home` from the Home empty state); nil falls back to
    ///     `openSettings`.
    ///   - homeCardOrder: `[home] cards`, provider ids in Home order (default empty: the Home empty state).
    ///   - additionalHomeCards: cards of providers that are not modules (scripts, Epic 12).
    ///   - pointerLocation: the pointer in global AppKit coordinates; `NSEvent.mouseLocation` in production.
    ///   - makeExpandedPanel: builds the expanded panel window; an ``ExpandedPanel`` in production.
    ///   - dropsDirectory: `AppEnvironment.dropsDirectory`, where file promises are materialized (AD-17, AD-19);
    ///     nil refuses file promises.
    ///   - dropEscape: Esc while the drop display is open; a ``SystemDropEscapeMonitor`` by default.
    ///   - makeDropDisplayPanel: builds the drop display window; a ``DropDisplayPanelController`` in production.
    ///   - announce: posts a VoiceOver announcement (a transient readout's); the system one by default.
    ///   - privacy: the launch's Privacy mode state (Story 21.2); one that is off by default.
    public init(
        themeController: ThemeController,
        registry: ModuleRegistry,
        contextMenu: NotchContextMenu,
        maxSideWidth: @escaping @MainActor () -> CGFloat = { 120 },
        closedSlots: @escaping @MainActor () -> Int = { ClosedNotchArbiter.defaultSlots },
        virtualNotch: @escaping @MainActor () -> VirtualNotchSettings = { .default },
        displaySelection: @escaping @MainActor () -> DisplaySelection = { .notched },
        hideInFullScreen: @escaping @MainActor () -> Bool = { true },
        displayPromptPending: @escaping @MainActor () -> Bool = { false },
        onDisplayPromptAnswer: (@MainActor (DisplayPromptAnswer) -> Void)? = nil,
        displays: @escaping @MainActor () -> [DisplayInfo] = { DisplayInfo.current() },
        menuBarProbe: (any MenuBarProbing)? = nil,
        makeIslandPanel: (@MainActor (NotchHost, CGDirectDisplayID) -> any IslandPanelHosting)? = nil,
        focusPolicy: FocusPolicy = FocusPolicy(),
        openOnHover: @escaping @MainActor () -> Bool = { false },
        hoverDelay: @escaping @MainActor () -> Duration = { NotchHost.defaultHoverDelay },
        closeOnLeave: @escaping @MainActor () -> Bool = { false },
        tabOrder: @escaping @MainActor () -> [String] = { [] },
        openSettings: (@MainActor () -> Void)? = nil,
        openSettingsPane: (@MainActor (String) -> Void)? = nil,
        homeCardOrder: @escaping @MainActor () -> [String] = { [] },
        additionalHomeCards: @escaping @MainActor () -> [HomeCardModel] = { [] },
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
        makeExpandedPanel: (@MainActor (NotchHost) -> any ExpandedPanelHosting)? = nil,
        dropsDirectory: URL? = nil,
        dropEscape: (any DropEscapeMonitoring)? = nil,
        dropModifierFlags: @escaping @MainActor () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags },
        dropExitGrace: Duration = DropDisplayController.defaultExitGrace,
        makeDropDisplayPanel: (@MainActor (DropDisplayController) -> any DropDisplayPanelDriver)? = nil,
        announce: (@MainActor (String) -> Void)? = nil,
        privacy: CorePrivacyService? = nil,
        logger: Logger
    ) {
        self.privacy = privacy ?? CorePrivacyService()
        self.announce = announce ?? NotchHost.postAnnouncement
        self.themeController = themeController
        self.registry = registry
        self.contextMenu = contextMenu
        self.maxSideWidth = maxSideWidth
        self.closedSlots = closedSlots
        self.virtualNotch = virtualNotch
        self.displaySelection = displaySelection
        self.hideInFullScreen = hideInFullScreen
        self.displayPromptPending = displayPromptPending
        self.onDisplayPromptAnswer = onDisplayPromptAnswer
        self.readDisplays = displays
        self.menuBarProbe = menuBarProbe ?? SystemMenuBarProbe()
        self.focusPolicy = focusPolicy
        self.openOnHover = openOnHover
        self.hoverDelay = hoverDelay
        self.closeOnLeave = closeOnLeave
        self.tabOrder = tabOrder
        self.openSettings = openSettings
        self.openSettingsPane = openSettingsPane
        self.homeCardOrder = homeCardOrder
        self.additionalHomeCards = additionalHomeCards
        self.pointerLocation = pointerLocation
        self.makeIslandPanel =
            makeIslandPanel ?? { host, id in
                let panel = NotchPanel(
                    contentRect: .zero,
                    rootView: NotchRootView(host: host, displayID: id, themeController: host.themeController),
                    contextMenu: host.contextMenu)
                panel.onClick = { [weak host] in host?.islandClicked() }
                panel.dragTarget = IslandDragTarget(controller: host.dropDisplay, displayID: id)
                return panel
            }
        self.makeExpandedPanel =
            makeExpandedPanel ?? { host in
                ExpandedPanel(host: host, rootView: ExpandedRootView(host: host, themeController: themeController))
            }
        self.logger = logger
        dropDisplay = DropDisplayController(
            zones: { [registry] in registry.runningModules.flatMap(\.dropZones) },
            theme: { [themeController] in themeController.theme },
            dropsDirectory: dropsDirectory,
            escape: dropEscape,
            modifierFlags: dropModifierFlags,
            exitGrace: dropExitGrace,
            makeDriver: makeDropDisplayPanel ?? { controller in
                DropDisplayPanelController(themeController: themeController, controller: controller)
            },
            logger: logger)
        expandedSurface.host = self
        dropDisplay.anchorProvider = { [weak self] id in self?.dropAnchor(for: id) }
        dropDisplay.onReadout = { [weak self] text in self?.showTransient(.message(text)) }
        dropDisplay.onConfirmation = { [weak self] readout in self?.showTransient(readout) }
        dropDisplay.onProgress = { [weak self] text in
            if let text { self?.showProgress(.message(text)) } else { self?.clearTransient() }
        }
    }

    /// Where the drop display grows: the island of `displayID`, else the one under the pointer (else main).
    func dropAnchor(for displayID: CGDirectDisplayID?) -> IslandAnchor? {
        if let displayID, anchorsOverride == nil, let island = island(for: displayID) { return island.anchor }
        return anchor(forDisplayUnder: pointerLocation())
    }

    /// Places the islands and follows screen parameter changes until `stop()`.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersChanged() }
        }
        rearbitrate()
        layout()
    }

    public func stop() {
        dropDisplay.cancel()
        collapse()
        hideTask?.cancel()
        expandedPanel?.hide()
        expandedPanel = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        isStarted = false
        arbitrationGeneration += 1  // drops the armed observation
        transientTask?.cancel()
        transientTask = nil
        transient = nil
        transientDrain = nil
        transientDuration = nil
        for panel in panels.values { panel.hide() }
        panels = [:]
        islands = []
        hoverStripDisplayID = nil
        setMenuBarPolling(false)
        setStripMonitors(false)
    }

    /// Re-reads the display settings (`[display]`, `[virtual_notch]`, `closed.max_side_width`,
    /// `general.hide_in_fullscreen`) and re-places the islands. The App calls it when ConfigStore reports a change
    /// under those keys.
    public func reloadDisplayConfiguration() {
        guard isStarted else { return }
        layout()
    }

    /// A display was connected or disconnected, or a resolution, arrangement or lid change happened: re-place
    /// on the next run-loop turn (AppKit has settled the new screen list by then), coalescing bursts.
    func screenParametersChanged() {
        guard !layoutScheduled else { return }
        layoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.layoutScheduled = false
                if self.isStarted { self.layout() }
            }
        }
    }

    // MARK: Placement

    /// The displays that show an island, main Vigie display first (``DisplaySelector``).
    func selectedDisplays(_ displays: [DisplayInfo]) -> [DisplayInfo] {
        DisplaySelector.select(displays, selection: displaySelection())
    }

    /// True when no module wants either side (FR11).
    var isIdle: Bool { leadingLayout.isEmpty && trailingLayout.isEmpty }

    /// Recomputes the placement and moves, shows, hides, creates or removes the panels. A display that keeps its
    /// island keeps its panel: only its frame moves.
    func layout() {
        let displays = readDisplays()
        if displays != self.displays { self.displays = displays }
        let settings = virtualNotch()
        let idle = isIdle
        lastIdle = idle
        let autoHide = menuBarProbe.autoHidesMenuBar
        let chosen = selectedDisplays(displays)
        hiddenMenuBars =
            autoHide
            ? Set(chosen.filter { $0.kind.usesVirtualNotch && !menuBarProbe.isMenuBarVisible(on: $0.frame) }.map(\.id))
            : []
        let placed = chosen.compactMap { place($0, settings: settings, isIdle: idle) }
        if placed != islands { islands = placed }
        if placed.isEmpty {
            logger.info("No display shows Vigie")
        }
        let prompt =
            !displayPromptAnswered && displayPromptPending() && displays.contains { $0.kind.usesVirtualNotch }
        if prompt != showsDisplayPrompt { showsDisplayPrompt = prompt }
        syncPanels()
        let hasVirtual = placed.contains { $0.geometry.isVirtual }
        setMenuBarPolling(hasVirtual && autoHide)
        setStripMonitors(hasVirtual)
    }

    private func place(_ display: DisplayInfo, settings: VirtualNotchSettings, isIdle: Bool) -> PlacedIsland? {
        let theme = themeController.islandTheme
        let bandHeight = theme.spacing(.bandHeight)
        let radius = theme.radius(.islandClosed)
        if display.hasNotch {
            guard
                let geometry = NotchGeometry.physical(
                    screen: display.metrics, bandHeight: bandHeight, maxSideWidth: maxSideWidth(),
                    cornerRadius: radius)
            else {
                logger.error("Notch geometry unavailable for \(display.name, privacy: .public)")
                return nil
            }
            return PlacedIsland(display: display, geometry: geometry, surface: .black, isHidden: false)
        }
        let geometry = NotchGeometry.virtual(
            screen: display.metrics, settings: settings, menuBar: menuBarProbe.menuBar(on: display.frame),
            bandHeight: bandHeight, maxSideWidth: maxSideWidth(), cornerRadius: radius, isIdle: isIdle)
        let idleHidden = isIdle && settings.idle == .hide && hoverStripDisplayID != display.id
        return PlacedIsland(
            display: display, geometry: geometry, surface: settings.style == .menuBar ? .menuBar : .black,
            isHidden: idleHidden || hiddenMenuBars.contains(display.id))
    }

    private func syncPanels() {
        let ids = Set(islands.map(\.display.id))
        let hidesInFullScreen = hideInFullScreen()
        for (id, panel) in panels where !ids.contains(id) {
            panel.hide()
            panels[id] = nil
        }
        for island in islands {
            let id = island.display.id
            let panel = panels[id] ?? makeIslandPanel(self, id)
            panels[id] = panel
            panel.setHidesInFullScreen(hidesInFullScreen)
            panel.place(frame: island.geometry.islandFrame)
            if island.isHidden {
                panel.hide()
            } else {
                panel.show()
            }
        }
    }

    /// The placed island on a display.
    public func island(for displayID: CGDirectDisplayID) -> PlacedIsland? {
        islands.first { $0.display.id == displayID }
    }

    /// The theme an island draws with: the main theme for a light `menu_bar` virtual notch (light role set,
    /// `surface-vn-*`), the island (dark) theme otherwise (UX-DR76, OQ15).
    public func theme(for island: PlacedIsland) -> Theme {
        let main = themeController.theme
        return island.surface == .menuBar && main.look == .light ? main : themeController.islandTheme
    }

    /// The islands on screen, main Vigie display first.
    public var islandAnchors: [IslandAnchor] {
        if let anchorsOverride { return anchorsOverride }
        return islands.map(\.anchor)
    }

    /// The peek anchors (one per island) and the main Vigie display's, for ``PeekAnchor/select(pointer:islands:main:)``.
    public var peekAnchors: [PeekAnchor] {
        islands.map { PeekAnchor(screenFrame: $0.display.frame, geometry: $0.geometry) }
    }

    /// The island on the display under `pointer`, or on the main Vigie display when that display shows none
    /// (SPEC §5.4). Peeks and the expanded view anchor here.
    public func anchor(forDisplayUnder pointer: CGPoint) -> IslandAnchor? {
        IslandAnchor.select(islandAnchors, pointer: pointer)
    }

    /// The island frame (global AppKit coordinates) on the display under `pointer`, or on the main Vigie display.
    public func anchorFrame(forDisplayUnder pointer: CGPoint) -> CGRect? {
        anchor(forDisplayUnder: pointer)?.islandFrame
    }

    // MARK: Display prompt (A60)

    /// Answers the display prompt: hides it for good and hands the answer to the App, which writes
    /// `[display] display` and records the prompt as done.
    public func answerDisplayPrompt(_ answer: DisplayPromptAnswer) {
        displayPromptAnswered = true
        showsDisplayPrompt = false
        onDisplayPromptAnswer?(answer)
        if case .choose = answer {
            logger.info("Display prompt answered: \(String(describing: answer), privacy: .public)")
        }
    }

    /// "This display": the display the expanded view is on (else the one under the pointer, else the main Vigie
    /// display), by name.
    public func answerDisplayPromptWithThisDisplay() {
        guard let display = promptDisplay() else { return answerDisplayPrompt(.choose(.notched)) }
        answerDisplayPrompt(.choose(.named(display.name)))
    }

    func promptDisplay() -> DisplayInfo? {
        let point =
            expandedPanel?.panelFrame.map { CGPoint(x: $0.midX, y: $0.maxY) } ?? pointerLocation()
        return displays.first { Self.contains($0.frame, point) }
            ?? activeDisplayID.flatMap { id in displays.first { $0.id == id } }
    }

    // MARK: Auto-hidden menu bar (FR26)

    private func setMenuBarPolling(_ on: Bool) {
        if !on {
            menuBarTimer?.invalidate()
            menuBarTimer = nil
            return
        }
        guard menuBarTimer == nil else { return }
        let timer = Timer(timeInterval: Self.menuBarPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMenuBarVisibility() }
        }
        RunLoop.main.add(timer, forMode: .common)
        menuBarTimer = timer
    }

    /// How often the host checks whether an auto-hidden menu bar is showing.
    static let menuBarPollInterval: TimeInterval = 0.2

    /// Re-places when an auto-hidden menu bar appears or disappears on a display with a virtual notch.
    func refreshMenuBarVisibility() {
        let autoHide = menuBarProbe.autoHidesMenuBar
        let hidden: Set<CGDirectDisplayID> =
            autoHide
            ? Set(
                islands.filter { $0.geometry.isVirtual && !menuBarProbe.isMenuBarVisible(on: $0.display.frame) }
                    .map(\.display.id))
            : []
        if hidden != hiddenMenuBars || !autoHide { layout() }
    }

    // MARK: Hover strip (FR27)

    private func setStripMonitors(_ on: Bool) {
        guard on != !stripMonitors.isEmpty else { return }
        if !on {
            for monitor in stripMonitors { NSEvent.removeMonitor(monitor) }
            stripMonitors.removeAll()
            return
        }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: moves,
            handler: { _ in
                MainActor.assumeIsolated { [weak self] in self?.stripPointerMoved(to: NSEvent.mouseLocation) }
            })
        {
            stripMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: moves,
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.stripPointerMoved(to: NSEvent.mouseLocation) }
                return event
            })
        {
            stripMonitors.append(local)
        }
    }

    /// The pointer moved: on a plain display, the top-center strip (and the pill while it shows) is the hover
    /// target. Entering it plays the hover reaction (and shows a pill hidden by `idle = hide`); leaving it ends.
    func stripPointerMoved(to point: CGPoint) {
        let hit = islands.first { island in
            guard let strip = island.geometry.hoverStrip else { return false }
            return Self.contains(strip, point)
                || (island.display.id == hoverStripDisplayID && Self.contains(island.geometry.islandFrame, point))
        }?.display.id
        guard hit != hoverStripDisplayID else { return }
        hoverStripDisplayID = hit
        islandHoverChanged(hit != nil)
        layout()
    }

    // MARK: Arbitration

    /// Re-runs closed-notch arbitration now and re-arms observation of everything it read: the registry's
    /// statuses, each running module's `state`, and whatever each module's `leftWingItems()` and compact
    /// views read. Any change schedules another run on the main actor.
    public func rearbitrate() {
        arbitrationGeneration += 1
        let generation = arbitrationGeneration
        let (leading, trailing) = withObservationTracking {
            computeLayouts()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.arbitrationGeneration == generation else { return }
                self.rearbitrate()
            }
        }
        leadingLayout = leading
        trailingLayout = trailing
        if isStarted, let lastIdle, lastIdle != isIdle, islands.contains(where: \.geometry.isVirtual) {
            layout()
        }
    }

    /// Shows a transient readout on the left wing (SPEC §5: after the first item, the last visible item steps
    /// into `+X`) for `duration`, by default the theme's `motion.confirm-readout` (2 s). A newer readout
    /// replaces the current one and restarts the clock. While the pointer is over the notch the readout holds
    /// (its drain line stays full); when the pointer leaves, it runs its full duration again (DESIGN "Copied
    /// readout"). A readout with an announcement posts it to VoiceOver.
    public func showTransient(_ readout: TransientReadout, duration: Duration? = nil) {
        let duration = duration ?? themeController.islandTheme.motion(.confirmReadout)
        transientTask?.cancel()
        transientTask = nil
        transient = readout
        transientDuration = duration
        rearbitrate()
        if let announcement = readout.announcement { announce(announcement) }
        if isPointerOverIsland {
            transientDrain = readout.drains ? .held : nil
        } else {
            runTransientClock()
        }
    }

    /// Shows `readout` (Image to Text `READING…`) until ``showTransient(_:duration:)`` replaces it or
    /// ``clearTransient()`` removes it: no clock, no drain.
    public func showProgress(_ readout: TransientReadout) {
        transientTask?.cancel()
        transientTask = nil
        transient = readout
        transientDuration = nil
        transientDrain = nil
        rearbitrate()
    }

    /// Removes the transient readout now.
    public func clearTransient() {
        transientTask?.cancel()
        transientTask = nil
        guard transient != nil else { return }
        transient = nil
        transientDuration = nil
        transientDrain = nil
        rearbitrate()
    }

    /// Hover over a closed island holds the transient readout; leaving runs its clock again from full.
    func transientHoverChanged(_ hovering: Bool) {
        guard isPointerOverIsland != hovering else { return }
        isPointerOverIsland = hovering
        guard let transient, transientDuration != nil else { return }
        if hovering {
            transientTask?.cancel()
            transientTask = nil
            transientDrain = transient.drains ? .held : nil
        } else {
            runTransientClock()
        }
    }

    private func runTransientClock() {
        guard let transient, let duration = transientDuration else { return }
        transientTrigger += 1
        transientDrain = transient.drains ? .draining(duration, trigger: transientTrigger) : nil
        transientTask?.cancel()
        transientTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.transientTask = nil
            self.clearTransient()
        }
    }

    /// A VoiceOver announcement through the app (non-activating panels are never key).
    static func postAnnouncement(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [
                .announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
    }

    private func computeLayouts() -> (SideLayout, SideLayout) {
        _ = registry.statuses  // module starts and stops
        let snapshots = registry.runningModules.map { module in
            ArbiterModuleSnapshot(moduleID: module.manifest.id, state: module.state, items: module.leftWingItems())
        }
        let slots = closedSlots()
        return (
            ClosedNotchArbiter.leading(
                snapshots, slots: slots, transient: transient, isRenderable: LaneRenderer.canRender),
            ClosedNotchArbiter.trailing(snapshots, slots: slots, isRenderable: LaneRenderer.canRender)
        )
    }
}

/// A panel's root view: the island of one display with the host's wing content (the same state on every
/// display, FR23), themed with ``NotchHost/theme(for:)``.
struct NotchRootView: View {
    let host: NotchHost
    let displayID: CGDirectDisplayID
    let themeController: ThemeController

    var body: some View {
        if let island = host.island(for: displayID) {
            let geometry = island.geometry
            IslandView(
                wings: geometry.wings,
                surface: island.surface,
                floating: geometry.isFloating,
                hoverHighlight: host.hoverStripDisplayID == displayID,
                marker: host.showsDisplayPrompt,
                leading: { lane(host.leadingLayout) },
                trailing: { lane(host.trailingLayout) }
            )
            .overlay(alignment: .bottomLeading) {
                if let drain = host.transientDrain, host.transient != nil {
                    TransientReadoutDrain(drain).frame(width: geometry.wings.leading)
                }
            }
            .frame(width: geometry.islandFrame.width, height: geometry.islandFrame.height)
            .onHover { host.islandHoverChanged($0) }
            .privacyActive(host.privacy.isActive)
            .vigieTheme(host.theme(for: island))
        }
    }

    private func lane(_ layout: SideLayout) -> AnyView? {
        guard !layout.isEmpty else { return nil }
        return AnyView(WingLane(entries: LaneRenderer.entries(layout), overflowCount: layout.overflowCount))
    }
}
