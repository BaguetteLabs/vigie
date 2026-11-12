import Foundation
import ModuleKit

/// `context.scriptFolder.settings` (AD-8, AD-18, Story 12.6), through ``ConfigStore`` (the only writer of config
/// files):
///
/// ```toml
/// # local.toml (this Mac only): a script file disabled here; absent = enabled
/// [scripts.enabled]
/// "modules/github.md" = false
///
/// # config.toml (synced): a script's configured settings, by its front-matter id
/// [modules."github.prs"]
/// repo = "me/project"
/// ```
///
/// The enabled flags are read from `local.toml` only (a `[scripts]` table in `config.toml` disables nothing).
/// A script's settings are known keys only while the integrations module has them registered; `secret` settings
/// are never registered (they live in the Keychain under `<script id>.<setting key>`).
public struct ConfigScriptSettings: ScriptSettingsStore {
    let store: ConfigStore
    let tracker: RegistrationTracker

    public init(store: ConfigStore, tracker: RegistrationTracker) {
        self.store = store
        self.tracker = tracker
    }

    static let enabledTable = ConfigKeyPath(["scripts", "enabled"])

    // MARK: - Enabled on this Mac

    @MainActor public func isEnabled(_ relativePath: String) -> Bool {
        store.rawValue(at: CoreSettings.scriptEnabledPath(relativePath), in: .local) != .bool(false)
    }

    /// Disabling writes `false`; enabling removes the key (the default applies).
    public func setEnabled(_ enabled: Bool, for relativePath: String) async throws {
        let path = CoreSettings.scriptEnabledPath(relativePath)
        await MainActor.run { store.registerScriptEnabled(relativePath) }
        if enabled {
            try await store.remove(path)
        } else {
            try await store.set(path, to: .bool(false))
        }
    }

    // MARK: - Configured values

    @MainActor public func register(_ id: ModuleID, settings: [SettingDescriptor]) {
        store.registerScriptSettings(id, settings: settings)
    }

    @MainActor public func unregister(_ id: ModuleID) {
        store.unregisterScriptSettings(id)
    }

    /// The configured value when `config.toml` holds one for a registered key (a `path` reads as a file URL, `~`
    /// expanded); nil otherwise.
    @MainActor public func value(_ id: ModuleID, key: String) -> (any SettingValue)? {
        let path = ConfigKeyPath.module(id, key, scope: .synced)
        guard let entry = store.schema.entries[path], store.rawValue(at: path, in: .synced) != nil,
            let resolved = store.resolvedValue(path)
        else { return nil }
        if case .path = entry.descriptor.kind { return resolved.typed(as: URL.self) }
        switch resolved {
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .duration(let value): return value
        case .strings(let value): return value
        case .none: return nil
        }
    }

    public func setValue(_ value: (any SettingValue)?, id: ModuleID, key: String) async throws {
        let path = ConfigKeyPath.module(id, key, scope: .synced)
        guard let value else {
            try await store.remove(path)
            return
        }
        guard let resolved = ConfigResolvedValue(settingValue: value) else {
            throw ConfigError.invalidValue(key: path.description, reason: "unsupported value type \(type(of: value))")
        }
        try await store.set(path, to: resolved)
    }

    /// Yields after each load or write that changes an enabled flag or a key under the table of a registered script.
    @MainActor public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let source = store.changes
        let store = store
        let enabledTable = Self.enabledTable
        let task = Task { @MainActor in
            for await paths in source {
                let scripts = store.schema.scriptSettingPaths.keys.map { ConfigKeyPath(["modules", $0.rawValue]) }
                let relevant = paths.contains { path in
                    path.hasPrefix(enabledTable) || scripts.contains { path.hasPrefix($0) }
                }
                if relevant { continuation.yield() }
            }
            continuation.finish()
        }
        let token = tracker.track(
            RegistrationToken {
                task.cancel()
                continuation.finish()
            })
        continuation.onTermination = { _ in token.cancel() }
        return stream
    }
}
