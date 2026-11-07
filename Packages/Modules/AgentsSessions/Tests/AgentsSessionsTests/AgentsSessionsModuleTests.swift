import AgentKit
import Foundation
import ModuleKit
import Testing

@testable import AgentsSessions

@MainActor @Suite struct AgentsSessionsModuleTests {
    @Test func manifest() {
        let module = AgentsSessionsModule(adapters: AgentAdapters([]), terminals: TerminalAdapters([]))
        #expect(module.manifest.id == "agents.sessions")
        #expect(module.manifest.defaultEnabled)
        #expect(module.state == .hidden)
        #expect(module.adapters.adapters.isEmpty)
    }

    @Test func nameResolvesFromCatalog() {
        let name = String(localized: AgentsSessionsModule.staticManifest.name)
        #expect(name == "Agents")
    }
}
