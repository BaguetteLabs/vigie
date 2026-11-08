import AppKit
import SwiftUI
import VigieUI

/// What the Notch Host needs from the expanded panel window. ``ExpandedPanel`` is the AppKit one; tests use a
/// fake.
@MainActor
public protocol ExpandedPanelHosting: AnyObject {
    /// The panel outline (global AppKit coordinates) while shown, else nil.
    var panelFrame: CGRect? { get }
    /// True while the panel holds keyboard focus.
    var isKey: Bool { get }
    /// Places the panel outline at `panelFrame` and orders it front without taking focus.
    func show(panelFrame: CGRect)
    /// Orders the panel out (it gives up focus).
    func hide()
    /// Takes keyboard focus. The host calls it only through ``FocusPolicy`` with a `UserIntent`.
    func takeKey()
    /// Stops accepting keyboard focus; another surface becoming key takes it.
    func dropKey()
}

/// The expanded view's window (SPEC §10, AD-13): a borderless, non-activating panel above the island that grows
/// out of the notch. It becomes key only while the host presents it with a `UserIntent` (``allowsKey``), so
/// opening it by hover never steals focus, and the frontmost app stays active either way.
///
/// The window is the panel outline plus a margin on the sides and bottom for the drop shadow; its top edge is
/// the screen edge, so the 34px band is the top of the panel.
@MainActor
public final class ExpandedPanel: NSPanel, ExpandedPanelHosting {
    /// Above the island, which sits one level above the status bar.
    public static let expandedLevel = NSWindow.Level(rawValue: NotchPanel.islandLevel.rawValue + 1)

    /// True while the host lets the panel become key (presented with a `UserIntent`).
    public var allowsKey = false
    public private(set) var panelFrame: CGRect?

    private weak var host: NotchHost?
    private var resignObserver: (any NSObjectProtocol)?

    public init(host: NotchHost, rootView: some View) {
        self.host = host
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        level = Self.expandedLevel
        let hosting = ExpandedHostingView(rootView: AnyView(rootView))
        hosting.panel = self
        hosting.sizingOptions = []
        contentView = hosting
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.host?.expandedPanelDidResignKey() }
        }
    }

    isolated deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    public override var canBecomeKey: Bool { allowsKey }
    public override var canBecomeMain: Bool { false }

    public var isKey: Bool { isKeyWindow }

    /// The window frame for a panel outline: the outline plus the shadow margin on the sides and bottom.
    public static func windowFrame(forPanel frame: CGRect) -> CGRect {
        let margin = ExpandedMetrics.shadowMargin
        return CGRect(
            x: frame.minX - margin, y: frame.minY - margin,
            width: frame.width + 2 * margin, height: frame.height + margin)
    }

    public func show(panelFrame frame: CGRect) {
        panelFrame = frame
        setFrame(Self.windowFrame(forPanel: frame), display: true)
        orderFrontRegardless()
    }

    public func hide() {
        allowsKey = false
        panelFrame = nil
        orderOut(nil)
    }

    public func takeKey() {
        allowsKey = true
        makeKeyAndOrderFront(nil)
    }

    public func dropKey() {
        allowsKey = false
    }

    /// ⌘, opens Settings while the panel is key (an accessory app has no app menu to carry the shortcut).
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isSettingsShortcut(event), let openSettings = host?.openSettings {
            openSettings()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    static func isSettingsShortcut(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && event.charactersIgnoringModifiers == ","
    }

    /// Esc when no view handles it.
    public override func cancelOperation(_ sender: Any?) {
        host?.handleEscape()
    }

    /// Borderless windows may sit over the menu bar; never let AppKit push the panel down.
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    fileprivate func mouseDownInside(_ event: NSEvent) {
        host?.expandedPanelMouseDown(at: convertPoint(toScreen: event.locationInWindow))
    }
}

/// Accepts the first click without activating the app and reports clicks to the host (a click on a panel
/// opened without focus takes focus; a click on the shadow margin counts as outside).
final class ExpandedHostingView: NSHostingView<AnyView> {
    weak var panel: ExpandedPanel?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        panel?.mouseDownInside(event)
        super.mouseDown(with: event)
    }
}

/// The expanded view as a ``KeySurface`` of the ``FocusPolicy``.
@MainActor
final class ExpandedSurface: KeySurface {
    static let id = "notch.expanded"
    weak var host: NotchHost?

    var surfaceID: String { Self.id }

    func makeKey() { host?.expandedPanel?.takeKey() }

    func resignKey() { host?.expandedPanel?.dropKey() }

    func close() { host?.collapse() }
}

/// The expanded panel's root view: the shell with the host's tabs, the panel theme for the body and the
/// island theme for the band, growing out of the notch.
struct ExpandedRootView: View {
    let host: NotchHost
    let themeController: ThemeController

    var body: some View {
        let theme = themeController.theme
        let size = theme.expandedPanelSize
        ExpandedShellView(
            tabs: host.expandedTabs,
            selection: Binding(get: { host.selectedTabID }, set: { host.selectedTabID = $0 }),
            bandTheme: themeController.islandTheme.withBandHeight(atLeast: host.expansionOrigin.height),
            openSettings: host.openSettings,
            content: { host.expandedContent(for: $0) }
        )
        .overlay(alignment: .bottom) {
            if host.showsDisplayPrompt {
                DisplayPromptCard(host: host).padding(theme.spacing(.cardPaddingX))
            }
        }
        .frame(width: size.width, height: size.height)
        .expandedPanelPresentation(isShown: host.isExpanded, origin: host.expansionOrigin)
        .allowsHitTesting(host.isExpanded)
        .onExitCommand { host.handleEscape() }
        .padding(.horizontal, ExpandedMetrics.shadowMargin)
        .padding(.bottom, ExpandedMetrics.shadowMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Privacy mode (AD-24): tabs, Home cards and the tab-row indicator read it.
        .privacyActive(host.privacy.isActive)
        .vigieTheme(theme.withBandHeight(atLeast: host.expansionOrigin.height))
    }
}
