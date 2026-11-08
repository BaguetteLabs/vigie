import AgentKit
import Foundation
import Testing

@testable import WarpTerminal

@Suite("Warp openTab (Story 9.6)")
struct WarpOpenTabTests {
    @Test("new-tab URL with the folder percent-encoded")
    func url() {
        #expect(
            WarpAdapter.newTabURL(cwd: URL(fileURLWithPath: "/Users/me/my dev"))?.absoluteString
                == "warp://action/new_tab?path=/Users/me/my%20dev")
        #expect(WarpAdapter.newTabURL(cwd: nil)?.absoluteString == "warp://action/new_tab")
    }

    @Test("opens the tab in the folder, activates Warp, command not run")
    func opens() async throws {
        let system = FakeSystem(running: ["dev.warp.Warp-Stable"])
        let adapter = WarpAdapter(urlOpener: system, activator: system)
        #expect(!adapter.supportsTypedText)
        let outcome = try await adapter.openTab(
            argv: ["/bin/claude"], cwd: URL(fileURLWithPath: "/tmp"), typedText: nil, context: makeContext())
        #expect(outcome == .commandNotRun)
        #expect(
            system.calls == [
                .open(URL(string: "warp://action/new_tab?path=/tmp")!), .activate("dev.warp.Warp-Stable"),
            ])
    }

    @Test("URL refused: launches Warp, still command not run")
    func refused() async throws {
        let system = FakeSystem(openSucceeds: false, installed: ["dev.warp.Warp-Stable"])
        let adapter = WarpAdapter(urlOpener: system, activator: system)
        let outcome = try await adapter.openTab(argv: ["/bin/claude"], cwd: nil, typedText: nil, context: makeContext())
        #expect(outcome == .commandNotRun)
        #expect(system.calls.last == .launch("dev.warp.Warp-Stable"))
    }
}
