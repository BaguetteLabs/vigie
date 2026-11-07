import Foundation
import Testing

@testable import AgentKit

struct OtherTerminal: TerminalAdapter {
    let id: TerminalID = "generic"
    var name: LocalizedStringResource { "Terminal app" }
    let bundleIDs: [String] = []

    func matches(env: [String: String]) -> Bool { true }
    func capture(env: [String: String], pid: Int32?, tty: String?) -> TerminalLocator? { nil }
    func focus(_ locator: TerminalLocator, context: any AdapterContext) async -> FocusResult { .appOnly }
}

@Suite struct TerminalFallbackTests {
    @Test func resolveUsesTheMatchThenTheFallback() {
        let terminals = TerminalAdapters([FakeTerminal()], fallback: OtherTerminal())
        #expect(terminals.resolve(env: TerminalHintTests.warpEnv)?.id == "warp")
        #expect(terminals.resolve(env: ["TERM_PROGRAM": "iTerm.app"])?.id == "generic")
        #expect(terminals.fallback?.id == "generic")
        #expect(TerminalAdapters([FakeTerminal()]).resolve(env: [:]) == nil)
    }

    @Test func hintRebuildsItsEnvironment() throws {
        let warp = try #require(TerminalHint(env: TerminalHintTests.warpEnv))
        let rebuilt = try #require(TerminalHint(env: warp.environment))
        #expect(rebuilt == warp)
        #expect(FakeTerminal().matches(env: warp.environment))

        let iterm = TerminalHint(
            program: "iTerm.app", sessionID: "w0t0p0:ABC", warpFocusURL: nil, bundleID: "com.googlecode.iterm2",
            insideTmux: true)
        #expect(iterm.environment["ITERM_SESSION_ID"] == "w0t0p0:ABC")
        #expect(iterm.environment["TMUX"] != nil)
        #expect(TerminalHint(env: iterm.environment) == iterm)

        let apple = TerminalHint(program: "Apple_Terminal", sessionID: "X", warpFocusURL: nil, bundleID: nil)
        #expect(apple.environment["TERM_SESSION_ID"] == "X")
    }
}
