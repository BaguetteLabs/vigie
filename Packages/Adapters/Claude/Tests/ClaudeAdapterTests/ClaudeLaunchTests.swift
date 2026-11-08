import AgentKit
import Foundation
import Testing

@testable import ClaudeAdapter

@Suite("Claude Ask AI launch (Story 9.6)")
struct ClaudeLaunchTests {
    let adapter = ClaudeAdapter()

    @Test("mentions: plain, with spaces, with spaces and quotes")
    func mentions() {
        let files = [
            URL(fileURLWithPath: "/Users/me/a.swift"),
            URL(fileURLWithPath: "/Users/me/my file.md"),
            URL(fileURLWithPath: "/Users/me/say \"hi\" now.txt"),
            URL(fileURLWithPath: "/Users/me/it's$x.txt"),
        ]
        #expect(
            ClaudeAdapter.mentions(files)
                == "@/Users/me/a.swift @\"/Users/me/my file.md\" /Users/me/say \"hi\" now.txt @/Users/me/it's$x.txt ")
    }

    @Test("launch: bare claude, mentions typed, or sent as the first prompt")
    func launch() {
        let command = adapter.launchCommand(files: [URL(fileURLWithPath: "/tmp/x y.png")], cwd: nil)
        #expect(
            command
                == LaunchCommand(
                    executable: "claude", arguments: [], typedText: "@\"/tmp/x y.png\" ",
                    promptArguments: ["@\"/tmp/x y.png\" "]))
    }

    @Test("the executable setting wins over the PATH lookup")
    func executable() async {
        let command = LaunchCommand(executable: "claude", arguments: [])
        let configured = makeContext(settings: ["executable": "/opt/claude"])
        #expect(await adapter.launchExecutable(for: command, context: configured)?.path == "/opt/claude")
        let byName = makeContext(paths: ["claude": URL(fileURLWithPath: "/usr/local/bin/claude")])
        #expect(await adapter.launchExecutable(for: command, context: byName)?.path == "/usr/local/bin/claude")
        #expect(await adapter.launchExecutable(for: command, context: makeContext()) == nil)
    }
}
