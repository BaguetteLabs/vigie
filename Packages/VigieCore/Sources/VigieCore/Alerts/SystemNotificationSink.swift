import Foundation
import ModuleKit
import UserNotifications

/// The macOS notification output (FR30). It asks for the notifications permission only when the first alert
/// needs it (A70), posts title and body, routes a click to the alert's action, and reports a denied permission
/// once through `onPermissionDenied` (the setup-problem seam; other outputs are unaffected).
@MainActor public final class SystemNotificationSink: SystemOutputSink {
    private let client: any NotificationCenterClient
    private let permissions: PermissionsCoordinator?
    private let router: any AlertActionRouter
    private let onPermissionDenied: (String) -> Void
    private var requestedOnce = false
    private var reportedDenied = false
    private var posted: [UUID: ActiveAlert] = [:]

    /// - Parameters:
    ///   - permissions: when given, its status cache is refreshed after a check (Settings reads it).
    ///   - onPermissionDenied: receives the localized setup-problem text, once.
    public init(
        client: any NotificationCenterClient,
        permissions: PermissionsCoordinator? = nil,
        router: any AlertActionRouter,
        onPermissionDenied: @escaping (String) -> Void = { _ in }
    ) {
        self.client = client
        self.permissions = permissions
        self.router = router
        self.onPermissionDenied = onPermissionDenied
        client.setClickHandler { [weak self] id in self?.handleClick(alertID: id) }
    }

    /// `AlertCenter` calls this synchronously; the work continues asynchronously.
    public func deliver(_ alert: ActiveAlert) {
        Task { await show(alert: alert) }
    }

    public func show(alert: ActiveAlert) async {
        guard await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.event.title
        if let body = alert.event.body { content.body = body }
        content.userInfo = [systemNotificationAlertIDKey: alert.id.uuidString]
        let request = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        posted[alert.id] = alert
        do {
            try await client.add(request)
        } catch {
            posted[alert.id] = nil
        }
    }

    /// Removes the delivered notification when its alert resolves.
    public func retract(alert id: UUID) {
        posted[id] = nil
        let client = client
        Task { await client.removeDelivered(ids: [id.uuidString]) }
    }

    func handleClick(alertID: String) {
        guard let id = UUID(uuidString: alertID), let alert = posted[id], let action = alert.event.action else {
            return
        }
        switch action {
        case .module(let module, let actionID, let payload):
            router.routeToModule(module, actionID: actionID, payload: payload)
        case .openSettings(let pane):
            router.openSettings(pane: pane)
        case .openURL(let url):
            router.openURL(url)
        }
    }

    private func isAuthorized() async -> Bool {
        var status = await client.authorizationStatus()
        if status == .notDetermined, !requestedOnce {
            requestedOnce = true
            _ = try? await client.requestAuthorization(options: [.alert, .badge])
            status = await client.authorizationStatus()
        }
        if let permissions { _ = await permissions.status(of: .notifications) }
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            if !reportedDenied {
                reportedDenied = true
                onPermissionDenied(String(localized: "alerts.system.permissionDenied", bundle: .module))
            }
            return false
        }
    }
}
