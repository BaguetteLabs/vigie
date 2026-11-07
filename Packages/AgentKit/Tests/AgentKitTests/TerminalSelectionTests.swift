import Foundation
import Testing

@testable import AgentKit

@Suite struct TerminalSelectionTests {
    let terminals = TerminalAdapters([FakeTerminal()], fallback: OtherTerminal())

    @Test func matchWinsOverThePreferredTerminal() {
        #expect(terminals.select(env: ["TERM_PROGRAM": "WarpTerminal"], preferred: "generic")?.id == "warp")
    }

    @Test func preferredOnlyWhenTheEnvNamesNoTerminal() {
        #expect(terminals.select(env: [:], preferred: "warp")?.id == "warp")
        #expect(terminals.select(env: ["TERM_PROGRAM": ""], preferred: "warp")?.id == "warp")
        #expect(terminals.select(env: ["TERM_PROGRAM": "ghostty"], preferred: "warp")?.id == "generic")
        #expect(
            terminals.select(env: ["__CFBundleIdentifier": "com.mitchellh.ghostty"], preferred: "warp")?.id
                == "generic")
    }

    @Test func unknownOrMissingPreferenceFallsBack() {
        #expect(terminals.select(env: [:], preferred: "kitty")?.id == "generic")
        #expect(terminals.select(env: [:], preferred: nil)?.id == "generic")
        #expect(TerminalAdapters([FakeTerminal()]).select(env: [:], preferred: nil) == nil)
    }

    @Test func anyAdapterFindsTheFallback() {
        #expect(terminals.anyAdapter(for: "warp")?.id == "warp")
        #expect(terminals.anyAdapter(for: "generic")?.id == "generic")
        #expect(terminals.anyAdapter(for: "iterm") == nil)
    }
}
