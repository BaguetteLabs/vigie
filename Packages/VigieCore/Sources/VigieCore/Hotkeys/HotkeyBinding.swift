import KeyboardShortcuts

/// Binds and unbinds one global shortcut. `HotkeyCenter` decides what is bound (names, conflicts, config);
/// the binding only talks to the system, so tests can substitute a fake (global hotkeys cannot be registered
/// reliably under `swift test`).
@MainActor
public protocol HotkeyBinding: AnyObject {
    /// Binds `shortcut` to `name` (a full name such as `core.expand`), replacing any earlier binding of `name`.
    func bind(name: String, shortcut: HotkeySpec, onKeyUp: @escaping @MainActor () -> Void)
    /// Removes the binding of `name`; no-op if it is not bound.
    func unbind(name: String)
}

/// The production binding, backed by KeyboardShortcuts (AD-16).
///
/// KeyboardShortcuts names cannot contain dots, so `core.expand` is stored as `core:expand`. Vigie's config is
/// the source of truth: the resolved shortcut is written with `setShortcut` on every bind, overriding whatever
/// KeyboardShortcuts persisted in UserDefaults.
@MainActor
public final class KeyboardShortcutsBinding: HotkeyBinding {
    public init() {}

    public func bind(name: String, shortcut: HotkeySpec, onKeyUp: @escaping @MainActor () -> Void) {
        let ksName = Self.ksName(name)
        KeyboardShortcuts.removeHandler(for: ksName)
        KeyboardShortcuts.setShortcut(shortcut.shortcut, for: ksName)
        KeyboardShortcuts.enable(ksName)
        KeyboardShortcuts.onKeyUp(for: ksName) { onKeyUp() }
    }

    public func unbind(name: String) {
        let ksName = Self.ksName(name)
        KeyboardShortcuts.removeHandler(for: ksName)
        KeyboardShortcuts.disable(ksName)
    }

    static func ksName(_ fullName: String) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name(fullName.replacingOccurrences(of: ".", with: ":"))
    }
}
