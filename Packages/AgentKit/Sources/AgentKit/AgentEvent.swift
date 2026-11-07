import Foundation

/// A session's identity (AD-5): `<adapter id>:<native session id>`.
public struct SessionKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let agentID: AgentID
    /// The agent's own session id, e.g. Claude Code's `session_id`.
    public let sessionID: String

    public init(agentID: AgentID, sessionID: String) {
        self.agentID = agentID
        self.sessionID = sessionID
    }

    public var description: String { "\(agentID.rawValue):\(sessionID)" }
}

/// The agent process a session belongs to, picked by `AgentAdapter.agentProcess(in:environment:)` from the
/// hook's ancestor chain (AD-5). Liveness compares both fields.
public struct AgentProcessRef: Hashable, Sendable, Codable {
    public let pid: Int32
    public let startTime: Date?

    public init(pid: Int32, startTime: Date?) {
        self.pid = pid
        self.startTime = startTime
    }

    public init(_ entry: ProcessInfoEntry) {
        self.init(pid: entry.pid, startTime: entry.startTime)
    }

    private enum CodingKeys: String, CodingKey {
        case pid
        case startTime = "start_time"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int32.self, forKey: .pid)
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime).map(WireDate.decode)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pid, forKey: .pid)
        try container.encodeIfPresent(startTime.map(WireDate.string(from:)), forKey: .startTime)
    }
}

extension WireDate {
    /// Parses a Wire timestamp or throws `WireError.invalidDate`.
    static func decode(_ stamp: String) throws -> Date {
        guard let date = WireDate.date(from: stamp) else { throw WireError.invalidDate(stamp) }
        return date
    }
}

/// What the hook's whitelisted environment says about the terminal (SPEC §7.1.1, §8.2). Terminal adapters
/// still decide with `matches(env:)` / `capture(env:pid:tty:)`; this is the summary kept on the session.
public struct TerminalHint: Hashable, Sendable, Codable {
    /// `TERM_PROGRAM`, e.g. `WarpTerminal`, `iTerm.app`, `Apple_Terminal`, `ghostty`.
    public let program: String?
    /// The terminal's own session id: `ITERM_SESSION_ID`, else `TERM_SESSION_ID`, else `WARP_TERMINAL_SESSION_UUID`.
    public let sessionID: String?
    /// `WARP_FOCUS_URL` (`warp://session/<uuid>`, spike 1.5).
    public let warpFocusURL: String?
    /// `__CFBundleIdentifier` when forwarded, e.g. `dev.warp.Warp-Stable`.
    public let bundleID: String?
    /// True when `TMUX` is set: the tty belongs to tmux, not to the terminal tab.
    public let insideTmux: Bool

    public init(
        program: String?, sessionID: String?, warpFocusURL: String?, bundleID: String?, insideTmux: Bool = false
    ) {
        self.program = program
        self.sessionID = sessionID
        self.warpFocusURL = warpFocusURL
        self.bundleID = bundleID
        self.insideTmux = insideTmux
    }

    /// Pure extraction from a hook's environment. Returns nil when no terminal key is present (headless runs).
    public init?(env: [String: String]) {
        func value(_ key: String) -> String? {
            guard let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            return value
        }
        let program = value("TERM_PROGRAM")
        let sessionID = value("ITERM_SESSION_ID") ?? value("TERM_SESSION_ID") ?? value("WARP_TERMINAL_SESSION_UUID")
        let warpFocusURL = value("WARP_FOCUS_URL")
        let bundleID = value("__CFBundleIdentifier")
        let insideTmux = value("TMUX") != nil
        guard program != nil || sessionID != nil || warpFocusURL != nil || bundleID != nil || insideTmux else {
            return nil
        }
        self.init(
            program: program, sessionID: sessionID, warpFocusURL: warpFocusURL, bundleID: bundleID,
            insideTmux: insideTmux)
    }
}

/// Where and when a normalized event happened. Built by the adapter from the `HookPayload`.
///
/// Dates encode as Wire timestamps (ISO 8601 UTC, millisecond precision; Conventions: Dates on disk / wire)
/// whatever the encoder's date strategy.
public struct AgentEventContext: Hashable, Sendable, Codable {
    public let sessionKey: SessionKey
    public let cwd: URL?
    public let tty: String?
    public let terminal: TerminalHint?
    public let agentProcess: AgentProcessRef?
    /// The envelope's `sent_at` (AD-5, AD-7): all session timing uses it, never arrival time.
    public let at: Date

    public var agentID: AgentID { sessionKey.agentID }

    public init(
        sessionKey: SessionKey,
        cwd: URL? = nil,
        tty: String? = nil,
        terminal: TerminalHint? = nil,
        agentProcess: AgentProcessRef? = nil,
        at: Date
    ) {
        self.sessionKey = sessionKey
        self.cwd = cwd
        self.tty = tty
        self.terminal = terminal
        self.agentProcess = agentProcess
        self.at = at
    }

    private enum CodingKeys: String, CodingKey {
        case sessionKey = "session_key"
        case cwd
        case tty
        case terminal
        case agentProcess = "agent_process"
        case at
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionKey = try container.decode(SessionKey.self, forKey: .sessionKey)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd).map { URL(fileURLWithPath: $0) }
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        terminal = try container.decodeIfPresent(TerminalHint.self, forKey: .terminal)
        agentProcess = try container.decodeIfPresent(AgentProcessRef.self, forKey: .agentProcess)
        at = try WireDate.decode(try container.decode(String.self, forKey: .at))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionKey, forKey: .sessionKey)
        try container.encodeIfPresent(cwd?.path, forKey: .cwd)
        try container.encodeIfPresent(tty, forKey: .tty)
        try container.encodeIfPresent(terminal, forKey: .terminal)
        try container.encodeIfPresent(agentProcess, forKey: .agentProcess)
        try container.encode(WireDate.string(from: at), forKey: .at)
    }
}

/// Why a session waits for the user (`needs.input`).
public enum BlockReason: String, Hashable, Sendable, Codable, CaseIterable {
    /// The agent asks to approve a tool call.
    case permissionPrompt = "permission_prompt"
    /// The agent asks the user a question.
    case question
}

/// The normalized agent events of SPEC §7.1. Adapters only produce them (`AgentAdapter.normalize`); the
/// `SessionStore` in `agents.sessions` alone turns them into statuses (AD-5). Names follow SPEC §7.1 exactly
/// (`AgentEvent.Name.rawValue`). The native payload stays in the hook; it is never copied into an event.
public enum AgentEvent: Hashable, Sendable {
    /// `session.start`: the session started. `model` when the agent reports it.
    case sessionStart(AgentEventContext, model: String? = nil)
    /// `prompt.submit`: the user sent a prompt.
    case promptSubmit(AgentEventContext)
    /// `tool.start`: a tool call started (also a heartbeat).
    case toolStart(AgentEventContext, tool: String)
    /// `tool.end`: a tool call finished (also a heartbeat).
    case toolEnd(AgentEventContext, tool: String)
    /// `subagent.end`: a subagent finished; the parent may still be working.
    case subagentEnd(AgentEventContext)
    /// `needs.input`: the agent waits for the user (permission request or question).
    case needsInput(AgentEventContext, reason: BlockReason, message: String? = nil)
    /// `turn.end`: the agent finished its turn and waits for the next prompt.
    case turnEnd(AgentEventContext)
    /// `session.error`: a run-breaking error (connection lost, login required).
    case sessionError(AgentEventContext, message: String? = nil)
    /// `session.end`: the session closed. `reason` as the agent gives it, e.g. `prompt_input_exit`.
    case sessionEnd(AgentEventContext, reason: String? = nil)

    /// SPEC §7.1 event names.
    public enum Name: String, Hashable, Sendable, Codable, CaseIterable {
        case sessionStart = "session.start"
        case promptSubmit = "prompt.submit"
        case toolStart = "tool.start"
        case toolEnd = "tool.end"
        case subagentEnd = "subagent.end"
        case needsInput = "needs.input"
        case turnEnd = "turn.end"
        case sessionError = "session.error"
        case sessionEnd = "session.end"
    }

    public var name: Name {
        switch self {
        case .sessionStart: .sessionStart
        case .promptSubmit: .promptSubmit
        case .toolStart: .toolStart
        case .toolEnd: .toolEnd
        case .subagentEnd: .subagentEnd
        case .needsInput: .needsInput
        case .turnEnd: .turnEnd
        case .sessionError: .sessionError
        case .sessionEnd: .sessionEnd
        }
    }

    public var context: AgentEventContext {
        switch self {
        case .sessionStart(let context, _), .promptSubmit(let context), .toolStart(let context, _),
            .toolEnd(let context, _), .subagentEnd(let context), .needsInput(let context, _, _),
            .turnEnd(let context), .sessionError(let context, _), .sessionEnd(let context, _):
            context
        }
    }
}

extension AgentEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case event
        case context
        case model
        case tool
        case reason
        case message
    }

    /// Encodes as `{"event": "<SPEC name>", "context": {...}, ...}` with only the fields the event has.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .event)
        try container.encode(context, forKey: .context)
        switch self {
        case .sessionStart(_, let model):
            try container.encodeIfPresent(model, forKey: .model)
        case .toolStart(_, let tool), .toolEnd(_, let tool):
            try container.encode(tool, forKey: .tool)
        case .needsInput(_, let reason, let message):
            try container.encode(reason.rawValue, forKey: .reason)
            try container.encodeIfPresent(message, forKey: .message)
        case .sessionError(_, let message):
            try container.encodeIfPresent(message, forKey: .message)
        case .sessionEnd(_, let reason):
            try container.encodeIfPresent(reason, forKey: .reason)
        case .promptSubmit, .subagentEnd, .turnEnd:
            break
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(Name.self, forKey: .event)
        let context = try container.decode(AgentEventContext.self, forKey: .context)
        switch name {
        case .sessionStart:
            self = .sessionStart(context, model: try container.decodeIfPresent(String.self, forKey: .model))
        case .promptSubmit:
            self = .promptSubmit(context)
        case .toolStart:
            self = .toolStart(context, tool: try container.decode(String.self, forKey: .tool))
        case .toolEnd:
            self = .toolEnd(context, tool: try container.decode(String.self, forKey: .tool))
        case .subagentEnd:
            self = .subagentEnd(context)
        case .needsInput:
            self = .needsInput(
                context,
                reason: try container.decode(BlockReason.self, forKey: .reason),
                message: try container.decodeIfPresent(String.self, forKey: .message))
        case .turnEnd:
            self = .turnEnd(context)
        case .sessionError:
            self = .sessionError(context, message: try container.decodeIfPresent(String.self, forKey: .message))
        case .sessionEnd:
            self = .sessionEnd(context, reason: try container.decodeIfPresent(String.self, forKey: .reason))
        }
    }
}
