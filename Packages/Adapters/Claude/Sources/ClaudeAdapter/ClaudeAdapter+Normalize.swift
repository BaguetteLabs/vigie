import AgentKit
import Foundation

extension ClaudeAdapter {
    /// Native `hook_event_name` values (SPEC §8.3), in the order the installer writes them.
    public static let hookEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SubagentStop",
        "SessionEnd",
    ]

    /// `Notification.notification_type` that means a permission dialog is open (spike 1.4, SPEC §14.4). The other
    /// observed subtype, `idle_prompt`, is a 60 s idle reminder and must not raise blocked.
    static let permissionPromptType = "permission_prompt"

    /// Pure (SPEC §7.1, FR82). Mapping, checked against `Tests/Fixtures/<version>/`:
    /// - `SessionStart` → `session.start` (`model` when present)
    /// - `UserPromptSubmit` → `prompt.submit`, including the synthetic `<agent-message …>` prompt Claude Code
    ///   injects when a background subagent hands back: Claude does work again after it
    /// - `PreToolUse` / `PostToolUse` → `tool.start` / `tool.end` (`tool_name`)
    /// - `Notification` with `notification_type == "permission_prompt"` → `needs.input(.permissionPrompt)`;
    ///   a type containing `error` → `session.error`; `idle_prompt` and anything else → nothing
    /// - `Stop` → `turn.end`, also while `background_tasks` still run
    /// - `SubagentStop` → `subagent.end`, except Claude Code's internal helpers (`agent_type` empty or absent)
    /// - `SessionEnd` → `session.end` (`reason`)
    /// - anything else (incl. `PermissionRequest`, not installed and not in the fixtures), or no `session_id` → `[]`
    public func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] {
        let raw = hook.raw
        guard let event = raw["hook_event_name"]?.stringValue,
            let sessionID = raw["session_id"]?.stringValue, !sessionID.isEmpty
        else { return [] }
        let context = AgentEventContext(
            sessionKey: SessionKey(agentID: id, sessionID: sessionID),
            cwd: Self.nonEmpty(raw["cwd"]).map { URL(fileURLWithPath: $0, isDirectory: true) },
            tty: hook.tty,
            terminal: TerminalHint(env: hook.env),
            agentProcess: agentProcess(in: hook.ancestors, environment: hook.env),
            at: sentAt)

        switch event {
        case "SessionStart":
            return [.sessionStart(context, model: Self.nonEmpty(raw["model"]))]
        case "UserPromptSubmit":
            return [.promptSubmit(context)]
        case "PreToolUse":
            guard let tool = Self.nonEmpty(raw["tool_name"]) else { return [] }
            return [.toolStart(context, tool: tool)]
        case "PostToolUse":
            guard let tool = Self.nonEmpty(raw["tool_name"]) else { return [] }
            return [.toolEnd(context, tool: tool)]
        case "Notification":
            let type = raw["notification_type"]?.stringValue ?? ""
            let message = Self.nonEmpty(raw["message"])
            if type == Self.permissionPromptType {
                return [.needsInput(context, reason: .permissionPrompt, message: message)]
            }
            if type.localizedCaseInsensitiveContains("error") {
                return [.sessionError(context, message: message)]
            }
            return []
        case "Stop":
            return [.turnEnd(context)]
        case "SubagentStop":
            guard Self.nonEmpty(raw["agent_type"]) != nil else { return [] }
            return [.subagentEnd(context)]
        case "SessionEnd":
            return [.sessionEnd(context, reason: Self.nonEmpty(raw["reason"]))]
        default:
            return []
        }
    }

    private static func nonEmpty(_ value: JSONValue?) -> String? {
        guard let text = value?.stringValue, !text.isEmpty else { return nil }
        return text
    }

    /// Pure (AD-5). The Claude Code process is the hook's direct parent (spike 1.4), named after its version
    /// (`2.1.319`, since `~/.local/bin/claude` links to `versions/2.1.319`) or `claude`. Order:
    /// 1. `CLAUDE_PID` from the environment, when it names an ancestor;
    /// 2. the first ancestor named `claude` or `<int>.<int>.<int>`;
    /// 3. the direct parent when it is `node` (npm installs run Claude Code under node).
    /// Never a shell: nil when nothing matches.
    public func agentProcess(in ancestors: [ProcessInfoEntry], environment: [String: String]) -> AgentProcessRef? {
        if let pid = environment["CLAUDE_PID"].flatMap({ Int32($0.trimmingCharacters(in: .whitespaces)) }),
            let entry = ancestors.first(where: { $0.pid == pid })
        {
            return AgentProcessRef(entry)
        }
        if let entry = ancestors.first(where: { $0.name == Self.executableName || Self.isVersionName($0.name) }) {
            return AgentProcessRef(entry)
        }
        if let parent = ancestors.first, parent.name == "node" {
            return AgentProcessRef(parent)
        }
        return nil
    }

    /// `<digits>.<digits>.<digits>`, e.g. `2.1.319`.
    static func isVersionName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3
            && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }
}
