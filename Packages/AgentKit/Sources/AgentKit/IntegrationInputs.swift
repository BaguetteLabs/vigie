import Foundation

/// What App assembly knows and an adapter needs to plan its integration edits (AD-22): the CLI link path and the
/// folders the agent's config lives under.
public struct IntegrationInputs: Hashable, Sendable {
    /// Absolute path of `~/.local/bin/<AppEnvironment.cliName>` (`CLIInstaller.linkURL.path`). Hooks always call
    /// this path, never a bare name.
    public let cliPath: String
    /// The user's home folder (user-scope agent config, e.g. `~/.claude/settings.json`).
    public let homeDirectory: URL
    /// The project folder for project-scope agent config; nil when none was chosen.
    public let projectDirectory: URL?

    public init(cliPath: String, homeDirectory: URL, projectDirectory: URL? = nil) {
        self.cliPath = cliPath
        self.homeDirectory = homeDirectory
        self.projectDirectory = projectDirectory
    }

    /// The exact managed hook command for `agent` (AD-22): `<cli path> hook <adapter id>`. A path with characters
    /// a shell would split or expand is single-quoted. Plans add or remove only entries with this exact command.
    public func hookCommand(for agent: AgentID) -> String {
        "\(Self.shellQuoted(cliPath)) hook \(agent.rawValue)"
    }

    static func shellQuoted(_ path: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+@:,")
        guard !path.isEmpty, path.unicodeScalars.allSatisfy(safe.contains) else {
            return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return path
    }
}

/// Reads an agent config file for an integration plan. Injected so plans are testable without touching `~`.
public protocol ConfigFileReader: Sendable {
    /// The file's bytes, or nil when it does not exist. Throws on any other read error.
    func read(_ url: URL) throws -> Data?
    /// True when `url` is an existing folder (an Account's config location, Story 7.11). Default: the file
    /// system.
    func directoryExists(_ url: URL) -> Bool
}

extension ConfigFileReader {
    public func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// An Account's config location (Story 7.11) that does not exist: the integration cannot be installed there
/// until the agent has created it (or the user fixes the path). `path` is the location as the user wrote it;
/// it is user text, shown only in sensitive fields (Privacy mode, AD-24).
public struct MissingAccountLocation: Error, Hashable, Sendable {
    public let account: AccountID
    public let path: String

    public init(account: AccountID, path: String) {
        self.account = account
        self.path = path
    }
}

/// `ConfigFileReader` over the file system.
public struct FileSystemConfigFileReader: ConfigFileReader {
    public init() {}

    public func read(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
}
