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

    /// Setting keys at `[modules."agents.sessions".adapter.claude]` (SPEC §11 `adapters.claude`; see `CoreSettings.adapterTableSegment`).
    public enum SettingKey {
        /// Absolute path (or `~/…`) of the `claude` executable; unset → resolved by name. Local (per Mac).
        public static let executable = "executable"
        /// `user` (`~/.claude/settings.json`) or `project` (`<project>/.claude/settings.json`).
        public static let hooksScope = "hooks_scope"
        /// Usage sources (SPEC §11): `local` (logs, Story 7.1) and `plan` (remote limits, Story 7.3). Synced.
        public static let usageProviders = "usage_providers"
        /// How plan usage signs in: ``PlanAuth``. Local (per Mac).
        public static let planAuth = "plan_auth"
        /// The pasted plan token (`secret`: SecretStore only, owner `adapter.claude`).
        public static let planToken = "plan_token"
    }

    /// `usage_providers` entries.
    public enum UsageSource {
        public static let local = "local"
        public static let plan = "plan"
    }

    /// `plan_auth` values (A57).
    public enum PlanAuth: String, CaseIterable, Sendable {
        /// A token the user pasted (`plan_token`).
        case token
        /// Claude Code's stored login, read with the user's consent.
        case claudeCode = "claude_code"
    }

    /// Where the hooks are installed.
    public enum HooksScope: String, CaseIterable, Sendable {
        case user
        case project
    }

    private let runner: any ProcessRunner
    private let fileReader: any ConfigFileReader
    /// Where `~/.claude/projects` (the `logReader` root) is resolved.
    private let homeDirectory: URL
    /// Claude Code's login, held in memory across `usageProvider` calls for the life of the adapter (one per
    /// process), so the Keychain is read once per launch (SPEC §7.2).
    private let credentialCache: ExternalCredentialCache

    public init(
        runner: any ProcessRunner = SystemProcessRunner(),
        fileReader: any ConfigFileReader = FileSystemConfigFileReader(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        credentialCache: ExternalCredentialCache = ExternalCredentialCache()
    ) {
        self.runner = runner
        self.fileReader = fileReader
        self.homeDirectory = homeDirectory
        self.credentialCache = credentialCache
    }

    public var id: AgentID { Self.agentID }

    public var name: LocalizedStringResource { L10n.resource("claude.adapter.name") }

    /// Hooks, Ask AI, local log reading (Story 7.1) and opt-in plan limits (Story 7.3).
    public var capabilities: Set<AgentCapability> { [.hooks, .launch, .logReader, .usage] }

    /// Plan windows from the unofficial endpoint (Story 7.3); called only while `usage_providers` has `plan`
    /// (per Account, Story 7.10).
    public var usageProvider: (any UsageProvider)? {
        ClaudePlanUsageProvider(homeDirectory: homeDirectory, credentialCache: credentialCache)
    }

    /// `~/.claude/projects/**/*.jsonl` (Story 7.1, AD-23).
    public var logReader: (any AgentLogReader)? { ClaudeLogReader(homeDirectory: homeDirectory) }

    // MARK: Accounts (Story 7.10, A82)

    /// The environment variable Claude Code reads its config folder from.
    public static let configDirectoryVariable = "CLAUDE_CONFIG_DIR"

    /// `~/.claude`.
    public var defaultAccountLocation: AccountLocation? {
        .configDirectory(homeDirectory.appendingPathComponent(".claude", isDirectory: true).path)
    }

    /// `CLAUDE_CONFIG_DIR` from the hook's environment (whitelisted by Wire), else `~/.claude`.
    public func accountLocationHint(env: [String: String]) -> AccountLocation? {
        if let value = env[Self.configDirectoryVariable]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return .configDirectory(value)
        }
        return defaultAccountLocation
    }

    /// `<config dir>/projects/**/*.jsonl`: the same parser over the Account's own folder.
    public func logReader(for location: AccountLocation) -> (any AgentLogReader)? {
        ClaudeLogReader(
            roots: [location.url(home: homeDirectory).appendingPathComponent("projects", isDirectory: true)])
    }

    public var settings: [SettingDescriptor] {
        baseSettings
            + AgentAccounts.descriptors(perAccount: baseSettings.filter { Self.perAccountKeys.contains($0.key) })
    }

    /// The keys each Account has its own copy of (`account.<id>.<key>`, local); the default Account keeps the
    /// 7.3 keys. `plan_token` is per Account in SecretStore (`plan_token.<id>`).
    static let perAccountKeys: Set<String> = [SettingKey.usageProviders, SettingKey.planAuth]

    private var baseSettings: [SettingDescriptor] {
        [
            SettingDescriptor(
                key: SettingKey.executable, label: L10n.resource("claude.settings.executable.label"),
                kind: .path(default: nil), scope: .local,
                help: L10n.resource("claude.settings.executable.help")),
            SettingDescriptor(
                key: SettingKey.hooksScope, label: L10n.resource("claude.settings.hooksScope.label"),
                kind: .enumeration(options: HooksScope.allCases.map(\.rawValue), default: HooksScope.user.rawValue),
                help: L10n.resource("claude.settings.hooksScope.help")),
            SettingDescriptor(
                key: SettingKey.usageProviders, label: L10n.resource("claude.settings.usageProviders.label"),
                kind: .list(of: .string, default: [UsageSource.local]),
                help: L10n.resource("claude.settings.usageProviders.help")),
            SettingDescriptor(
                key: SettingKey.planAuth, label: L10n.resource("claude.settings.planAuth.label"),
                kind: .enumeration(options: PlanAuth.allCases.map(\.rawValue), default: PlanAuth.token.rawValue),
                scope: .local, help: L10n.resource("claude.settings.planAuth.help")),
            SettingDescriptor(
                key: SettingKey.planToken, label: L10n.resource("claude.settings.planToken.label"), kind: .secret,
                scope: .local, help: L10n.resource("claude.settings.planToken.help")),
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

    /// Bare `claude` (interactive), with the files' `@` mentions as the unsent typed prompt, or as the first
    /// (sent) prompt on a terminal that cannot type (`docs/decisions/ask-ai-launch.md`). No files: bare `claude`.
    public func launchCommand(files: [URL], cwd: URL?) -> LaunchCommand? {
        let mentions = Self.mentions(files)
        guard !mentions.isEmpty else { return LaunchCommand(executable: Self.executableName, arguments: []) }
        return LaunchCommand(
            executable: Self.executableName, arguments: [], typedText: mentions, promptArguments: [mentions])
    }

    /// The `executable` setting first, else `claude` by name (as `detectVersion`).
    public func launchExecutable(for command: LaunchCommand, context: any AdapterContext) async -> URL? {
        await executableURL(context: context)
    }

    /// Claude Code's mention parser takes `@"<path>"` and an unquoted `@<non-whitespace>` token (verified in
    /// 2.1.319). A path without whitespace → `@/a/b`; with whitespace → `@"/a b"`; with whitespace and a `"` → the
    /// bare path (it cannot be mentioned). Joined by spaces, with a trailing space for the user's question.
    static func mentions(_ files: [URL]) -> String {
        let parts = files.map { url -> String in
            let path = url.path
            guard path.contains(where: \.isWhitespace) else { return "@" + path }
            return path.contains("\"") ? path : "@\"" + path + "\""
        }
        return parts.isEmpty ? "" : parts.joined(separator: " ") + " "
    }

    // MARK: Integration (AD-22)

    public func integrationPlan(context: any AdapterContext, inputs: IntegrationInputs) async throws -> [ConfigDiff] {
        try hooksPlan(try settingsURL(context: context, inputs: inputs), inputs: inputs).install()
    }

    public func removalPlan(context: any AdapterContext, inputs: IntegrationInputs) async throws -> [ConfigDiff] {
        try hooksPlan(try settingsURL(context: context, inputs: inputs), inputs: inputs).remove()
    }

    /// Story 7.11: the default Account's plan is the one above; another Account's targets
    /// `<location>/settings.json` only (Claude Code reads that file when `CLAUDE_CONFIG_DIR` names the location).
    ///
    /// The hook command stays the exact managed command `<cli> hook claude` in every location (AD-22: a managed
    /// entry is identified only by that command, so Disconnect and the other build's plans keep working). It
    /// needs no Account argument: Claude Code runs its hooks with its own environment, so a session started with
    /// `CLAUDE_CONFIG_DIR=<location>` (the only way that location's `settings.json` is read) hands the variable to
    /// the hook CLI, which forwards it (Wire's whitelist, A82); `accountLocationHint(env:)` turns it into the
    /// Account through `AgentAccounts.attribute`, which compares normalised paths (`~`, trailing and duplicate
    /// slashes, symlinks).
    public func integrationPlan(context: any AdapterContext, inputs: IntegrationInputs, account: AgentAccount)
        async throws -> [ConfigDiff]
    {
        if account.isDefault { return try await integrationPlan(context: context, inputs: inputs) }
        guard let url = try accountSettingsURL(context: context, inputs: inputs, account: account, forRemoval: false)
        else { return [] }
        return try hooksPlan(url, inputs: inputs).install()
    }

    public func removalPlan(context: any AdapterContext, inputs: IntegrationInputs, account: AgentAccount)
        async throws -> [ConfigDiff]
    {
        if account.isDefault { return try await removalPlan(context: context, inputs: inputs) }
        guard let url = try accountSettingsURL(context: context, inputs: inputs, account: account, forRemoval: true)
        else { return [] }
        return try hooksPlan(url, inputs: inputs).remove()
    }

    private func hooksPlan(_ url: URL, inputs: IntegrationInputs) -> ClaudeHooksPlan {
        ClaudeHooksPlan(settingsURL: url, command: inputs.hookCommand(for: id), reader: fileReader)
    }

    /// `~/.claude/settings.json` for `user` scope, `<project>/.claude/settings.json` for `project` scope.
    func settingsURL(context: any AdapterContext, inputs: IntegrationInputs) throws -> URL {
        switch hooksScope(context) {
        case .user:
            return inputs.homeDirectory.appendingPathComponent(".claude/settings.json")
        case .project:
            guard let project = inputs.projectDirectory else { throw ClaudeAdapterError.noProjectDirectory }
            return project.appendingPathComponent(".claude/settings.json")
        }
    }

    /// `<location>/settings.json` of a non-default Account; nil with `project` scope (the project's file serves
    /// every Account) or without a location. A location folder that does not exist throws
    /// `MissingAccountLocation` for install (Claude Code creates it on first use; Vigie does not guess) and has
    /// nothing to remove. A folder without `settings.json` gets a new file holding only Vigie's hooks.
    func accountSettingsURL(
        context: any AdapterContext, inputs: IntegrationInputs, account: AgentAccount, forRemoval: Bool
    ) throws -> URL? {
        guard hooksScope(context) == .user, let location = account.location else { return nil }
        let folder = location.url(home: inputs.homeDirectory)
        guard fileReader.directoryExists(folder) else {
            if forRemoval { return nil }
            throw MissingAccountLocation(account: account.id, path: location.path)
        }
        return folder.appendingPathComponent("settings.json")
    }

    private func hooksScope(_ context: any AdapterContext) -> HooksScope {
        let raw = context.settings.value(SettingKey.hooksScope, as: String.self) ?? HooksScope.user.rawValue
        return HooksScope(rawValue: raw) ?? .user
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
