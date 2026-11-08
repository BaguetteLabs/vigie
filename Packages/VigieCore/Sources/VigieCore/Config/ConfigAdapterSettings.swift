import Foundation
import ModuleKit

/// One agent adapter's settings, backed by `ConfigStore` (Story 7.3, AD-8, AD-23): the descriptor keys the adapter
/// declares, at ``CoreSettings/adapterPath(module:adapter:_:)``, each routed by its scope to `config.toml` or
/// `local.toml`. App assembly wraps it as the adapter's read-only `AdapterContext.settings` and hands the
/// writable value only to the module that owns the adapter's Settings block.
public struct ConfigAdapterSettings: ModuleSettings {
    let shared: ConfigSharedState
    let store: ConfigStore
    public let module: ModuleID
    public let adapterID: String

    /// Registers `settings` with `store` (idempotent).
    @MainActor
    public init(store: ConfigStore, module: ModuleID, adapterID: String, settings: [SettingDescriptor]) {
        store.registerAdapter(adapterID, module: module, settings: settings)
        shared = store.shared
        self.store = store
        self.module = module
        self.adapterID = adapterID
    }

    /// The key's path when declared, or an instance of a declared template (`account.<id>.label`, Story 7.10:
    /// registered by ConfigStore on its first write or when a file holds it).
    private func path(_ key: String) -> ConfigKeyPath? {
        let path = CoreSettings.adapterPath(module: module, adapter: adapterID, key)
        return shared.read { $0.schema.entries[path] != nil || $0.schema.template(matching: path) != nil }
            ? path : nil
    }

    public func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? {
        guard let path = path(key) else { return nil }
        if let value = shared.value(at: path) { return value.typed(as: type) }
        // A template instance nobody wrote yet: the template's default.
        return shared.read { $0.schema.template(matching: path)?.descriptor.defaultValue } as? T
    }

    /// Writes through `ConfigStore.set` (nil: `remove`). Only declared keys; a `secret` key throws `.secretKey`.
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
        return shared.observe(path).stream
    }
}
