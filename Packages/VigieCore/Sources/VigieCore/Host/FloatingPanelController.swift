import AppKit
import ModuleKit
import Observation
import SwiftUI
import VigieUI
import os

/// The app a floating panel gives keyboard focus back to when it closes.
public struct FocusReturnTarget: Hashable, Sendable {
    public let processID: pid_t

    public init(processID: pid_t) {
        self.processID = processID
    }
}

/// Reads the frontmost app and gives focus back to it. ``WorkspaceFocusReturn`` in production; tests use a fake,
/// so no test ever activates an app.
@MainActor
public protocol AppFocusReturning: AnyObject {
    /// The frontmost app now; nil when there is none or it is Vigie itself.
    func frontmostApp() -> FocusReturnTarget?
    /// Makes `app` active again (when it still runs and is not active already).
    func returnFocus(to app: FocusReturnTarget)
}

/// `NSWorkspace` / `NSRunningApplication`.
@MainActor
public final class WorkspaceFocusReturn: AppFocusReturning {
    public init() {}

    public func frontmostApp() -> FocusReturnTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return FocusReturnTarget(processID: app.processIdentifier)
    }

    public func returnFocus(to target: FocusReturnTarget) {
        guard let app = NSRunningApplication(processIdentifier: target.processID), !app.isTerminated, !app.isActive
        else { return }
        app.activate()
    }
}

/// What the controller needs from the floating panel window. ``FloatingPanelWindow`` is the AppKit one; tests use
/// a fake and never put a window on screen.
@MainActor
public protocol FloatingPanelPresenting: AnyObject {
    /// True while the panel holds keyboard focus.
    var isKey: Bool { get }
    /// Places the panel outline at `frame` (global AppKit coordinates) and orders it front without focus.
    func show(frame: CGRect)
    /// Takes keyboard focus (called only through ``FocusPolicy`` with a `UserIntent`).
    func takeKey()
    /// Stops accepting keyboard focus.
    func dropKey()
    /// Orders the panel out.
    func hide()
}

/// The screen a floating panel is placed on: its frame and the part the menu bar and Dock leave
/// (`NSScreen.visibleFrame`), in global AppKit coordinates.
public struct FloatingPanelScreen: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    /// The `NSScreen` whose frame is `displayFrame` (the main Vigie display, the one with the notch), else the
    /// main screen.
    @MainActor
    public static func current(displayFrame: CGRect?, screens: [NSScreen] = NSScreen.screens) -> FloatingPanelScreen? {
        let screen = screens.first { $0.frame == displayFrame } ?? NSScreen.main ?? screens.first
        return screen.map { FloatingPanelScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }
}

/// The module floating panel (Story 15.3, AD-13: the only window a module may request, through
/// `context.host.presentFloatingPanel`).
///
/// - **One at a time.** A request while a panel is shown replaces it: the shown panel's `onClose` runs first, and
///   focus later returns to the app that was frontmost before the first panel.
/// - **Deliberate focus (UX-DR45).** A request needs a live `UserIntent` (issued at most ``intentLifetime`` ago);
///   without one it is refused. The panel is a ``KeySurface`` of the app-wide ``FocusPolicy``: it becomes key the
///   way the expanded view does (a non-activating panel that takes key status, Vigie is never activated), and
///   the frontmost app is remembered when it opens.
/// - **Esc** while key: the request's `onEscape` (the module saves), then the policy closes the key surface.
/// - **Closing** (Esc, `dismissFloatingPanel`, replacement) runs `onClose` once; when the panel held focus at
///   that moment, the remembered app is made active again (``AppFocusReturning``). A panel that lost focus to a
///   click in another app gives nothing back, so it never steals focus from where the user went.
/// - A click outside never closes it; it stays above normal windows (`.floating`), on the active Space.
@MainActor @Observable
public final class FloatingPanelController {
    /// The panel on screen and who asked for it.
    public struct Shown {
        public let request: FloatingPanelRequest
        public let owner: ModuleID
        /// Focus goes back here on close.
        public let previousApp: FocusReturnTarget?
        public let frame: CGRect
    }

    /// How old a `UserIntent` may be and still open the panel: the module answers its hotkey at once.
    public static let intentLifetime: TimeInterval = 5

    public private(set) var shown: Shown?

    @ObservationIgnored let surface = FloatingPanelSurface()
    @ObservationIgnored private let focusPolicy: FocusPolicy
    @ObservationIgnored let theme: @MainActor () -> Theme
    @ObservationIgnored let privacyActive: @MainActor () -> Bool
    @ObservationIgnored private let screen: @MainActor () -> FloatingPanelScreen?
    @ObservationIgnored private let makePresenter: @MainActor (FloatingPanelController) -> any FloatingPanelPresenting
    @ObservationIgnored private let focusReturn: any AppFocusReturning
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private(set) var presenter: (any FloatingPanelPresenting)?

    /// - Parameters:
    ///   - focusPolicy: the app-wide focus arbiter (the host's).
    ///   - theme: the panel theme (`ThemeController.theme`).
    ///   - privacyActive: Privacy mode (AD-24), set on the panel's root.
    ///   - screen: where the panel goes; the main Vigie display in production.
    ///   - makePresenter: builds the panel window once; a ``FloatingPanelWindow`` in production.
    ///   - focusReturn: frontmost-app reading and focus return; ``WorkspaceFocusReturn`` in production.
    public init(
        focusPolicy: FocusPolicy,
        theme: @escaping @MainActor () -> Theme,
        privacyActive: @escaping @MainActor () -> Bool = { false },
        screen: @escaping @MainActor () -> FloatingPanelScreen?,
        makePresenter: (@MainActor (FloatingPanelController) -> any FloatingPanelPresenting)? = nil,
        focusReturn: (any AppFocusReturning)? = nil,
        now: @escaping @MainActor () -> Date = { Date() },
        logger: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "floating-panel")
    ) {
        self.focusPolicy = focusPolicy
        self.theme = theme
        self.privacyActive = privacyActive
        self.screen = screen
        self.makePresenter = makePresenter ?? { FloatingPanelWindow(controller: $0) }
        self.focusReturn = focusReturn ?? WorkspaceFocusReturn()
        self.now = now
        self.logger = logger
        surface.controller = self
    }

    /// The production controller of a Notch Host: its focus policy, panel theme and Privacy mode, placed on the
    /// main Vigie display.
    public convenience init(host: NotchHost) {
        let themeController = host.themeController
        let privacy = host.privacy
        self.init(
            focusPolicy: host.focusPolicy,
            theme: { themeController.theme },
            privacyActive: { privacy.isActive },
            screen: { [weak host] in
                let display = host.flatMap { host in host.displays.first { $0.id == host.activeDisplayID } }
                return FloatingPanelScreen.current(displayFrame: display?.frame)
            },
            logger: host.logger)
    }

    /// True while the panel holds keyboard focus.
    public var isKey: Bool { focusPolicy.isKey(surface) }

    // MARK: Requests

    /// Shows `request` for `owner` and makes it key. Refused (false) without a live intent or a screen.
    @discardableResult
    public func present(_ request: FloatingPanelRequest, owner: ModuleID, focus: UserIntent?) -> Bool {
        guard let focus, Self.isLive(focus, now: now()) else {
            logger.info("Floating panel \(request.id, privacy: .public) refused: no live user intent")
            return false
        }
        guard let screen = screen() else {
            logger.info("Floating panel \(request.id, privacy: .public) refused: no screen")
            return false
        }
        let previousApp: FocusReturnTarget?
        if let current = shown {
            previousApp = current.previousApp
            close(returningFocus: false)
        } else {
            previousApp = focusReturn.frontmostApp()
        }
        let theme = theme()
        let frame = Self.panelFrame(
            size: request.size ?? theme.notesPanelSize, screen: screen, gap: theme.floatingPanelTopGap)
        shown = Shown(request: request, owner: owner, previousApp: previousApp, frame: frame)
        let presenter = self.presenter ?? makePresenter(self)
        self.presenter = presenter
        presenter.show(frame: frame)
        focusPolicy.present(surface, focus: focus)
        return true
    }

    /// Closes `owner`'s panel, if it is the one shown.
    public func dismiss(owner: ModuleID) {
        guard shown?.owner == owner else { return }
        close()
    }

    /// Esc in the panel: the module's `onEscape`, then the policy closes the key surface (this panel). A panel
    /// that is not key (focus went elsewhere and came back by a click) closes directly.
    public func escapePressed() {
        guard let shown else { return }
        shown.request.onEscape()
        guard self.shown != nil else { return }
        if focusPolicy.isKey(surface) {
            focusPolicy.handleEscape()
        } else {
            close()
        }
    }

    /// The panel window lost key status outside the policy (a click in another app).
    func panelDidResignKey() {
        focusPolicy.surfaceDidResignKey(surface)
    }

    /// Orders the panel out and runs `onClose`. Focus returns to the remembered app when the panel was key
    /// (`returningFocus` nil) or when asked.
    func close(returningFocus: Bool? = nil) {
        guard let current = shown else { return }
        let wasKey = presenter?.isKey ?? false
        shown = nil
        focusPolicy.dismissed(surface)
        presenter?.dropKey()
        presenter?.hide()
        current.request.onClose()
        if returningFocus ?? wasKey, let app = current.previousApp {
            focusReturn.returnFocus(to: app)
        }
    }

    // MARK: Rules

    /// An intent issued at most ``intentLifetime`` ago (and not in the future).
    static func isLive(_ intent: UserIntent, now: Date) -> Bool {
        let age = now.timeIntervalSince(intent.issuedAt)
        return age >= -1 && age <= intentLifetime
    }

    /// The panel outline: centred horizontally on the screen, its top `gap` below the menu bar
    /// (`visibleFrame.maxY`), kept on screen. Whole points.
    public static func panelFrame(size: CGSize, screen: FloatingPanelScreen, gap: CGFloat) -> CGRect {
        let frame = screen.frame
        let minX = frame.minX
        let maxX = max(frame.maxX - size.width, minX)
        let x = min(max(frame.midX - size.width / 2, minX), maxX)
        let top = min(screen.visibleFrame.maxY, frame.maxY) - gap
        let y = max(top - size.height, screen.visibleFrame.minY)
        return CGRect(x: x.rounded(.down), y: y.rounded(.down), width: size.width, height: size.height)
    }
}

/// The floating panel as a ``KeySurface`` of the ``FocusPolicy``.
@MainActor
final class FloatingPanelSurface: KeySurface {
    static let id = "floating.panel"
    weak var controller: FloatingPanelController?

    var surfaceID: String { Self.id }

    func makeKey() { controller?.presenter?.takeKey() }

    func resignKey() { controller?.presenter?.dropKey() }

    func close() { controller?.close() }
}

/// The panel's root view: the host's frame (`surface-panel`, `rounded.notes-panel`, iris filament) around the
/// module's content, with the panel theme and Privacy mode (AD-24).
struct FloatingPanelRootView: View {
    let controller: FloatingPanelController

    var body: some View {
        Group {
            if let shown = controller.shown {
                FloatingPanelFrame { shown.request.content() }
                    .frame(width: shown.frame.width, height: shown.frame.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .privacyActive(controller.privacyActive())
        .vigieTheme(controller.theme())
    }
}
