import AppKit
import Observation
import SwiftUI
import VigieUI

/// The borderless, non-activating panel a peek grows in (AD-2, AD-13, NFR2, UX-DR45). It is never a key
/// surface: the frontmost app keeps keyboard focus while it shows, and it never registers with
/// `FocusPolicy`. It floats one level above the island panel on every Space, outside window cycling.
@MainActor
public final class PeekPanel: NSPanel {
    /// Above the island panel (status bar + 1).
    public static let peekLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)

    public init(contentRect: NSRect, rootView: some View) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        // The drop shadow is drawn by the view, inside the window margin.
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        // Set last: other panel properties reset the level.
        level = Self.peekLevel
        let hosting = PeekHostingView(rootView: AnyView(rootView))
        hosting.sizingOptions = []
        contentView = hosting
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// The panel sits over the menu bar; never let AppKit push it down.
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Accepts the first click (on an action) without activating the app.
final class PeekHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// What the panel's root view reads.
@MainActor @Observable
final class PeekPanelModel {
    var content: PeekContent?
    var dwell = PeekDwellState(total: .zero, remaining: .zero, isRunning: false)
    var isRevealed = false
    /// Changes per presentation, so the dwell line restarts.
    var presentation = 0
    var shadowMargin: CGFloat = 0
    @ObservationIgnored var handlers: PeekHandlers?
}

/// The real ``PeekPanelDriver``: one reusable ``PeekPanel`` placed under the anchor's notch.
@MainActor
public final class PeekPanelController: PeekPanelDriver {
    private let themeController: ThemeController
    private let privacy: CorePrivacyService?
    private let model = PeekPanelModel()
    private var panel: PeekPanel?
    private var hideTask: Task<Void, Never>?

    /// - Parameter privacy: Privacy mode; while active the peek shows dots and the band's eye-slash.
    public init(themeController: ThemeController, privacy: CorePrivacyService? = nil) {
        self.themeController = themeController
        self.privacy = privacy
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    public func present(_ content: PeekContent, dwell: PeekDwellState, anchor: PeekAnchor, handlers: PeekHandlers) {
        hideTask?.cancel()
        hideTask = nil
        let theme = themeController.theme
        let margin = theme.peekShadow.margin
        let frame = PeekLayout.windowFrame(
            panel: PeekLayout.panelFrame(anchor: anchor, size: theme.peekSize), shadowMargin: margin)
        model.content = content
        model.dwell = dwell
        model.handlers = handlers
        model.shadowMargin = margin
        model.presentation += 1
        model.isRevealed = false
        let panel =
            self.panel
            ?? PeekPanel(
                contentRect: frame,
                rootView: PeekRootView(model: model, themeController: themeController, privacy: privacy))
        self.panel = panel
        panel.appearance = NSAppearance(named: theme.look == .dark ? .darkAqua : .aqua)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        // Grow on the next turn of the run loop, so the band-only frame is drawn first.
        Task { @MainActor [model] in model.isRevealed = true }
    }

    public func update(dwell: PeekDwellState) {
        model.dwell = dwell
    }

    public func retract() {
        model.isRevealed = false
        model.handlers = nil
        let delay = themeController.theme.motion(.exit)
        let presentation = model.presentation
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.model.presentation == presentation else { return }
            self.panel?.orderOut(nil)
            self.model.content = nil
        }
    }
}

/// The panel's root: the peek at the top of the window, with room for its shadow.
struct PeekRootView: View {
    let model: PeekPanelModel
    let themeController: ThemeController
    var privacy: CorePrivacyService?

    var body: some View {
        if let content = model.content {
            PeekView(
                content: content,
                dwell: model.dwell,
                isRevealed: model.isRevealed,
                onPrimary: { model.handlers?.primary() },
                onSecondary: { model.handlers?.secondary() },
                onHover: { model.handlers?.hover($0) },
                onTertiary: { model.handlers?.tertiary() }
            )
            .id(model.presentation)
            .padding(.horizontal, model.shadowMargin)
            .padding(.bottom, model.shadowMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .privacyActive(privacy?.isActive ?? false)
            .vigieTheme(themeController.theme)
        }
    }
}
