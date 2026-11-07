import AgentKit
import Foundation
import ModuleKit
import os

/// The AD-23 version gate (Stories 4.6 / 4.11 follow-up): each adapter's support is computed from
/// `detectVersion(context:)` before the first event is applied, and again when the `adapters` setting changes.
/// ``HookPipeline`` normalizes through `normalize(_:sentAt:support:)`, so an adapter whose support does not
/// `emitsEvents` contributes nothing. An `unsupported` version raises one `SETUP · AGENT` alert per adapter
/// (dedupe `support:<adapter id>`), resolved once the support is anything else; `notInstalled` raises none
/// (Settings › Agents shows it).
extension AgentsSessionsModule {
    /// Detects every adapter's version, updates the pipeline gate and the support alerts.
    func refreshAdapterSupport() async {
        for adapter in adapters.adapters {
            let context = adapterContexts[adapter.id] ?? fallbackAdapterContext(for: adapter)
            let version = await adapter.detectVersion(context: context)
            let support = adapter.support(for: version)
            pipeline?.setSupport(support, for: adapter.id)
            adapterSupport[adapter.id] = support
            updateSupportAlert(adapter, support: support)
        }
    }

    /// A context for an adapter App assembly gave none: its declared defaults and this module's services.
    func fallbackAdapterContext(for adapter: any AgentAdapter) -> any AdapterContext {
        AdapterContextBox(
            settings: DefaultsReadOnlySettings(descriptors: adapter.settings),
            secrets: moduleSecrets ?? NoAdapterSecrets(),
            executables: moduleExecutables ?? NoAdapterExecutables(),
            http: URLSessionHTTPClient(), log: log ?? Logger(subsystem: "vigie", category: "agents.sessions"))
    }

    nonisolated static func supportDedupeKey(_ id: AgentID) -> String { "support:\(id.rawValue)" }

    func updateSupportAlert(_ adapter: any AgentAdapter, support: AdapterSupport) {
        guard case .unsupported(let version) = support else {
            supportAlerts.removeValue(forKey: adapter.id)?.resolve()
            return
        }
        guard supportAlerts[adapter.id] == nil, let notifier else { return }
        supportAlerts[adapter.id] = notifier.post(Self.unsupportedEvent(adapter, version: version))
        log?.notice("\(adapter.id.rawValue, privacy: .public) CLI version unsupported: events ignored")
    }

    func resolveAllSupportAlerts() {
        let open = supportAlerts.values
        supportAlerts.removeAll()
        for handle in open { handle.resolve() }
    }

    nonisolated static func unsupportedEvent(_ adapter: any AgentAdapter, version: AgentVersion) -> NotifierEvent {
        NotifierEvent(
            kind: setupProblemKind,
            severity: .warn,
            title: SessionRowText.format(
                "agentsSessions.support.unsupported.title", String(localized: adapter.name), version.display),
            body: string("agentsSessions.support.unsupported.body"),
            action: .openSettings(pane: settingsPane),
            dedupeKey: supportDedupeKey(adapter.id),
            category: string("agentsSessions.support.category"))
    }
}
