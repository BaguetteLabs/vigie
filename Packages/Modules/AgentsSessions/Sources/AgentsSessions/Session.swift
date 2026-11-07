import AgentKit
import Foundation
import VigieUI

/// One tracked agent session (SPEC §7.1). Only `SessionReducer` writes `status` (AD-5).
///
/// The status type is VigieUI's `SessionStatus`, so labels and colors come straight from the theme. The
/// reducer only ever produces `idle`, `working`, `done`, `blocked` and `failed`; `stale` is a display state
/// computed by liveness (Story 4.8) and is never stored.
public struct Session: Hashable, Sendable, Identifiable {
    /// `<adapter id>:<native session id>` (AD-5).
    public let key: SessionKey
    public internal(set) var status: SessionStatus
    /// `sent_at` of the event that entered `status` (AD-5). Re-entering the same status keeps it, so
    /// `WORKING · 14M` and blocked/failed `T+` count from when the state began.
    public internal(set) var statusSince: Date
    /// The latest `sent_at` applied to this session; events older than this never change status.
    public internal(set) var lastEventAt: Date
    /// The last tool the agent ran (`tool.start` / `tool.end`).
    public internal(set) var lastAction: String?
    public internal(set) var cwd: URL?
    public internal(set) var tty: String?
    public internal(set) var terminal: TerminalHint?
    public internal(set) var agentProcess: AgentProcessRef?
    /// The model the agent reported on `session.start`.
    public internal(set) var model: String?
    /// Why the session waits; set while `blocked`.
    public internal(set) var blockReason: BlockReason?
    /// The agent's message for `needs.input` or `session.error`; set while `blocked` or `failed`.
    public internal(set) var lastMessage: String?
    /// The terminal adapter chosen for this session (Story 5.1, AD-23): the first `matches(env:)`, else the
    /// `terminal` setting when the env names no terminal, else the fallback.
    public internal(set) var terminalAdapterID: TerminalID?
    /// What that adapter's `capture(env:pid:tty:)` returned, once, when the adapter was chosen. nil when the env
    /// did not identify a tab (Focus then activates the app).
    public internal(set) var terminalLocator: TerminalLocator?

    public var id: SessionKey { key }
    public var agentID: AgentID { key.agentID }
    /// The project name: the last path component of `cwd`.
    public var projectName: String? {
        guard let cwd else { return nil }
        let name = cwd.standardizedFileURL.lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    public init(
        key: SessionKey,
        status: SessionStatus,
        statusSince: Date,
        lastEventAt: Date,
        lastAction: String? = nil,
        cwd: URL? = nil,
        tty: String? = nil,
        terminal: TerminalHint? = nil,
        agentProcess: AgentProcessRef? = nil,
        model: String? = nil,
        blockReason: BlockReason? = nil,
        lastMessage: String? = nil,
        terminalAdapterID: TerminalID? = nil,
        terminalLocator: TerminalLocator? = nil
    ) {
        self.key = key
        self.status = status
        self.statusSince = statusSince
        self.lastEventAt = lastEventAt
        self.lastAction = lastAction
        self.cwd = cwd
        self.tty = tty
        self.terminal = terminal
        self.agentProcess = agentProcess
        self.model = model
        self.blockReason = blockReason
        self.lastMessage = lastMessage
        self.terminalAdapterID = terminalAdapterID
        self.terminalLocator = terminalLocator
    }
}

/// `sessions.json` shape (schema 1): snake_case keys, the session key as its `<adapter>:<native id>` string,
/// dates in the storage encoder's Wire format.
extension Session: Codable {
    private enum CodingKeys: String, CodingKey {
        case key
        case status
        case statusSince = "status_since"
        case lastEventAt = "last_event_at"
        case lastAction = "last_action"
        case cwd
        case tty
        case terminal
        case agentProcess = "agent_process"
        case model
        case blockReason = "block_reason"
        case lastMessage = "last_message"
        case terminalAdapterID = "terminal_adapter"
        case terminalLocator = "terminal_locator"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .key)
        guard let key = SessionKey(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .key, in: container, debugDescription: "Invalid session key: \(raw)")
        }
        self.key = key
        status = try container.decode(SessionStatus.self, forKey: .status)
        statusSince = try container.decode(Date.self, forKey: .statusSince)
        lastEventAt = try container.decode(Date.self, forKey: .lastEventAt)
        lastAction = try container.decodeIfPresent(String.self, forKey: .lastAction)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd).map { URL(fileURLWithPath: $0) }
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        terminal = try container.decodeIfPresent(TerminalHint.self, forKey: .terminal)
        agentProcess = try container.decodeIfPresent(AgentProcessRef.self, forKey: .agentProcess)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        blockReason = try container.decodeIfPresent(BlockReason.self, forKey: .blockReason)
        lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        terminalAdapterID = try container.decodeIfPresent(TerminalID.self, forKey: .terminalAdapterID)
        terminalLocator = try container.decodeIfPresent(TerminalLocator.self, forKey: .terminalLocator)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key.description, forKey: .key)
        try container.encode(status, forKey: .status)
        try container.encode(statusSince, forKey: .statusSince)
        try container.encode(lastEventAt, forKey: .lastEventAt)
        try container.encodeIfPresent(lastAction, forKey: .lastAction)
        try container.encodeIfPresent(cwd?.path, forKey: .cwd)
        try container.encodeIfPresent(tty, forKey: .tty)
        try container.encodeIfPresent(terminal, forKey: .terminal)
        try container.encodeIfPresent(agentProcess, forKey: .agentProcess)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(blockReason, forKey: .blockReason)
        try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try container.encodeIfPresent(terminalAdapterID, forKey: .terminalAdapterID)
        try container.encodeIfPresent(terminalLocator, forKey: .terminalLocator)
    }
}
