import CoreGraphics
import SwiftUI

/// The one window a module may ask the host for (AD-13, Story 15.3): a floating panel such as the notes panel.
///
/// The host draws the frame (corner radius, `surface-panel` body, the iris filament along the top, shadow),
/// places it centred below the menu bar of the main Vigie display and makes it the key surface. The module
/// supplies only the content.
///
/// - Only one floating panel exists at a time: a second request replaces the first (the first one's
///   ``onClose`` runs before the new panel shows).
/// - The panel takes keyboard focus, so the host shows it only with a live `UserIntent` (minted for a hotkey,
///   click or menu action moments ago); without one the request is refused.
/// - Esc while the panel is key runs ``onEscape``, then the host closes the panel and gives focus back to the
///   app that was frontmost when it opened.
/// - A click outside never closes it (a deliberate surface, UX-DR45).
public struct FloatingPanelRequest: Sendable {
    /// Identifies the request in logs; unique per module.
    public let id: String
    /// The panel outline; nil uses the theme's `components.notes-panel` size.
    public let size: CGSize?
    /// The panel body, built on the main actor each time the host needs it.
    public let content: @MainActor @Sendable () -> AnyView
    /// Esc pressed while the panel is key, just before the host closes it.
    public let onEscape: @MainActor @Sendable () -> Void
    /// The panel went away, whatever the reason (Esc, ``HostControl/dismissFloatingPanel()``, a replacing
    /// request, the module stopping). Runs once per shown panel.
    public let onClose: @MainActor @Sendable () -> Void

    public init(
        id: String,
        size: CGSize? = nil,
        content: @escaping @MainActor @Sendable () -> AnyView,
        onEscape: @escaping @MainActor @Sendable () -> Void = {},
        onClose: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.id = id
        self.size = size
        self.content = content
        self.onEscape = onEscape
        self.onClose = onClose
    }
}
