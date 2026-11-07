import Foundation
import KeyboardShortcuts
import ModuleKit

/// Binds the temporary peek shortcuts. ``KeyboardShortcutsTemporaryBackend`` in the app, a fake in tests.
@MainActor
public protocol TemporaryShortcutBackend: HotkeyBinding {
    /// Silences other Vigie shortcuts (full names, as `HotkeyCenter` binds them) without unbinding them.
    func suspend(names: Set<String>)
    /// Lets suspended shortcuts fire again.
    func resume(names: Set<String>)
}

/// The peek shortcuts `⌥⌘↵` (primary) and `⌥⌘⌫` (Dismiss), bound only while a peek is visible (Story 3.3,
/// AD-13, Conventions: Hotkeys).
///
/// **Mechanism.** They are Carbon hotkeys through KeyboardShortcuts (AD-16), under the fixed names
/// `peek:primary` and `peek:secondary`, outside `HotkeyCenter`: they are not user-configurable, take no part in
/// its conflict rules and never appear in Settings. Carbon hotkeys need no Accessibility or Input Monitoring
/// permission (an `NSEvent` global key monitor would) and never change the frontmost app, so the user's editor
/// keeps focus. Every other key, bare Esc included, is not registered and reaches the frontmost app.
///
/// **Precedence.** While active, any other Vigie shortcut bound to one of the two combinations (read from
/// `others`, normally `HotkeyCenter.bound`) is suspended, so only the peek action fires; it fires again after
/// the peek retracts. The handlers run on key-up, like `HotkeyCenter`'s, so the releasing key-up of the press
/// that retracted the peek cannot reach a resumed shortcut.
@MainActor
public final class TemporaryShortcuts {
    /// Full name of the primary shortcut (the KeyboardShortcuts name is `peek:primary`).
    public static let primaryName = "peek.primary"
    /// Full name of the Dismiss shortcut.
    public static let secondaryName = "peek.secondary"
    // Known valid: Option + Command on a non-typing key.
    // swiftlint:disable force_try
    /// `⌥⌘↵`.
    public static let primarySpec = try! HotkeySpec(parsing: "opt+cmd+return")
    /// `⌥⌘⌫`.
    public static let secondarySpec = try! HotkeySpec(parsing: "opt+cmd+delete")
    // swiftlint:enable force_try

    /// True while the shortcuts are bound.
    public private(set) var isActive = false

    private let backend: any TemporaryShortcutBackend
    private let others: @MainActor () -> [String: HotkeySpec]
    private var suspended: Set<String> = []

    /// - Parameters:
    ///   - backend: binds the shortcuts; KeyboardShortcuts by default.
    ///   - others: the other Vigie shortcuts bound now (full name to combination), e.g. `{ hotkeys.bound }`.
    public init(
        backend: (any TemporaryShortcutBackend)? = nil,
        others: @escaping @MainActor () -> [String: HotkeySpec] = { [:] }
    ) {
        self.backend = backend ?? KeyboardShortcutsTemporaryBackend()
        self.others = others
    }

    /// Binds `⌥⌘↵` to `primary` (when given) and `⌥⌘⌫` to `secondary`, replacing any earlier handlers. Each press
    /// mints a `UserIntent` for the handler.
    public func activate(
        primary: (@MainActor (UserIntent) -> Void)?,
        secondary: @escaping @MainActor (UserIntent) -> Void
    ) {
        let specs: Set<HotkeySpec> = primary == nil ? [Self.secondarySpec] : [Self.primarySpec, Self.secondarySpec]
        let clashing = Set(
            others().filter { specs.contains($0.value) && !$0.key.hasPrefix("peek.") }.map(\.key))
        let release = suspended.subtracting(clashing)
        if !release.isEmpty { backend.resume(names: release) }
        let hold = clashing.subtracting(suspended)
        if !hold.isEmpty { backend.suspend(names: hold) }
        suspended = clashing

        if let primary {
            backend.bind(name: Self.primaryName, shortcut: Self.primarySpec) {
                primary(UserIntentMinter.mint(source: .hotkey(Self.primaryName)))
            }
        } else {
            backend.unbind(name: Self.primaryName)
        }
        backend.bind(name: Self.secondaryName, shortcut: Self.secondarySpec) {
            secondary(UserIntentMinter.mint(source: .hotkey(Self.secondaryName)))
        }
        isActive = true
    }

    /// Unbinds both shortcuts and lets the suspended ones fire again. No-op when inactive.
    public func deactivate() {
        guard isActive else { return }
        backend.unbind(name: Self.primaryName)
        backend.unbind(name: Self.secondaryName)
        if !suspended.isEmpty { backend.resume(names: suspended) }
        suspended = []
        isActive = false
    }
}

/// The production backend: KeyboardShortcuts (Carbon hotkeys, no permission needed).
///
/// Suspending a name uses `KeyboardShortcuts.disable`, which stops its handlers while its shortcut stays
/// registered for the peek name. Resuming waits for the current event to finish, so the key event being handled
/// when the peek retracted is not delivered to the resumed name as well.
@MainActor
public final class KeyboardShortcutsTemporaryBackend: TemporaryShortcutBackend {
    private let binding = KeyboardShortcutsBinding()
    private var suspended: Set<String> = []

    public init() {}

    public func bind(name: String, shortcut: HotkeySpec, onKeyUp: @escaping @MainActor () -> Void) {
        binding.bind(name: name, shortcut: shortcut, onKeyUp: onKeyUp)
    }

    public func unbind(name: String) {
        binding.unbind(name: name)
    }

    public func suspend(names: Set<String>) {
        suspended.formUnion(names)
        KeyboardShortcuts.disable(names.map(KeyboardShortcutsBinding.ksName))
    }

    public func resume(names: Set<String>) {
        suspended.subtract(names)
        Task { @MainActor [weak self] in
            // A peek shown meanwhile may have suspended some of them again.
            let still = names.subtracting(self?.suspended ?? [])
            KeyboardShortcuts.enable(still.map(KeyboardShortcutsBinding.ksName))
        }
    }
}
