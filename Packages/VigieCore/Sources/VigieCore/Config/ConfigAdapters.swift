import Foundation
import ModuleKit

/// A module's `context.settings`, backed by `ConfigStore` (AD-8). Keys are the manifest's descriptor keys;
/// each is routed by its declared scope to `modules."<id>".<key>` or `modules."<id>".local.<key>`.
public struct ConfigModuleSettings: ModuleSettings {
    let shared: ConfigSharedState
    public let moduleID: ModuleID
    let tracker: RegistrationTracker?

    /// - Parameter tracker: when given, observation streams end when the module stops.
    public init(store: ConfigStore, moduleID: ModuleID, tracker: RegistrationTracker? = nil) {
        shared = store.shared
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

    public func set<T: SettingValue>(_ value: T?, for key: String) async throws {
        guard path(key) != nil else { throw ConfigError.unknownSetting(key) }
        throw ConfigError.readOnlyUntilStory213
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
