import Foundation
import ModuleKit

/// A core setting: its place in the config files and its descriptor.
public struct CoreSetting: Sendable {
    public let path: ConfigKeyPath
    public let descriptor: SettingDescriptor
}

/// The core (non-module) settings of SPEC §11, with their scope (AD-8). Module settings come from manifests.
///
/// `.local` settings live at the same path in `local.toml`: `[display]`, `[virtual_notch]`, `[privacy]`, `[sync]`
/// and `general.launch_at_login`.
public enum CoreSettings {
    /// Tables whose keys are free-form (`[appearance.colors]` overrides any status, pace or warning color).
    /// `[integrations]` (local.toml) holds one table per connected agent adapter (Story 4.7, AD-22); its keys
    /// become known when `IntegrationInstaller` registers the adapter (`ConfigSchema.registerIntegration`).
    /// `[consents]` (local.toml) holds one table per external credential the user allowed (Story 7.3, AD-9); its
    /// keys become known when the secret store first touches the descriptor (`ConfigSchema.registerConsent`).
    public static let openTables: [ConfigKeyPath] = ["appearance.colors", "integrations", "consents"]

    /// `[consents."<descriptor id>"] granted_at` in `local.toml`, written only by the secret store (AD-9).
    public static let consentGrantedAtKey = "granted_at"

    /// `consents."<descriptor id>".granted_at`.
    public static func consentPath(_ descriptorID: String) -> ConfigKeyPath {
        ConfigKeyPath(["consents", descriptorID, consentGrantedAtKey])
    }

    /// The table segment under `[modules."<module id>"]` that holds one table per agent adapter (Story 7.3).
    ///
    /// AD-23 / SPEC §11 name `[modules."agents.sessions".adapters.<id>]`, but `[modules."agents.sessions"]
    /// adapters` is already the list of enabled adapters, and TOML cannot hold both (`adapters` would be an array
    /// and a table). Until the spine is amended, adapter tables live under `adapter` (singular). Change it here only.
    public static let adapterTableSegment = "adapter"

    /// `modules."<module id>".adapter."<adapter id>".<key>`, in `config.toml` or `local.toml` by scope. A dotted
    /// `key` is a sub-table path (`account.work.label`, Story 7.10).
    public static func adapterPath(module: ModuleID, adapter adapterID: String, _ key: String) -> ConfigKeyPath {
        let keySegments = key.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        return ConfigKeyPath(["modules", module.rawValue, adapterTableSegment, adapterID] + keySegments)
    }

    /// `[integrations."<adapter id>"]` keys in `local.toml`, written only by `IntegrationInstaller` (AD-22).
    public static let integrationKeys = ["installed_at", "target", "backup", "cli_path"]

    /// `integrations."<adapter id>".<key>`.
    public static func integrationPath(_ adapterID: String, _ key: String) -> ConfigKeyPath {
        ConfigKeyPath(["integrations", adapterID, key])
    }

    public static let all: [CoreSetting] = [
        // [general]
        make("general", "hide_in_fullscreen", .bool(default: true)),
        make("general", "open_on_hover", .bool(default: false)),
        make("general", "close_on_leave", .bool(default: false)),
        make("general", "hover_delay", .duration(default: .milliseconds(150))),
        make("general", "expand_hotkey", .hotkey(default: "cmd+shift+space")),
        make("general", "prevent_idle_sleep", .bool(default: false), help: true),
        make("general", "launch_at_login", .bool(default: false), .local),
        make("general", "tab_order", .list(of: .string, default: [])),
        // [appearance]
        make("appearance", "theme", .string(default: "chrome-hologram")),
        make("appearance", "mode", .enumeration(options: ["system", "light", "dark"], default: "system")),
        make("appearance", "presence", .enumeration(options: ["full", "calm"], default: "full")),
        // [sounds]
        make("sounds", "enabled", .bool(default: true)),
        make("sounds", "blocked", .string(default: "builtin:blocked")),
        make("sounds", "failed", .string(default: "builtin:failed")),
        make("sounds", "done", .string(default: "off")),
        make("sounds", "quota_warning", .string(default: "builtin:warn")),
        make("sounds", "timer_end", .string(default: "off")),
        make("sounds", "break_reminder", .string(default: "off")),
        make("sounds", "calendar_reminder", .string(default: "off")),
        // [notify]
        make("notify", "quiet_hours", .string(default: "")),
        make("notify", "after_focus", .enumeration(options: ["drop", "replay"], default: "drop")),
        make("notify", "min_severity", .enumeration(options: ["info", "warn", "critical"], default: "info")),
        make("notify", "cooldown", .duration(default: .zero)),
        // [privacy] (local)
        make("privacy", "auto", .bool(default: true), .local),
        make("privacy", "force", .bool(default: false), .local),
        // [home]
        make("home", "cards", .list(of: .string, default: [])),
        // [sync] (local)
        make("sync", "icloud", .bool(default: false), .local),
        // [updates]
        make("updates", "auto_check", .bool(default: true)),
        make("updates", "check_interval", .duration(default: .seconds(24 * 3600))),
        make("updates", "auto_install", .bool(default: false)),
        make("updates", "channel", .enumeration(options: ["stable", "beta"], default: "stable")),
        // [closed]
        make("closed", "max_side_width", .int(default: 120, min: 40, max: 600)),
        make("closed", "slots", .int(default: 3, min: 1, max: 4)),
        make("closed", "peek", .bool(default: true)),
        make("closed", "peek_duration", .duration(default: .seconds(5))),
        // [display] (local)
        make("display", "display", .string(default: "notched"), .local),
        // [virtual_notch] (local)
        make("virtual_notch", "width", .int(default: 200, min: 80, max: 800), .local),
        make("virtual_notch", "idle", .enumeration(options: ["shrink", "hide", "keep"], default: "shrink"), .local),
        make("virtual_notch", "position", .enumeration(options: ["center", "right"], default: "center"), .local),
        make(
            "virtual_notch", "placement", .enumeration(options: ["menu_bar", "below"], default: "menu_bar"), .local),
        make("virtual_notch", "style", .enumeration(options: ["black", "menu_bar"], default: "black"), .local),
    ]

    /// The path of a core setting, e.g. `CoreSettings.path("general", "hover_delay")`.
    public static func path(_ table: String, _ key: String) -> ConfigKeyPath {
        ConfigKeyPath([table, key])
    }

    /// `help: true` reads the description from `config.<table>.<key>.help`.
    private static func make(
        _ table: String, _ key: String, _ kind: SettingKind, _ scope: SettingScope = .synced, help: Bool = false
    ) -> CoreSetting {
        CoreSetting(
            path: path(table, key),
            descriptor: SettingDescriptor(
                key: key,
                label: label("config.\(table).\(key)"),
                kind: kind,
                scope: scope,
                help: help ? label("config.\(table).\(key).help") : nil
            )
        )
    }

    /// Labels live in the `Config` String Catalog of VigieCore.
    static func label(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(key), table: "Config", bundle: .atURL(Bundle.module.bundleURL))
    }
}
