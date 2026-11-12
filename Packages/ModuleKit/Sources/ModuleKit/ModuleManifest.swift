import Foundation

/// What a module declares about itself (SPEC §4.2). Available without starting the module.
public struct ModuleManifest: Sendable {
    public let id: ModuleID
    public let name: LocalizedStringResource
    /// SF Symbol name.
    public let icon: String
    public let permissions: Set<Permission>
    public let settings: [SettingDescriptor]
    /// Notifier kinds this module posts (AD-13), e.g. `session.blocked`. The alert settings UI is generated from them.
    public let alertKinds: [String]
    /// Used when config has no `[modules."<id>"] enabled` key.
    public let defaultEnabled: Bool
    /// The module starts while a declared permission is missing (Story 13.1). It then asks for it itself through
    /// `context.permissions` in `start(context:)` (still only while enabled, SPEC §4.3 step 2) and shows its own
    /// setup card in its tab and pane (UX-DR23). Default false: the Registry requests the declared permissions
    /// and keeps the module stopped, "needs permission" in Settings, until they are granted (SPEC §4.3 step 3).
    public let startsWithoutPermissions: Bool

    public init(
        id: ModuleID,
        name: LocalizedStringResource,
        icon: String,
        permissions: Set<Permission> = [],
        settings: [SettingDescriptor] = [],
        alertKinds: [String] = [],
        defaultEnabled: Bool = true,
        startsWithoutPermissions: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.permissions = permissions
        self.settings = settings
        self.alertKinds = alertKinds
        self.defaultEnabled = defaultEnabled
        self.startsWithoutPermissions = startsWithoutPermissions
    }
}
