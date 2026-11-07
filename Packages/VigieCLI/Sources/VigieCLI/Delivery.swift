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
///
/// The app drains the spool by renaming it under the same lock (Story 4.2). A writer that opened
/// the file before such a rename would otherwise append to the renamed inode after the app has
/// read it, so once the lock is held the writer checks that the path still names its inode and
/// reopens if not. Lines written under the lock to the current inode are therefore read exactly once.
enum Spool {
    /// Reopen attempts when the spool is renamed between `open` and `flock`.
    static let maxAttempts = 8

    static func append(_ line: Data, to url: URL) -> Bool {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for _ in 0..<maxAttempts {
            switch appendOnce(line, to: url.path) {
            case .written: return true
            case .failed: return false
            case .renamed: continue
            }
        }
        return false
    }

    private enum Attempt {
        case written
        case failed
        case renamed
    }

    private static func appendOnce(_ line: Data, to path: String) -> Attempt {
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return .failed }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return .failed }
        defer { flock(fd, LOCK_UN) }
        var opened = stat()
        var current = stat()
        guard fstat(fd, &opened) == 0 else { return .failed }
        guard stat(path, &current) == 0, current.st_dev == opened.st_dev, current.st_ino == opened.st_ino else {
            return .renamed
        }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        return written == line.count ? .written : .failed
    }
}
