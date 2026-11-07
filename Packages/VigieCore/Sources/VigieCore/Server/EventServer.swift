import Darwin
import Foundation
import ModuleKit
import Synchronization
import Wire
import os

public enum EventServerError: Error, Equatable, Sendable {
    /// The socket path does not fit in `sockaddr_un.sun_path`.
    case pathTooLong
    /// `start` was called twice, or after `stop`.
    case alreadyStarted
    /// A system call failed; `errno` value attached.
    case posix(String, Int32)
}

/// The app side of the hook path (FR78, AD-6, AD-7, AD-21): a user-only `AF_UNIX` stream socket that
/// receives one `Envelope` JSON line per message and publishes it as an `EventMessage` on the bus.
///
/// - Lines arriving before `releaseQueue()` are decoded and queued (bounded, oldest dropped first), so
///   nothing is dispatched before the Registry has started modules (AD-6 launch order).
/// - The server never interprets payloads; versions `v` and `v-1` are accepted, anything else is dropped
///   with one log entry (AD-7).
/// - `start` takes the `InstanceLock` to prove the caller holds it: only then is a stale socket unlinked.
///   `stop` unlinks the path only if it is still the inode this server bound (AD-21).
///
/// Accepting runs on a dedicated thread; each client is read by a `DispatchSource` on its own serial
/// queue. Nothing blocks a Swift concurrency thread. All public API is callable from any thread.
public final class EventServer: Sendable {
    public let socketURL: URL
    private let core: Core

    public init(
        socketURL: URL,
        bus: InProcessEventBus,
        logger: Logger,
        maxLineBytes: Int = 1 << 20,
        maxQueuedLines: Int = 10_000,
        maxClients: Int = 64
    ) {
        self.socketURL = socketURL
        core = Core(
            path: socketURL.path, bus: bus, logger: logger, maxLineBytes: maxLineBytes,
            maxQueuedLines: maxQueuedLines, maxClients: maxClients)
    }

    deinit {
        core.stop()
    }

    /// Creates the parent directory (0700) if missing, unlinks a stale socket, binds with mode 0600,
    /// listens and starts accepting. `lockHeld` is the instance lock the caller holds (AD-21).
    public func start(lockHeld: InstanceLock) throws {
        try core.start(lock: lockHeld)
    }

    /// Dispatches queued messages in arrival order; later messages are published as they arrive.
    /// Call after `ModuleRegistry.start()` (and, from Story 4.2, after the spool replay).
    public func releaseQueue() {
        core.releaseQueue()
    }

    /// Stops accepting, closes clients and the listening socket, and unlinks the socket path if it is
    /// still the inode this server bound. Idempotent; queued messages are discarded.
    public func stop() {
        core.stop()
    }

    /// Messages decoded but held until `releaseQueue()`.
    public var queuedCount: Int { core.queuedCount }

    /// Connected clients (for tests and diagnostics).
    public var clientCount: Int { core.clientCount }

    /// Whether the socket is bound and accepting.
    public var isRunning: Bool { core.isRunning }
}

// MARK: - Core

extension EventServer {
    /// Owns all state; referenced by the accept thread and client sources so that the public wrapper's
    /// `deinit` can stop it.
    fileprivate final class Core: Sendable {
        struct FileIdentity: Equatable {
            let device: dev_t
            let inode: ino_t
        }

        struct Running {
            let listenFD: Int32
            let wakeRead: Int32
            let wakeWrite: Int32
            let identity: FileIdentity
            let exited: DispatchSemaphore
            let lock: InstanceLock
        }

        struct State {
            var phase: Phase = .idle
            var released = false
            var queue: [EventMessage] = []
            var queueHead = 0
            var overflowLogged = false
            var clients: [Int: Client] = [:]
            var nextClientID = 0
        }

        enum Phase {
            case idle
            case running(Running)
            case stopped
        }

        let path: String
        let bus: InProcessEventBus
        let logger: Logger
        let maxLineBytes: Int
        let maxQueuedLines: Int
        let maxClients: Int
        private let state = Mutex(State())

        init(
            path: String, bus: InProcessEventBus, logger: Logger, maxLineBytes: Int, maxQueuedLines: Int,
            maxClients: Int
        ) {
            self.path = path
            self.bus = bus
            self.logger = logger
            self.maxLineBytes = max(1, maxLineBytes)
            self.maxQueuedLines = max(1, maxQueuedLines)
            self.maxClients = max(1, maxClients)
        }

        var queuedCount: Int { state.withLock { $0.queue.count - $0.queueHead } }
        var clientCount: Int { state.withLock { $0.clients.count } }
        var isRunning: Bool {
            state.withLock {
                if case .running = $0.phase { return true }
                return false
            }
        }

        // MARK: Lifecycle

        func start(lock: InstanceLock) throws {
            try state.withLock { state in
                guard case .idle = state.phase else { throw EventServerError.alreadyStarted }
                let running = try bind(lock: lock)
                state.phase = .running(running)
                let thread = Thread { [self] in
                    acceptLoop(listenFD: running.listenFD, wakeFD: running.wakeRead)
                    running.exited.signal()
                }
                thread.name = "EventServer.accept"
                thread.start()
            }
            logger.info("event server listening on \(self.path, privacy: .public)")
        }

        func stop() {
            let taken: (Running?, [Client])? = state.withLock { state in
                let running: Running?
                switch state.phase {
                case .stopped: return nil
                case .idle: running = nil
                case .running(let value): running = value
                }
                state.phase = .stopped
                let clients = Array(state.clients.values)
                state.clients.removeAll()
                state.queue.removeAll()
                state.queueHead = 0
                return (running, clients)
            }
            guard let (running, clients) = taken else { return }
            for client in clients { client.cancel() }
            guard let running else { return }
            var byte: UInt8 = 1
            _ = write(running.wakeWrite, &byte, 1)
            running.exited.wait()
            close(running.listenFD)
            close(running.wakeRead)
            close(running.wakeWrite)
            if Self.identity(of: path, requireSocket: true) == running.identity {
                unlink(path)
            } else {
                logger.notice("socket path no longer ours; left in place")
            }
            withExtendedLifetime(running.lock) {}
            logger.info("event server stopped")
        }

        // MARK: Gate (AD-6)

        func releaseQueue() {
            state.withLock { state in
                guard !state.released else { return }
                state.released = true
                for message in state.queue[state.queueHead...] { bus.publish(message) }
                state.queue.removeAll()
                state.queueHead = 0
            }
        }

        /// Publishes or queues under the lock, so queued messages always precede live ones.
        private func deliver(_ message: EventMessage) {
            state.withLock { state in
                if case .stopped = state.phase { return }
                if state.released {
                    bus.publish(message)
                    return
                }
                if state.queue.count - state.queueHead >= maxQueuedLines {
                    state.queueHead += 1
                    if !state.overflowLogged {
                        state.overflowLogged = true
                        logger.warning("event queue full (\(self.maxQueuedLines)); dropping oldest messages")
                    }
                    if state.queueHead > maxQueuedLines {
                        state.queue.removeFirst(state.queueHead)
                        state.queueHead = 0
                    }
                }
                state.queue.append(message)
            }
        }

        // MARK: Lines (AD-7)

        func handle(line: Data) {
            guard !line.isEmpty, line != Data([0x0D]) else {
                logger.warning("dropped empty line")
                return
            }
            guard line.count <= maxLineBytes else {
                logger.warning("dropped line over \(self.maxLineBytes) bytes")
                return
            }
            let envelope: Envelope
            do {
                envelope = try Envelope.decodeLine(line)
            } catch WireError.unsupportedVersion(let version) {
                logger.warning("dropped message with unsupported version \(version)")
                return
            } catch WireError.invalidDate {
                logger.warning("dropped message with invalid sent_at")
                return
            } catch {
                logger.warning("dropped malformed line (\(line.count) bytes)")
                return
            }
            let payload: Data
            do {
                payload = try JSONEncoder().encode(envelope.payload)
            } catch {
                logger.warning("dropped \(envelope.topic, privacy: .public): payload not encodable")
                return
            }
            deliver(
                EventMessage(
                    topic: envelope.topic, payload: payload, sentAt: envelope.sentAt, receivedAt: Date(),
                    replayed: false))
        }

        // MARK: Socket

        private func bind(lock: InstanceLock) throws -> Running {
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(path.utf8)
            guard !bytes.isEmpty, bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
                throw EventServerError.pathTooLong
            }
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes + [0]) }
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

            let directory = (path as NSString).deletingLastPathComponent
            if !FileManager.default.fileExists(atPath: directory) {
                do {
                    try FileManager.default.createDirectory(
                        atPath: directory, withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700])
                } catch {
                    throw EventServerError.posix("mkdir", Int32((error as NSError).code))
                }
            }

            // AD-21: the caller holds the instance lock, so whatever sits at our path is stale.
            var existing = stat()
            if lstat(path, &existing) == 0, existing.st_mode & S_IFMT != S_IFDIR {
                if unlink(path) != 0 { throw EventServerError.posix("unlink", errno) }
                logger.notice("unlinked stale socket")
            }

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw EventServerError.posix("socket", errno) }
            var cleanup: [Int32] = [fd]
            func fail(_ call: String, _ code: Int32) -> EventServerError {
                for descriptor in cleanup { close(descriptor) }
                return EventServerError.posix(call, code)
            }
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            // No umask(2): it is process-wide. The parent is 0700 and the socket is chmod'ed right after bind.
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0 else { throw fail("bind", errno) }
            guard chmod(path, 0o600) == 0 else {
                let code = errno
                unlink(path)
                throw fail("chmod", code)
            }
            guard let identity = Self.identity(of: path, requireSocket: true) else {
                let code = errno
                throw fail("stat", code)
            }
            let owned = { [path] (call: String, code: Int32) -> EventServerError in
                unlink(path)
                return fail(call, code)
            }
            guard listen(fd, 64) == 0 else { throw owned("listen", errno) }
            var pipeFDs: [Int32] = [-1, -1]
            guard pipe(&pipeFDs) == 0 else { throw owned("pipe", errno) }
            cleanup += pipeFDs
            for descriptor in pipeFDs { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }
            return Running(
                listenFD: fd, wakeRead: pipeFDs[0], wakeWrite: pipeFDs[1], identity: identity,
                exited: DispatchSemaphore(value: 0), lock: lock)
        }

        private static func identity(of path: String, requireSocket: Bool) -> FileIdentity? {
            var info = stat()
            guard lstat(path, &info) == 0 else { return nil }
            if requireSocket, info.st_mode & S_IFMT != S_IFSOCK { return nil }
            return FileIdentity(device: info.st_dev, inode: info.st_ino)
        }

        /// Runs on the dedicated accept thread until the wake pipe becomes readable.
        private func acceptLoop(listenFD: Int32, wakeFD: Int32) {
            while true {
                var descriptors = [
                    pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0),
                    pollfd(fd: wakeFD, events: Int16(POLLIN), revents: 0),
                ]
                let ready = poll(&descriptors, 2, -1)
                if ready < 0 {
                    if errno == EINTR { continue }
                    logger.error("event server poll failed: \(errno)")
                    return
                }
                if descriptors[1].revents != 0 { return }
                guard descriptors[0].revents & Int16(POLLIN) != 0 else { continue }
                let client = accept(listenFD, nil, nil)
                if client < 0 {
                    let code = errno
                    if code == EMFILE || code == ENFILE {
                        logger.error("accept: out of descriptors")
                        usleep(50_000)
                    }
                    continue
                }
                adopt(client)
            }
        }

        private func adopt(_ fd: Int32) {
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            var on: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let client: Client? = state.withLock { state in
                guard case .running = state.phase else { return nil }
                guard state.clients.count < maxClients else {
                    logger.warning("too many event clients (\(self.maxClients)); refusing connection")
                    return nil
                }
                let id = state.nextClientID
                state.nextClientID += 1
                let client = Client(id: id, fd: fd, core: self)
                state.clients[id] = client
                return client
            }
            guard let client else {
                close(fd)
                return
            }
            client.resume()
        }

        fileprivate func remove(clientID: Int) {
            _ = state.withLock { $0.clients.removeValue(forKey: clientID) }
        }
    }

    /// One connection, read by a `DispatchSource` on its own serial queue; the splitter is only touched there.
    fileprivate final class Client: @unchecked Sendable {
        let id: Int
        private let fd: Int32
        private let queue: DispatchQueue
        private let source: any DispatchSourceRead
        private var splitter: LineSplitter
        private let core: Core

        init(id: Int, fd: Int32, core: Core) {
            self.id = id
            self.fd = fd
            self.core = core
            queue = DispatchQueue(label: "EventServer.client.\(id)")
            source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            splitter = LineSplitter(maxLineBytes: core.maxLineBytes)
        }

        func resume() {
            // Cycles (source → handler → client) end when the source is cancelled.
            source.setEventHandler { [self] in readAvailable() }
            source.setCancelHandler { [fd, id, core] in
                close(fd)
                core.remove(clientID: id)
            }
            source.resume()
        }

        func cancel() {
            source.cancel()
        }

        private func readAvailable() {
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while !source.isCancelled {
                let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                if count > 0 {
                    let (lines, overflow) = splitter.append(buffer[0..<count])
                    for line in lines { core.handle(line: line) }
                    if overflow {
                        core.logger.warning("dropped line over \(self.core.maxLineBytes) bytes; closing connection")
                        source.cancel()
                    }
                    continue
                }
                if count == 0 {
                    if !splitter.pending.isEmpty {
                        core.logger.notice(
                            "dropped \(self.splitter.pending.count)-byte fragment without newline at EOF")
                    }
                    source.cancel()
                    return
                }
                let code = errno
                if code == EINTR { continue }
                if code != EAGAIN && code != EWOULDBLOCK { source.cancel() }
                return
            }
        }
    }
}
