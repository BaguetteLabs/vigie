import Foundation
import ModuleKit
import VigieUI

extension ScriptSetting {
    /// The ModuleKit descriptor of this script setting (`[modules."<script id>"] <key>`, synced; AD-8 keeps only
    /// `secret` settings per Mac, in the Keychain). The label is the script's own text, shown as written.
    var descriptor: SettingDescriptor {
        SettingDescriptor(
            key: key, label: ScriptSettingRows.verbatim(label), kind: kind.settingKind, scope: .synced,
            help: help.map(ScriptSettingRows.verbatim))
    }
}

extension ScriptSetting.Kind {
    /// The generated control's kind (min, max, step and options kept).
    var settingKind: SettingKind {
        switch self {
        case .bool(let value): .bool(default: value)
        case .int(let value, let min, let max, let step): .int(default: value, min: min, max: max, step: step)
        case .double(let value, let min, let max, let step): .double(default: value, min: min, max: max, step: step)
        case .string(let value): .string(default: value)
        case .secret: .secret
        case .enumeration(let options, let value): .enumeration(options: options, default: value)
        case .duration(let value, _): .duration(default: value)
        case .path(let value): .path(default: value)
        case .list(let element, let value): .list(of: element == .path ? .path : .string, default: value)
        }
    }
}

/// Builds Settings › Scripts' generated rows (VigieUI `SettingRow`, the same native controls as every module
/// pane) for one script's declared settings.
enum ScriptSettingRows {
    /// A resource that shows `text` as written: a table no catalog has, so the lookup falls back to the key.
    static func verbatim(_ text: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(text), table: "ScriptText", bundle: IntegrationsText.bundle)
    }

    @MainActor
    static func row(
        for setting: ScriptSetting, scriptID: ModuleID, store: any ScriptSettingsStore, secrets: (any SecretStore)?
    ) -> SettingRowModel {
        let key = setting.key
        let kind = setting.kind
        let secret: SecretSettingBinding?
        if case .secret = kind {
            secret = secrets.map {
                secretBinding($0, key: ScriptEnvironment.secretKey(scriptID: scriptID, settingKey: key))
            }
        } else {
            secret = nil
        }
        return SettingRowModel(
            id: "modules.\(scriptID.rawValue).\(key)", label: verbatim(setting.label), help: setting.help.map(verbatim),
            kind: kind.settingKind,
            binding: SettingBinding(
                get: { controlValue(store.value(scriptID, key: key)) },
                set: { value in
                    if case .secret = kind { throw ModuleServiceError.notAvailable }
                    try await store.setValue(settingValue(value, kind: kind), id: scriptID, key: key)
                }),
            secret: secret)
    }

    /// The Keychain binding of a `secret` setting: stored on this Mac only, never read back into the UI.
    static func secretBinding(_ secrets: any SecretStore, key: String) -> SecretSettingBinding {
        SecretSettingBinding(
            isSet: { try await secrets.contains(key) },
            set: { value in try await secrets.write(value, for: key) })
    }

    /// A configured value as the controls show it; a path abbreviates the home folder to `~`.
    static func controlValue(_ value: (any SettingValue)?) -> SettingControlValue? {
        switch value {
        case let value as Bool: .bool(value)
        case let value as Int: .int(value)
        case let value as Double: .double(value)
        case let value as String: .string(value)
        case let value as Duration: .duration(value)
        case let value as URL: .string((value.path as NSString).abbreviatingWithTildeInPath)
        case let value as [String]: .strings(value)
        default: nil
        }
    }

    /// What a control writes: nil resets to the front-matter default (also an emptied path); numbers are clamped
    /// to the declared min and max.
    static func settingValue(_ value: SettingControlValue?, kind: ScriptSetting.Kind) -> (any SettingValue)? {
        guard let value else { return nil }
        switch (value, kind) {
        case (.int(let number), .int(_, let min, let max, _)):
            return clamp(number, min: min, max: max)
        case (.int(let number), .double(_, let min, let max, _)):
            return clamp(Double(number), min: min, max: max)
        case (.double(let number), .double(_, let min, let max, _)):
            return clamp(number, min: min, max: max)
        case (.double(let number), .int(_, let min, let max, _)):
            return clamp(Int(number.rounded()), min: min, max: max)
        case (.bool(let flag), _): return flag
        case (.int(let number), _): return number
        case (.double(let number), _): return number
        case (.string(let text), _): return text
        case (.duration(let duration), _): return duration
        case (.strings(let items), _): return items
        case (.none, _): return nil
        }
    }

    static func clamp<T: Comparable>(_ value: T, min: T?, max: T?) -> T {
        var result = value
        if let min { result = Swift.max(result, min) }
        if let max { result = Swift.min(result, max) }
        return result
    }
}
