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
    public static func run(
        arguments: [String],
        startedAt: ContinuousClock.Instant = .now,
        hookRunner: HookRunner = liveHookRunner,
        delivery: Delivery? = nil,
        readStdin: () -> Data? = ProcessInspector.pipedStandardInput,
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
}
