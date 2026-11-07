import KeyboardShortcuts
import SwiftUI
import VigieUI

/// The `hotkey` control: KeyboardShortcuts' recorder (only here, in Settings), bound to the config value.
///
/// The recorder works on a binding, not a KeyboardShortcuts name, so nothing is stored in UserDefaults: config
/// stays the source of truth and `HotkeyConfigBridge` re-binds the hotkey after the write. A combination
/// `HotkeySpec` rejects (Option-only, no modifier) shows an inline error and writes nothing.
struct HotkeyRecorderField: View {
    @Environment(\.settingControlServices) private var services
    let binding: SettingBinding
    let state: SettingFieldState

    var body: some View {
        let current = Self.shortcut(from: binding.get())
        KeyboardShortcuts.Recorder(
            shortcut: Binding(get: { current }, set: { _ in }),
            onChange: { shortcut in
                Task { @MainActor in
                    await Self.write(shortcut, binding: binding, state: state, services: services)
                }
            })
    }

    static func shortcut(from value: SettingControlValue?) -> KeyboardShortcuts.Shortcut? {
        guard case .string(let text) = value, let spec = try? HotkeySpec(parsing: text) else { return nil }
        return spec.shortcut
    }

    /// Writes the recorded shortcut as its canonical config string; nil clears it.
    @MainActor
    static func write(
        _ shortcut: KeyboardShortcuts.Shortcut?, binding: SettingBinding, state: SettingFieldState,
        services: SettingControlServices
    ) async {
        guard let shortcut else {
            await state.apply(SettingControlValue.none, to: binding, services: services)
            return
        }
        guard let key = shortcut.key, let spec = try? HotkeySpec(key: key, modifiers: shortcut.modifiers) else {
            state.report(SettingsText.string("settings.error.hotkey"))
            return
        }
        await state.apply(.string(spec.description), to: binding, services: services)
    }
}
