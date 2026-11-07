import Darwin
import Foundation

/// One-shot, non-blocking `AF_UNIX` stream client shared by the `vigie` CLI and the app's
/// second-instance path (AD-6).
///
/// `send` connects without blocking, writes the whole line and returns `true`, or returns
/// `false` as soon as anything fails or `deadline` passes. It never retries, never raises
/// `SIGPIPE` and never leaves the descriptor open. The peer reading the line is not awaited.
public enum SocketClient {
    /// Writes `line` to the socket at `path` before `deadline`.
    public static func send(_ line: Data, toSocketAt path: String, deadline: ContinuousClock.Instant) -> Bool {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard !pathBytes.isEmpty, pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0 else { return false }

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected != 0 {
            guard errno == EINPROGRESS, waitWritable(fd, deadline: deadline) else { return false }
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else { return false }
        }

        return line.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, base + offset, buffer.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EAGAIN || errno == EINTR {
                    guard waitWritable(fd, deadline: deadline) else { return false }
                } else {
                    return false
                }
            }
            return true
        }
    }

    /// Polls for writability until `deadline`.
    private static func waitWritable(_ fd: Int32, deadline: ContinuousClock.Instant) -> Bool {
        while true {
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { return false }
            let (seconds, attoseconds) = remaining.components
            let milliseconds = Int32(clamping: seconds * 1000 + max(1, attoseconds / 1_000_000_000_000_000))
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&descriptor, 1, milliseconds)
            if ready > 0 { return descriptor.revents & Int16(POLLOUT) != 0 }
            if ready == 0 || errno != EINTR { return ready > 0 }
        }
    }
}
