import Foundation

/// `context.scriptFolder` (AD-18, SPEC §9.1): what the integrations module needs from the host to discover
/// script modules. Implemented by VigieCore; other modules have no use for it.
///
/// The folder is `<config folder>/modules/`, derived from `AppEnvironment` by the host (AD-17): modules never
/// build it from a literal. The host never creates it.
public protocol ScriptFolderService: Sendable {
    /// `<config folder>/modules/`; nil when the host has no config folder (tests, a host without ConfigStore).
    var url: URL? { get }
    /// Ids a script must not declare (AD-18): the ids of the modules App assembly lists (the registry's built-in
    /// descriptors) plus the SPEC §7 built-in ids not shipped yet. The `agents.` prefix is checked separately.
    var builtInModuleIDs: Set<ModuleID> { get }
    /// `[modules."<id>"] enabled` as configured, for a script id; nil when the key is absent (the script is then
    /// enabled, SPEC §9).
    func isEnabled(_ id: ModuleID) -> Bool?
    /// Yields once after any change in the folder: a file added, removed, renamed, replaced or written in place,
    /// and when the folder itself appears or disappears (AD-12: the directory is watched, never one inode). It
    /// does not say what changed; the caller rescans. The stream ends when the module stops.
    @MainActor func changes() -> AsyncStream<Void>
}

/// The default `context.scriptFolder`: no folder, nothing reserved beyond the SPEC ids, no changes.
public struct NoScriptFolder: ScriptFolderService {
    public init() {}
    public var url: URL? { nil }
    public var builtInModuleIDs: Set<ModuleID> { ModuleID.specBuiltIns }
    public func isEnabled(_ id: ModuleID) -> Bool? { nil }
    @MainActor public func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

extension ModuleID {
    /// The built-in module ids SPEC §7 and the Conventions (Module ids) reserve, shipped or not: a script can
    /// never take one, even before its module exists.
    public static let specBuiltIns: Set<ModuleID> = [
        "agents.sessions", "agents.usage", "shelf", "integrations", "calendar", "notes", "time",
    ]
}
