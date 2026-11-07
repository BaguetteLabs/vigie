import AppKit
import Foundation
import ModuleKit
import os

/// The App's `AlertActionRouter` (AD-13): carries out the actions of delivered alerts.
///
/// - `.module(id, actionID, payload)`: `NotchModule` has no action entry point yet; logged until Story 3.3.
/// - `.openSettings(pane)`: logged until the Settings window exists (Story 2.14).
/// - `.openURL`: opened with `NSWorkspace`.
@MainActor
public final class AppAlertActionRouter: AlertActionRouter {
    private let registry: () -> ModuleRegistry?
    private let logger: Logger

    /// - Parameter registry: the running registry, read lazily (the AlertCenter is built before it).
    public init(registry: @escaping @MainActor () -> ModuleRegistry?, logger: Logger) {
        self.registry = registry
        self.logger = logger
    }

    public func routeToModule(_ id: ModuleID, actionID: String, payload: Data) {
        let running = registry()?.module(id) != nil
        // TODO(Story 3.3): forward to the module once NotchModule exposes an alert action entry point.
        logger.info(
            "alert action \(actionID, privacy: .public) for \(id.rawValue, privacy: .public) (running: \(running, privacy: .public)); module action routing arrives with Story 3.3"
        )
    }

    public func openSettings(pane: String) {
        // TODO(Story 2.14): open the Settings window on `pane`.
        logger.info("alert action open settings \(pane, privacy: .public); Settings arrives with Story 2.14")
    }

    public func openURL(_ url: URL) {
        if !NSWorkspace.shared.open(url) {
            logger.error("alert action could not open \(url.absoluteString, privacy: .private)")
        }
    }
}
