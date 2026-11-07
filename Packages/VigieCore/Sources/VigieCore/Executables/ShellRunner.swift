import Darwin
import Foundation

/// Runs one program and returns its standard output. Injected into `ExecutableResolverImpl` so tests can simulate
/// slow or failing shells.
public protocol ShellRunner: Sendable {
    /// Runs the program at `executablePath` (an absolute path, never a bare name) with `arguments`, stdin and stderr closed.
    /// Returns stdout as UTF-8. Throws on launch failure or a non-zero exit. When the calling task is cancelled the
    /// process is terminated and the call throws `CancellationError`.
    func run(executablePath: String, arguments: [String]) async throws -> String
}

public enum ShellRunnerError: Error, Equatable, Sendable {
    case notAbsolute(String)
    case exited(status: Int32)
}

/// The production `ShellRunner`, backed by `Process`. Stdout goes to a temporary file rather than a pipe, so a
/// background job started by a login profile that keeps the descriptor open cannot hold the read forever.
public struct SystemShellRunner: ShellRunner {
    public init() {}

    public func run(executablePath: String, arguments: [String]) async throws -> String {
        // Checked on the string: `URL(fileURLWithPath:)` would silently make a bare name absolute.
        guard executablePath.hasPrefix("/") else { throw ShellRunnerError.notAbsolute(executablePath) }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vigie-shell-\(UUID().uuidString).out")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, any Error>) in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Self.stop(process)
        }
        try Task.checkCancellation()
        guard status == 0 else { throw ShellRunnerError.exited(status: status) }
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// SIGTERM now, SIGKILL after 500 ms if the process is still running.
    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}
