import Foundation
import ModuleKit

/// Feeds configured shortcuts from `ConfigStore` into `HotkeyCenter.applyConfig` and re-applies on change.
///
/// `core.expand` ← `[general] expand_hotkey`; each `hotkey` setting of a manifest ←
/// `[modules."<id>"] <key>` as `"<module id>.<key>"`.
@MainActor
public final class HotkeyConfigBridge {
    private let store: ConfigStore
    private let center: HotkeyCenter
    /// Full hotkey name to the config key that configures it.
    private let mapping: [String: ConfigKeyPath]
    private var task: Task<Void, Never>?

    public init(store: ConfigStore, center: HotkeyCenter, manifests: [ModuleManifest]) {
        self.store = store
        self.center = center
        var mapping: [String: ConfigKeyPath] = [
            CoreHotkeys.expandName: CoreSettings.path("general", "expand_hotkey")
        ]
        for manifest in manifests {
            for setting in manifest.settings {
                guard case .hotkey = setting.kind else { continue }
                mapping["\(manifest.id.rawValue).\(setting.key)"] = .module(
                    manifest.id, setting.key, scope: setting.scope)
            }
        }
        self.mapping = mapping
    }

    /// Applies the current config, then follows changes to the mapped keys until `stop()`.
    public func start() {
        guard task == nil else { return }
        let changes = store.changes  // subscribe before the first apply so no change is missed
        apply()
        task = Task { [weak self] in
            for await keys in changes {
                guard let self else { return }
                if self.mapping.values.contains(where: { path in
                    keys.contains { $0.hasPrefix(path) || path.hasPrefix($0) }
                }) {
                    self.apply()
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func apply() {
        var values: [String: String] = [:]
        for (name, path) in mapping {
            if let value = store.value(path, as: String.self) { values[name] = value }
        }
        center.applyConfig(values)
    }
}
