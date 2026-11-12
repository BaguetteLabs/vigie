import Foundation

/// `context.scriptFolder.settings` (AD-8, AD-18, Story 12.6): what Settings › Scripts and the runner read and write
/// for script modules, through the host's ConfigStore (the only writer of config files).
///
/// - **Enabled on this Mac** (AD-8: per-Mac): `local.toml`, keyed by the file's path relative to the config folder
///   (`modules/github.md`), like the confirmation records; absent means enabled. Never read from the synced
///   `config.toml`.
/// - **Configured values** of a script's declared settings: `[modules."<script id>"] <key>` in the synced
///   `config.toml` (SPEC §9.2, §11). A key is known only while its script is registered (``register(_:settings:)``);
///   `secret` settings are never registered: they live in `context.secrets` under `<script id>.<setting key>`.
public protocol ScriptSettingsStore: Sendable {
    /// Whether the script file is enabled on this Mac (default true).
    @MainActor func isEnabled(_ relativePath: String) -> Bool
    /// Enables or disables the script file on this Mac only. Call only from a user action.
    func setEnabled(_ enabled: Bool, for relativePath: String) async throws

    /// Makes a script's declared settings known under `[modules."<id>"]` (synced), replacing the ones registered
    /// for `id` before (a file edit may change a type). Settings of kind `secret` are skipped. Idempotent.
    @MainActor func register(_ id: ModuleID, settings: [SettingDescriptor])
    /// Forgets what ``register(_:settings:)`` made known for `id` (the script was removed or errored). Values stay
    /// in the file.
    @MainActor func unregister(_ id: ModuleID)
    /// The value configured for a registered setting, as `Bool`, `Int`, `Double`, `String`, `Duration` or
    /// `[String]` by its kind; nil when the file has no value for it (the front-matter default then applies).
    @MainActor func value(_ id: ModuleID, key: String) -> (any SettingValue)?
    /// Writes a registered setting into `config.toml`; nil removes it (the default applies again). Throws when
    /// the key is not registered or the value does not fit its kind.
    func setValue(_ value: (any SettingValue)?, id: ModuleID, key: String) async throws

    /// Yields once after any change of an enabled flag or of a registered script setting, including edits made
    /// outside the app. The stream ends when the module stops.
    @MainActor func changes() -> AsyncStream<Void>
}

/// The default store: every script enabled, no configured value, writes refused with
/// ``ModuleServiceError/notAvailable``.
public struct NoScriptSettings: ScriptSettingsStore {
    public init() {}
    @MainActor public func isEnabled(_ relativePath: String) -> Bool { true }
    public func setEnabled(_ enabled: Bool, for relativePath: String) async throws {
        throw ModuleServiceError.notAvailable
    }
    @MainActor public func register(_ id: ModuleID, settings: [SettingDescriptor]) {}
    @MainActor public func unregister(_ id: ModuleID) {}
    @MainActor public func value(_ id: ModuleID, key: String) -> (any SettingValue)? { nil }
    public func setValue(_ value: (any SettingValue)?, id: ModuleID, key: String) async throws {
        throw ModuleServiceError.notAvailable
    }
    @MainActor public func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
