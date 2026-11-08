import AppKit
import Observation
import SwiftUI
import VigieUI

/// The borderless, non-activating panel the drop display grows in (AD-2, UX-DR45). It never becomes key or
/// main, floats above the island and a peek on every Space, and is a drag destination for file URLs and file
/// promises.
@MainActor
public final class DropDisplayPanel: NSPanel {
    /// Above the island (status bar + 1) and the peek (+ 2).
    public static let dropLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)

    init(contentRect: NSRect, hosting: DropDisplayHostingView) {
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
        isReleasedWhenClosed = false
        level = Self.dropLevel
        hosting.sizingOptions = []
        contentView = hosting
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The display's hosting view: forwards the drag to the ``DropDisplayController`` with points in display
/// coordinates (top-left origin; the window adds the shadow margin on the sides and below).
final class DropDisplayHostingView: NSHostingView<AnyView> {
    weak var controller: DropDisplayController?
    var shadowMargin: CGFloat = 0

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func displayPoint(_ info: any NSDraggingInfo) -> CGPoint {
        let location = info.draggingLocation
        return CGPoint(x: location.x - shadowMargin, y: bounds.height - location.y)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        controller?.displayDragEntered(at: displayPoint(sender)) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        controller?.displayDragUpdated(at: displayPoint(sender)) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        controller?.displayDragExited()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        controller?.performDrop(at: displayPoint(sender), items: DropDragItems.read(sender)) ?? false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        controller?.dragEnded()
    }
}

/// What the panel's root view reads.
@MainActor @Observable
final class DropPanelState {
    var model: DropDisplayModel?
    var shadowMargin: CGFloat = 0
    var presentation = 0
}

/// The real ``DropDisplayPanelDriver``: one reusable ``DropDisplayPanel`` under the anchor's notch.
@MainActor
public final class DropDisplayPanelController: DropDisplayPanelDriver {
    private let themeController: ThemeController
    private weak var controller: DropDisplayController?
    private let state = DropPanelState()
    private var panel: DropDisplayPanel?
    private var hosting: DropDisplayHostingView?
    private var hideTask: Task<Void, Never>?

    public init(themeController: ThemeController, controller: DropDisplayController) {
        self.themeController = themeController
        self.controller = controller
    }

    public func present(_ model: DropDisplayModel, anchor: IslandAnchor) {
        hideTask?.cancel()
        hideTask = nil
        let theme = themeController.theme
        let margin = theme.dropDisplayShadow.margin
        let frame = PeekLayout.windowFrame(panel: anchor.panelFrame(size: theme.dropDisplaySize), shadowMargin: margin)
        state.model = model
        state.shadowMargin = margin
        state.presentation += 1
        let hosting =
            self.hosting
            ?? DropDisplayHostingView(
                rootView: AnyView(DropPanelRootView(state: state, themeController: themeController)))
        hosting.controller = controller
        hosting.shadowMargin = margin
        hosting.registerForDraggedTypes(DropDragItems.draggedTypes)
        self.hosting = hosting
        let panel = self.panel ?? DropDisplayPanel(contentRect: frame, hosting: hosting)
        self.panel = panel
        panel.appearance = NSAppearance(named: theme.look == .dark ? .darkAqua : .aqua)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        // Grow on the next turn of the run loop, so the band-only frame is drawn first.
        Task { @MainActor in model.isRevealed = true }
    }

    public func retract() {
        state.model?.isRevealed = false
        hosting?.unregisterDraggedTypes()
        let delay = themeController.theme.a11y.motionEnabled ? themeController.theme.motion(.exit) : .zero
        let presentation = state.presentation
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.state.presentation == presentation else { return }
            self.panel?.orderOut(nil)
            self.state.model = nil
        }
    }
}

/// The panel's root: the display at the top of the window, with room for its shadow.
struct DropPanelRootView: View {
    let state: DropPanelState
    let themeController: ThemeController

    var body: some View {
        if let model = state.model {
            DropDisplayView(model: model, bandTheme: themeController.islandTheme)
                .id(state.presentation)
                .padding(.horizontal, state.shadowMargin)
                .padding(.bottom, state.shadowMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .vigieTheme(themeController.theme)
        }
    }
}

/// The island's side of a drag: binds a display's island to the controller (``NotchPanel`` forwards to it).
@MainActor
public final class IslandDragTarget {
    private weak var controller: DropDisplayController?
    private let displayID: CGDirectDisplayID?

    public init(controller: DropDisplayController, displayID: CGDirectDisplayID?) {
        self.controller = controller
        self.displayID = displayID
    }

    func entered(_ info: any NSDraggingInfo) -> NSDragOperation {
        controller?.islandDragEntered(displayID: displayID, items: DropDragItems.read(info)) ?? []
    }

    func updated(_ info: any NSDraggingInfo) -> NSDragOperation {
        guard let controller, controller.isOpen else { return [] }
        return DropDragItems.operation(for: info.draggingSourceOperationMask)
    }

    func exited() { controller?.islandDragExited() }
    func ended() { controller?.dragEnded() }
}
