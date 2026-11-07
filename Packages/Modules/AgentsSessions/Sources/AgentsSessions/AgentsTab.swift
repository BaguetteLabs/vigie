import AgentKit
import Foundation
import ModuleKit
import SwiftUI
import VigieUI

/// Story 4.10: the Agents tab (FR39, FR92) and Focus (SPEC §7.1.1, FR44, A16).
extension AgentsSessionsModule {
    /// Settings pane of the `NO AGENT CONNECTED` button: this module's pane (Settings › Agents).
    nonisolated static let settingsPane = "agents.sessions"

    /// The Agents tab: the urgency-sorted rows rebuilt every second, Focus on click or `↵`, Dismiss on a failed
    /// row whose process ended.
    public func expandedView() -> AnyView? {
        var settingsAction: (@MainActor () -> Void)?
        if let open = openSettings {
            settingsAction = { open(Self.settingsPane) }
        }
        return AnyView(
            SessionsTabView(
                snapshot: { [weak self] now in self?.tabSnapshot(now: now) ?? SessionsSnapshot(rows: []) },
                onFocus: { [weak self] id in
                    guard let self, let key = SessionKey(id) else { return }
                    Task { await self.focus(key) }
                },
                onDismiss: { [weak self] id in
                    guard let self, let key = SessionKey(id), self.canDismiss(key) else { return }
                    Task { await self.dismiss(key) }
                },
                openSettings: settingsAction))
    }

    /// What the tab shows at `now`: rows in display order, or the empty state.
    func tabSnapshot(now: Date) -> SessionsSnapshot {
        let text = rowText
        let rows = displaySessions.map { rowModel($0, text: text, now: now) }
        let empty: SessionsEmptyState? =
            rows.isEmpty ? (adapters.adapters.isEmpty ? .noAgentConnected : .noActiveSessions) : nil
        return SessionsSnapshot(rows: rows, empty: empty)
    }

    /// One row: the display status at `now` (stale ticks in without waiting for the next liveness pass).
    func rowModel(_ session: Session, text: SessionRowText, now: Date) -> SessionRowModel {
        let status = session.displayStatus(now: now, staleAfter: text.staleAfter)
        let lastAction =
            status == .failed
            ? (session.lastMessage ?? text.lastActionLine(session, now: now))
            : text.lastActionLine(session, now: now)
        return SessionRowModel(
            id: session.key.description,
            glyphStatus: status,
            agentName: agentName(session.agentID),
            project: text.project(session),
            lastAction: lastAction,
            terminalName: terminalName(session),
            statusLabel: text.statusLabel(session, now: now),
            canDismiss: canDismiss(session.key),
            accessibilityLabel: text.accessibilityLabel(session, now: now))
    }

    /// The agent adapter's name (`Claude Code`), else its id.
    func agentName(_ id: AgentID) -> String {
        adapters.adapter(for: id).map { String(localized: $0.name) } ?? id.rawValue
    }

    /// The terminal app of the adapter that would focus the session (A55): the generic fallback names the app
    /// itself (`Warp`, `iTerm2`). Nil without terminal info.
    func terminalName(_ session: Session) -> String? {
        guard let env = session.terminal?.environment, let adapter = terminals.resolve(env: env) else { return nil }
        if let naming = adapter as? any TerminalAppNaming, let name = naming.appName(env: env) { return name }
        return String(localized: adapter.name)
    }

    /// A failed session whose agent process ended, or that has no tracked process (only `DISMISS` or the 24 h
    /// retention removes it, FR36).
    func canDismiss(_ key: SessionKey) -> Bool {
        guard let session = store.table[key], session.status == .failed else { return false }
        return session.agentProcess == nil || endedProcesses.contains(key)
    }

    /// Focus (SPEC §7.1.1): the session's terminal adapter (matched on its env, else the fallback, which only
    /// activates the app, A16) brings it forward. Never changes the session (EXPERIENCE "Focusing or dismissing
    /// does not change the state"). The outcome goes to the activity log.
    @discardableResult
    public func focus(_ key: SessionKey) async -> FocusResult {
        guard let session = store.table[key] else { return .failed(reason: "unknown session") }
        let env = session.terminal?.environment ?? [:]
        guard let adapter = terminals.resolve(env: env) else {
            return recordFocus(.failed(reason: "no terminal adapter"), adapter: nil)
        }
        guard let context = terminalContexts[adapter.id] ?? fallbackTerminalContext else {
            return recordFocus(.failed(reason: "no adapter context"), adapter: adapter.id)
        }
        let locator =
            adapter.capture(env: env, pid: session.agentProcess?.pid, tty: session.tty)
            ?? TerminalLocator(terminalID: adapter.id, fields: [:])
        let result = await adapter.focus(locator, context: context)
        return recordFocus(result, adapter: adapter.id)
    }

    private func recordFocus(_ result: FocusResult, adapter: TerminalID?) -> FocusResult {
        let outcome: ActivityOutcome =
            switch result {
            case .exact: .focusExact
            case .appOnly: .focusAppOnly
            case .failed(let reason): .focusFailed(reason: reason)
            }
        activity?.record(.focus(module: manifest.id, adapter: adapter?.rawValue, outcome: outcome))
        if case .failed(let reason) = result {
            log?.notice("focus failed: \(reason, privacy: .public)")
        }
        return result
    }
}
