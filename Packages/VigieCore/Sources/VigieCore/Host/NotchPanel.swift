import AppKit
import SwiftUI

/// The borderless, non-activating panel that holds the island above the menu bar (AD-2, AD-13, NFR2).
///
/// It never becomes key or main: the frontmost app keeps keyboard focus. A left click opens the expanded view
/// (``onClick``), which is its own panel and becomes key only on a `UserIntent`.
@MainActor
public final class NotchPanel: NSPanel {
    /// One level above the status bar, so the island draws over the menu bar.
    public static let islandLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    /// Left click on the island.
    public var onClick: (@MainActor () -> Void)? {
        get { (contentView as? IslandHostingView)?.onClick }
        set { (contentView as? IslandHostingView)?.onClick = newValue }
    }

    public init(contentRect: NSRect, rootView: some View, contextMenu: NotchContextMenu?) {
        super.init(
            contentRect: contentRect,
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
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        // The hardware island is always black with the dark role set (UX-DR9).
        appearance = NSAppearance(named: .darkAqua)
        // Set last: other panel properties (e.g. `isFloatingPanel`) reset the level.
        level = Self.islandLevel
        let hosting = IslandHostingView(rootView: AnyView(rootView))
        hosting.contextMenu = contextMenu
        hosting.sizingOptions = []
        contentView = hosting
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// Borderless windows may sit over the menu bar; never let AppKit push the island down.
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosting view that opens the notch context menu on right-click and accepts the first click without
/// activating the app.
final class IslandHostingView: NSHostingView<AnyView> {
    weak var contextMenu: NotchContextMenu?
    var onClick: (@MainActor () -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let contextMenu {
            // Control-click is a right click.
            contextMenu.show(at: convert(event.locationInWindow, from: nil), in: self)
            return
        }
        super.mouseDown(with: event)
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let contextMenu else { return super.rightMouseDown(with: event) }
        contextMenu.show(at: convert(event.locationInWindow, from: nil), in: self)
    }
}
