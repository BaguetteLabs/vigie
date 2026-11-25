import AgentKit
import Foundation
import Testing

@testable import AgentsSessions

/// Copy diagnostics (Story 17.4): one line per adapter with version, support status and hook state.
struct AgentsDiagnosticsLineTests {
    @Test func linesShowVersionSupportAndHook() throws {
        let claude = try #require(AgentID("claude"))
        let version = AgentVersion(raw: "2.1.3 (Claude Code)")
        #expect(
            AgentsSessionsModule.diagnosticsLine(adapter: claude, support: .supported(version), hook: .connected)
                == "adapter claude  version=2.1.3  support=supported  hook=installed")
        #expect(
            AgentsSessionsModule.diagnosticsLine(adapter: claude, support: .unsupported(version), hook: .partial)
                == "adapter claude  version=2.1.3  support=unsupported (events ignored)  hook=partial")
        #expect(
            AgentsSessionsModule.diagnosticsLine(adapter: claude, support: .notInstalled, hook: nil)
                == "adapter claude  version=none  support=not installed  hook=unknown")
        #expect(
            AgentsSessionsModule.diagnosticsLine(adapter: claude, support: nil, hook: .some(.none))
                == "adapter claude  version=none  support=unchecked  hook=none needed")
    }
}
