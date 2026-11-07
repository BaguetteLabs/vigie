import Foundation
import UserNotifications

/// The slice of `UNUserNotificationCenter` the system output uses, so tests run without an app bundle.
public protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removeDelivered(ids: [String]) async
    /// Installs the notification-click callback (receives the `alertID` user-info value). Called once, by the sink.
    func setClickHandler(_ handler: @escaping @MainActor @Sendable (String) -> Void)
}

/// Key of the alert id in a notification's `userInfo`.
let systemNotificationAlertIDKey = "alertID"

/// The real center. Every call is a no-op outside an app bundle (`UNUserNotificationCenter.current()` traps there).
public final class UNUserNotificationCenterClient: NotificationCenterClient {
    private let delegate = ClickDelegate()

    public init() {}

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        guard let center else { return .denied }
        return await center.notificationSettings().authorizationStatus
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        guard let center else { return false }
        return try await center.requestAuthorization(options: options)
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center?.add(request)
    }

    public func removeDelivered(ids: [String]) async {
        center?.removeDeliveredNotifications(withIdentifiers: ids)
    }

    public func setClickHandler(_ handler: @escaping @MainActor @Sendable (String) -> Void) {
        delegate.handler = handler
        center?.delegate = delegate
    }
}

private final class ClickDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    var handler: (@MainActor @Sendable (String) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let id = response.notification.request.content.userInfo[systemNotificationAlertIDKey] as? String
        else { return }
        let handler = self.handler
        await MainActor.run { handler?(id) }
    }
}
