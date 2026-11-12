import Foundation

/// How one run of a script ended (Story 12.4, UX-DR87). Everything but ``succeeded(_:)`` errors the script.
public enum ScriptRunOutcome: Equatable, Sendable {
    /// Exit 0 and stdout decoded as a ``ScriptOutput`` whose widget type matches the front matter.
    case succeeded(ScriptOutput)
    /// The run exceeded `min(interval, 30s)` (`seconds`, rounded up); its process group was killed.
    case timedOut(seconds: Int)
    /// A non-zero exit; a process killed by a signal it did not get from the runner reads as `128 + signal`
    /// (the shell's convention).
    case failed(exitCode: Int32)
    /// Exit 0 but stdout is empty, not JSON, fails the schema or declares another widget type. `message` is
    /// localized and names the key when there is one.
    case invalidOutput(String)
    /// `runtime` did not resolve through `context.executables`.
    case runtimeNotFound(String)
    /// The process could not be started (temporary file or `posix_spawn` error); `message` is for the log.
    case launchFailed(String)

    public var isSuccess: Bool {
        if case .succeeded = self { return true }
        return false
    }

    /// The exit code the runs card shows, when the process exited on its own.
    public var exitCode: Int32? {
        switch self {
        case .succeeded, .invalidOutput: 0
        case .failed(let code): code
        default: nil
        }
    }
}

/// One run, for the runs card (Story 12.7) and Settings › Scripts (12.6).
public struct ScriptRunRecord: Equatable, Sendable {
    public let startedAt: Date
    public let duration: Duration
    public let outcome: ScriptRunOutcome
    /// The end of the run's stderr (at most ``ScriptRunner/stderrLimit`` bytes, secrets masked); empty if none.
    public let stderrExcerpt: String

    public init(startedAt: Date, duration: Duration, outcome: ScriptRunOutcome, stderrExcerpt: String) {
        self.startedAt = startedAt
        self.duration = duration
        self.outcome = outcome
        self.stderrExcerpt = stderrExcerpt
    }
}

/// What the runner publishes for one eligible script (SPEC §9.2, Story 12.4).
public struct ScriptRunState: Equatable, Sendable {
    /// The result of the latest finished run.
    public enum Phase: Equatable, Sendable {
        /// No run has finished since the script became eligible (or its file changed): `WAITING · FIRST RUN`,
        /// no level glyph.
        case waitingFirstRun
        /// The latest run succeeded.
        case ok(ScriptOutput, at: Date)
        /// The latest run failed (`reason` is never ``ScriptRunOutcome/succeeded(_:)``); the last good output, if
        /// any, stays on screen with a warning badge until the next good run.
        case errored(ScriptRunOutcome, lastGoodOutput: ScriptOutput?, at: Date)
    }

    public internal(set) var phase: Phase
    /// A run is in progress (the phase still shows the previous result).
    public internal(set) var isRunning: Bool
    /// The latest runs, newest first, at most ``ScriptRunner/recordLimit``.
    public internal(set) var records: [ScriptRunRecord]
    /// When the next scheduled run starts; nil while running or stopped.
    public internal(set) var nextRunAt: Date?

    public init(
        phase: Phase = .waitingFirstRun, isRunning: Bool = false, records: [ScriptRunRecord] = [],
        nextRunAt: Date? = nil
    ) {
        self.phase = phase
        self.isRunning = isRunning
        self.records = records
        self.nextRunAt = nextRunAt
    }

    /// The output to render: the latest good one, also while errored.
    public var lastGoodOutput: ScriptOutput? {
        switch phase {
        case .waitingFirstRun: nil
        case .ok(let output, _): output
        case .errored(_, let output, _): output
        }
    }

    public var isErrored: Bool {
        if case .errored = phase { return true }
        return false
    }
}
