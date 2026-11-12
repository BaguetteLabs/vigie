import Darwin
import Foundation

/// One process the runner starts: `executable` (absolute, resolved through `context.executables`) with
/// `arguments`, exactly `environment`, in `workingDirectory`, stdin on `/dev/null`, stdout and stderr captured.
struct ScriptLaunchRequest: Sendable {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL?
    var timeout: Duration
    /// Where the launcher keeps the captured stdout and stderr while the process runs (removed afterwards).
    var scratchDirectory: URL
}

/// How a launched process ended, with what it printed.
struct ScriptLaunchResult: Sendable, Equatable {
    enum Termination: Sendable, Equatable {
        case exited(Int32)
        /// Killed by a signal the runner did not send.
        case signaled(Int32)
        /// The timeout hit and the runner killed the process group.
        case timedOut
    }

    var termination: Termination
    /// At most ``ScriptProcessLauncher/stdoutLimit`` bytes; `stdoutTruncated` says when more was printed.
    var stdout: Data
    var stdoutTruncated: Bool = false
    /// The last ``ScriptRunner/stderrLimit`` bytes.
    var stderr: Data
    var duration: Duration
}

/// The process seam of the runner (tests inject a fake). Throws only when the process could not start.
/// Cancelling the calling task kills the process group; the caller then discards the result.
protocol ScriptProcessLaunching: Sendable {
    func launch(_ request: ScriptLaunchRequest) async throws -> ScriptLaunchResult
}

struct ScriptLaunchError: Error, Equatable, Sendable, CustomStringConvertible {
    let description: String
}

/// The production launcher (AD-18, AD-19): `posix_spawn` of the resolved absolute path, never a bare name, in a
/// process group of its own (`POSIX_SPAWN_SETPGROUP`, group id = the child's pid) so a timeout or a stop kills
/// the script and everything it started (`kill(-pgid, SIGKILL)`). Inherits no descriptor
/// (`POSIX_SPAWN_CLOEXEC_DEFAULT`), default signal handlers, an empty signal mask. stdout and stderr go to files
/// in the scratch directory, not pipes, so a background job that keeps them open cannot hold the run (same
/// reason as `SystemShellRunner`).
struct ScriptProcessLauncher: ScriptProcessLaunching {
    /// Stdout beyond this is not read (the run is reported as invalid output).
    static let stdoutLimit = 1 << 20

    func launch(_ request: ScriptLaunchRequest) async throws -> ScriptLaunchResult {
        guard request.executable.isFileURL, request.executable.path.hasPrefix("/") else {
            throw ScriptLaunchError(description: "not an absolute path: \(request.executable.relativeString)")
        }
        let token = UUID().uuidString
        let stdoutURL = request.scratchDirectory.appendingPathComponent("\(token).out", isDirectory: false)
        let stderrURL = request.scratchDirectory.appendingPathComponent("\(token).err", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }
        let clock = ContinuousClock()
        let start = clock.now
        let pid = try Self.spawn(request, stdout: stdoutURL.path, stderr: stderrURL.path)
        let exit = Task.detached { await Self.reap(pid) }

        // Races the exit against the timeout; cancellation of the caller counts as a timeout (the group is
        // killed either way, the caller ignores the result).
        let killed = await withTaskCancellationHandler {
            await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    _ = await exit.value
                    return false
                }
                group.addTask {
                    try? await Task.sleep(for: request.timeout)
                    return true
                }
                let timedOut = await group.next() ?? false
                if timedOut { Self.killGroup(pid) }
                group.cancelAll()
                return timedOut
            }
        } onCancel: {
            Self.killGroup(pid)
        }
        let status = await exit.value
        let duration = clock.now - start

        let termination: ScriptLaunchResult.Termination
        if killed {
            termination = .timedOut
        } else if Self.exitedNormally(status) {
            termination = .exited(Self.exitStatus(status))
        } else {
            termination = .signaled(Self.termSignal(status))
        }
        let (stdout, truncated) = Self.readHead(stdoutURL, limit: Self.stdoutLimit)
        return ScriptLaunchResult(
            termination: termination, stdout: stdout, stdoutTruncated: truncated,
            stderr: Self.readTail(stderrURL, limit: ScriptRunner.stderrLimit), duration: duration)
    }

    /// Starts the process; returns its pid (also its process group id).
    static func spawn(_ request: ScriptLaunchRequest, stdout: String, stderr: String) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, stdout, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, stderr, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        if let directory = request.workingDirectory {
            posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        }

        let argv = [request.executable.path] + request.arguments
        let environment = request.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let result = withCStrings(argv) { argvPointers in
            withCStrings(environment) { environmentPointers in
                posix_spawn(&pid, request.executable.path, &actions, &attributes, argvPointers, environmentPointers)
            }
        }
        guard result == 0 else {
            throw ScriptLaunchError(description: "posix_spawn failed: \(String(cString: strerror(result)))")
        }
        return pid
    }

    /// SIGKILL to the whole group; a group already gone is fine.
    static func killGroup(_ pid: pid_t) {
        guard pid > 0 else { return }
        _ = kill(-pid, SIGKILL)
    }

    /// Waits for the child on a dispatch thread (a blocking `waitpid` must not hold a cooperative thread).
    static func reap(_ pid: pid_t) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var status: Int32 = 0
                while waitpid(pid, &status, 0) == -1 {
                    guard errno == EINTR else {
                        status = 0
                        break
                    }
                }
                continuation.resume(returning: status)
            }
        }
    }

    // The <sys/wait.h> macros are not imported into Swift.
    static func exitedNormally(_ status: Int32) -> Bool { status & 0x7f == 0 }
    static func exitStatus(_ status: Int32) -> Int32 { (status >> 8) & 0xff }
    static func termSignal(_ status: Int32) -> Int32 { status & 0x7f }

    static func readHead(_ url: URL, limit: Int) -> (Data, truncated: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (Data(), false) }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: limit + 1)) ?? Data()
        return data.count > limit ? (data.prefix(limit), true) : (data, false)
    }

    static func readTail(_ url: URL, limit: Int) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(limit) ? size - UInt64(limit) : 0)
        return (try? handle.readToEnd()) ?? Data()
    }
}

/// A NULL-terminated `char *[]` for `posix_spawn`, valid inside `body`.
private func withCStrings<R>(_ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> R) -> R {
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    pointers.append(nil)
    defer { for pointer in pointers { free(pointer) } }
    return body(pointers)
}
