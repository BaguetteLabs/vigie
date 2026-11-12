import Foundation

/// What an agent adapter can do (SPEC §8.3 integration tiers, FR80).
public enum AgentCapability: String, Hashable, Sendable, Codable, CaseIterable {
    /// The agent calls `vigie hook <agent>` (tier 1).
    case hooks
    /// The adapter follows the agent's transcript files (tier 2).
    case transcriptWatch
    /// The adapter parses the agent's logs for usage (`logReader`, AD-11).
    case logReader
    /// The adapter offers a usage provider (SPEC §7.2).
    case usage
    /// The adapter can start the agent for Ask AI (`launchCommand`).
    case launch
    /// Sessions can also be reported through `vigie agent` (SPEC §8.4).
    case genericReporting
}

/// How to start an agent for the Ask AI drop zone (SPEC §7.1). Handed to `TerminalAdapter.openTab`.
public struct LaunchCommand: Hashable, Sendable {
    /// A bare executable name (e.g. `claude`), resolved later through `ExecutableResolver`; never run as is.
    public let executable: String
    public let arguments: [String]
    /// Extra environment for the launched agent.
    public let environment: [String: String]
    /// Text typed into the agent's prompt once it runs, with no Return: an unsent prompt the user completes (Claude
    /// Code: the `@` mentions of the files). Typed only by terminals that `supportsTypedText`. nil = nothing.
    public let typedText: String?
    /// Arguments that replace ``arguments`` when the terminal cannot type ``typedText``: the agent then starts with
    /// the text as its first, sent prompt (Claude Code: `["@/a.swift "]`), so the files are still attached. nil
    /// when the CLI has no such argument: the caller copies ``typedText`` for the user to paste
    /// (`docs/decisions/ask-ai-launch.md`).
    public let promptArguments: [String]?

    public init(
        executable: String, arguments: [String], environment: [String: String] = [:], typedText: String? = nil,
        promptArguments: [String]? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.typedText = typedText
        self.promptArguments = promptArguments
    }
}

/// The only agent-specific code (SPEC §8.3, FR80, AD-23). Compiled into the app, listed once by App assembly and
/// handed to `agents.sessions` and `agents.usage` through their initializers (AD-4). Adding an agent = one new
/// package + one line in assembly (NFR23).
///
/// Conformers are `Sendable`; any mutable state is actor-isolated (AD-23). An adapter only translates native
/// events into `AgentEvent`s; it never decides a session status (AD-5).
public protocol AgentAdapter: Sendable {
    /// Lowercase single word: `claude`, `codex`, `gemini`.
    var id: AgentID { get }
    var name: LocalizedStringResource { get }
    var capabilities: Set<AgentCapability> { get }
    /// Stored at `[modules."agents.sessions".adapters.<id>]` (AD-23), read through `AdapterContext.settings`.
    /// Default: none.
    var settings: [SettingDescriptor] { get }

    /// The installed CLI version, or nil when the CLI is not found (AD-23 version gate). Resolves the CLI through
    /// `context.executables`. Default: nil.
    func detectVersion(context: any AdapterContext) async -> AgentVersion?

    /// Where the installed CLI stands against the adapter's fixture-tested range (AD-23). Pure. Default:
    /// `.notInstalled` for nil, else `.unsupported`: an adapter without a support matrix never guesses.
    func support(for version: AgentVersion?) -> AdapterSupport

    /// Edits that install the integration (hooks, notify program), for the user to confirm (Story 4.7, AD-22).
    /// An empty plan means the integration is already installed. The default Account's location (Story 7.11:
    /// see ``integrationPlan(context:inputs:account:)`` for the others). Default: none.
    func integrationPlan(context: any AdapterContext, inputs: IntegrationInputs) async throws -> [ConfigDiff]
    /// Edits that remove the integration: only Vigie's managed entries (AD-22). Default: none.
    func removalPlan(context: any AdapterContext, inputs: IntegrationInputs) async throws -> [ConfigDiff]
    /// The install edits for one Account's config location (Story 7.11): the default Account's are
    /// ``integrationPlan(context:inputs:)``; another Account's target its own location and leave every other
    /// location alone. Throws ``MissingAccountLocation`` when the Account's folder does not exist. Default: the
    /// default Account's plan, none for any other Account.
    func integrationPlan(context: any AdapterContext, inputs: IntegrationInputs, account: AgentAccount)
        async throws -> [ConfigDiff]
    /// The removal edits for one Account's config location (Story 7.11): only that location's managed entries.
    /// A missing folder has nothing to remove. Default: the default Account's plan, none for any other Account.
    func removalPlan(context: any AdapterContext, inputs: IntegrationInputs, account: AgentAccount)
        async throws -> [ConfigDiff]

    /// Pure: the native event in `hook.raw` → normalized events (SPEC §7.1). `sentAt` is the envelope's
    /// `sent_at` and becomes each event's `context.at` (AD-5). Unknown or ignored native events → `[]`.
    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent]

    /// Pure: picks the agent process from the hook's ancestors (parent first) and its whitelisted environment
    /// (AD-5). Default: nil.
    func agentProcess(in ancestors: [ProcessInfoEntry], environment: [String: String]) -> AgentProcessRef?

    /// Tier-2 integration (SPEC §8.3). Default: nil.
    var transcriptWatcher: (any TranscriptWatcher)? { get }
    /// The one parser of the agent's logs, shared by both agent modules (AD-23). Default: nil.
    var logReader: (any AgentLogReader)? { get }
    /// One provider per adapter, `id` = adapter id (AD-23). Default: nil.
    var usageProvider: (any UsageProvider)? { get }
    /// The `providers` section of the price table (`prices.json`, Story 6.5) that prices this adapter's models.
    /// Default: the adapter id. An adapter whose models are sold by another provider names that provider's section.
    var priceProviderID: String { get }

    /// The Ask AI command for `files`, started in `cwd` (SPEC §7.1, §14.16). Default: nil (Ask AI unavailable).
    func launchCommand(files: [URL], cwd: URL?) -> LaunchCommand?
    /// The absolute executable for `command` (Story 9.6). Default: `context.executables.resolve(command.executable)`;
    /// an adapter with its own executable setting (Claude Code's `executable`) reads it first. nil = not installed.
    func launchExecutable(for command: LaunchCommand, context: any AdapterContext) async -> URL?

    // MARK: Accounts (Story 7.10, A82)

    /// The agent's default config location, the default Account's (Claude Code: `~/.claude`). Default: nil (the
    /// adapter has no Accounts beyond the implicit default).
    var defaultAccountLocation: AccountLocation? { get }
    /// Pure: the config location the hook's whitelisted environment names (Claude Code: `CLAUDE_CONFIG_DIR`,
    /// else the default location). Sessions are attributed to the Account with that location (A82). Default:
    /// nil (the default Account).
    func accountLocationHint(env: [String: String]) -> AccountLocation?
    /// The log parser of one Account's location (AD-23: still the one parser of the format). Default:
    /// `logReader` for ``defaultAccountLocation`` (or when the adapter has none), else nil.
    func logReader(for location: AccountLocation) -> (any AgentLogReader)?
}

extension AgentAdapter {
    public var settings: [SettingDescriptor] { [] }
    public func detectVersion(context: any AdapterContext) async -> AgentVersion? { nil }
    public func support(for version: AgentVersion?) -> AdapterSupport {
        version.map(AdapterSupport.unsupported) ?? .notInstalled
    }
    public func integrationPlan(context: any AdapterContext, inputs: IntegrationInputs) async throws -> [ConfigDiff] {
        []
    }
    public func removalPlan(context: any AdapterContext, inputs: IntegrationInputs) async throws -> [ConfigDiff] {
        []
    }
    public func integrationPlan(context: any AdapterContext, inputs: IntegrationInputs, account: AgentAccount)
        async throws -> [ConfigDiff]
    {
        account.isDefault ? try await integrationPlan(context: context, inputs: inputs) : []
    }
    public func removalPlan(context: any AdapterContext, inputs: IntegrationInputs, account: AgentAccount)
        async throws -> [ConfigDiff]
    {
        account.isDefault ? try await removalPlan(context: context, inputs: inputs) : []
    }
    public func agentProcess(in ancestors: [ProcessInfoEntry], environment: [String: String]) -> AgentProcessRef? {
        nil
    }
    public var transcriptWatcher: (any TranscriptWatcher)? { nil }
    public var logReader: (any AgentLogReader)? { nil }
    public var usageProvider: (any UsageProvider)? { nil }
    public var priceProviderID: String { id.rawValue }
    public func launchCommand(files: [URL], cwd: URL?) -> LaunchCommand? { nil }
    public func launchExecutable(for command: LaunchCommand, context: any AdapterContext) async -> URL? {
        await context.executables.resolve(command.executable)
    }
    public var defaultAccountLocation: AccountLocation? { nil }
    public func accountLocationHint(env: [String: String]) -> AccountLocation? { nil }
    public func logReader(for location: AccountLocation) -> (any AgentLogReader)? {
        guard let defaultLocation = defaultAccountLocation else { return logReader }
        return defaultLocation == location ? logReader : nil
    }
}

extension AgentAdapter {
    /// The adapter's Accounts from its settings (``AgentAccounts/accounts(in:defaultLocation:)``): the default
    /// first, then the listed ones. Always at least the default.
    public func accounts(settings: any ReadOnlySettings) -> [AgentAccount] {
        AgentAccounts.accounts(in: settings, defaultLocation: defaultAccountLocation)
    }

    /// The log reader of `account`: the default Account reads `logReader`; another reads its own location.
    public func logReader(for account: AgentAccount) -> (any AgentLogReader)? {
        if account.isDefault { return logReader }
        return account.location.flatMap { logReader(for: $0) }
    }
}

extension AgentAdapter {
    /// The version-gated entry point for `agents.sessions` (AD-23): `normalize(_:sentAt:)` when `support` lets
    /// events through, else `[]`.
    public func normalize(_ hook: HookPayload, sentAt: Date, support: AdapterSupport) -> [AgentEvent] {
        support.emitsEvents ? normalize(hook, sentAt: sentAt) : []
    }
}

/// How one Ask AI launch runs on a given terminal (Story 9.6, `docs/decisions/ask-ai-launch.md`): pure.
public struct LaunchPlan: Hashable, Sendable {
    /// `argv[0]` absolute; `/usr/bin/env K=V …` first when the command has an environment.
    public let argv: [String]
    /// What the terminal types without Return (only when it `supportsTypedText`).
    public let typedText: String?
    /// What the caller copies for the user to paste into the agent once the tab runs (the CLI has no
    /// `promptArguments` and the terminal cannot type). nil when nothing needs pasting.
    public let pasteText: String?

    public init(argv: [String], typedText: String?, pasteText: String?) {
        self.argv = argv
        self.typedText = typedText
        self.pasteText = pasteText
    }

    /// Typed text when the terminal can type it; else the `promptArguments` form; else the bare launch with the
    /// typed text left to paste.
    public init(command: LaunchCommand, executable: URL, terminalTypesText: Bool) {
        let prefix: [String] =
            command.environment.isEmpty
            ? [] : ["/usr/bin/env"] + command.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        let typed = command.typedText.flatMap { $0.isEmpty ? nil : $0 }
        if typed != nil, !terminalTypesText, let promptArguments = command.promptArguments {
            self.init(argv: prefix + [executable.path] + promptArguments, typedText: nil, pasteText: nil)
        } else if let typed, !terminalTypesText {
            self.init(argv: prefix + [executable.path] + command.arguments, typedText: nil, pasteText: typed)
        } else {
            self.init(argv: prefix + [executable.path] + command.arguments, typedText: typed, pasteText: nil)
        }
    }
}
