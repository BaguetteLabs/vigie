import ModuleKit
import os

/// Late binding between module contexts and the Notch Host: App assembly builds the context factory before
/// the host exists, then sets ``host``. Until then (and in tests) host requests do nothing.
@MainActor
public final class NotchHostLink {
    public weak var host: NotchHost?

    public init(host: NotchHost? = nil) {
        self.host = host
    }
}

/// `context.host` for one module (AD-19, SPEC §4.2).
///
/// The expanded view never opens by itself (Story 2.10, UX-DR41): `expand` and `openOwnTab` act only with a
/// `UserIntent`, which only VigieCore mints from a click, hotkey, menu or peek action. Without one they are
/// ignored.
public struct CoreHostControl: HostControl {
    public let moduleID: ModuleID
    public let link: NotchHostLink

    public init(moduleID: ModuleID, link: NotchHostLink) {
        self.moduleID = moduleID
        self.link = link
    }

    @MainActor public func requestPeek() {
        // TODO(Story 3.2): show this module's closed-notch content briefly.
    }

    @MainActor public func expand(focus: UserIntent?) {
        guard let focus else { return }
        link.host?.expand(focus: focus)
    }

    @MainActor public func openOwnTab(focus: UserIntent?) {
        guard let focus else { return }
        link.host?.openTab(moduleID.rawValue, focus: focus)
    }

    @MainActor public func registerDynamicModule(_ module: any NotchModule) throws -> RegistrationToken {
        // Epic 15 (dynamic script modules).
        throw ModuleServiceError.notAvailable
    }
}
