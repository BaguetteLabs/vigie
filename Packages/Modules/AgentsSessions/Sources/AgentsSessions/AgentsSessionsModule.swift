import AgentKit
import Foundation
import ModuleKit
import Observation

/// `agents.sessions` (SPEC §7.1): tracks every running CLI agent session.
///
/// App assembly builds the adapter lists once and passes the same instances here and to `agents.usage`
/// (AD-4); this module never discovers adapters itself, so adding an agent needs no change here (NFR23).
/// Story 4.5 adds the SessionStore.
@MainActor @Observable
public final class AgentsSessionsModule: NotchModule {
    public nonisolated static let staticManifest = ModuleManifest(
        id: "agents.sessions",
        name: LocalizedStringResource("agentsSessions.module.name", bundle: .atURL(Bundle.module.bundleURL)),
        icon: "terminal",
        defaultEnabled: true
    )

    public let manifest = AgentsSessionsModule.staticManifest
    public private(set) var state: ModuleState = .hidden

    public let adapters: AgentAdapters
    public let terminals: TerminalAdapters

    public init(adapters: AgentAdapters, terminals: TerminalAdapters) {
        self.adapters = adapters
        self.terminals = terminals
    }

    public func start(context: any ModuleContext) async throws {}

    public func stop() async {}
}
