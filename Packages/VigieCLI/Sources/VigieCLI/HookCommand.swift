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
    public typealias Outcome = Delivery.Outcome

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
        return Delivery(socketPath: socketPath, spoolURL: spoolURL, deadline: deadline).deliver(line)
    }
}

/// Reads facts about this process and its ancestors through `sysctl`.
public enum ProcessInspector {
    /// All of stdin, or nothing when stdin is a terminal (a human typed the command).
    static func readStandardInput() -> Data {
        pipedStandardInput() ?? Data()
    }

    /// All of stdin, or `nil` when stdin is a terminal.
    public static func pipedStandardInput() -> Data? {
        guard isatty(STDIN_FILENO) == 0 else { return nil }
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
