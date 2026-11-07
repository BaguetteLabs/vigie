import Darwin
import Foundation

/// Runs one program at an absolute path and returns its standard output (AD-19). Shared by adapters, e.g. for
/// `<cli> --version`. Injected so tests never launch a process.
public protocol ProcessRunner: Sendable {
    /// Runs `executableURL` (absolute, already resolved through `ExecutableResolver`) with `arguments`, stdin and
    /// stderr closed. Returns stdout as UTF-8. Throws `ProcessRunnerError` on a relative path, a non-zero exit or a
    /// timeout (the process is then terminated), or the launch error. Cancelling the task terminates the process.
    func run(executableURL: URL, arguments: [String], timeout: Duration) async throws -> String
}

public enum ProcessRunnerError: Error, Equatable, Sendable {
    case notAbsolute(String)
    case exited(status: Int32)
    case timedOut
}

/// The production `ProcessRunner`, backed by `Process`. Stdout goes to a temporary file rather than a pipe, so a
/// child that leaves the descriptor open in a background job cannot hold the read forever (same pattern as
/// VigieCore's `SystemShellRunner`).
public struct SystemProcessRunner: ProcessRunner {
    public init() {}

    public func run(executableURL: URL, arguments: [String], timeout: Duration) async throws -> String {
        guard executableURL.isFileURL, executableURL.path.hasPrefix("/") else {
            throw ProcessRunnerError.notAbsolute(executableURL.relativeString)
        }
        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask { try await Self.launch(executableURL: executableURL, arguments: arguments) }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let output = first else {
                throw ProcessRunnerError.timedOut
            }
            return output
        }
    }

    private static func launch(executableURL: URL, arguments: [String]) async throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vigie-process-\(UUID().uuidString).out")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        let process = Process()
        process.executableURL = executableURL
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
            stop(process)
        }
        try Task.checkCancellation()
        guard status == 0 else { throw ProcessRunnerError.exited(status: status) }
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
