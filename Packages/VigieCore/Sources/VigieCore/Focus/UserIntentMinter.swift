import Foundation
@_spi(Host) import ModuleKit

/// The user action a `UserIntent` is minted for (AD-13). Naming it at every mint site keeps the rule auditable:
/// intents come only from clicks, hotkey callbacks, menu actions and peek action buttons.
public enum IntentSource: Hashable, Sendable {
    case click
    /// A global hotkey fired; carries its full name, e.g. `core.expand`.
    case hotkey(String)
    /// A menu item was chosen; carries its identifier.
    case menu(String)
    /// A peek action button was pressed.
    case peekAction
}

/// The only place outside tests that creates `UserIntent` tokens (AD-13). Call it from inside the user-action
/// callback itself, never ahead of time or from a timer, alert or drag.
@MainActor
public enum UserIntentMinter {
    /// A fresh token (new id, issued now) for a user action from `source`.
    public static func mint(source: IntentSource) -> UserIntent {
        UserIntent(issuedAt: Date())
    }
}
