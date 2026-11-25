import AgentKit
import AppKit
import ModuleKit

/// Copy diagnostics (Story 17.4): each adapter's detected CLI version, AD-23 support status and hook state, then
/// the terminal adapters and whether their app is installed. In-process state only (the last version check, the
/// integrations rows, Launch Services); never a session title, path, prompt or secret.
extension AgentsSessionsModule: DiagnosticsContributing {
    public func diagnostics() async -> [ModuleDiagnostics] {
        let hooks = Dictionary(
            (integrations?.rows ?? []).map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
        let adapterLines = adapters.adapters.map { adapter in
            Self.diagnosticsLine(adapter: adapter.id, support: adapterSupport[adapter.id], hook: hooks[adapter.id])
        }
        let terminalLines = terminals.adapters.map { terminal in
            let installed = terminal.bundleIDs.contains {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }
            return "terminal \(terminal.id.rawValue)  installed=\(installed)"
        }
        return [ModuleDiagnostics(section: .agents, lines: adapterLines + terminalLines)]
    }

    /// `adapter claude  version=2.1.3  support=supported  hook=connected`.
    nonisolated static func diagnosticsLine(
        adapter: AgentID, support: AdapterSupport?, hook: AgentIntegrationsModel.Status?
    ) -> String {
        let version = support?.version?.description ?? "none"
        let supportText =
            switch support {
            case nil: "unchecked"
            case .supported: "supported"
            case .assumed: "assumed (newer than tested)"
            case .unsupported: "unsupported (events ignored)"
            case .notInstalled: "not installed"
            }
        let hookText =
            switch hook {
            case nil, .some(.unknown): "unknown"
            case .some(.connected): "installed"
            case .some(.notConnected): "not installed"
            case .some(.partial): "partial"
            case .some(.none): "none needed"
            }
        return "adapter \(adapter.rawValue)  version=\(version)  support=\(supportText)  hook=\(hookText)"
    }
}
