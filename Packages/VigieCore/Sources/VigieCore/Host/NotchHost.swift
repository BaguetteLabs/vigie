import AppKit
import ModuleKit
import Observation
import SwiftUI
import VigieUI
import os

/// Where the closed island lives.
public enum NotchDisplayMode {
    /// Around the hardware notch of this screen.
    case physical(NSScreen)
    /// Nowhere yet: no notched screen (the virtual notch arrives in Story 2.6).
    case none
}

/// Owns the island panel and its placement (AD-2): finds the notched screen, lays out the island around the
/// hardware notch, follows screen changes, and fills the wings.
///
/// The wings come from ``ClosedNotchArbiter`` (SPEC §5): ``leadingLayout`` and ``trailingLayout`` are
/// recomputed on the main actor whenever a running module's `state` (or anything its `leftWingItems()` reads)
/// changes, a module starts or stops, or a transient readout comes or goes. Call ``rearbitrate()`` when
/// `closed.slots` changes.
///
/// The expanded view (Story 2.10, SPEC §10) opens only on a click on the island, the expand hotkey or, when
/// `open_on_hover` is on, a hover longer than `hover_delay`; see `NotchHost+Expanded.swift`.
@MainActor @Observable
public final class NotchHost {
    public private(set) var displayMode: NotchDisplayMode = .none
    public private(set) var geometry: NotchGeometry?
    public var isPresented: Bool { panel?.isVisible ?? false }
    /// The island frame in global AppKit coordinates, when presented.
    public var frame: CGRect? { geometry?.islandFrame }
    /// The left wing: the shared item lane.
    public private(set) var leadingLayout = SideLayout.empty
    /// The right wing: `agents.sessions` only.
    public private(set) var trailingLayout = SideLayout.empty
    /// The transient readout on the left wing, while it lasts.
    public private(set) var transient: TransientReadout?
    /// True from `expand` until `collapse` (the panel stays on screen for the exit motion after that).
    public internal(set) var isExpanded = false
    /// The active tab of the expanded view; nil shows the first tab.
    public var selectedTabID: String?
    /// The closed island's size when the expanded view opened: where it grows from.
    public internal(set) var expansionOrigin: CGSize = .zero

    @ObservationIgnored let themeController: ThemeController
    @ObservationIgnored let registry: ModuleRegistry
    @ObservationIgnored private let contextMenu: NotchContextMenu
    @ObservationIgnored private let maxSideWidth: @MainActor () -> CGFloat
    @ObservationIgnored private let closedSlots: @MainActor () -> Int
    @ObservationIgnored private var arbitrationGeneration = 0
    @ObservationIgnored private var transientTask: Task<Void, Never>?
    @ObservationIgnored private let screens: @MainActor () -> [NSScreen]
    @ObservationIgnored let logger: Logger
    @ObservationIgnored private var panel: NotchPanel?
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var islandScreenFrame: CGRect?

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
    @ObservationIgnored let expandedSurface = ExpandedSurface()
    @ObservationIgnored var expandedPanel: (any ExpandedPanelHosting)?
    @ObservationIgnored var expansionGeneration = 0
    @ObservationIgnored var hoverTask: Task<Void, Never>?
    @ObservationIgnored var hideTask: Task<Void, Never>?
    @ObservationIgnored var eventMonitors: [Any] = []
    @ObservationIgnored var pointerWasInside = false
    /// Test seam: anchors used instead of the laid-out island.
    @ObservationIgnored var anchorsOverride: [IslandAnchor]?

    /// - Parameters:
    ///   - maxSideWidth: `closed.max_side_width` (SPEC §5.3, default 120). ConfigStore wiring: Stories 2.6/2.7.
    ///   - closedSlots: `closed.slots` (SPEC §5, default 3, clamped 1…4). ConfigStore wiring comes later.
    ///   - screens: the screens to search; `NSScreen.screens` in production.
    ///   - focusPolicy: the app-wide focus arbiter (AD-13); the expanded view is one of its surfaces.
    ///   - openOnHover: `[general] open_on_hover` (default false).
    ///   - hoverDelay: `[general] hover_delay` (default 150 ms).
    ///   - closeOnLeave: `[general] close_on_leave` (default false).
    ///   - tabOrder: `[general] tab_order`, module ids (default empty: registry order).
    ///   - openSettings: opens the Settings window from the gear; nil until Story 2.14.
    ///   - pointerLocation: the pointer in global AppKit coordinates; `NSEvent.mouseLocation` in production.
    ///   - makeExpandedPanel: builds the expanded panel window; an ``ExpandedPanel`` in production.
    public init(
        themeController: ThemeController,
        registry: ModuleRegistry,
        contextMenu: NotchContextMenu,
        maxSideWidth: @escaping @MainActor () -> CGFloat = { 120 },
        closedSlots: @escaping @MainActor () -> Int = { ClosedNotchArbiter.defaultSlots },
        screens: @escaping @MainActor () -> [NSScreen] = { NSScreen.screens },
        focusPolicy: FocusPolicy = FocusPolicy(),
        openOnHover: @escaping @MainActor () -> Bool = { false },
        hoverDelay: @escaping @MainActor () -> Duration = { NotchHost.defaultHoverDelay },
        closeOnLeave: @escaping @MainActor () -> Bool = { false },
        tabOrder: @escaping @MainActor () -> [String] = { [] },
        openSettings: (@MainActor () -> Void)? = nil,
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
        makeExpandedPanel: (@MainActor (NotchHost) -> any ExpandedPanelHosting)? = nil,
        logger: Logger
    ) {
        self.themeController = themeController
        self.registry = registry
        self.contextMenu = contextMenu
        self.maxSideWidth = maxSideWidth
        self.closedSlots = closedSlots
        self.screens = screens
        self.focusPolicy = focusPolicy
        self.openOnHover = openOnHover
        self.hoverDelay = hoverDelay
        self.closeOnLeave = closeOnLeave
        self.tabOrder = tabOrder
        self.openSettings = openSettings
        self.pointerLocation = pointerLocation
        self.makeExpandedPanel =
            makeExpandedPanel ?? { host in
                ExpandedPanel(host: host, rootView: ExpandedRootView(host: host, themeController: themeController))
            }
        self.logger = logger
        expandedSurface.host = self
    }

    /// Places the island and follows screen parameter changes until `stop()`.
    public func start() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        rearbitrate()
        layout()
    }

    public func stop() {
        collapse()
        hideTask?.cancel()
        expandedPanel?.hide()
        expandedPanel = nil
        islandScreenFrame = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        arbitrationGeneration += 1  // drops the armed observation
        transientTask?.cancel()
        transientTask = nil
        transient = nil
        panel?.orderOut(nil)
        panel = nil
        geometry = nil
        displayMode = .none
    }

    /// Recomputes the placement and moves, shows or hides the panel.
    func layout() {
        guard let (screen, metrics) = notchedScreen() else {
            if case .physical = displayMode {
                logger.info("Notched screen gone; island hidden")
            } else {
                logger.info("No physical notch; virtual notch arrives in Story 2.6")
            }
            panel?.orderOut(nil)
            geometry = nil
            islandScreenFrame = nil
            displayMode = .none
            return
        }
        let theme = themeController.islandTheme
        guard
            let geometry = NotchGeometry.physical(
                screen: metrics,
                bandHeight: theme.spacing(.bandHeight),
                maxSideWidth: maxSideWidth(),
                cornerRadius: theme.radius(.islandClosed))
        else {
            logger.error("Notch geometry unavailable for \(screen.localizedName, privacy: .public)")
            return
        }
        self.geometry = geometry
        islandScreenFrame = metrics.frame
        displayMode = .physical(screen)
        let panel = self.panel ?? makePanel(frame: geometry.islandFrame)
        self.panel = panel
        panel.setFrame(geometry.islandFrame, display: true)
        panel.orderFrontRegardless()
        logger.info(
            "Island on \(screen.localizedName, privacy: .public): frame \(NSStringFromRect(geometry.islandFrame), privacy: .public), notch \(NSStringFromRect(geometry.notchRect), privacy: .public)"
        )
    }

    private func makePanel(frame: CGRect) -> NotchPanel {
        let panel = NotchPanel(
            contentRect: frame,
            rootView: NotchRootView(host: self, themeController: themeController),
            contextMenu: contextMenu)
        panel.onClick = { [weak self] in self?.islandClicked() }
        return panel
    }

    /// The islands on screen, main Vigie display first. One today (the notched display); Stories 2.6/2.8 add
    /// virtual notches and `[display] show_on`.
    var islandAnchors: [IslandAnchor] {
        if let anchorsOverride { return anchorsOverride }
        guard let geometry, let islandScreenFrame else { return [] }
        return [
            IslandAnchor(
                screenFrame: islandScreenFrame, islandFrame: geometry.islandFrame, notchRect: geometry.notchRect)
        ]
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

    private func notchedScreen() -> (NSScreen, ScreenMetrics)? {
        if let screen = screens().first(where: { $0.auxiliaryTopLeftArea != nil }) {
            return (screen, ScreenMetrics(screen: screen))
        }
        #if DEBUG
            // Development aid for Macs without a notch (lid closed, external display): draw the island
            // around a simulated 200 pt cut-out at the top of the main screen. Removed by Story 2.6.
            if UserDefaults.standard.bool(forKey: "VigieSimulateNotch"), let screen = NSScreen.main ?? screens().first {
                return (screen, Self.simulatedMetrics(for: screen.frame))
            }
        #endif
        return nil
    }

    #if DEBUG
        nonisolated static func simulatedMetrics(for frame: CGRect) -> ScreenMetrics {
            let notchWidth: CGFloat = 200
            let side = (frame.width - notchWidth) / 2
            let height: CGFloat = 32
            return ScreenMetrics(
                frame: frame, safeAreaTop: height,
                auxiliaryTopLeftArea: CGRect(x: frame.minX, y: frame.maxY - height, width: side, height: height),
                auxiliaryTopRightArea: CGRect(
                    x: frame.maxX - side, y: frame.maxY - height, width: side, height: height))
        }
    #endif

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
    }

    /// Shows a transient readout on the left wing (SPEC §5: after the first item, the last visible item steps
    /// into `+X`) for `duration`, by default the theme's `motion.confirm-readout` (2 s). A newer readout
    /// replaces the current one and restarts the clock.
    public func showTransient(_ readout: TransientReadout, duration: Duration? = nil) {
        let duration = duration ?? themeController.islandTheme.motion(.confirmReadout)
        transientTask?.cancel()
        transient = readout
        rearbitrate()
        transientTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.transient = nil
            self.transientTask = nil
            self.rearbitrate()
        }
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

/// The panel's root view: the island with the host's wing content, themed with the island (dark) theme.
struct NotchRootView: View {
    let host: NotchHost
    let themeController: ThemeController

    var body: some View {
        if let geometry = host.geometry {
            IslandView(
                wings: geometry.wings,
                leading: { lane(host.leadingLayout) },
                trailing: { lane(host.trailingLayout) }
            )
            .frame(width: geometry.islandFrame.width, height: geometry.islandFrame.height)
            .onHover { host.islandHoverChanged($0) }
            .vigieTheme(themeController.islandTheme)
        }
    }

    private func lane(_ layout: SideLayout) -> AnyView? {
        guard !layout.isEmpty else { return nil }
        return AnyView(WingLane(entries: LaneRenderer.entries(layout), overflowCount: layout.overflowCount))
    }
}
