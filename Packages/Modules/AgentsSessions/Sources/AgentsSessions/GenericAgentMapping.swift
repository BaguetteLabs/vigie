import AgentKit
import Foundation
import Wire

/// The generic path (AD-5, FR86): `agent.generic` reports from `vigie agent` (and later `vigie run`) become
/// normalized agent events here, without an adapter and without the adapter support gate.
///
/// - `--status working` → `prompt.submit`
/// - `--status blocked` → `needs.input` (reason `.permissionPrompt`, so the alert reads `<agent> needs input`
///   unless `--message` gives the detail)
/// - `--status done` → `turn.end`
/// - `--status failed` → `session.error` (`--message`)
/// - `--status idle` → `session.start`, also for a running session (re-entry: the reducer sets idle)
/// - `--end` → `session.end` (wins over a status)
///
/// Identity is `generic.<agent>:<session>`; the agent process is the first ancestor that is not a shell.
enum GenericAgentMapping {
    /// Shell process names skipped when choosing the agent process (a leading `-` marks a login shell).
    static let shellNames: Set<String> = ["zsh", "bash", "sh", "fish", "nu", "dash", "ksh", "tcsh", "csh"]

    /// True for `zsh`, `-zsh`, `/bin/zsh` and the other `shellNames`.
    static func isShell(_ name: String) -> Bool {
        var base = name
        if base.hasPrefix("-") { base.removeFirst() }
        if let slash = base.lastIndex(of: "/") { base = String(base[base.index(after: slash)...]) }
        return shellNames.contains(base)
    }

    /// The first ancestor that is not a shell (AD-5), so liveness and Focus follow the tool, not the wrapper.
    static func agentProcess(in ancestors: [ProcessInfoEntry]) -> AgentProcessRef? {
        ancestors.first { !isShell($0.name) }.map(AgentProcessRef.init)
    }

    /// Pure. `[]` when `agent` is not a valid adapter-id shaped name, the session id is empty, or neither a
    /// status nor `end` is set.
    static func normalize(_ payload: GenericAgentPayload, sentAt: Date) -> [AgentEvent] {
        guard let id = AgentID(generic: payload.agent), !payload.session.isEmpty else { return [] }
        let context = AgentEventContext(
            sessionKey: SessionKey(agentID: id, sessionID: payload.session),
            cwd: payload.cwd.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) },
            tty: payload.tty,
            terminal: TerminalHint(env: payload.env),
            agentProcess: agentProcess(in: payload.ancestors),
            at: sentAt)
        let message = payload.message.flatMap { $0.isEmpty ? nil : $0 }
        if payload.end { return [.sessionEnd(context)] }
        switch payload.status {
        case .working: return [.promptSubmit(context)]
        case .blocked: return [.needsInput(context, reason: .permissionPrompt, message: message)]
        case .done: return [.turnEnd(context)]
        case .failed: return [.sessionError(context, message: message)]
        case .idle: return [.sessionStart(context)]
        case nil: return []
        }
    }
}
