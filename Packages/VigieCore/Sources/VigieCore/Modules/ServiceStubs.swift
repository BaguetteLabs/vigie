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
