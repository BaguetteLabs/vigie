import Foundation
import Wire

/// Entry logic for the `vigie` command-line tool.
public enum CLI {
    /// Runs `vigie hook <agent>` for this process.
    public typealias HookRunner = @Sendable (_ agent: String, _ startedAt: ContinuousClock.Instant) -> Void

    /// Localized usage text (AD-15 sample lookup).
    public static var usage: String {
        String(localized: "cli.usage", bundle: .module)
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

    /// Runs the CLI with the given arguments (excluding the program name) and returns the exit code.
    ///
    /// `hook` never calls `output` and always returns 0 (AD-6), even without an agent id.
    public static func run(
        arguments: [String],
        startedAt: ContinuousClock.Instant = .now,
        hookRunner: HookRunner = liveHookRunner,
        output: (String) -> Void
    ) -> Int32 {
        switch arguments.first {
        case "hook":
            if arguments.count >= 2, !arguments[1].isEmpty {
                hookRunner(arguments[1], startedAt)
            }
            return 0
        case "version":
            output(versionLine)
            return 0
        default:
            output(usage)
            return 0
        }
    }
}
