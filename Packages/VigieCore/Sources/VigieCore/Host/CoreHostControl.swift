import ModuleKit
import os

/// Late binding between module contexts and the Notch Host: App assembly builds the context factory before
/// the host exists, then sets ``host``. Until then (and in tests) host requests do nothing.
@MainActor
public final class NotchHostLink {
    public weak var host: NotchHost?
    /// The module floating panel (Story 15.3), built from ``host`` on first use; tests set their own.
    public var floatingPanels: FloatingPanelController?

    public init(host: NotchHost? = nil) {
        self.host = host
    }

    /// ``floatingPanels``, built for ``host`` the first time; nil while the link is unbound.
    public func floatingPanelController() -> FloatingPanelController? {
        if let floatingPanels { return floatingPanels }
        guard let host else { return nil }
        let controller = FloatingPanelController(host: host)
        floatingPanels = controller
        return controller
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

    /// Opens Settings on this module's pane (pane id = module id), only with a `UserIntent` (Story 12.9: the
    /// Script Confirmation of a `vigie://install` link lives in Settings › Scripts).
    @MainActor public func openOwnSettings(focus: UserIntent?) {
        guard focus != nil, let host = link.host else { return }
        if let openPane = host.openSettingsPane {
            openPane(moduleID.rawValue)
        } else {
            host.openSettings?()
        }
    }

    /// Shows this module's floating panel with focus (Story 15.3, AD-13); refused without a live `UserIntent` or
    /// while the link is unbound. One floating panel at a time: it replaces any shown one.
    @MainActor @discardableResult public func presentFloatingPanel(
        _ request: FloatingPanelRequest, focus: UserIntent?
    ) -> Bool {
        guard focus != nil, let controller = link.floatingPanelController() else { return false }
        return controller.present(request, owner: moduleID, focus: focus)
    }

    /// Closes this module's floating panel, if it is the one shown.
    @MainActor public func dismissFloatingPanel() {
        link.floatingPanels?.dismiss(owner: moduleID)
    }

    /// Registers a script module with the host's ``ModuleRegistry`` on behalf of this module (AD-18, Story
    /// 12.5): it then takes part in arbitration, Home, the tabs and Settings like a built-in. Throws
    /// ``ModuleServiceError/notAvailable`` while the link is unbound, ``DynamicModuleError`` when the id is taken.
    @MainActor public func registerDynamicModule(_ module: any NotchModule) throws -> RegistrationToken {
        guard let registry = link.host?.registry else { throw ModuleServiceError.notAvailable }
        return try registry.registerDynamic(module, owner: moduleID)
    }
}
