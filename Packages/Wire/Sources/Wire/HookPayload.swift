import Foundation

/// One process in the hook's ancestor chain (AD-5): the CLI reports it, adapters pick the agent PID.
public struct ProcessInfoEntry: Codable, Sendable, Equatable {
    public var pid: Int32
    public var ppid: Int32
    public var name: String
    public var startTime: Date?

    enum CodingKeys: String, CodingKey {
        case pid
        case ppid
        case name
        case startTime = "start_time"
    }

    public init(pid: Int32, ppid: Int32, name: String, startTime: Date?) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.startTime = startTime
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int32.self, forKey: .pid)
        ppid = try container.decode(Int32.self, forKey: .ppid)
        name = try container.decode(String.self, forKey: .name)
        if let stamp = try container.decodeIfPresent(String.self, forKey: .startTime) {
            guard let date = WireDate.date(from: stamp) else { throw WireError.invalidDate(stamp) }
            startTime = date
        } else {
            startTime = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pid, forKey: .pid)
        try container.encode(ppid, forKey: .ppid)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(startTime.map(WireDate.string(from:)), forKey: .startTime)
    }
}

/// Payload of topic `agent.hook`: the agent's native event plus the caller's context (SPEC §8.2).
public struct HookPayload: Codable, Sendable, Equatable {
    /// Maximum ancestor levels the CLI reports (AD-5).
    public static let maxAncestors = 8

    /// Adapter id, e.g. `claude`.
    public var agent: String
    /// The native event exactly as received (stdin JSON for Claude Code).
    public var raw: JSONValue
    /// Terminal device path of the caller, e.g. `/dev/ttys003`, if any.
    public var tty: String?
    /// Whitelisted environment variables only (see `HookPayload.isWhitelistedEnvironmentKey`).
    public var env: [String: String]
    /// The hook's parent first, up to `maxAncestors` levels.
    public var ancestors: [ProcessInfoEntry]

    public init(
        agent: String, raw: JSONValue, tty: String?, env: [String: String], ancestors: [ProcessInfoEntry]
    ) {
        self.agent = agent
        self.raw = raw
        self.tty = tty
        self.env = env
        self.ancestors = ancestors
    }

    /// Exact environment keys forwarded with a hook event (SPEC §8.2).
    public static let environmentKeys: Set<String> = [
        "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "ITERM_SESSION_ID",
        "GHOSTTY_RESOURCES_DIR", "GHOSTTY_BIN_DIR", "TMUX", "SHELL", "PWD",
    ]

    /// Key prefixes forwarded with a hook event.
    public static let environmentPrefixes = ["WARP_"]

    public static func isWhitelistedEnvironmentKey(_ key: String) -> Bool {
        environmentKeys.contains(key) || environmentPrefixes.contains { key.hasPrefix($0) }
    }

    /// The whitelisted subset of `environment`.
    public static func filterEnvironment(_ environment: [String: String]) -> [String: String] {
        environment.filter { isWhitelistedEnvironmentKey($0.key) }
    }
}
