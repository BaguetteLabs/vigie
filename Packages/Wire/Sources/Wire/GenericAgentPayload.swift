import Foundation

/// A status reported by `vigie agent --status` (SPEC §8, AD-5).
public enum GenericStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case working
    case blocked
    case done
    case failed
    case idle
}

/// Payload of topic `agent.generic`: the raw `vigie agent` flags plus the caller's context (SPEC §8, AD-5).
///
/// The CLI never maps statuses; `agents.sessions` alone turns this into normalized agent events.
/// Exactly one of `status` or `end` is set by the CLI; a receiver treats `end == true` as `session.end`.
public struct GenericAgentPayload: Codable, Sendable, Equatable {
    /// The `--agent` value, e.g. `mytool`. Never a reserved adapter id (`ReservedAgentIDs`).
    public var agent: String
    /// The `--session` value: the tool's own session id.
    public var session: String
    /// The `--status` value; nil with `--end`.
    public var status: GenericStatus?
    /// True for `--end`.
    public var end: Bool
    /// The `--cwd` value as an absolute path, if given.
    public var cwd: String?
    /// The `--message` value, if given.
    public var message: String?
    /// Terminal device path of the caller, e.g. `/dev/ttys003`, if any.
    public var tty: String?
    /// Whitelisted environment variables only (`HookPayload.isWhitelistedEnvironmentKey`).
    public var env: [String: String]
    /// The CLI's parent first, up to `HookPayload.maxAncestors` levels.
    public var ancestors: [ProcessInfoEntry]

    enum CodingKeys: String, CodingKey {
        case agent
        case session
        case status
        case end
        case cwd
        case message
        case tty
        case env
        case ancestors
    }

    public init(
        agent: String,
        session: String,
        status: GenericStatus?,
        end: Bool = false,
        cwd: String? = nil,
        message: String? = nil,
        tty: String? = nil,
        env: [String: String] = [:],
        ancestors: [ProcessInfoEntry] = []
    ) {
        self.agent = agent
        self.session = session
        self.status = status
        self.end = end
        self.cwd = cwd
        self.message = message
        self.tty = tty
        self.env = env
        self.ancestors = ancestors
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agent = try container.decode(String.self, forKey: .agent)
        session = try container.decode(String.self, forKey: .session)
        status = try container.decodeIfPresent(GenericStatus.self, forKey: .status)
        end = try container.decodeIfPresent(Bool.self, forKey: .end) ?? false
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        ancestors = try container.decodeIfPresent([ProcessInfoEntry].self, forKey: .ancestors) ?? []
    }
}

/// Agent ids that belong to a registered (or planned) adapter (AD-5): `vigie agent --agent <id>` drops them,
/// since that agent reports through `vigie hook <id>`.
public enum ReservedAgentIDs {
    public static let all: Set<String> = ["claude", "codex", "gemini"]

    public static func contains(_ agent: String) -> Bool { all.contains(agent) }
}
