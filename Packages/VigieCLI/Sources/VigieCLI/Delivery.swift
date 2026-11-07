import Darwin
import Foundation
import Wire

/// The socket-else-spool path every CLI command uses to reach the app (AD-6).
///
/// One line goes to the socket with a non-blocking connect and write that must finish
/// before `deadline`; on any failure the same line is appended to the spool, which the
/// app replays at its next start.
public struct Delivery: Sendable {
    /// How a line left the process.
    public enum Outcome: Equatable, Sendable {
        case sent
        case spooled
        case dropped
    }

    public var socketPath: String
    public var spoolURL: URL
    public var deadline: ContinuousClock.Instant

    public init(socketPath: String, spoolURL: URL, deadline: ContinuousClock.Instant) {
        self.socketPath = socketPath
        self.spoolURL = spoolURL
        self.deadline = deadline
    }

    /// `AppEnvironment.current`'s socket and spool, with `budget` measured from `start`.
    public static func live(startedAt start: ContinuousClock.Instant, budget: Duration) -> Delivery {
        let env = AppEnvironment.current
        return Delivery(
            socketPath: env.socketURL.path, spoolURL: env.spoolURL, deadline: start.advanced(by: budget))
    }

    /// Sends `line`, else spools it; `.dropped` only when both failed.
    public func deliver(_ line: Data) -> Outcome {
        if SocketClient.send(line, toSocketAt: socketPath, deadline: deadline) { return .sent }
        return Spool.append(line, to: spoolURL) ? .spooled : .dropped
    }
}

/// Appends lines to the spool file (AD-6): `O_APPEND`, `flock(LOCK_EX)`, one `write`.
enum Spool {
    static func append(_ line: Data, to url: URL) -> Bool {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return false }
        defer { flock(fd, LOCK_UN) }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        return written == line.count
    }
}
