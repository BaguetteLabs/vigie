import AppKit

/// Right-click menu of the closed notch (SPEC 10.1, A32). `NotchPanel` opens it on right-click.
@MainActor
public final class NotchContextMenu: NSObject {
    public let menu = NSMenu()
    public let settingsItem: NSMenuItem
    public let quitItem: NSMenuItem

    private let openSettings: @MainActor () -> Void
    private let quit: @MainActor () -> Void

    public init(
        openSettings: @escaping @MainActor () -> Void = {},
        quit: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        self.openSettings = openSettings
        self.quit = quit
        settingsItem = NSMenuItem(
            title: String(localized: "menu.settings", bundle: .module),
            action: #selector(performOpenSettings), keyEquivalent: ",")
        quitItem = NSMenuItem(
            title: String(localized: "menu.quit", bundle: .module),
            action: #selector(performQuit), keyEquivalent: "q")
        super.init()
        settingsItem.target = self
        quitItem.target = self
        // TODO(Story 2.14): enable once the Settings window exists.
        settingsItem.isEnabled = false
        menu.autoenablesItems = false
        menu.addItem(settingsItem)
        menu.addItem(quitItem)
    }

    public func show(at point: NSPoint, in view: NSView?) {
        menu.popUp(positioning: nil, at: point, in: view)
    }

    @objc public func performOpenSettings() { openSettings() }

    @objc public func performQuit() { quit() }
}
