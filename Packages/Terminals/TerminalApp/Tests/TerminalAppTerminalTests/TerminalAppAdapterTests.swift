import AgentKit
import Foundation
import Testing
import os

@testable import TerminalAppTerminal

// MARK: - Fakes

actor FakeScripts: AppleScriptRunning {
    private(set) var sources: [String] = []
    let result: Result<String?, AppleScriptError>

    init(_ result: Result<String?, AppleScriptError>) { self.result = result }

    func run(source: String) async throws -> String? {
        sources.append(source)
        return try result.get()
    }
}

actor FakeActivator: AppActivating {
    private(set) var calls: [[String]] = []
    let available: Bool

    init(available: Bool = true) { self.available = available }

    func activate(bundleIDs: [String]) async -> Bool {
        calls.append(bundleIDs)
        return available
    }
}

struct NoSecrets: SecretStore {
    func read(_ key: String) async throws -> String? { nil }
    func write(_ value: String?, for key: String) async throws {}
}

struct NoExecutables: ExecutableResolver {
    func resolve(_ name: String) async -> URL? { nil }
}

struct NoHTTP: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

func makeContext() -> AdapterContextBox {
    AdapterContextBox(
        settings: DefaultsReadOnlySettings(descriptors: []), secrets: NoSecrets(), executables: NoExecutables(),
        http: NoHTTP(), log: Logger(subsystem: "fr.baguettelabs.vigie.tests", category: "terminal"))
}

let locator = TerminalLocator(terminalID: "terminal", fields: ["tty": "/dev/ttys003"])

// MARK: - Tests

@Suite struct TerminalAppAdapterTests {
    @Test func identity() {
        let adapter = TerminalAppAdapter(scripts: FakeScripts(.success(nil)), activator: FakeActivator())
        #expect(adapter.id == "terminal")
        #expect(adapter.bundleIDs == ["com.apple.Terminal"])
        #expect(adapter.requiredPermissions == [.automation(bundleID: "com.apple.Terminal")])
        #expect(String(localized: adapter.name) == "Terminal")
    }

    @Test func matchesOnlyAppleTerminal() {
        let adapter = TerminalAppAdapter()
        #expect(adapter.matches(env: ["TERM_PROGRAM": "Apple_Terminal"]))
        #expect(!adapter.matches(env: ["TERM_PROGRAM": "iTerm.app"]))
        #expect(!adapter.matches(env: ["TERM_PROGRAM": "WarpTerminal"]))
        #expect(!adapter.matches(env: [:]))
    }

    @Test func captureStoresTTYAndSessionIDWithoutScripts() async {
        let scripts = FakeScripts(.success("found"))
        let activator = FakeActivator()
        let adapter = TerminalAppAdapter(scripts: scripts, activator: activator)
        let env = ["TERM_PROGRAM": "Apple_Terminal", "TERM_SESSION_ID": "8D2B5F0E-0000-4000-8000-000000000001"]

        let full = adapter.capture(env: env, pid: 42, tty: "/dev/ttys003")
        #expect(full?.terminalID == "terminal")
        #expect(full?.fields["tty"] == "/dev/ttys003")
        #expect(full?.fields["term_session_id"] == "8D2B5F0E-0000-4000-8000-000000000001")

        // `ps`-style tty names are normalized; unusable ones give no locator.
        #expect(adapter.capture(env: [:], pid: nil, tty: "ttys012")?.fields == ["tty": "/dev/ttys012"])
        #expect(adapter.capture(env: env, pid: 42, tty: nil) == nil)
        #expect(adapter.capture(env: env, pid: 42, tty: "??") == nil)
        #expect(adapter.capture(env: env, pid: 42, tty: "/dev/ttys0\" & quit") == nil)

        // Capture is pure: no Apple Events, no activation (AD-23).
        #expect(await scripts.sources.isEmpty)
        #expect(await activator.calls.isEmpty)
    }

    @Test func scriptTargetsTheTTYAndSelectsTheTab() {
        let source = TerminalAppAdapter.focusScript(tty: "/dev/ttys003")
        #expect(source.contains("tty of t is \"/dev/ttys003\""))
        #expect(source.contains("set selected of t to true"))
        #expect(source.contains("set index of w to 1"))
        #expect(source.contains("activate"))
        #expect(source.contains("is not running"))
    }

    @Test func foundTabIsExact() async {
        let scripts = FakeScripts(.success("found"))
        let activator = FakeActivator()
        let adapter = TerminalAppAdapter(scripts: scripts, activator: activator)

        let result = await adapter.focus(locator, context: makeContext())

        #expect(result == .exact)
        let sources = await scripts.sources
        #expect(sources.count == 1)
        #expect(sources.first?.contains("\"/dev/ttys003\"") == true)
        #expect(await activator.calls.isEmpty)
    }

    @Test func missingTabActivatesTheAppOnly() async {
        let activator = FakeActivator()
        let adapter = TerminalAppAdapter(scripts: FakeScripts(.success("notfound")), activator: activator)
        #expect(await adapter.focus(locator, context: makeContext()) == .appOnly)
        // The script activated Terminal.app itself.
        #expect(await activator.calls.isEmpty)
    }

    @Test func notRunningOrOddOutputActivatesThroughWorkspace() async {
        for output in ["notrunning", nil, "weird"] as [String?] {
            let activator = FakeActivator()
            let adapter = TerminalAppAdapter(scripts: FakeScripts(.success(output)), activator: activator)
            #expect(await adapter.focus(locator, context: makeContext()) == .appOnly)
            #expect(await activator.calls == [["com.apple.Terminal"]])
        }
    }

    @Test func permissionDeniedThrowsTypedErrorAfterActivating() async {
        let activator = FakeActivator()
        let adapter = TerminalAppAdapter(
            scripts: FakeScripts(.failure(AppleScriptError(number: -1743, message: "Not authorized"))),
            activator: activator)

        await #expect(throws: TerminalFocusError.permissionRequired(.automation(bundleID: "com.apple.Terminal"))) {
            try await adapter.attemptFocus(locator, context: makeContext())
        }
        #expect(await activator.calls == [["com.apple.Terminal"]])
        // The protocol entry point folds it into an app-level result.
        #expect(await adapter.focus(locator, context: makeContext()) == .appOnly)
    }

    @Test func otherScriptErrorsFallBackToTheApp() async {
        let activator = FakeActivator()
        let adapter = TerminalAppAdapter(
            scripts: FakeScripts(.failure(AppleScriptError(number: -1728, message: "Can't get"))), activator: activator)
        let result = try? await adapter.attemptFocus(locator, context: makeContext())
        #expect(result == .appOnly)
        #expect(await activator.calls == [["com.apple.Terminal"]])
    }

    @Test func locatorWithoutTTYSkipsTheScript() async {
        let scripts = FakeScripts(.success("found"))
        let activator = FakeActivator(available: false)
        let adapter = TerminalAppAdapter(scripts: scripts, activator: activator)
        let result = await adapter.focus(TerminalLocator(terminalID: "terminal", fields: [:]), context: makeContext())
        #expect(result == .failed(reason: "Terminal.app is not available"))
        #expect(await scripts.sources.isEmpty)
    }
}
