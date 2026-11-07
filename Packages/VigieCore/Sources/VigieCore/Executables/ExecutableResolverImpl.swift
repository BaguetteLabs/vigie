import Darwin
import Foundation
import ModuleKit
import Synchronization
import os

/// The `ExecutableResolver` behind `ModuleContext.executables` and `AdapterContext.executables` (AD-19,
/// Conventions: External executables). One instance per launch, shared by every context.
///
/// - The user's login-shell `PATH` is captured once (on first use or on `prime()`), by running `$SHELL -l -c`
///   with a deadline (2 s by default). On timeout or failure the shell is terminated and the fallback is this
///   process's `PATH` plus `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`.
/// - `resolve(name)` checks the per-runtime overrides first (`local.toml`, table `[executables]`, e.g.
///   `claude = "/opt/homebrew/bin/claude"`; served by ConfigStore from Stories 2.3 / 2.13 through `overrides`),
///   then each captured `PATH` entry, keeping the first executable file (`access(X_OK)`). Hits are cached per name
///   until the next `prime()`.
public actor ExecutableResolverImpl: ExecutableResolver {
    /// The `local.toml` table that holds per-runtime overrides: `[executables] <name> = "<absolute path>"`.
    public static let overridesTable = "executables"
    public static let defaultTimeout: Duration = .seconds(2)
    static let fallbackShell = "/bin/zsh"
    static let fallbackEntries = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    static let startMarker = "__VIGIE_PATH_START__"
    static let endMarker = "__VIGIE_PATH_END__"

    /// Where the search path came from.
    public enum Source: Equatable, Sendable {
        case loginShell
        /// The shell failed, printed nothing usable, or missed the deadline.
        case fallback
    }

    private let environment: [String: String]
    private let shellRunner: any ShellRunner
    private let timeout: Duration
    private let overrides: @Sendable () -> [String: String]
    private let isExecutable: @Sendable (String) -> Bool
    private let log: Logger

    private var capture: Task<(entries: [String], source: Source), Never>?
    private var captured: (entries: [String], source: Source)?
    private var cache: [String: URL] = [:]
    private(set) var shellRuns = 0

    /// - Parameters:
    ///   - environment: this process's environment (`SHELL`, `PATH`, `HOME`).
    ///   - timeout: the login-shell deadline (AD-19: 2 s); tests pass a few milliseconds.
    ///   - overrides: `[executables]` from `local.toml`, read on every `resolve` so edits apply at once.
    ///   - isExecutable: `access(path, X_OK) == 0` on a regular file; injectable for tests.
    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        shellRunner: any ShellRunner = SystemShellRunner(),
        timeout: Duration = ExecutableResolverImpl.defaultTimeout,
        overrides: @escaping @Sendable () -> [String: String] = { [:] },
        isExecutable: @escaping @Sendable (String) -> Bool = ExecutableResolverImpl.isExecutableFile,
        log: Logger
    ) {
        self.environment = environment
        self.shellRunner = shellRunner
        self.timeout = timeout
        self.overrides = overrides
        self.isExecutable = isExecutable
        self.log = log
    }

    /// Captures the login-shell `PATH` now (call once at launch) and clears the cache. Calling it again re-captures.
    public func prime() async {
        cache.removeAll()
        captured = nil
        let task = startCapture()
        let result = await task.value
        if capture == task { captured = result }
    }

    /// The directories searched, in order (for diagnostics). Captures the `PATH` if not done yet.
    public var searchPath: [String] {
        get async { await capturedPath().entries }
    }

    /// Where `searchPath` came from. Captures the `PATH` if not done yet.
    public var searchPathSource: Source {
        get async { await capturedPath().source }
    }

    public func resolve(_ name: String) async -> URL? {
        guard !name.isEmpty, !name.contains("\0") else { return nil }
        if name.contains("/") {
            // Only an absolute path is accepted as is; a relative path would depend on the working directory.
            guard name.hasPrefix("/"), isExecutable(name) else { return nil }
            return URL(fileURLWithPath: name)
        }
        if let override = overrides()[name] {
            let path = expandTilde(override)
            if path.hasPrefix("/"), isExecutable(path) {
                return URL(fileURLWithPath: path)
            }
            log.error(
                "executables override for \(name, privacy: .public) is not an executable absolute path; using PATH")
        }
        if let hit = cache[name], isExecutable(hit.path) { return hit }
        for directory in await capturedPath().entries {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name).path
            if isExecutable(candidate) {
                let url = URL(fileURLWithPath: candidate)
                cache[name] = url
                return url
            }
        }
        cache[name] = nil
        return nil
    }

    // MARK: - Capture

    private func capturedPath() async -> (entries: [String], source: Source) {
        if let captured { return captured }
        let task = capture ?? startCapture()
        let result = await task.value
        if capture == task { captured = result }
        return result
    }

    private func startCapture() -> Task<(entries: [String], source: Source), Never> {
        shellRuns += 1
        let shell = Self.loginShell(environment: environment, isExecutable: isExecutable)
        let runner = shellRunner
        let timeout = timeout
        let fallback = Self.fallbackPath(environment: environment)
        let log = log
        let task = Task<(entries: [String], source: Source), Never> {
            let clock = ContinuousClock()
            let start = clock.now
            let output = await Self.run(runner, shell: shell, timeout: timeout)
            let elapsed = clock.now - start
            if let output, let entries = Self.parse(output), !entries.isEmpty {
                log.info(
                    "login-shell PATH captured from \(shell, privacy: .public) in \(elapsed, privacy: .public): \(entries.joined(separator: ":"), privacy: .private)"
                )
                return (entries, .loginShell)
            }
            log.error(
                "login-shell PATH unavailable from \(shell, privacy: .public) after \(elapsed, privacy: .public); using fallback: \(fallback.joined(separator: ":"), privacy: .private)"
            )
            return (fallback, .fallback)
        }
        capture = task
        return task
    }

    /// Runs the shell with a deadline. On timeout the run is cancelled (the runner terminates the process) and the
    /// result is nil without waiting for the process to exit.
    private static func run(_ runner: any ShellRunner, shell: String, timeout: Duration) async -> String? {
        let gate = FirstResult()
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            gate.set(continuation)
            let work = Task {
                let output = try? await runner.run(
                    executablePath: shell,
                    arguments: ["-l", "-c", "printf '%s%s%s' '\(startMarker)' \"$PATH\" '\(endMarker)'"])
                gate.finish(output)
            }
            Task {
                try? await Task.sleep(for: timeout)
                if gate.finish(nil) { work.cancel() }
            }
        }
    }

    // MARK: - Pure helpers

    /// `$SHELL` when it is an absolute path to an executable, else `/bin/zsh`. Never a bare name.
    static func loginShell(environment: [String: String], isExecutable: (String) -> Bool) -> String {
        if let shell = environment["SHELL"], shell.hasPrefix("/"), !shell.contains("\0"), isExecutable(shell) {
            return shell
        }
        return fallbackShell
    }

    /// The text between the markers, split on `:`; empty and relative entries dropped, duplicates removed.
    /// nil when the markers are missing.
    static func parse(_ output: String) -> [String]? {
        guard let start = output.range(of: startMarker),
            let end = output.range(of: endMarker, range: start.upperBound..<output.endIndex)
        else { return nil }
        return clean(output[start.upperBound..<end.lowerBound].split(separator: ":").map(String.init))
    }

    static func fallbackPath(environment: [String: String]) -> [String] {
        let current = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return clean(current + fallbackEntries)
    }

    static func clean(_ entries: [String]) -> [String] {
        var seen: Set<String> = []
        return entries.filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }

    public static func isExecutableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return access(path, X_OK) == 0
    }

    private func expandTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/"), let home = environment["HOME"], home.hasPrefix("/") else {
            return path
        }
        return home + path.dropFirst()
    }
}

/// Resumes a continuation with whichever result arrives first.
private final class FirstResult: Sendable {
    private let state = Mutex<(continuation: CheckedContinuation<String?, Never>?, done: Bool)>((nil, false))

    func set(_ continuation: CheckedContinuation<String?, Never>) {
        state.withLock { $0.continuation = continuation }
    }

    /// True when this call delivered the result.
    @discardableResult
    func finish(_ value: String?) -> Bool {
        let continuation: CheckedContinuation<String?, Never>? = state.withLock { state in
            guard !state.done else { return nil }
            state.done = true
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.resume(returning: value)
        return continuation != nil
    }
}
