import Foundation
import Testing

@testable import AgentKit

@Suite("Ask AI launch (Story 9.6)")
struct AskAILaunchTests {
    @Test("shell quoting keeps spaces, quotes and $ literal")
    func quoting() {
        #expect(ShellQuote.quote("/a b/c") == "'/a b/c'")
        #expect(ShellQuote.quote("it's") == "'it'\\''s'")
        #expect(ShellQuote.quote("$HOME \"x\" `y`") == "'$HOME \"x\" `y`'")
    }

    @Test("command line with and without a folder")
    func commandLine() {
        let argv = ["/usr/local/bin/claude", "@/a b.swift "]
        #expect(
            ShellQuote.commandLine(argv: argv, cwd: URL(fileURLWithPath: "/Users/me/my dev"))
                == "cd '/Users/me/my dev' && '/usr/local/bin/claude' '@/a b.swift '")
        #expect(ShellQuote.commandLine(argv: ["/bin/x"], cwd: nil) == "'/bin/x'")
    }

    let exe = URL(fileURLWithPath: "/opt/bin/claude")
    let command = LaunchCommand(
        executable: "claude", arguments: [], typedText: "@/a.swift ", promptArguments: ["@/a.swift "])

    @Test("a terminal that types gets the bare launch and the typed text")
    func typing() {
        let plan = LaunchPlan(command: command, executable: exe, terminalTypesText: true)
        #expect(plan == LaunchPlan(argv: ["/opt/bin/claude"], typedText: "@/a.swift ", pasteText: nil))
    }

    @Test("a terminal that cannot type gets the prompt arguments")
    func promptArguments() {
        let plan = LaunchPlan(command: command, executable: exe, terminalTypesText: false)
        #expect(plan == LaunchPlan(argv: ["/opt/bin/claude", "@/a.swift "], typedText: nil, pasteText: nil))
    }

    @Test("no prompt arguments and no typing: the text is left to paste")
    func paste() {
        let bare = LaunchCommand(executable: "x", arguments: ["--flag"], typedText: "/a.swift")
        let plan = LaunchPlan(command: bare, executable: exe, terminalTypesText: false)
        #expect(plan == LaunchPlan(argv: ["/opt/bin/claude", "--flag"], typedText: nil, pasteText: "/a.swift"))
    }

    @Test("environment goes through /usr/bin/env, sorted")
    func environment() {
        let withEnv = LaunchCommand(executable: "x", arguments: [], environment: ["B": "2", "A": "1"])
        let plan = LaunchPlan(command: withEnv, executable: exe, terminalTypesText: true)
        #expect(plan.argv == ["/usr/bin/env", "A=1", "B=2", "/opt/bin/claude"])
        #expect(plan.typedText == nil)
    }

    struct Bare: TerminalAdapter {
        let id: TerminalID = "bare"
        var name: LocalizedStringResource { "Bare" }
        let bundleIDs: [String] = []
        func matches(env: [String: String]) -> Bool { false }
        func capture(env: [String: String], pid: Int32?, tty: String?) -> TerminalLocator? { nil }
        func focus(_ locator: TerminalLocator, context: any AdapterContext) async -> FocusResult { .appOnly }
    }

    @Test("defaults: no typing, and openTab is not supported")
    func defaults() async {
        let terminal = Bare()
        #expect(!terminal.supportsTypedText)
        let context = AdapterContextBox(
            settings: DefaultsReadOnlySettings(descriptors: []), secrets: NoSecrets(),
            executables: NoExecutables(), http: URLSessionHTTPClient(),
            log: .init(subsystem: "test", category: "launch"))
        await #expect(throws: AdapterError.notSupported) {
            _ = try await terminal.openTab(argv: ["/bin/x"], cwd: nil, typedText: nil, context: context)
        }
    }
}
