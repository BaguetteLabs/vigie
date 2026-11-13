import AppKit
import SwiftUI

/// The floating panel window (Story 15.3): a borderless, non-activating `NSPanel` at `.floating` level that takes
/// key status only while the controller presents it with a `UserIntent` (``allowsKey``), like the expanded view.
/// Vigie is never activated: the app the user was in stays active, and keyboard focus goes back to it when the
/// panel orders out. Movable by its background; shown on the active Space and over full-screen apps; it stays
/// when Vigie or the other app deactivates. The window draws the drop shadow around the rounded content.
@MainActor
final class FloatingPanelWindow: NSPanel, FloatingPanelPresenting {
    /// True while the controller lets the panel become key.
    var allowsKey = false

    private weak var controller: FloatingPanelController?
    private var resignObserver: (any NSObjectProtocol)?

    init(controller: FloatingPanelController) {
        self.controller = controller
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true)
        isFloatingPanel = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = true
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        // Set last: `isFloatingPanel` resets the level.
        level = .floating
        let hosting = FloatingPanelHostingView(rootView: AnyView(FloatingPanelRootView(controller: controller)))
        hosting.sizingOptions = []
        contentView = hosting
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller?.panelDidResignKey() }
        }
    }

    isolated deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    var isKey: Bool { isKeyWindow }

    func show(frame: CGRect) {
        setFrame(frame, display: true)
        orderFrontRegardless()
        invalidateShadow()
    }

    func takeKey() {
        allowsKey = true
        makeKeyAndOrderFront(nil)
    }

    func dropKey() {
        allowsKey = false
    }

    func hide() {
        allowsKey = false
        orderOut(nil)
    }

    /// Esc reaches the controller before the text view (which would treat it as `complete:`), unless an input
    /// method is composing.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, Self.isEscape(event), !isComposing {
            controller?.escapePressed()
            return
        }
        super.sendEvent(event)
    }

    /// Esc when no view handles it.
    override func cancelOperation(_ sender: Any?) {
        controller?.escapePressed()
    }

    private var isComposing: Bool {
        (firstResponder as? any NSTextInputClient)?.hasMarkedText() ?? false
    }

    /// Esc without Command, Option, Control or Shift.
    static func isEscape(_ event: NSEvent) -> Bool {
        event.keyCode == escapeKeyCode
            && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }

    static let escapeKeyCode: UInt16 = 53
}

/// Accepts the first click without activating the app.
final class FloatingPanelHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
