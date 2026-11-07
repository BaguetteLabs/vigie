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

    public init(
        id: ModuleID,
        name: LocalizedStringResource,
        icon: String,
        permissions: Set<Permission> = [],
        settings: [SettingDescriptor] = [],
        alertKinds: [String] = [],
        defaultEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.permissions = permissions
        self.settings = settings
        self.alertKinds = alertKinds
        self.defaultEnabled = defaultEnabled
    }
}
