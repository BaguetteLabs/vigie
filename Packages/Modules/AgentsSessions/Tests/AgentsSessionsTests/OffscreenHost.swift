import AppKit
import SwiftUI

/// The only place tests create windows. Hosts `view` in a borderless window parked far outside every screen, so
/// render and accessibility tests never cover the developer's windows or take keyboard focus. Never `makeKey`.
/// The window is still "on screen" for AppKit (ordered in), so SwiftUI lays out, draws and builds its AX tree.
@MainActor
func hostOffscreen<V: View>(_ view: V, size: CGSize) -> (NSWindow, NSHostingView<V>) {
    OffscreenHostSetup.prepareApp()
    let hosting = NSHostingView(rootView: view)
    hosting.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    quietOffscreen(window)
    window.orderFrontRegardless()
    return (window, hosting)
}

/// Parks an existing window far off every screen and makes it inert (no mouse, no hide-on-deactivate, no Spaces).
@MainActor
func quietOffscreen(_ window: NSWindow) {
    window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
    window.ignoresMouseEvents = true
    window.hidesOnDeactivate = false
    window.collectionBehavior = [.transient, .ignoresCycle]
    window.level = .normal
}

/// Makes SwiftUI build its accessibility tree (it does so only for an AX client).
@MainActor
func announceAccessibilityClient() {
    _ = NSApplication.shared.perform(
        NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: NSNumber(value: true),
        with: "AXEnhancedUserInterface")
}

@MainActor
private enum OffscreenHostSetup {
    private static let once: Void = {
        NSApplication.shared.setActivationPolicy(.prohibited)
    }()
    static func prepareApp() { _ = once }
}
