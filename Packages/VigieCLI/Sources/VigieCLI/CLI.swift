import Darwin
import Foundation
import Wire

/// Entry logic for the `vigie` command-line tool.
public enum CLI {
    /// Runs `vigie hook <agent>` for this process.
    public typealias HookRunner = @Sendable (_ agent: String, _ startedAt: ContinuousClock.Instant) -> Void

    /// Exit status for a command-line usage error (bad topic, bad JSON, extra arguments).
    public static let usageErrorStatus: Int32 = 2
    /// Exit status when a message could neither be sent nor spooled.
    public static let deliveryFailedStatus: Int32 = 1

    /// Localized usage text (AD-15 sample lookup).
    public static var usage: String {
        String(localized: "cli.usage", bundle: CLIResources.bundle)
    }

    /// `<cli name> <bundle id>` for the current environment.
    public static var versionLine: String {
        let env = AppEnvironment.current
        return "\(env.cliName) \(env.bundleID)"
    }

    /// The production hook runner: live stdin, environment, ancestors and paths.
    public static let liveHookRunner: HookRunner = { agent, start in
        HookCommand.live(agent: agent, startedAt: start).run()
    }

    /// Writes one line to stderr.
    public static func writeToStandardError(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    /// Runs the CLI with the given arguments (excluding the program name) and returns the exit code.
    ///
    /// `hook` never calls `output` or `errorOutput` and always returns 0 (AD-6), even without an
    /// agent id. `event` and `reload` deliver through `delivery` (by default `AppEnvironment.current`'s
    /// socket and spool, with the hook budget from `startedAt`); they return 0 when the message was
    /// sent or spooled, 1 when both failed and 2 on a usage error.
    ///
    /// `agent` returns 2 with one stderr line on a usage error, its only output; otherwise it delivers through
    /// the same path (or logs and drops a reserved agent id) and returns 0 with no output, also when the line
    /// could neither be sent nor spooled (AD-6).
    public static func run(
        arguments: [String],
        startedAt: ContinuousClock.Instant = .now,
        hookRunner: HookRunner = liveHookRunner,
        delivery: Delivery? = nil,
        readStdin: () -> Data? = ProcessInspector.pipedStandardInput,
        agentCaller: () -> AgentCommand.Caller = AgentCommand.Caller.live,
        log: (String) -> Void = AgentCommand.logLine,
        now: @escaping @Sendable () -> Date = { Date() },
        errorOutput: (String) -> Void = writeToStandardError,
        output: (String) -> Void
    ) -> Int32 {
        let resolvedDelivery = { delivery ?? Delivery.live(startedAt: startedAt, budget: HookCommand.budget) }
        switch arguments.first {
        case "hook":
            if arguments.count >= 2, !arguments[1].isEmpty {
                hookRunner(arguments[1], startedAt)
            }
            return 0
        case "agent":
            let options: AgentCommand.Options
            do {
                options = try AgentCommand.parse(arguments: Array(arguments.dropFirst()))
            } catch {
                errorOutput(message(for: error))
                return usageErrorStatus
            }
            let command = AgentCommand(options: options, caller: agentCaller(), now: now)
            command.run(deliver: { resolvedDelivery().deliver($0) }, log: log)
            return 0
        case "event":
            let command: EventCommand
            do {
                command = try EventCommand.parse(
                    arguments: Array(arguments.dropFirst()), readStdin: readStdin, now: now)
            } catch {
                errorOutput(message(for: error))
                return usageErrorStatus
            }
            return status(for: command.run(through: resolvedDelivery()), errorOutput: errorOutput)
        case "reload":
            if arguments.count > 1 {
                errorOutput(message(for: .unexpectedArgument(arguments[1])))
                return usageErrorStatus
            }
            let outcome = EventCommand(topic: Topic.appReload, payload: .object([:]), now: now)
                .run(through: resolvedDelivery())
            switch outcome {
            case .sent: output(String(localized: "cli.reload.requested", bundle: CLIResources.bundle))
            case .spooled: output(String(localized: "cli.reload.queued", bundle: CLIResources.bundle))
            case .dropped: break
            }
            return status(for: outcome, errorOutput: errorOutput)
        case "version":
            output(versionLine)
            return 0
        default:
            output(usage)
            return 0
        }
    }

    private static func status(for outcome: Delivery.Outcome, errorOutput: (String) -> Void) -> Int32 {
        guard outcome == .dropped else { return 0 }
        errorOutput(String(localized: "cli.error.deliveryFailed", bundle: CLIResources.bundle))
        return deliveryFailedStatus
    }

    static func message(for error: EventCommand.ArgumentError) -> String {
        switch error {
        case .missingTopic:
            String(localized: "cli.error.missingTopic", bundle: CLIResources.bundle)
        case .invalidTopic(let topic):
            String(
                format: String(localized: "cli.error.invalidTopic", bundle: CLIResources.bundle), topic,
                EventCommand.maxTopicLength)
        case .invalidJSON:
            String(localized: "cli.error.invalidJSON", bundle: CLIResources.bundle)
        case .unexpectedArgument(let argument):
            String(format: String(localized: "cli.error.unexpectedArgument", bundle: CLIResources.bundle), argument)
        }
    }

    static func message(for error: AgentCommand.ArgumentError) -> String {
        func text(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: CLIResources.bundle) }
        let problem: String
        switch error {
        case .unknownFlag(let flag):
            problem = String(format: text("cli.agent.error.unknownFlag"), flag)
        case .missingValue(let flag):
            problem = String(format: text("cli.agent.error.missingValue"), flag)
        case .duplicateFlag(let flag):
            problem = String(format: text("cli.agent.error.duplicateFlag"), flag)
        case .missingAgent:
            problem = text("cli.agent.error.missingAgent")
        case .missingSession:
            problem = text("cli.agent.error.missingSession")
        case .invalidAgent(let agent):
            problem = String(format: text("cli.agent.error.invalidAgent"), agent)
        case .invalidStatus(let status):
            problem = String(format: text("cli.agent.error.invalidStatus"), status)
        case .missingStatus:
            problem = text("cli.agent.error.missingStatus")
        case .statusAndEnd:
            problem = text("cli.agent.error.statusAndEnd")
        }
        return String(format: text("cli.agent.error.line"), problem, text("cli.agent.synopsis"))
    }
}
