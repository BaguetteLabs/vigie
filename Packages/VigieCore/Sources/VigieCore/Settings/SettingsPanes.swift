import Foundation
import ModuleKit

/// A group of core settings inside a pane, with an optional heading.
public struct SettingsSection: Sendable {
    public let title: LocalizedStringResource?
    public let keys: [ConfigKeyPath]

    public init(title: LocalizedStringResource? = nil, keys: [ConfigKeyPath]) {
        self.title = title
        self.keys = keys
    }
}

/// One entry of the Settings sidebar.
public struct SettingsPane: Identifiable, Sendable {
    public enum Content: Sendable {
        /// Generated rows for core keys (SPEC §11 tables).
        case core([SettingsSection])
        /// A module's pane: `enabled`, status, its descriptors, then its optional custom view.
        case module(ModuleManifest)
        /// Settings › General › Activity log (A80).
        case activity
    }

    /// Pane id as `openSettings(pane:)` takes it: a core pane id or a module id.
    public let id: String
    public let title: LocalizedStringResource
    /// SF Symbol.
    public let icon: String
    public let content: Content

    public var isModule: Bool {
        if case .module = content { true } else { false }
    }
}

/// The pane skeleton (UX-DR74 as amended 2026-11-07, EXPERIENCE "Settings") mapped onto the SPEC §11 tables.
///
/// | Pane id      | Title        | Config tables / keys                                                    |
/// |--------------|--------------|-------------------------------------------------------------------------|
/// | `general`    | General      | `[general]` (minus `tab_order`), Launch at login, `[privacy]`, CLI status |
/// | `activity`   | Activity Log | read-only activity log (A80; "Settings › General › Activity log")      |
/// | `appearance` | Appearance   | `[appearance]` (+ Reduce motion warning next to Presence)               |
/// | `closed`     | Notch        | `[closed]`                                                              |
/// | `display`    | Displays     | `[display]`, `[virtual_notch]` (local)                                  |
/// | `home`       | Home         | `[home] cards`, `[general] tab_order`                                   |
/// | `notify`     | Alerts       | `[notify]`                                                              |
/// | `sounds`     | Sounds       | `[sounds]`                                                              |
/// | `sync`       | Sync         | `[sync]` (local)                                                        |
/// | `updates`    | Updates      | `[updates]`                                                             |
/// | `<module id>`| module name  | `[modules."<id>"]` (`enabled` + the manifest's descriptors)             |
///
/// Module panes (Agents, Usage, Shelf, Calendar, Time, Notes, Scripts…) follow in registry order.
/// `[appearance.colors]` is free-form and has no generated rows yet. Aliases: `privacy` → `general`,
/// `virtual_notch` / `displays` → `display`, `notch` → `closed`, `alerts` → `notify`.
public enum SettingsPaneCatalog {
    /// Settings › Home (Story 11.1): the Home card list, then `[general] tab_order`.
    public static let homePaneID = "home"

    public static let corePaneIDs = [
        "general", "activity", "appearance", "closed", "display", "home", "notify", "sounds", "sync", "updates",
    ]

    public static let aliases: [String: String] = [
        "privacy": "general",
        "virtual_notch": "display",
        "displays": "display",
        "notch": "closed",
        "alerts": "notify",
    ]

    static func keys(_ table: String, _ names: [String]) -> [ConfigKeyPath] {
        names.map { CoreSettings.path(table, $0) }
    }

    public static func corePanes() -> [SettingsPane] {
        [
            SettingsPane(
                id: "general", title: SettingsText.resource("settings.pane.general"), icon: "gearshape",
                content: .core([
                    SettingsSection(
                        keys: keys(
                            "general",
                            [
                                "hide_in_fullscreen", "open_on_hover", "close_on_leave", "hover_delay", "home_after",
                                "expand_hotkey", "prevent_idle_sleep",
                            ])),
                    SettingsSection(
                        title: SettingsText.resource("settings.section.privacy"),
                        keys: keys("privacy", ["auto", "force"])),
                ])),
            SettingsPane(
                id: "activity", title: SettingsText.resource("settings.pane.activity"), icon: "list.bullet.rectangle",
                content: .activity),
            SettingsPane(
                id: "appearance", title: SettingsText.resource("settings.pane.appearance"), icon: "paintpalette",
                content: .core([
                    SettingsSection(keys: keys("appearance", ["theme", "mode", "presence"])),
                    SettingsSection(keys: keys("closed", ["notch_overlap", "notch_side_inset"])),
                ])),
            SettingsPane(
                id: "closed", title: SettingsText.resource("settings.pane.closed"),
                icon: "rectangle.topthird.inset.filled",
                content: .core([
                    SettingsSection(keys: keys("closed", ["max_side_width", "slots", "peek", "peek_duration"]))
                ])),
            SettingsPane(
                id: "display", title: SettingsText.resource("settings.pane.display"), icon: "display",
                content: .core([
                    SettingsSection(keys: keys("display", ["display"])),
                    SettingsSection(
                        title: SettingsText.resource("settings.section.virtualNotch"),
                        keys: keys("virtual_notch", ["width", "idle", "position", "placement", "style"])),
                ])),
            SettingsPane(
                id: homePaneID, title: SettingsText.resource("settings.pane.home"), icon: "square.grid.3x2",
                // `[home] cards` is edited by the Home card list (HomePaneContent), not a generated row.
                content: .core([SettingsSection(keys: [CoreSettings.path("general", "tab_order")])])),
            SettingsPane(
                id: "notify", title: SettingsText.resource("settings.pane.notify"), icon: "bell.badge",
                content: .core([
                    SettingsSection(keys: keys("notify", ["quiet_hours", "after_focus", "min_severity", "cooldown"]))
                ])),
            SettingsPane(
                id: "sounds", title: SettingsText.resource("settings.pane.sounds"), icon: "speaker.wave.2",
                content: .core([
                    SettingsSection(
                        keys: keys(
                            "sounds",
                            [
                                "enabled", "blocked", "failed", "done", "quota_warning", "timer_end", "break_reminder",
                                "calendar_reminder",
                            ]))
                ])),
            SettingsPane(
                id: "sync", title: SettingsText.resource("settings.pane.sync"), icon: "icloud",
                content: .core([SettingsSection(keys: keys("sync", ["icloud"]))])),
            SettingsPane(
                id: "updates", title: SettingsText.resource("settings.pane.updates"),
                icon: "arrow.triangle.2.circlepath",
                content: .core([
                    // `channel` has no row: A63 keeps a single stable feed until the public release (Story 19.3).
                    SettingsSection(keys: keys("updates", ["auto_check", "check_interval", "auto_install"]))
                ])),
        ]
    }

    public static func modulePane(_ manifest: ModuleManifest) -> SettingsPane {
        SettingsPane(id: manifest.id.rawValue, title: manifest.name, icon: manifest.icon, content: .module(manifest))
    }
}

/// Lookups in VigieCore's `Localizable` catalog for the Settings window (keys are dynamic here).
enum SettingsText {
    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(
            format: string(key), locale: Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en"),
            arguments: arguments)
    }

    static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(Bundle.module.bundleURL))
    }

    /// An enumeration option label from the `Config` catalog (`config.<table>.<key>.option.<value>`), or the
    /// raw value when the catalog has none (module options).
    static func option(path: ConfigKeyPath, value: String) -> String {
        let key = "config.\(path.segments.joined(separator: ".")).option.\(value)"
        let found = Bundle.module.localizedString(forKey: key, value: nil, table: "Config")
        return found == key ? value : found
    }
}
