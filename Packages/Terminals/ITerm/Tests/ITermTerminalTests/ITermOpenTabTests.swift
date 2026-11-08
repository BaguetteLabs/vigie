import AgentKit
import Foundation
import Testing

@testable import ITermTerminal

@Suite("iTerm2 openTab (Story 9.6)")
struct ITermOpenTabTests {
    @Test("script snapshot: new tab, quoted command, typed text without newline")
    func scriptSnapshot() {
        let command = ShellQuote.commandLine(argv: ["/opt/bin/claude"], cwd: URL(fileURLWithPath: "/Users/me/my dev"))
        let expected = """
            tell application id "com.googlecode.iterm2"
                activate
                if (count of windows) is 0 then
                    create window with default profile
                else
                    tell current window to create tab with default profile
                end if
                tell current session of current window
                    write text "cd '/Users/me/my dev' && '/opt/bin/claude'"
                    delay 1.5
                    write text "@\\"/a b.md\\" @/c\\\\d.swift " newline no
                end tell
            end tell
            """
        #expect(ITermAdapter.openTabScript(command: command, typedText: "@\"/a b.md\" @/c\\d.swift ") == expected)
    }

    @Test("no typed text: no delay, no second write")
    func noTypedText() {
        let script = ITermAdapter.openTabScript(command: "'/bin/x'", typedText: nil)
        #expect(!script.contains("delay"))
        #expect(!script.contains("newline no"))
    }

    @Test("runs one script and types")
    func runs() async throws {
        let scripts = FakeScripts(.success(nil))
        let adapter = ITermAdapter(scripts: scripts, activator: FakeActivator())
        #expect(adapter.supportsTypedText)
        let outcome = try await adapter.openTab(
            argv: ["/bin/claude"], cwd: nil, typedText: "@/x ", context: makeContext())
        #expect(outcome == .running)
        #expect(await scripts.sources.first?.contains("write text \"@/x \" newline no") == true)
    }

    @Test("Automation denied → permissionRequired after activating")
    func permission() async {
        let activator = FakeActivator()
        let adapter = ITermAdapter(
            scripts: FakeScripts(.failure(AppleScriptError(number: -1743, message: "Not authorized"))),
            activator: activator)
        await #expect(throws: TerminalFocusError.permissionRequired(.automation(bundleID: "com.googlecode.iterm2"))) {
            _ = try await adapter.openTab(argv: ["/bin/claude"], cwd: nil, typedText: nil, context: makeContext())
        }
        #expect(await activator.calls.count == 1)
    }
}
