import ModuleKit

/// What VigieCore's own hotkeys do. Wired by the App to the Notch Host.
public struct CoreHotkeyActions {
    /// `core.expand`: expand (or collapse) the notch, taking focus with the hotkey's intent.
    public var expand: @MainActor (UserIntent) -> Void

    public init(expand: @escaping @MainActor (UserIntent) -> Void) {
        self.expand = expand
    }
}

/// VigieCore's default global shortcuts (SPEC §11, FR111).
public enum CoreHotkeys {
    /// Full name of the expand hotkey; configured by `[general] expand_hotkey`.
    public static let expandName = "core.expand"

    /// Default shortcut strings by short name. None is Option-only (enforced by `HotkeySpec`).
    public static let defaults: [String: String] = [
        "expand": "cmd+shift+space"
    ]

    /// Registers the core hotkeys in `center`. Keep the returned tokens for the app's lifetime.
    @MainActor
    public static func registerDefaults(in center: HotkeyCenter, actions: CoreHotkeyActions) throws
        -> [RegistrationToken]
    {
        let expand = try center.register(
            owner: .core,
            name: "expand",
            default: try defaults["expand"].map { try HotkeySpec(parsing: $0) },
            handler: actions.expand
        )
        return [expand]
    }
}
