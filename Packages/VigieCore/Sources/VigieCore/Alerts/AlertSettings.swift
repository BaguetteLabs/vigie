import Foundation
import ModuleKit

/// One rule key of `[modules."<id>".notify."<kind>"]` that the generated alert settings edit (SPEC §6, AD-13).
public enum AlertSettingKey: String, CaseIterable, Sendable {
    /// `mute = true` silences the kind; the Settings "Enabled" toggle shows it inverted.
    case mute
    /// `outputs = ["peek", "system", "sound"]`.
    case outputs
    /// `reminder = "2m"`; absent (or `"0s"`) means no reminder.
    case reminder
}

/// The generated settings of one declared alert kind (AD-13: Notifier owns them, modules never declare
/// alert settings; the UI is built from the manifest's `alertKinds`).
public struct AlertKindSetting: Identifiable, Hashable, Sendable {
    public let module: ModuleID
    public let kind: String

    public init(module: ModuleID, kind: String) {
        self.module = module
        self.kind = kind
    }

    public var id: String { kind }

    /// `modules."<id>".notify."<kind>".<key>`; the kind is one quoted segment (`"session.done"`).
    public func path(_ key: AlertSettingKey) -> ConfigKeyPath {
        AlertSettings.path(module: module, kind: kind, key: key)
    }

    /// The kind's label from the catalog (`settings.alerts.kind.<kind>`), else the kind id itself.
    public var label: String {
        let key = "settings.alerts.kind.\(kind)"
        let found = Bundle.module.localizedString(forKey: key, value: nil, table: nil)
        return found == key ? kind : found
    }
}

/// Builds the alert settings of a module from its manifest, and their config schema entries.
public enum AlertSettings {
    /// The per-module rule table (`[modules."<id>".notify]`).
    public static let table = "notify"

    /// Display and write order of outputs (Peek / System notification / Sound).
    public static let outputOrder: [AlertOutput] = [.peek, .system, .sound]

    /// Outputs when no rule layer sets `outputs` (AD-13 default, `NotifyRule.defaultOutputs`).
    public static var defaultOutputs: [AlertOutput] {
        ordered(NotifyRule.defaultOutputs(for: .info))
    }

    /// One entry per kind the manifest declares, in declaration order (duplicates dropped).
    public static func kinds(for manifest: ModuleManifest) -> [AlertKindSetting] {
        var seen = Set<String>()
        return manifest.alertKinds.filter { seen.insert($0).inserted }.map {
            AlertKindSetting(module: manifest.id, kind: $0)
        }
    }

    public static func path(module: ModuleID, kind: String, key: AlertSettingKey) -> ConfigKeyPath {
        ConfigKeyPath(["modules", module.rawValue, table, kind, key.rawValue])
    }

    public static func ordered(_ outputs: some Sequence<AlertOutput>) -> [AlertOutput] {
        let set = Set(outputs)
        return outputOrder.filter(set.contains)
    }

    /// The schema entries `ConfigSchema.register` adds per declared kind, so Settings writes are validated
    /// and these keys are known (`mute`, `outputs`, `reminder`; other rule keys stay free-form).
    static func schemaDescriptors(for manifest: ModuleManifest) -> [(ConfigKeyPath, SettingDescriptor)] {
        kinds(for: manifest).flatMap { setting in
            AlertSettingKey.allCases.map { key in
                (setting.path(key), descriptor(key))
            }
        }
    }

    static func descriptor(_ key: AlertSettingKey) -> SettingDescriptor {
        switch key {
        case .mute:
            SettingDescriptor(
                key: key.rawValue, label: SettingsText.resource("settings.alerts.mute"), kind: .bool(default: false))
        case .outputs:
            SettingDescriptor(
                key: key.rawValue, label: SettingsText.resource("settings.alerts.outputs"),
                kind: .list(of: .string, default: defaultOutputs.map(\.rawValue)))
        case .reminder:
            SettingDescriptor(
                key: key.rawValue, label: SettingsText.resource("settings.alerts.reminder"),
                kind: .duration(default: .zero))
        }
    }
}

extension ConfigStore {
    /// The generated alert settings of `manifest` (empty when it declares no kinds).
    public func alertSettings(for manifest: ModuleManifest) -> [AlertKindSetting] {
        AlertSettings.kinds(for: manifest)
    }

    /// Not muted (default on).
    public func isAlertEnabled(_ setting: AlertKindSetting) -> Bool {
        !(value(setting.path(.mute), as: Bool.self) ?? false)
    }

    /// Off writes `mute = true`; on removes `mute` (the default, not muted).
    public func setAlertEnabled(_ setting: AlertKindSetting, _ enabled: Bool) async throws(ConfigError) {
        if enabled {
            try await remove(setting.path(.mute))
        } else {
            try await set(setting.path(.mute), to: .bool(true))
        }
    }

    /// The configured outputs in Peek / System / Sound order (unknown names dropped), or the default.
    public func alertOutputs(_ setting: AlertKindSetting) -> [AlertOutput] {
        guard let names = value(setting.path(.outputs), as: [String].self) else { return AlertSettings.defaultOutputs }
        return AlertSettings.ordered(names.compactMap(AlertOutput.init(rawValue:)))
    }

    /// Writes `outputs` in Peek / System / Sound order; nil removes the key (default outputs).
    public func setAlertOutputs(_ setting: AlertKindSetting, _ outputs: Set<AlertOutput>?) async throws(ConfigError) {
        guard let outputs else {
            try await remove(setting.path(.outputs))
            return
        }
        try await set(setting.path(.outputs), to: .strings(AlertSettings.ordered(outputs).map(\.rawValue)))
    }

    /// The reminder delay, nil for none.
    public func alertReminder(_ setting: AlertKindSetting) -> Duration? {
        guard let duration = value(setting.path(.reminder), as: Duration.self), duration > .zero else { return nil }
        return duration
    }

    /// nil or zero removes `reminder` (no reminder); else writes it (`"2m"`).
    public func setAlertReminder(_ setting: AlertKindSetting, _ reminder: Duration?) async throws(ConfigError) {
        guard let reminder, reminder > .zero else {
            try await remove(setting.path(.reminder))
            return
        }
        try await set(setting.path(.reminder), to: .duration(reminder))
    }

    /// Removes the kind's `mute`, `outputs` and `reminder` (back to defaults).
    public func resetAlert(_ setting: AlertKindSetting) async throws(ConfigError) {
        for key in AlertSettingKey.allCases { try await remove(setting.path(key)) }
    }
}
