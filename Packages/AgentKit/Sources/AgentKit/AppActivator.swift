import AppKit

/// Brings an app to the front without Apple Events, so the app-level focus fallback (SPEC §14.1) works even
/// when Automation is denied. Injected so tests never activate an app.
public protocol AppActivating: Sendable {
    /// Activates the first running app among `bundleIDs`, or launches the first installed one. Returns false
    /// when none is running or installed.
    @discardableResult
    func activate(bundleIDs: [String]) async -> Bool
}

/// The production `AppActivating`, backed by `NSRunningApplication` / `NSWorkspace`.
public struct WorkspaceAppActivator: AppActivating {
    public init() {}

    @discardableResult
    public func activate(bundleIDs: [String]) async -> Bool {
        let running: Bool = await MainActor.run {
            for bundleID in bundleIDs {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                    return app.activate()
                }
            }
            return false
        }
        if running { return true }
        let url: URL? = await MainActor.run {
            bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
        }
        guard let url else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return true
        } catch {
            return false
        }
    }
}
