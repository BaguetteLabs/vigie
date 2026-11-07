import AppKit

/// One connected display, as the Notch Host sees it (SPEC §5.4, FR21). Built from `NSScreen` in production and by
/// hand in tests.
public struct DisplayInfo: Sendable, Equatable, Identifiable {
    /// The host's classification of a display (FR21, PRD FR-2).
    public enum Kind: String, Sendable, Equatable {
        /// A hardware notch: the island wraps it.
        case physical
        /// No notch: Vigie draws a virtual notch.
        case plain
        /// macOS draws its own Dynamic Island. Handled exactly like `plain` for all of v1 (A26); no Mac reports
        /// it yet, so the classifier never returns it.
        case island

        /// True when Vigie draws the notch itself (plain mode).
        public var usesVirtualNotch: Bool { self != .physical }
    }

    /// `CGDirectDisplayID`.
    public var id: CGDirectDisplayID
    /// `NSScreen.localizedName`: what `[display] display = "<display name>"` matches.
    public var name: String
    public var kind: Kind
    /// The main display (`CGDisplayIsMain`: the one with the menu bar at the origin).
    public var isMain: Bool
    /// The built-in panel of a laptop (gone from the list while the lid is closed).
    public var isBuiltIn: Bool
    public var metrics: ScreenMetrics

    public var frame: CGRect { metrics.frame }
    public var hasNotch: Bool { kind == .physical }

    public init(
        id: CGDirectDisplayID, name: String, kind: Kind, isMain: Bool, isBuiltIn: Bool, metrics: ScreenMetrics
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.metrics = metrics
    }

    /// Classifies a display: `physical` when AppKit reports the areas beside a notch, else `plain`.
    public static func classify(_ metrics: ScreenMetrics) -> Kind {
        metrics.hasPhysicalNotch ? .physical : .plain
    }

    /// The connected displays, from `NSScreen.screens`.
    ///
    /// DEBUG: `-VigieSimulateNotch YES` turns the main display into a simulated notched display (a 200 pt
    /// cut-out), for working on the physical-notch layout without a notched Mac.
    @MainActor
    public static func current(_ screens: [NSScreen] = NSScreen.screens) -> [DisplayInfo] {
        var displays = screens.map { screen in
            let metrics = ScreenMetrics(screen: screen)
            let id = screen.displayID
            return DisplayInfo(
                id: id, name: screen.localizedName, kind: classify(metrics), isMain: CGDisplayIsMain(id) != 0,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0, metrics: metrics)
        }
        #if DEBUG
            if UserDefaults.standard.bool(forKey: "VigieSimulateNotch") {
                displays = simulatingNotch(displays)
            }
        #endif
        return displays
    }

    #if DEBUG
        /// Gives the main display (else the first one) a simulated hardware notch, unless one already has a notch.
        nonisolated static func simulatingNotch(_ displays: [DisplayInfo]) -> [DisplayInfo] {
            guard !displays.contains(where: \.hasNotch),
                let index = displays.firstIndex(where: \.isMain) ?? displays.indices.first
            else { return displays }
            var displays = displays
            displays[index].metrics = simulatedMetrics(for: displays[index].frame)
            displays[index].kind = .physical
            return displays
        }

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
}

extension NSScreen {
    /// The screen's `CGDirectDisplayID`.
    public var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// What the host reads from the window server about each display's menu bar (FR24, FR26). Production:
/// ``SystemMenuBarProbe``; tests use a fake.
@MainActor
public protocol MenuBarProbing: AnyObject {
    /// True when macOS "Automatically hide and show the menu bar" is on.
    var autoHidesMenuBar: Bool { get }
    /// The menu bar of the display with `screenFrame`.
    func menuBar(on screenFrame: CGRect) -> MenuBarMetrics
    /// False while an auto-hidden menu bar is hidden on that display.
    func isMenuBarVisible(on screenFrame: CGRect) -> Bool
}

/// Reads the menu bar and status items from `CGWindowListCopyWindowInfo` (window bounds and levels only, which
/// need no permission) and the auto-hide preference from the global domain.
@MainActor
public final class SystemMenuBarProbe: MenuBarProbing {
    public init() {}

    public var autoHidesMenuBar: Bool {
        CFPreferencesCopyAppValue("_HIHideMenuBar" as CFString, kCFPreferencesAnyApplication) as? Bool ?? false
    }

    public func menuBar(on screenFrame: CGRect) -> MenuBarMetrics {
        let windows = Self.windows()
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let bar = windows.first { $0.level == menuLevel && Self.isOnTopRow($0.frame, of: screenFrame) }
        let height = bar?.frame.height ?? Self.fallbackHeight(screenFrame)
        let status = windows.filter {
            $0.level == statusLevel && Self.isOnTopRow($0.frame, of: screenFrame) && $0.frame.height <= height + 1
        }
        return MenuBarMetrics(height: height, statusItemsMinX: status.map(\.frame.minX).min())
    }

    public func isMenuBarVisible(on screenFrame: CGRect) -> Bool {
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        return Self.windows().contains {
            $0.level == menuLevel && $0.frame.minX < screenFrame.maxX && $0.frame.maxX > screenFrame.minX
                && $0.frame.minY < screenFrame.maxY - 1 && $0.frame.maxY >= screenFrame.maxY - 1
        }
    }

    private struct WindowBox {
        var level: Int
        var frame: CGRect  // AppKit coordinates
    }

    /// On-screen windows, flipped from window-server (top-left) to AppKit (bottom-left) coordinates.
    private static func windows() -> [WindowBox] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return list.compactMap { info in
            guard let level = info[kCGWindowLayer as String] as? Int,
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            let frame = CGRect(
                x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            return WindowBox(level: level, frame: frame)
        }
    }

    private static func isOnTopRow(_ frame: CGRect, of screen: CGRect) -> Bool {
        frame.midX >= screen.minX && frame.midX <= screen.maxX && abs(frame.maxY - screen.maxY) <= 1
    }

    private static func fallbackHeight(_ screenFrame: CGRect) -> CGFloat {
        if let screen = NSScreen.screens.first(where: { $0.frame == screenFrame }) {
            let inset = screen.frame.maxY - screen.visibleFrame.maxY
            if inset > 0 { return inset }
        }
        return NSStatusBar.system.thickness
    }
}
