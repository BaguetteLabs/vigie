// SPIKE: replaced by the Event Server in Story 4.1
import Darwin
import Foundation
import Synchronization
import Wire

/// Minimal `AF_UNIX` listener for the hook spike (Story 1.4): binds a 0600 socket, accepts
/// connections and hands each decoded newline-delimited `Envelope` to a callback.
public final class SocketListener: Sendable {
    public enum ListenerError: Error {
        case pathTooLong
        case posix(String, Int32)
    }

    public let path: String
    private let fd: Int32
    private let stopped = Atomic<Bool>(false)
    private let onEnvelope: @Sendable (Envelope) -> Void
    private let onError: @Sendable (any Error) -> Void

    /// Unlinks a stale socket file, binds `path` with mode 0600 and starts listening.
    public init(
        path: String,
        onError: @escaping @Sendable (any Error) -> Void = { _ in },
        onEnvelope: @escaping @Sendable (Envelope) -> Void
    ) throws {
        self.path = path
        self.onEnvelope = onEnvelope
        self.onError = onError

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw ListenerError.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes + [0]) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        unlink(path)

        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw ListenerError.posix("socket", errno) }
        _ = fcntl(socketFD, F_SETFD, FD_CLOEXEC)
        // No umask(2): it is process-wide and races with other threads creating files.
        // The parent directory is 0700 and the socket is chmod'ed right after bind.
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        let bindErrno = errno
        guard bound == 0 else {
            close(socketFD)
            throw ListenerError.posix("bind", bindErrno)
        }
        chmod(path, 0o600)
        guard listen(socketFD, 64) == 0 else {
            let listenErrno = errno
            close(socketFD)
            throw ListenerError.posix("listen", listenErrno)
        }
        fd = socketFD
    }

    deinit {
        close(fd)
    }

    /// Accepts connections on a dedicated thread until `stop()`.
    public func start() {
        let thread = Thread { [self] in acceptLoop() }
        thread.name = "SocketListener.accept"
        thread.start()
    }

    /// Stops accepting and removes the socket file.
    public func stop() {
        stopped.store(true, ordering: .sequentiallyConsistent)
        unlink(path)
    }

    private func acceptLoop() {
        while !stopped.load(ordering: .sequentiallyConsistent) {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 200) > 0 else { continue }
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }
            DispatchQueue.global().async { [self] in readLines(from: client) }
        }
    }

    private func readLines(from client: Int32) {
        defer { close(client) }
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 { break }
            pending.append(contentsOf: buffer[0..<count])
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex...newline]
                pending = Data(pending[pending.index(after: newline)...])
                deliver(Data(line))
            }
        }
        // A trailing fragment without a newline is incomplete (the writer gave up): drop it.
    }

    private func deliver(_ line: Data) {
        do {
            onEnvelope(try Envelope.decodeLine(line))
        } catch {
            onError(error)
        }
    }
}
