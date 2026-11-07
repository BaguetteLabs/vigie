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

    public init(executable: String, arguments: [String], environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
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

    /// Edits that install the integration (hooks, notify program), for the user to confirm (Story 4.7, AD-22).
    /// Default: none.
    func integrationPlan(context: any AdapterContext) async throws -> [ConfigDiff]
    /// Edits that remove the integration. Default: none.
    func removalPlan(context: any AdapterContext) async throws -> [ConfigDiff]

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

    /// The Ask AI command for `files`, started in `cwd` (SPEC §7.1, §14.16). Default: nil (Ask AI unavailable).
    func launchCommand(files: [URL], cwd: URL?) -> LaunchCommand?
}

extension AgentAdapter {
    public var settings: [SettingDescriptor] { [] }
    public func detectVersion(context: any AdapterContext) async -> AgentVersion? { nil }
    public func integrationPlan(context: any AdapterContext) async throws -> [ConfigDiff] { [] }
    public func removalPlan(context: any AdapterContext) async throws -> [ConfigDiff] { [] }
    public func agentProcess(in ancestors: [ProcessInfoEntry], environment: [String: String]) -> AgentProcessRef? {
        nil
    }
    public var transcriptWatcher: (any TranscriptWatcher)? { nil }
    public var logReader: (any AgentLogReader)? { nil }
    public var usageProvider: (any UsageProvider)? { nil }
    public func launchCommand(files: [URL], cwd: URL?) -> LaunchCommand? { nil }
}
