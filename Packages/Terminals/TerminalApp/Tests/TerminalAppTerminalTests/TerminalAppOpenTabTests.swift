import AgentKit
import Foundation
import Testing

@testable import TerminalAppTerminal

@Suite("Terminal.app openTab (Story 9.6)")
struct TerminalAppOpenTabTests {
    @Test("script snapshot: new window running the quoted command")
    func scriptSnapshot() {
        let command = ShellQuote.commandLine(
            argv: ["/opt/bin/claude", "@\"/a b/it's.md\" "], cwd: URL(fileURLWithPath: "/Users/me/my dev"))
        let expected = """
            set wasRunning to application id "com.apple.Terminal" is running
            tell application id "com.apple.Terminal"
                if wasRunning or (count of windows) is 0 then
                    do script "cd '/Users/me/my dev' && '/opt/bin/claude' '@\\"/a b/it'\\\\''s.md\\" '"
                else
                    do script "cd '/Users/me/my dev' && '/opt/bin/claude' '@\\"/a b/it'\\\\''s.md\\" '" in window 1
                end if
                activate
            end tell
            """
        #expect(TerminalAppAdapter.openTabScript(command: command) == expected)
    }

    @Test("runs one script, cannot type")
    func runs() async throws {
        let scripts = FakeScripts(.success(nil))
        let adapter = TerminalAppAdapter(scripts: scripts, activator: FakeActivator())
        #expect(!adapter.supportsTypedText)
        let outcome = try await adapter.openTab(
            argv: ["/bin/claude"], cwd: URL(fileURLWithPath: "/tmp"), typedText: "@/x ", context: makeContext())
        #expect(outcome == .running)
        let sources = await scripts.sources
        #expect(sources.count == 1)
        #expect(sources.first?.contains("do script \"cd '/tmp' && '/bin/claude'\"") == true)
        #expect(sources.first?.contains("@/x") == false)
    }

    @Test("Automation denied → permissionRequired after activating")
    func permission() async {
        let activator = FakeActivator()
        let adapter = TerminalAppAdapter(
            scripts: FakeScripts(.failure(AppleScriptError(number: -1743, message: "Not authorized"))),
            activator: activator)
        await #expect(throws: TerminalFocusError.permissionRequired(.automation(bundleID: "com.apple.Terminal"))) {
            _ = try await adapter.openTab(argv: ["/bin/claude"], cwd: nil, typedText: nil, context: makeContext())
        }
        #expect(await activator.calls.count == 1)
    }
}
