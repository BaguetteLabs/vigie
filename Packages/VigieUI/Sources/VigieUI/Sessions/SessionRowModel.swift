import Foundation

/// One Agents tab row (DESIGN "Session row", FR39), already formatted by the agents module so VigieUI stays
/// agent-agnostic.
public struct SessionRowModel: Identifiable, Sendable, Equatable {
    /// The session key; passed back to Focus and Dismiss.
    public let id: String
    /// The display status (stale included): glyph, status hue and alert tint.
    public var glyphStatus: SessionStatus
    /// `Claude Code`, `Codex`.
    public var agentName: String
    /// The project (from `cwd`).
    public var project: String
    /// The last tool, or the stale `LAST EVENT 14:30 · Bash` line; nil shows nothing under the project.
    public var lastAction: String?
    /// The terminal app (A55); shown only when rows span more than one app.
    public var terminalName: String?
    /// `BLOCKED · 12M`, `IDLE`, `STALE · 18M`.
    public var statusLabel: String
    /// A failed session whose process ended: selecting it shows `DISMISS` (FR36).
    public var canDismiss: Bool
    /// "vigie, blocked, 12 minutes" (UX-DR63).
    public var accessibilityLabel: String

    public init(
        id: String,
        glyphStatus: SessionStatus,
        agentName: String,
        project: String,
        lastAction: String? = nil,
        terminalName: String? = nil,
        statusLabel: String,
        canDismiss: Bool = false,
        accessibilityLabel: String
    ) {
        self.id = id
        self.glyphStatus = glyphStatus
        self.agentName = agentName
        self.project = project
        self.lastAction = lastAction
        self.terminalName = terminalName
        self.statusLabel = statusLabel
        self.canDismiss = canDismiss
        self.accessibilityLabel = accessibilityLabel
    }

    /// Blocked and failed rows carry the alert tint and count as alerts in the header.
    public var isAlert: Bool { glyphStatus == .blocked || glyphStatus == .failed }
}

/// The Agents tab's empty states (FR92, EXPERIENCE "Surface states").
public enum SessionsEmptyState: Sendable, Equatable {
    /// No agent adapter is set up: `NO AGENT CONNECTED` with a button to Settings › Agents.
    case noAgentConnected
    /// Adapters exist but no session runs: `NO ACTIVE SESSIONS`.
    case noActiveSessions

    public var copy: VigieCopy.EmptyState {
        switch self {
        case .noAgentConnected: VigieCopy.noAgentConnected
        case .noActiveSessions: VigieCopy.noActiveSessions
        }
    }

    /// Only "no agent" offers the Settings button.
    public var offersSettings: Bool { self == .noAgentConnected }
}

/// What the Agents tab shows at one instant: urgency-sorted rows, or an empty state.
public struct SessionsSnapshot: Sendable, Equatable {
    public var rows: [SessionRowModel]
    public var empty: SessionsEmptyState?

    public init(rows: [SessionRowModel], empty: SessionsEmptyState? = nil) {
        self.rows = rows
        self.empty = empty
    }

    /// The terminal column appears only when the rows span more than one terminal app (FR39).
    public var showsTerminalColumn: Bool {
        Set(rows.compactMap(\.terminalName)).count > 1
    }

    public var alertCount: Int { rows.count { $0.isAlert } }

    /// `SESSIONS · 9 · 3 ALERTS`, `SESSIONS · 4 · 1 ALERT`, `SESSIONS · 2`.
    public var header: String {
        switch alertCount {
        case 0: L10n.format("sessions.header", rows.count)
        case 1: L10n.format("sessions.header.oneAlert", rows.count)
        default: L10n.format("sessions.header.alerts", rows.count, alertCount)
        }
    }
}

/// Keyboard selection in the Agents tab: `↑↓` move it, clamped at both ends; nothing selected starts at the
/// first (↓) or last (↑) row. A selection whose row went away is dropped.
public enum SessionsSelection {
    public static func move(_ selection: String?, by step: Int, in ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let selection, let index = ids.firstIndex(of: selection) else {
            return step >= 0 ? ids.first : ids.last
        }
        return ids[min(max(index + step, 0), ids.count - 1)]
    }

    /// The selection if its row still exists.
    public static func valid(_ selection: String?, in ids: [String]) -> String? {
        guard let selection, ids.contains(selection) else { return nil }
        return selection
    }
}
