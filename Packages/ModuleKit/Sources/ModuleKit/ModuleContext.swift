import Foundation
import os

/// The complete service API a module may use (AD-19, FR6). Declared here, implemented only in VigieCore.
///
/// Each module gets its own context. Everything a module registers through it (scheduler jobs, hotkeys, event
/// subscriptions, power assertions, ...) is tracked and removed automatically when the module stops (FR3).
public protocol ModuleContext: Sendable {
    var settings: any ModuleSettings { get }
    var storage: any ModuleStorage { get }
    var secrets: any SecretStore { get }
    var scheduler: any Scheduler { get }
    var hotkeys: any HotkeyRegistry { get }
    var notifier: any Notifier { get }
    var events: any EventBus { get }
    var host: any HostControl { get }
    var permissions: any PermissionsService { get }
    var power: any PowerService { get }
    var clipboard: any ClipboardService { get }
    var executables: any ExecutableResolver { get }
    var privacy: any PrivacyService { get }
    var away: any AwayService { get }
    var activity: any ActivityLog { get }
    /// Applies agent config edits after the user confirms them (AD-22).
    var integrations: any IntegrationInstaller { get }
    /// `os.Logger`, subsystem = bundle id, category = module id. Never log secrets or note content.
    var log: Logger { get }
}

/// Error thrown by a service that is declared but not available yet (or not in this build).
public enum ModuleServiceError: Error, Equatable, Sendable {
    case notAvailable
}

/// A handle on something registered through a context service. Cancelling is idempotent.
/// The context cancels every outstanding token when the module stops.
public struct RegistrationToken: Hashable, Sendable {
    public let id: UUID
    private let onCancel: @Sendable () -> Void

    public init(id: UUID = UUID(), cancel: @escaping @Sendable () -> Void) {
        self.id = id
        self.onCancel = cancel
    }

    public func cancel() { onCancel() }

    public static func == (lhs: RegistrationToken, rhs: RegistrationToken) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Proof that an action comes from the user (hotkey callback, click, menu action), required for focus-taking
/// host calls (AD-13). Without one, surfaces open without focus.
///
/// Only VigieCore mints these: the initializer is SPI, reachable only through `@_spi(Host) import ModuleKit`,
/// which modules must never use.
public struct UserIntent: Hashable, Sendable {
    public let id: UUID
    public let issuedAt: Date

    @_spi(Host) public init(issuedAt: Date = Date()) {
        self.id = UUID()
        self.issuedAt = issuedAt
    }
}
