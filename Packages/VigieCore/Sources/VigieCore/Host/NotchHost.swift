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
/// Wing arbitration is Story 2.8. Until then the leading wing shows the compact view of the first running
/// module that offers a left-wing item, and the trailing wing is empty.
@MainActor @Observable
public final class NotchHost {
    public private(set) var displayMode: NotchDisplayMode = .none
    public private(set) var geometry: NotchGeometry?
    public var isPresented: Bool { panel?.isVisible ?? false }
    /// The island frame in global AppKit coordinates, when presented.
    public var frame: CGRect? { geometry?.islandFrame }

    @ObservationIgnored private let themeController: ThemeController
    @ObservationIgnored private let registry: ModuleRegistry
    @ObservationIgnored private let contextMenu: NotchContextMenu
    @ObservationIgnored private let maxSideWidth: @MainActor () -> CGFloat
    @ObservationIgnored private let screens: @MainActor () -> [NSScreen]
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private var panel: NotchPanel?
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?

    /// - Parameters:
    ///   - maxSideWidth: `closed.max_side_width` (SPEC §5.3, default 120). ConfigStore wiring: Stories 2.6/2.7.
    ///   - screens: the screens to search; `NSScreen.screens` in production.
    public init(
        themeController: ThemeController,
        registry: ModuleRegistry,
        contextMenu: NotchContextMenu,
        maxSideWidth: @escaping @MainActor () -> CGFloat = { 120 },
        screens: @escaping @MainActor () -> [NSScreen] = { NSScreen.screens },
        logger: Logger
    ) {
        self.themeController = themeController
        self.registry = registry
        self.contextMenu = contextMenu
        self.maxSideWidth = maxSideWidth
        self.screens = screens
        self.logger = logger
    }

    /// Places the island and follows screen parameter changes until `stop()`.
    public func start() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        layout()
    }

    public func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
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
        NotchPanel(
            contentRect: frame,
            rootView: NotchRootView(host: self, themeController: themeController),
            contextMenu: contextMenu)
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

    /// The leading wing's content until Story 2.8 arbitrates: the first running module's highest-priority
    /// left-wing item, as a `.short` compact view.
    func leadingWingContent() -> AnyView? {
        _ = registry.statuses  // observe module starts and stops
        for module in registry.runningModules {
            let items = module.leftWingItems().sorted { $0.priority > $1.priority }
            for item in items {
                if let view = item.compactView(.short) { return view }
            }
        }
        return nil
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
                leading: { host.leadingWingContent() },
                trailing: { nil }
            )
            .frame(width: geometry.islandFrame.width, height: geometry.islandFrame.height)
            .vigieTheme(themeController.islandTheme)
        }
    }
}
