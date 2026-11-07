import Foundation
import ModuleKit

/// A module's `context.settings`, backed by `ConfigStore` (AD-8). Keys are the manifest's descriptor keys;
/// each is routed by its declared scope to `modules."<id>".<key>` or `modules."<id>".local.<key>`.
public struct ConfigModuleSettings: ModuleSettings {
    let shared: ConfigSharedState
    let store: ConfigStore
    public let moduleID: ModuleID
    let tracker: RegistrationTracker?

    /// - Parameter tracker: when given, observation streams end when the module stops.
    public init(store: ConfigStore, moduleID: ModuleID, tracker: RegistrationTracker? = nil) {
        shared = store.shared
        self.store = store
        self.moduleID = moduleID
        self.tracker = tracker
    }

    private func path(_ key: String) -> ConfigKeyPath? {
        shared.read { $0.schema.path(module: moduleID, key: key) }
    }

    public func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? {
        guard let path = path(key) else { return nil }
        return shared.value(at: path)?.typed(as: type)
    }

    /// Writes through `ConfigStore.set` (nil: `ConfigStore.remove`, the default applies again). Only keys the
    /// manifest declares can be written. Throws `ConfigError`.
    public func set<T: SettingValue>(_ value: T?, for key: String) async throws {
        guard let path = path(key) else { throw ConfigError.unknownSetting(key) }
        guard let value else {
            try await store.remove(path)
            return
        }
        guard let resolved = ConfigResolvedValue(settingValue: value) else {
            throw ConfigError.invalidValue(key: path.description, reason: "unsupported value type \(T.self)")
        }
        try await store.set(path, to: resolved)
    }

    public func observe(_ key: String) -> AsyncStream<Void> {
        guard let path = path(key) else { return AsyncStream { $0.finish() } }
        let (stream, cancel) = shared.observe(path)
        tracker?.track(RegistrationToken(cancel: cancel))
        return stream
    }
}

/// `ModuleEnablement` for `ModuleRegistry`, backed by `modules."<id>".enabled` in `config.toml`.
public struct ConfigModuleEnablement: ModuleEnablement {
    let shared: ConfigSharedState

    public init(store: ConfigStore) {
        shared = store.shared
    }

    public func isEnabled(_ id: ModuleID) -> Bool? {
        shared.read { $0.enabled[id] }
    }

    /// Yields a module id when its configured `enabled` value changes. A new stream per access.
    public var changes: AsyncStream<ModuleID> {
        shared.subscribeEnablement()
    }
}
