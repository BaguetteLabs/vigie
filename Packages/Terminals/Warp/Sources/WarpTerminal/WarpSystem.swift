import AppKit
import Foundation

/// Opens a URL with its registered handler. The seam over `NSWorkspace.shared.open(_:)` so tests never open
/// anything.
public protocol URLOpening: Sendable {
    /// Hands `url` to its handler app. False when no app handles it or Launch Services refused it.
    @MainActor func open(_ url: URL) -> Bool
}

/// Brings an app forward by bundle id. The seam over `NSRunningApplication` / `NSWorkspace.openApplication`.
public protocol AppActivating: Sendable {
    /// Activates the running app with `bundleID`. False when no such app is running or it refused.
    @MainActor func activateRunning(bundleID: String) -> Bool
    /// Launches (or activates) the installed app with `bundleID`. False when it is not installed or fails to open.
    @MainActor func launch(bundleID: String) async -> Bool
}

/// The real `URLOpening` and `AppActivating`, on `NSWorkspace` and `NSRunningApplication`.
public struct WorkspaceSystem: URLOpening, AppActivating {
    public init() {}

    @MainActor public func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    @MainActor public func activateRunning(bundleID: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return false
        }
        return app.activate()
    }

    @MainActor public func launch(bundleID: String) async -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                continuation.resume(returning: app != nil && error == nil)
            }
        }
    }
}
