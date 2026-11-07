import Foundation
import ModuleKit

/// `context.hotkeys` for one module: registers `<module id>.<name>` in the shared `HotkeyCenter` and tracks the
/// token so the hotkey is removed when the module stops (FR3).
///
/// `HotkeyRegistry.register` is synchronous and not main-actor isolated in ModuleKit; modules are
/// `@MainActor` and call it from `start(context:)`, so it runs inline. A call from another thread throws
/// `HotkeyError.notOnMainActor`.
struct CoreHotkeyRegistry: HotkeyRegistry {
    let moduleID: ModuleID
    let center: HotkeyCenter
    let tracker: RegistrationTracker

    func register(
        name: String,
        default shortcut: String?,
        handler: @escaping @MainActor @Sendable (UserIntent) -> Void
    ) throws -> RegistrationToken {
        guard Thread.isMainThread else { throw HotkeyError.notOnMainActor }
        let token = try MainActor.assumeIsolated {
            let spec = try shortcut.map { try HotkeySpec(parsing: $0) }
            return try center.register(owner: .module(moduleID), name: name, default: spec, handler: handler)
        }
        return tracker.track(token)
    }
}
