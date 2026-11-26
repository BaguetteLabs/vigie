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

/// The pane skeleton (UX-DR74 as amended 2026-11-07, Story 17.2, EXPERIENCE "Settings") mapped onto the SPEC §11 tables.
///
/// The sidebar order is fixed: General, Appearance, Displays, Home, Agents, Usage, Shelf, Calendar, Time, Notes,
/// Scripts, Sounds, Sync, Updates. The module panes sit between Home and Sounds, in `moduleOrder`; a module
/// that is not listed there comes after the listed ones, in registry order.
///
/// | Pane id      | Title        | Config tables / keys                                                    |
/// |--------------|--------------|-------------------------------------------------------------------------|
/// | `general`    | General      | `[general]` (minus `tab_order`), Launch at login, `[privacy]` (A89), `[notify]` alert rules, Focus, config folder, CLI, diagnostics, the activity log (A80) |
/// | `appearance` | Appearance   | `[appearance]` (+ Reduce motion note next to Presence), custom status colors with their contrast (UX-DR13), `[closed]` |
/// | `display`    | Displays     | `[display]`, `[virtual_notch]` (local)                                  |
/// | `home`       | Home         | `[home] cards`, `[general] tab_order`                                   |
/// | `<module id>`| module name  | `[modules."<id>"]` (`enabled` + the manifest's descriptors)             |
/// | `sounds`     | Sounds       | `[sounds]`                                                              |
/// | `sync`       | Sync         | `[sync] icloud` (local), drawn by `SyncSection` (Story 16.2)            |
/// | `updates`    | Updates      | `[updates]`                                                             |
///
/// Aliases (older entry points keep working): `privacy`, `activity`, `notify`, `alerts` → `general`;
/// `closed`, `notch` → `appearance`; `virtual_notch`, `displays` → `display`.
public enum SettingsPaneCatalog {
    /// Settings › Home (Story 11.1): the Home card list, then `[general] tab_order`.
    public static let homePaneID = "home"

    /// The core panes in sidebar order. Module panes are inserted after `home` (see `panes(manifests:)`).
    public static let corePaneIDs = [
        "general", "appearance", "display", "home", "sounds", "sync", "updates",
    ]

    /// The core panes that come before the module panes.
    static let leadingCorePaneIDs = ["general", "appearance", "display", "home"]

    /// Module panes in sidebar order (Agents, Usage, Shelf, Calendar, Time, Notes, Scripts).
    public static let moduleOrder = [
        "agents.sessions", "agents.usage", "shelf", "calendar", "time", "notes", "integrations",
    ]

    public static let aliases: [String: String] = [
        "privacy": "general",
        "activity": "general",
        "notify": "general",
        "alerts": "general",
        "virtual_notch": "display",
        "displays": "display",
        "closed": "appearance",
        "notch": "appearance",
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
                    SettingsSection(
                        title: SettingsText.resource("settings.section.alerts"),
                        keys: keys("notify", ["quiet_hours", "after_focus", "min_severity", "cooldown"])),
                ])),
            SettingsPane(
                id: "appearance", title: SettingsText.resource("settings.pane.appearance"), icon: "paintpalette",
                content: .core([
                    SettingsSection(keys: keys("appearance", ["theme", "mode", "presence"])),
                    // The custom status colors are drawn by `StatusColorsSection` (Story 17.2), not generated rows.
                    SettingsSection(
                        title: SettingsText.resource("settings.section.closedNotch"),
                        keys: keys(
                            "closed",
                            ["max_side_width", "slots", "peek", "peek_duration", "notch_overlap", "notch_side_inset"])),
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
                // `[sync] icloud` is the Sync section's toggle (SyncSection), never a generated row: turning it on
                // moves folders (Story 16.2).
                content: .core([])),
            SettingsPane(
                id: "updates", title: SettingsText.resource("settings.pane.updates"),
                icon: "arrow.triangle.2.circlepath",
                content: .core([
                    // `channel` has no row: A63 keeps a single stable feed until the public release (Story 19.3).
                    SettingsSection(keys: keys("updates", ["auto_check", "check_interval", "auto_install", "prices"]))
                ])),
        ]
    }

    /// The whole sidebar: General, Appearance, Displays, Home, the module panes in `moduleOrder`, then Sounds, Sync
    /// and Updates (Story 17.2).
    public static func panes(manifests: [ModuleManifest]) -> [SettingsPane] {
        let all = corePanes()
        func core(_ ids: [String]) -> [SettingsPane] {
            ids.compactMap { id in all.first { $0.id == id } }
        }
        let rank = Dictionary(uniqueKeysWithValues: moduleOrder.enumerated().map { ($1, $0) })
        let ordered = manifests.enumerated().sorted { lhs, rhs in
            let l = rank[lhs.element.id.rawValue] ?? moduleOrder.count
            let r = rank[rhs.element.id.rawValue] ?? moduleOrder.count
            return l == r ? lhs.offset < rhs.offset : l < r
        }.map(\.element)
        let trailing = corePaneIDs.filter { !leadingCorePaneIDs.contains($0) }
        return core(leadingCorePaneIDs) + ordered.map(modulePane) + core(trailing)
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
