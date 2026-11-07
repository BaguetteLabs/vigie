import Darwin
import Foundation
import Wire

/// `vigie hook <agent>`: wraps the agent's native event in an `agent.hook` envelope and
/// delivers it to the app (SPEC §8.2, AD-6).
///
/// It sends one line to the socket with a non-blocking connect and write inside a total
/// budget, and on any failure appends the same line to the spool. It completes
/// synchronously, never forks, detaches or retries, never writes to stdout or stderr,
/// and its exit status is always 0.
public struct HookCommand: Sendable {
    /// Total time budget for the socket attempt, measured from process start (AD-6).
    public static let budget: Duration = .milliseconds(150)
    /// Lines longer than this get their native payload replaced (AD-6).
    public static let maxLineBytes = 1 << 20
    /// Raw fields kept when a payload is truncated: they identify the session and event.
    public static let identifyingKeys = ["session_id", "hook_event_name", "cwd"]

    /// How the event left the process.
    public enum Outcome: Equatable, Sendable {
        case sent
        case spooled
        case dropped
    }

    public var agent: String
    public var stdin: Data
    public var environment: [String: String]
    public var tty: String?
    public var ancestors: [ProcessInfoEntry]
    public var socketPath: String
    public var spoolURL: URL
    public var now: @Sendable () -> Date
    public var deadline: ContinuousClock.Instant

    public init(
        agent: String,
        stdin: Data,
        environment: [String: String],
        tty: String?,
        ancestors: [ProcessInfoEntry],
        socketPath: String,
        spoolURL: URL,
        now: @escaping @Sendable () -> Date = { Date() },
        deadline: ContinuousClock.Instant
    ) {
        self.agent = agent
        self.stdin = stdin
        self.environment = environment
        self.tty = tty
        self.ancestors = ancestors
        self.socketPath = socketPath
        self.spoolURL = spoolURL
        self.now = now
        self.deadline = deadline
    }

    /// The command wired to this process: stdin, environment, TTY, ancestors and `AppEnvironment.current`.
    public static func live(agent: String, startedAt start: ContinuousClock.Instant) -> HookCommand {
        let env = AppEnvironment.current
        let ancestors = ProcessInspector.ancestors(of: getppid())
        return HookCommand(
            agent: agent,
            stdin: ProcessInspector.readStandardInput(),
            environment: ProcessInfo.processInfo.environment,
            tty: ProcessInspector.ttyPath(ancestors: ancestors),
            ancestors: ancestors,
            socketPath: env.socketURL.path,
            spoolURL: env.spoolURL,
            deadline: start.advanced(by: budget))
    }

    /// Parses stdin as JSON; empty input is `null`, anything unparsable is kept as a string.
    public static func parseRaw(_ data: Data) -> JSONValue {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return .null }
        if let value = try? JSONDecoder().decode(JSONValue.self, from: data) { return value }
        return .string(String(decoding: data, as: UTF8.self))
    }

    /// `{"truncated": true}` plus the identifying fields of `raw` when present.
    public static func truncatedRaw(from raw: JSONValue) -> JSONValue {
        var members: [String: JSONValue] = ["truncated": .bool(true)]
        for key in identifyingKeys {
            if let value = raw[key] { members[key] = value }
        }
        return .object(members)
    }

    /// The envelope this invocation sends.
    public func makeEnvelope() throws -> Envelope {
        let payload = HookPayload(
            agent: agent,
            raw: Self.parseRaw(stdin),
            tty: tty,
            env: HookPayload.filterEnvironment(environment),
            ancestors: Array(ancestors.prefix(HookPayload.maxAncestors)))
        return Envelope(topic: Topic.agentHook, sentAt: now(), payload: try JSONValue(encoding: payload))
    }

    /// The line to deliver, with the native payload truncated if the line exceeds `maxLineBytes`.
    public func makeLine() throws -> Data {
        var envelope = try makeEnvelope()
        let line = try envelope.encodeLine()
        guard line.count > Self.maxLineBytes else { return line }
        let payload = try envelope.payload.decode(as: HookPayload.self)
        var truncated = payload
        truncated.raw = Self.truncatedRaw(from: payload.raw)
        envelope.payload = try JSONValue(encoding: truncated)
        return try envelope.encodeLine()
    }

    /// Delivers the event; swallows every error.
    @discardableResult
    public func run() -> Outcome {
        guard let line = try? makeLine() else { return .dropped }
        if SocketSender.send(line, toSocketAt: socketPath, deadline: deadline) { return .sent }
        return Spool.append(line, to: spoolURL) ? .spooled : .dropped
    }
}

/// One-shot, non-blocking `AF_UNIX` client.
enum SocketSender {
    static func send(_ line: Data, toSocketAt path: String, deadline: ContinuousClock.Instant) -> Bool {
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

/// Reads facts about this process and its ancestors through `sysctl`.
public enum ProcessInspector {
    /// All of stdin, or nothing when stdin is a terminal (a human typed the command).
    static func readStandardInput() -> Data {
        guard isatty(STDIN_FILENO) == 0 else { return Data() }
        return (try? FileHandle.standardInput.readToEnd()) ?? Data()
    }

    /// The first of stdin, stdout, stderr that is a terminal, else the controlling terminal of
    /// this process, else that of the nearest ancestor that has one. Claude Code runs hooks
    /// with piped stdio and no controlling terminal, so the ancestor fallback is what finds
    /// the agent's terminal (Story 1.4 spike).
    public static func ttyPath(ancestors: [ProcessInfoEntry] = []) -> String? {
        for fd in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            if let name = ttyname(fd) { return String(cString: name) }
        }
        for pid in [getpid()] + ancestors.map(\.pid) {
            if let path = controllingTerminal(of: pid) { return path }
        }
        return nil
    }

    /// `/dev/<name>` of the controlling terminal of `pid`, if any.
    static func controllingTerminal(of pid: pid_t) -> String? {
        guard let info = kinfo(of: pid), info.kp_eproc.e_tdev != -1,
            let name = devname(info.kp_eproc.e_tdev, S_IFCHR)
        else { return nil }
        let text = String(cString: name)
        return text.isEmpty || text == "??" ? nil : "/dev/" + text
    }

    /// `pid` and up to `limit - 1` of its ancestors, stopping before pid 1 (launchd) or 0.
    public static func ancestors(of pid: pid_t, limit: Int = HookPayload.maxAncestors) -> [ProcessInfoEntry] {
        var chain: [ProcessInfoEntry] = []
        var current = pid
        while current > 1, chain.count < limit, let info = kinfo(of: current) {
            let ppid = info.kp_eproc.e_ppid
            let start = info.kp_proc.p_starttime
            chain.append(
                ProcessInfoEntry(
                    pid: current,
                    ppid: ppid,
                    name: name(of: current, info: info),
                    startTime: Date(
                        timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)))
            guard ppid != current else { break }
            current = ppid
        }
        return chain
    }

    static func kinfo(of pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    private static func name(of pid: pid_t, info: kinfo_proc) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        var comm = info.kp_proc.p_comm
        return withUnsafeBytes(of: &comm) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
