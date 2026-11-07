import Darwin
import Foundation
import Wire
import os

/// `vigie agent --agent <id> --session <id> (--status <status> | --end) [--cwd <path>] [--message <text>]`:
/// reports a session of an agent Vigie has no adapter for (SPEC §8, FR86, AD-5).
///
/// The CLI sends the raw flags with the caller's TTY, whitelisted environment and ancestor chain as topic
/// `agent.generic`; `agents.sessions` alone maps the status. Delivery is the hook path (AD-6): socket else
/// spool within 150 ms of process start, no output, exit 0, also when both fail. The only non-silent path is a
/// usage error: one line on stderr and exit 2. An `--agent` naming a registered adapter id (`ReservedAgentIDs`)
/// is dropped with one log line (`os_log`, never stdout or stderr) and exit 0.
public struct AgentCommand: Sendable {
    /// The parsed flags.
    public struct Options: Sendable, Equatable {
        public var agent: String
        public var session: String
        public var status: GenericStatus?
        public var end: Bool
        public var cwd: String?
        public var message: String?

        public init(
            agent: String, session: String, status: GenericStatus?, end: Bool = false, cwd: String? = nil,
            message: String? = nil
        ) {
            self.agent = agent
            self.session = session
            self.status = status
            self.end = end
            self.cwd = cwd
            self.message = message
        }
    }

    /// Why the arguments were rejected.
    public enum ArgumentError: Error, Equatable, Sendable {
        case unknownFlag(String)
        case missingValue(String)
        case duplicateFlag(String)
        case missingAgent
        case missingSession
        case invalidAgent(String)
        case invalidStatus(String)
        /// Neither `--status` nor `--end`.
        case missingStatus
        /// Both `--status` and `--end`.
        case statusAndEnd
    }

    /// Where the call comes from: TTY, environment and ancestors, captured like `vigie hook`.
    public struct Caller: Sendable, Equatable {
        public var tty: String?
        public var environment: [String: String]
        public var ancestors: [ProcessInfoEntry]
        public var currentDirectory: String

        public init(
            tty: String?, environment: [String: String], ancestors: [ProcessInfoEntry], currentDirectory: String
        ) {
            self.tty = tty
            self.environment = environment
            self.ancestors = ancestors
            self.currentDirectory = currentDirectory
        }

        /// This process: its parent's ancestor chain, the TTY found from it, the environment and the cwd.
        public static func live() -> Caller {
            let ancestors = ProcessInspector.ancestors(of: getppid())
            return Caller(
                tty: ProcessInspector.ttyPath(ancestors: ancestors),
                environment: ProcessInfo.processInfo.environment,
                ancestors: ancestors,
                currentDirectory: FileManager.default.currentDirectoryPath)
        }
    }

    /// Flags that take a value.
    static let valueFlags: Set<String> = ["--agent", "--session", "--status", "--cwd", "--message"]

    /// Parses the arguments after `agent`. Each flag appears at most once, as `--flag value` or `--flag=value`.
    public static func parse(arguments: [String]) throws(ArgumentError) -> Options {
        var values: [String: String] = [:]
        var end = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if argument == "--end" {
                if end { throw .duplicateFlag(argument) }
                end = true
                continue
            }
            var flag = argument
            var value: String?
            if let equals = argument.firstIndex(of: "="), argument.hasPrefix("--") {
                flag = String(argument[..<equals])
                value = String(argument[argument.index(after: equals)...])
            }
            guard valueFlags.contains(flag) else { throw .unknownFlag(argument) }
            if value == nil {
                guard index < arguments.count else { throw .missingValue(flag) }
                value = arguments[index]
                index += 1
            }
            guard values[flag] == nil else { throw .duplicateFlag(flag) }
            values[flag] = value
        }

        guard let agent = values["--agent"], !agent.isEmpty else { throw .missingAgent }
        guard isValidAgent(agent) else { throw .invalidAgent(agent) }
        guard let session = values["--session"], !session.isEmpty else { throw .missingSession }
        var status: GenericStatus?
        if let raw = values["--status"] {
            guard let parsed = GenericStatus(rawValue: raw) else { throw .invalidStatus(raw) }
            status = parsed
        }
        if status != nil && end { throw .statusAndEnd }
        if status == nil && !end { throw .missingStatus }
        return Options(
            agent: agent, session: session, status: status, end: end,
            cwd: values["--cwd"].flatMap { $0.isEmpty ? nil : $0 },
            message: values["--message"].flatMap { $0.isEmpty ? nil : $0 })
    }

    /// An adapter-id shaped name (Conventions: Adapter ids): starts with `a-z`, then `a-z`, `0-9`, `_` or `-`.
    /// It becomes the `<agent>` of the session identity `generic.<agent>:<session>`.
    public static func isValidAgent(_ agent: String) -> Bool {
        guard let first = agent.unicodeScalars.first, ("a"..."z").contains(first) else { return false }
        return agent.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-"
        }
    }

    public var options: Options
    public var caller: Caller
    public var now: @Sendable () -> Date

    public init(options: Options, caller: Caller, now: @escaping @Sendable () -> Date = { Date() }) {
        self.options = options
        self.caller = caller
        self.now = now
    }

    /// True when `--agent` names a registered adapter: the event is dropped.
    public var isReserved: Bool { ReservedAgentIDs.contains(options.agent) }

    /// The payload this invocation sends; a relative `--cwd` is resolved against the caller's directory.
    public func makePayload() -> GenericAgentPayload {
        let cwd = options.cwd.map { path in
            path.hasPrefix("/")
                ? path
                : URL(fileURLWithPath: caller.currentDirectory, isDirectory: true).appendingPathComponent(path)
                    .standardizedFileURL.path
        }
        return GenericAgentPayload(
            agent: options.agent,
            session: options.session,
            status: options.status,
            end: options.end,
            cwd: cwd,
            message: options.message,
            tty: caller.tty,
            env: HookPayload.filterEnvironment(caller.environment),
            ancestors: Array(caller.ancestors.prefix(HookPayload.maxAncestors)))
    }

    public func makeEnvelope() throws -> Envelope {
        Envelope(topic: Topic.agentGeneric, sentAt: now(), payload: try JSONValue(encoding: makePayload()))
    }

    /// Delivers the report through `deliver` (socket else spool); a reserved agent id is logged and dropped.
    /// Swallows every error.
    @discardableResult
    public func run(
        deliver: (Data) -> Delivery.Outcome, log: (String) -> Void = AgentCommand.logLine
    ) -> Delivery.Outcome {
        if isReserved {
            log("vigie agent: --agent \(options.agent) is a registered adapter id; event dropped (use vigie hook)")
            return .dropped
        }
        guard let line = try? makeEnvelope().encodeLine() else { return .dropped }
        return deliver(line)
    }

    /// One line to the unified log, subsystem `AppEnvironment.current.logSubsystem`, category `cli`.
    public static let logLine: @Sendable (String) -> Void = { line in
        Logger(subsystem: AppEnvironment.current.logSubsystem, category: "cli").notice("\(line, privacy: .public)")
    }
}
