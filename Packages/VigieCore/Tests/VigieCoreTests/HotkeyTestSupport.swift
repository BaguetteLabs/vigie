import ModuleKit

@testable import VigieCore

/// Records binds instead of registering global hotkeys (which `swift test` cannot do reliably).
@MainActor
final class FakeHotkeyBinding: HotkeyBinding {
    private(set) var bound: [String: HotkeySpec] = [:]
    private var handlers: [String: @MainActor () -> Void] = [:]
    private(set) var bindCount = 0
    private(set) var unbindCount = 0

    func bind(name: String, shortcut: HotkeySpec, onKeyUp: @escaping @MainActor () -> Void) {
        bound[name] = shortcut
        handlers[name] = onKeyUp
        bindCount += 1
    }

    func unbind(name: String) {
        bound[name] = nil
        handlers[name] = nil
        unbindCount += 1
    }

    /// Simulates the user pressing the shortcut bound to `name`. Returns false if nothing is bound.
    @discardableResult
    func press(_ name: String) -> Bool {
        guard let handler = handlers[name] else { return false }
        handler()
        return true
    }
}

/// Test literals are known valid.
func spec(_ string: String) throws -> HotkeySpec {
    try HotkeySpec(parsing: string)
}
