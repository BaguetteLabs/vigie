import AgentKit
import Foundation

/// The Claude Code adapter (SPEC §8.3, FR82, AD-23): hooks in `settings.json` call `<cli> hook claude` on the 8
/// SPEC events; `normalize` turns each into SPEC §7.1 events. Version-gated by `supportMatrix`.
public struct ClaudeAdapter: AgentAdapter {
    public static let agentID: AgentID = "claude"
    /// The executable name resolved through `ExecutableResolver` when the `executable` setting is unset.
    public static let executableName = "claude"
    /// How long `claude --version` may take before the version counts as unreadable.
    public static let versionTimeout: Duration = .seconds(3)

    /// Fixture-tested Claude Code versions (AD-23). Every tested range's upper bound has a folder under
    /// `Tests/Fixtures/<version>/` (checked by `FixtureCatalogTests`). Rule: a newer patch of a tested `major.minor`
    /// is `assumed` (events flow, settings warn); any other version is `unsupported` (no events).
    /// Update this table whenever fixtures for a new version are recorded.
    public static let supportMatrix = VersionSupportMatrix(
        testedRanges: [AgentVersion.Semver(2, 1, 0)...AgentVersion.Semver(2, 1, 319)],
        assumesNewerPatches: true)

    /// Setting keys at `[modules."agents.sessions".adapters.claude]` (SPEC §11).
    public enum SettingKey {
        /// Absolute path (or `~/…`) of the `claude` executable; unset → resolved by name. Local (per Mac).
        public static let executable = "executable"
        /// `user` (`~/.claude/settings.json`) or `project` (`<project>/.claude/settings.json`).
        public static let hooksScope = "hooks_scope"
    }

    /// Where the hooks are installed.
    public enum HooksScope: String, CaseIterable, Sendable {
        case user
        case project
    }

    private let runner: any ProcessRunner
    private let fileReader: any ConfigFileReader

    public init(
        runner: any ProcessRunner = SystemProcessRunner(),
        fileReader: any ConfigFileReader = FileSystemConfigFileReader()
    ) {
        self.runner = runner
        self.fileReader = fileReader
    }

    public var id: AgentID { Self.agentID }

    public var name: LocalizedStringResource { L10n.resource("claude.adapter.name") }

    /// Hooks and Ask AI. Transcript, log reading and usage arrive in Epic 7.
    public var capabilities: Set<AgentCapability> { [.hooks, .launch] }

    public var settings: [SettingDescriptor] {
        [
            SettingDescriptor(
                key: SettingKey.executable, label: L10n.resource("claude.settings.executable.label"),
                kind: .path(default: nil), scope: .local,
                help: L10n.resource("claude.settings.executable.help")),
            SettingDescriptor(
                key: SettingKey.hooksScope, label: L10n.resource("claude.settings.hooksScope.label"),
                kind: .enumeration(options: HooksScope.allCases.map(\.rawValue), default: HooksScope.user.rawValue),
                help: L10n.resource("claude.settings.hooksScope.help")),
        ]
    }

    // MARK: Version gate (AD-23)

    /// Resolves `claude` (the `executable` setting first, else by name) and runs `<path> --version` off the main
    /// actor with a 3 s timeout. nil when the CLI is not found; a CLI that fails or times out reports an empty
    /// version, which `support(for:)` classifies `unsupported`.
    public func detectVersion(context: any AdapterContext) async -> AgentVersion? {
        guard let url = await executableURL(context: context) else { return nil }
        do {
            let output = try await runner.run(
                executableURL: url, arguments: ["--version"], timeout: Self.versionTimeout)
            return AgentVersion(raw: output)
        } catch {
            context.log.error("claude --version failed: \(String(describing: error), privacy: .public)")
            return AgentVersion(raw: "")
        }
    }

    public func support(for version: AgentVersion?) -> AdapterSupport {
        Self.supportMatrix.support(for: version)
    }

    func executableURL(context: any AdapterContext) async -> URL? {
        if let configured = context.settings.value(SettingKey.executable, as: String.self)?
            .trimmingCharacters(in: .whitespaces), !configured.isEmpty
        {
            let expanded = (configured as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: expanded)
        }
        return await context.executables.resolve(Self.executableName)
    }

    // MARK: Ask AI

    /// Bare `claude`; Epic 8 (`vigie run`, Ask AI) adds the file arguments.
    public func launchCommand(files: [URL], cwd: URL?) -> LaunchCommand? {
        LaunchCommand(executable: Self.executableName, arguments: [])
    }

    // MARK: Integration (AD-22)

    public func integrationPlan(context: any AdapterContext, inputs: IntegrationInputs) async throws -> [ConfigDiff] {
        try ClaudeHooksPlan(
            settingsURL: try settingsURL(context: context, inputs: inputs), command: inputs.hookCommand(for: id),
            reader: fileReader
        ).install()
    }

    public func removalPlan(context: any AdapterContext, inputs: IntegrationInputs) async throws -> [ConfigDiff] {
        try ClaudeHooksPlan(
            settingsURL: try settingsURL(context: context, inputs: inputs), command: inputs.hookCommand(for: id),
            reader: fileReader
        ).remove()
    }

    /// `~/.claude/settings.json` for `user` scope, `<project>/.claude/settings.json` for `project` scope.
    func settingsURL(context: any AdapterContext, inputs: IntegrationInputs) throws -> URL {
        let raw = context.settings.value(SettingKey.hooksScope, as: String.self) ?? HooksScope.user.rawValue
        switch HooksScope(rawValue: raw) ?? .user {
        case .user:
            return inputs.homeDirectory.appendingPathComponent(".claude/settings.json")
        case .project:
            guard let project = inputs.projectDirectory else { throw ClaudeAdapterError.noProjectDirectory }
            return project.appendingPathComponent(".claude/settings.json")
        }
    }
}

public enum ClaudeAdapterError: Error, Equatable, Sendable {
    /// `hooks_scope = "project"` but no project folder was given.
    case noProjectDirectory
    /// The settings file is not a JSON object, or its `hooks` section has an unexpected shape. Vigie never
    /// rewrites a file it cannot parse.
    case invalidSettings(path: String)
}

enum L10n {
    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
