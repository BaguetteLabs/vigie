import Foundation
import ModuleKit

// Placeholders for the AD-19 services that later stories implement. Each is replaced, not extended.

/// Used when no `ConfigStore` is given (tests): returns each descriptor's declared default.
struct DefaultsModuleSettings: ModuleSettings {
    let descriptors: [SettingDescriptor]

    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? {
        descriptors.first { $0.key == key }?.defaultValue as? T
    }

    func set<T: SettingValue>(_ value: T?, for key: String) async throws {
        throw ModuleServiceError.notAvailable
    }

    func observe(_ key: String) -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// Implemented in Story 7.2.
struct UnavailableSecretStore: SecretStore {
    func read(_ key: String) async throws -> String? { throw ModuleServiceError.notAvailable }
    func write(_ value: String?, for key: String) async throws { throw ModuleServiceError.notAvailable }
}

/// Implemented in Stories 2.5, 2.10, 3.2 and (dynamic modules) Epic 15.
struct StubHostControl: HostControl {
    func requestPeek() {}
    func expand(focus: UserIntent?) {}
    func openOwnTab(focus: UserIntent?) {}
    func registerDynamicModule(_ module: any NotchModule) throws -> RegistrationToken {
        throw ModuleServiceError.notAvailable
    }
}

/// Implemented in Story 4.12. Assertions are tracked but hold nothing.
struct StubPowerService: PowerService {
    let tracker: RegistrationTracker

    func preventIdleSleep(reason: String) -> RegistrationToken { tracker.track(RegistrationToken {}) }
    var sleepWake: AsyncStream<SleepWakeEvent> { AsyncStream { $0.finish() } }
}

/// Implemented in Story 9.9.
struct StubClipboardService: ClipboardService {
    func copy(_ text: String, clearAfter: Duration?) {}
}

/// Implemented in Story 21.2.
struct StubPrivacyService: PrivacyService {
    var isActive: Bool { false }
    var changes: AsyncStream<Bool> { AsyncStream { $0.finish() } }
}

/// Implemented in Story 20.3.
struct StubAwayService: AwayService {
    var presence: Presence { .present }
    var changes: AsyncStream<Presence> { AsyncStream { $0.finish() } }
}
