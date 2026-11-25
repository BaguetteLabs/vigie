import Foundation
import ModuleKit

/// Where each part of ``DiagnosticsInputs`` comes from (Story 17.4). Every source is a closure over in-process
/// state (the registry, ConfigStore, the Notifier, `ProcessInfo`, `sysctl`, `NSScreen`, the unified log of this
/// process): the collector has no other way to reach anything, so it cannot send a byte off the Mac (AD-16).
/// `DiagnosticsCollector.live(…)` builds the production sources; tests pass fakes.
public struct DiagnosticsSources: Sendable {
    public var app: @MainActor @Sendable () -> DiagnosticsInputs.App
    public var system: @MainActor @Sendable () -> DiagnosticsInputs.System
    public var displays: @MainActor @Sendable () -> [DiagnosticsInputs.Display]
    public var modules: @MainActor @Sendable () -> [DiagnosticsInputs.Module]
    /// What running modules add (``DiagnosticsContributing``).
    public var contributions: @MainActor @Sendable () async -> [ModuleDiagnostics]
    public var setupProblems:
        @MainActor @Sendable () -> (
            current: [DiagnosticsInputs.SetupProblem], resolved: [DiagnosticsInputs.ResolvedProblem]
        )
    public var config: @MainActor @Sendable () async -> DiagnosticsInputs.Config
    public var logs: any LogLinesProviding
    /// Values scrubbed exactly by ``DiagnosticsRedactor``.
    public var secretValues: SecretValues
    /// Replaced by `~` everywhere in the text.
    public var homeDirectory: URL
    public var now: @Sendable () -> Date

    public init(
        app: @escaping @MainActor @Sendable () -> DiagnosticsInputs.App,
        system: @escaping @MainActor @Sendable () -> DiagnosticsInputs.System,
        displays: @escaping @MainActor @Sendable () -> [DiagnosticsInputs.Display],
        modules: @escaping @MainActor @Sendable () -> [DiagnosticsInputs.Module],
        contributions: @escaping @MainActor @Sendable () async -> [ModuleDiagnostics] = { [] },
        setupProblems:
            @escaping @MainActor @Sendable () -> (
                current: [DiagnosticsInputs.SetupProblem], resolved: [DiagnosticsInputs.ResolvedProblem]
            ) = { ([], []) },
        config: @escaping @MainActor @Sendable () async -> DiagnosticsInputs.Config,
        logs: any LogLinesProviding,
        secretValues: SecretValues = .none,
        homeDirectory: URL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.app = app
        self.system = system
        self.displays = displays
        self.modules = modules
        self.contributions = contributions
        self.setupProblems = setupProblems
        self.config = config
        self.logs = logs
        self.secretValues = secretValues
        self.homeDirectory = homeDirectory
        self.now = now
    }
}

/// The finished, redacted Copy diagnostics text.
public struct DiagnosticsText: Sendable, Equatable {
    public let text: String
    /// The unified log could not be read (the Logs section says why).
    public let logsUnavailable: Bool

    /// UTF-8 size, for the `COPIED · 12 KB` status.
    public var byteCount: Int { text.utf8.count }
}

/// Gathers ``DiagnosticsInputs`` from its ``DiagnosticsSources``, renders ``DiagnosticsReport`` and passes the text
/// through ``DiagnosticsRedactor`` (Story 17.4). Runs only when the user clicks Copy diagnostics.
@MainActor
public final class DiagnosticsCollector {
    public let sources: DiagnosticsSources

    public init(sources: DiagnosticsSources) {
        self.sources = sources
    }

    public func collect() async -> DiagnosticsInputs {
        let now = sources.now()
        let contributions = await sources.contributions()
        let problems = sources.setupProblems()
        let logs: DiagnosticsInputs.Logs
        do {
            let since = now.addingTimeInterval(-Double(DiagnosticsReport.logWindow.components.seconds))
            let lines = try await sources.logs.recentLines(limit: DiagnosticsReport.maxLogLines, since: since)
            logs = DiagnosticsInputs.Logs(lines: Array(lines.suffix(DiagnosticsReport.maxLogLines)))
        } catch {
            logs = DiagnosticsInputs.Logs(lines: [], failure: String(describing: type(of: error)))
        }
        return DiagnosticsInputs(
            app: sources.app(), system: sources.system(), displays: sources.displays(), modules: sources.modules(),
            moduleLines: contributions.filter { $0.section == .modules }.flatMap(\.lines),
            agentLines: contributions.filter { $0.section == .agents }.flatMap(\.lines),
            setupProblems: problems.current,
            resolvedProblems: Array(problems.resolved.suffix(DiagnosticsReport.maxResolvedProblems)),
            config: await sources.config(), logs: logs, generatedAt: now)
    }

    /// The text to copy: rendered, then redacted line by line.
    public func makeText() async -> DiagnosticsText {
        let inputs = await collect()
        let redactor = DiagnosticsRedactor(
            secretValues: await sources.secretValues.values(), homeDirectory: sources.homeDirectory)
        return DiagnosticsText(
            text: redactor.redact(DiagnosticsReport.render(inputs)), logsUnavailable: inputs.logs.failure != nil)
    }
}
