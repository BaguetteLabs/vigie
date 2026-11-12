import Foundation
import ModuleKit
import VigieUI

/// Story 12.6: Settings › Scripts. Per-Mac enable (AD-8, `local.toml`), the scripts' configured setting values
/// (`[modules."<script id>"]`, synced) and their `secret` settings (this Mac's Keychain, through `context.secrets`
/// under `<script id>.<setting key>`, the key the runner reads).
extension IntegrationsModule {
    func startSettings(_ context: any ModuleContext) {
        scriptSettings = context.scriptFolder.settings
        secrets = context.secrets
        let changes = scriptSettings.changes()
        settingsTask = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                self?.applyEnablement()
            }
        }
    }

    func stopSettings() {
        settingsTask?.cancel()
        settingsTask = nil
        for id in registeredSettings.keys { scriptSettings.unregister(id) }
        registeredSettings = [:]
        scriptSettings = NoScriptSettings()
        secrets = nil
    }

    /// Re-reads this Mac's enabled flags without a rescan and restarts or stops runs that changed.
    func applyEnablement() {
        var changed = false
        let next = scripts.map { script in
            var script = script
            let enabled = scriptSettings.isEnabled(script.relativePath)
            if script.enabled != enabled {
                script.enabled = enabled
                changed = true
            }
            return script
        }
        guard changed else { return }
        scripts = next
        updateRunner()
    }

    /// Makes each usable script's declared settings known to the host's config (after every scan); forgets the
    /// ones of scripts that were removed, errored or changed id.
    func registerScriptSettings() {
        var wanted: [ModuleID: [ScriptSetting]] = [:]
        for script in scripts where script.status == .ok {
            guard let frontMatter = script.frontMatter else { continue }
            wanted[frontMatter.id] = frontMatter.settings
        }
        for id in registeredSettings.keys where wanted[id] == nil {
            scriptSettings.unregister(id)
        }
        for (id, settings) in wanted where registeredSettings[id] != settings {
            scriptSettings.register(id, settings: settings.map(\.descriptor))
        }
        registeredSettings = wanted
    }

    /// Enables or disables `definition` on this Mac only (a user action). The runner follows at once.
    public func setEnabled(_ enabled: Bool, for definition: ScriptModuleDefinition) async throws {
        try await scriptSettings.setEnabled(enabled, for: definition.relativePath)
        applyEnablement()
    }

    /// The generated rows of `definition`'s declared settings (empty for a file that did not parse).
    public func settingRows(for definition: ScriptModuleDefinition) -> [SettingRowModel] {
        guard let frontMatter = definition.frontMatter else { return [] }
        return frontMatter.settings.map {
            ScriptSettingRows.row(
                for: $0, scriptID: frontMatter.id, store: scriptSettings, secrets: secrets)
        }
    }

    /// The rows of Settings › Scripts, in file order.
    public func paneRows() -> [ScriptPaneRow] {
        scripts.map { script in
            ScriptPaneRow(
                script: script, localState: localState(for: script), isEligible: isEligible(script),
                runState: runner?.states[script.id], updateAvailable: updateAvailable(for: script))
        }
    }
}
