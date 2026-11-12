import AppKit

/// Right-click menu of the closed notch (SPEC 10.1, A32). `NotchPanel` opens it on right-click.
@MainActor
public final class NotchContextMenu: NSObject {
    public let menu = NSMenu()
    public let settingsItem: NSMenuItem
    /// `Check for Updates…` (Story 6.3); only in the menu when an updater is given.
    public let checkForUpdatesItem: NSMenuItem
    public let quitItem: NSMenuItem

    private let openSettings: @MainActor () -> Void
    private let updater: (any UpdaterControlling)?
    private let quit: @MainActor () -> Void

    /// - Parameter updater: the app's updater; nil leaves `Check for Updates…` out (tests, a build that cannot
    ///   update shows it disabled instead).
    public init(
        openSettings: @escaping @MainActor () -> Void = {},
        updater: (any UpdaterControlling)? = nil,
        quit: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        self.openSettings = openSettings
        self.updater = updater
        self.quit = quit
        settingsItem = NSMenuItem(
            title: String(localized: "menu.settings", bundle: .module),
            action: #selector(performOpenSettings), keyEquivalent: ",")
        checkForUpdatesItem = NSMenuItem(
            title: String(localized: "menu.checkForUpdates", bundle: .module),
            action: #selector(performCheckForUpdates), keyEquivalent: "")
        quitItem = NSMenuItem(
            title: String(localized: "menu.quit", bundle: .module),
            action: #selector(performQuit), keyEquivalent: "q")
        super.init()
        settingsItem.target = self
        checkForUpdatesItem.target = self
        quitItem.target = self
        settingsItem.isEnabled = true
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(settingsItem)
        if updater != nil { menu.addItem(checkForUpdatesItem) }
        menu.addItem(quitItem)
        refreshUpdateItem()
    }

    /// Enables `Check for Updates…` only while the updater can start a check.
    func refreshUpdateItem() {
        checkForUpdatesItem.isEnabled = updater?.canCheckForUpdates ?? false
    }

    public func show(at point: NSPoint, in view: NSView?) {
        menu.popUp(positioning: nil, at: point, in: view)
    }

    @objc public func performOpenSettings() { openSettings() }

    @objc public func performCheckForUpdates() {
        guard let updater, updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    @objc public func performQuit() { quit() }
}

extension NotchContextMenu: NSMenuDelegate {
    public nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { refreshUpdateItem() }
    }
}
