import Foundation
import ModuleKit
import SwiftUI
import VigieUI

extension ConfigStore {
    /// A binding for one generated alert control (Story 3.7). `.mute` reads and writes the inverted
    /// "Enabled" value; `.outputs` a list of output names; `.reminder` a duration or `.none` (no reminder).
    /// `set(nil)` resets the key. Refused writes throw `SettingWriteError` (catalog text).
    func alertBinding(_ setting: AlertKindSetting, _ key: AlertSettingKey) -> SettingBinding {
        SettingBinding(
            get: { [weak self] in
                guard let self else { return nil }
                switch key {
                case .mute: return .bool(self.isAlertEnabled(setting))
                case .outputs: return .strings(self.alertOutputs(setting).map(\.rawValue))
                case .reminder:
                    return self.alertReminder(setting).map(SettingControlValue.duration) ?? SettingControlValue.none
                }
            },
            set: { [weak self] value in
                guard let self else { return }
                do throws(ConfigError) {
                    switch (key, value) {
                    case (_, nil): try await self.remove(setting.path(key))
                    case (.mute, .bool(let enabled)?): try await self.setAlertEnabled(setting, enabled)
                    case (.outputs, .strings(let names)?):
                        try await self.setAlertOutputs(setting, Set(names.compactMap(AlertOutput.init(rawValue:))))
                    case (.reminder, .duration(let duration)?): try await self.setAlertReminder(setting, duration)
                    case (.reminder, SettingControlValue.none?): try await self.setAlertReminder(setting, nil)
                    default:
                        throw ConfigError.invalidValue(key: setting.path(key).description, reason: "wrong value type")
                    }
                } catch {
                    throw SettingWriteError(error)
                }
            })
    }
}

extension SettingsController {
    /// The generated alert settings of a module pane (one per declared kind; empty: no section).
    public func alertSettings(for manifest: ModuleManifest) -> [AlertKindSetting] {
        configStore.alertSettings(for: manifest)
    }

    /// The "Enabled" row of a kind: a generated bool row over the inverted `mute` key.
    func alertEnabledRow(_ setting: AlertKindSetting) -> SettingRowModel {
        SettingRowModel(
            id: setting.path(.mute).description,
            label: SettingsText.resource("settings.alerts.enabled"),
            kind: .bool(default: true),
            binding: configStore.alertBinding(setting, .mute))
    }
}

/// "Alerts" in a module pane (Story 3.7, FR15, AD-13): one group per kind the manifest declares, below the
/// module's generated rows and above its own view. Nothing when the module declares no kinds.
struct AlertSettingsSection: View {
    let controller: SettingsController
    let manifest: ModuleManifest

    var body: some View {
        let settings = controller.alertSettings(for: manifest)
        ForEach(Array(settings.enumerated()), id: \.element.id) { index, setting in
            Section {
                AlertKindRows(controller: controller, setting: setting)
            } header: {
                VStack(alignment: .leading) {
                    if index == 0 {
                        Text(SettingsText.resource("settings.alerts.section"))
                            .font(.headline)
                    }
                    Text(verbatim: setting.label)
                }
            }
        }
    }
}

/// Enabled, outputs and reminder of one kind. Outputs and reminder are dimmed while the kind is muted.
struct AlertKindRows: View {
    let controller: SettingsController
    let setting: AlertKindSetting

    var body: some View {
        let store = controller.configStore
        let enabled = store.isAlertEnabled(setting)
        SettingRow(controller.alertEnabledRow(setting))
        AlertOutputsRow(binding: store.alertBinding(setting, .outputs))
            .disabled(!enabled)
        AlertReminderRow(binding: store.alertBinding(setting, .reminder))
            .disabled(!enabled)
    }
}

/// Peek / System notification / Sound checkboxes over `outputs`.
struct AlertOutputsRow: View {
    @Environment(\.settingControlServices) private var services
    @State private var state = SettingFieldState()
    let binding: SettingBinding

    var body: some View {
        let current = Set((binding.get()?.stringsValue ?? []).compactMap(AlertOutput.init(rawValue:)))
        LabeledContent {
            HStack {
                ForEach(AlertSettings.outputOrder, id: \.self) { output in
                    Toggle(
                        isOn: Binding(
                            get: { current.contains(output) },
                            set: { on in
                                var next = current
                                if on { next.insert(output) } else { next.remove(output) }
                                write(.strings(AlertSettings.ordered(next).map(\.rawValue)))
                            })
                    ) {
                        Text(Self.label(output))
                    }
                    .toggleStyle(.checkbox)
                }
            }
        } label: {
            Text(SettingsText.resource("settings.alerts.outputs"))
            if let error = state.error {
                Text(verbatim: error).foregroundStyle(.red)
            }
        }
        .contextMenu {
            Button {
                write(nil)
            } label: {
                Text(SettingsText.resource("settings.alerts.reset"))
            }
        }
    }

    static func label(_ output: AlertOutput) -> LocalizedStringResource {
        SettingsText.resource("settings.alerts.output.\(output.rawValue)")
    }

    private func write(_ value: SettingControlValue?) {
        Task { await state.apply(value, to: binding, services: services) }
    }
}

/// Reminder delay field: a duration (`2m`), or empty for none (removes `reminder`).
struct AlertReminderRow: View {
    @Environment(\.settingControlServices) private var services
    @State private var state = SettingFieldState()
    @State private var draft = ""
    @FocusState private var focused: Bool
    let binding: SettingBinding

    var body: some View {
        let current = Self.text(binding.get(), services: services)
        LabeledContent {
            TextField(text: $draft, prompt: Text(SettingsText.resource("settings.alerts.reminder.none"))) {
                Text(SettingsText.resource("settings.alerts.reminder"))
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: SettingsMetrics.numberFieldWidth * 2)
            .focused($focused)
            .onSubmit { commit(current: current) }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit(current: current) } }
            .onAppear { draft = current }
            .onChange(of: current) { _, newValue in draft = newValue }
        } label: {
            Text(SettingsText.resource("settings.alerts.reminder"))
            Text(SettingsText.resource("settings.alerts.reminder.help"))
            if let error = state.error {
                Text(verbatim: error).foregroundStyle(.red)
            }
        }
        .contextMenu {
            Button {
                Task { await state.apply(nil, to: binding, services: services) }
            } label: {
                Text(SettingsText.resource("settings.alerts.reset"))
            }
        }
    }

    static func text(_ value: SettingControlValue?, services: SettingControlServices) -> String {
        value?.durationValue.map(services.formatDuration) ?? ""
    }

    private func commit(current: String) {
        guard draft != current else {
            state.clearError()
            return
        }
        let text = draft
        Task { await Self.commit(text, to: binding, state: state, services: services) }
    }

    /// Empty text removes the reminder; otherwise the text must parse as a duration, else the row shows the
    /// localized duration error and nothing is written.
    @discardableResult
    static func commit(
        _ text: String, to binding: SettingBinding, state: SettingFieldState, services: SettingControlServices
    ) async -> Bool {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            return await state.apply(SettingControlValue.none, to: binding, services: services)
        }
        return await state.commitDuration(text, to: binding, services: services)
    }
}
