import Foundation
import ServiceManagement

/// Registration state of Vigie as a login item (mirrors `SMAppService.Status`).
public enum LoginItemStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    /// Registered, but the user must allow it in System Settings › General › Login Items.
    case requiresApproval
    /// The service could not be found (e.g. a build that is not a proper app bundle).
    case notFound

    /// Whether the `Launch at login` toggle shows as on.
    public var isOn: Bool { self == .enabled || self == .requiresApproval }
}

/// Launch at login (A61, AD-21: only through `SMAppService.mainApp`). Injected so tests use a fake.
@MainActor
public protocol LoginItemControlling: AnyObject {
    /// The current registration state, read from the system each time (System Settings can change it).
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    /// Opens System Settings › General › Login Items.
    func openSystemSettings()
}

/// The production login item: `SMAppService.mainApp`.
@MainActor
public final class SMAppServiceLoginItem: LoginItemControlling {
    public init() {}

    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notRegistered
        }
    }

    public func register() throws { try SMAppService.mainApp.register() }

    public func unregister() throws { try SMAppService.mainApp.unregister() }

    public func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
