import AgentKit
import Foundation
import ModuleKit

/// Story 5.1: terminal selection at `session.start` (AD-23) and the `SETUP · PERMISSION` alert for Focus (FR44,
/// UX-DR62, UX-DR69, AD-20).
extension AgentsSessionsModule {
    /// The core setup-problem kind (AD-13). Declared in the manifest: AlertCenter drops undeclared kinds.
    public nonisolated static let setupProblemKind = "setup.problem"
    /// The `terminal` local setting's default (SPEC §11).
    nonisolated static let defaultTerminal: TerminalID = "terminal"

    /// An open permission alert and the adapter it is about.
    struct PermissionAlert {
        let adapter: TerminalID
        let handle: AlertHandle
    }

    /// The `terminal` local setting: the adapter used when a session's env names no terminal (and for `openTab`).
    var preferredTerminal: TerminalID {
        settings?.value("terminal", as: String.self).flatMap(TerminalID.init) ?? Self.defaultTerminal
    }

    // MARK: Selection

    /// Chooses the terminal of the session `change` created or updated when it has none yet, or when it was
    /// chosen before its env arrived and the env is now known. Returns true when the session changed.
    func selectTerminalIfNeeded(after change: SessionChange) -> Bool {
        switch change {
        case .created(let key, _), .status(let key, _, _), .metadataOnly(let key):
            return selectTerminal(key)
        case .removed(let key, _):
            unhintedSelections.remove(key)
            return false
        case .none:
            return false
        }
    }

    /// Chooses the terminal of every session without one (e.g. loaded from an older `sessions.json`).
    @discardableResult
    func selectMissingTerminals() -> Bool {
        var changed = false
        for key in store.table.keys.sorted(by: { $0.description < $1.description })
        where store.table[key]?.terminalAdapterID == nil {
            if selectTerminal(key) { changed = true }
        }
        return changed
    }

    /// The selection itself: `TerminalAdapters.select(env:preferred:)`, then one pure `capture(env:pid:tty:)`
    /// whose locator is stored on the session (AD-23: no Apple Events, AX or I/O here).
    @discardableResult
    func selectTerminal(_ key: SessionKey, force: Bool = false) -> Bool {
        guard let session = store.table[key] else { return false }
        let hinted = session.terminal != nil
        if !force, session.terminalAdapterID != nil, !(hinted && unhintedSelections.contains(key)) { return false }
        let env = session.terminal?.environment ?? [:]
        guard let adapter = terminals.select(env: env, preferred: preferredTerminal) else { return false }
        let locator = adapter.capture(env: env, pid: session.agentProcess?.pid, tty: session.tty)
        if hinted { unhintedSelections.remove(key) } else { unhintedSelections.insert(key) }
        return store.setTerminal(key, adapter: adapter.id, locator: locator)
    }

    /// The session's chosen adapter; chosen now when it has none, or when its adapter is no longer registered.
    func terminalAdapter(for key: SessionKey) -> (any TerminalAdapter)? {
        if let id = store.table[key]?.terminalAdapterID, let adapter = terminals.anyAdapter(for: id) {
            return adapter
        }
        if selectTerminal(key, force: true), let persister {
            let (sessions, generation) = (store.snapshot, store.generation)
            Task { await persister.write(sessions, generation: generation) }
        }
        return store.table[key]?.terminalAdapterID.flatMap(terminals.anyAdapter(for:))
    }

    // MARK: Permissions

    /// Permissions the terminals of current sessions need and that are denied, per terminal adapter (for
    /// Settings › Agents). Only terminals in use are checked (AD-20); `status(of:)` never prompts. Not determined
    /// is not reported: macOS asks on the first Focus.
    public func focusPermissionIssues() async -> [TerminalID: Set<Permission>] {
        guard let permissions else { return [:] }
        let inUse = Set(store.table.values.compactMap(\.terminalAdapterID)).sorted()
        var issues: [TerminalID: Set<Permission>] = [:]
        for id in inUse {
            guard let adapter = terminals.anyAdapter(for: id) else { continue }
            var missing: Set<Permission> = []
            for permission in adapter.requiredPermissions where await permissions.status(of: permission) == .denied {
                missing.insert(permission)
            }
            if !missing.isEmpty { issues[id] = missing }
        }
        return issues
    }

    /// `permission:<adapter id>:<permission>`.
    nonisolated static func permissionDedupeKey(adapter: TerminalID, permission: Permission) -> String {
        "permission:\(adapter.rawValue):\(permissionToken(permission))"
    }

    nonisolated static func permissionToken(_ permission: Permission) -> String {
        switch permission {
        case .accessibility: "accessibility"
        case .automation(let bundleID): "automation:\(bundleID)"
        case .calendar: "calendar"
        case .notifications: "notifications"
        case .screenRecording: "screenRecording"
        }
    }

    /// Posts `SETUP · PERMISSION` for a Focus that lacked `permission` (once per adapter and permission until it
    /// is resolved). The action opens this module's Settings pane, which shows the permission and its System
    /// Settings link.
    func reportMissingPermission(_ permission: Permission, adapter: any TerminalAdapter) {
        let key = Self.permissionDedupeKey(adapter: adapter.id, permission: permission)
        guard permissionAlerts[key] == nil, let notifier else { return }
        let handle = notifier.post(Self.permissionEvent(permission, adapter: adapter))
        permissionAlerts[key] = PermissionAlert(adapter: adapter.id, handle: handle)
        log?.notice("Focus needs a permission for \(adapter.id.rawValue, privacy: .public)")
    }

    /// A focus through `adapter` went through without a permission error: its permission alerts are resolved.
    func resolvePermissionAlerts(for adapter: TerminalID) {
        for (key, alert) in permissionAlerts where alert.adapter == adapter {
            permissionAlerts[key] = nil
            alert.handle.resolve()
        }
    }

    func resolveAllPermissionAlerts() {
        let open = permissionAlerts.values
        permissionAlerts.removeAll()
        for alert in open { alert.handle.resolve() }
    }

    nonisolated static func permissionEvent(_ permission: Permission, adapter: any TerminalAdapter) -> NotifierEvent {
        let app = String(localized: adapter.name)
        let variant: String =
            switch permission {
            case .automation: "automation"
            case .accessibility: "accessibility"
            case .calendar, .notifications, .screenRecording: "other"
            }
        return NotifierEvent(
            kind: setupProblemKind,
            severity: .warn,
            title: SessionRowText.format("agentsSessions.permission.title.\(variant)", app),
            body: SessionRowText.format("agentsSessions.permission.body.\(variant)", app),
            action: .openSettings(pane: settingsPane),
            dedupeKey: permissionDedupeKey(adapter: adapter.id, permission: permission),
            category: string("agentsSessions.permission.category"))
    }
}
