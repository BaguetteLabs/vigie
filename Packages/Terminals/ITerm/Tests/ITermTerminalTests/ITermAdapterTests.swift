import AgentKit
import Foundation
import Testing
import os

@testable import ITermTerminal

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
        http: NoHTTP(), log: Logger(subsystem: "fr.baguettelabs.vigie.tests", category: "iterm"))
}

let uuid = "6A1B3C2D-1111-4222-8333-944455556666"
let locator = TerminalLocator(terminalID: "iterm", fields: ["session_id": uuid, "tty": "/dev/ttys004"])

// MARK: - Tests

@Suite struct ITermAdapterTests {
    @Test func identity() {
        let adapter = ITermAdapter(scripts: FakeScripts(.success(nil)), activator: FakeActivator())
        #expect(adapter.id == "iterm")
        #expect(adapter.bundleIDs == ["com.googlecode.iterm2"])
        #expect(adapter.requiredPermissions == [.automation(bundleID: "com.googlecode.iterm2")])
        #expect(String(localized: adapter.name) == "iTerm2")
    }

    @Test func matchesSessionIDOrTermProgram() {
        let adapter = ITermAdapter()
        #expect(adapter.matches(env: ["ITERM_SESSION_ID": "w0t1p0:\(uuid)"]))
        #expect(adapter.matches(env: ["TERM_PROGRAM": "iTerm.app"]))
        #expect(!adapter.matches(env: ["TERM_PROGRAM": "Apple_Terminal"]))
        #expect(!adapter.matches(env: ["ITERM_SESSION_ID": ""]))
        #expect(!adapter.matches(env: [:]))
    }

    @Test func captureStoresSessionUUIDAndTTYWithoutScripts() async {
        let scripts = FakeScripts(.success("found"))
        let activator = FakeActivator()
        let adapter = ITermAdapter(scripts: scripts, activator: activator)

        let full = adapter.capture(env: ["ITERM_SESSION_ID": "w0t1p0:\(uuid)"], pid: 7, tty: "/dev/ttys004")
        #expect(full == locator)
        #expect(adapter.capture(env: ["ITERM_SESSION_ID": uuid], pid: nil, tty: nil)?.fields == ["session_id": uuid])
        #expect(
            adapter.capture(env: ["TERM_PROGRAM": "iTerm.app"], pid: nil, tty: "ttys009")?.fields
                == ["tty": "/dev/ttys009"])
        // Malformed ids never reach a script.
        #expect(adapter.capture(env: ["ITERM_SESSION_ID": "w0t0p0:x\" & quit"], pid: nil, tty: nil) == nil)
        #expect(adapter.capture(env: ["TERM_PROGRAM": "iTerm.app"], pid: nil, tty: "??") == nil)

        // Capture is pure: no Apple Events, no activation (AD-23).
        #expect(await scripts.sources.isEmpty)
        #expect(await activator.calls.isEmpty)
    }

    @Test func scriptSelectsWindowTabAndSessionByUniqueID() {
        let source = ITermAdapter.focusScript(.sessionID(uuid))
        #expect(source.contains("tell application id \"com.googlecode.iterm2\""))
        #expect(source.contains("unique ID of s is \"\(uuid)\""))
        #expect(source.contains("tell w to select"))
        #expect(source.contains("tell t to select"))
        #expect(source.contains("tell s to select"))
        #expect(source.contains("activate"))
        #expect(source.contains("is not running"))
        #expect(ITermAdapter.focusScript(.tty("/dev/ttys004")).contains("tty of s is \"/dev/ttys004\""))
    }

    @Test func foundSessionIsExactAndPrefersTheUUID() async {
        let scripts = FakeScripts(.success("found"))
        let activator = FakeActivator()
        let adapter = ITermAdapter(scripts: scripts, activator: activator)

        #expect(await adapter.focus(locator, context: makeContext()) == .exact)
        let sources = await scripts.sources
        #expect(sources.count == 1)
        #expect(sources.first?.contains(uuid) == true)
        #expect(sources.first?.contains("tty of s") == false)
        #expect(await activator.calls.isEmpty)
    }

    @Test func ttyIsUsedWithoutASessionID() async {
        let scripts = FakeScripts(.success("found"))
        let adapter = ITermAdapter(scripts: scripts, activator: FakeActivator())
        let byTTY = TerminalLocator(terminalID: "iterm", fields: ["tty": "/dev/ttys004"])
        #expect(await adapter.focus(byTTY, context: makeContext()) == .exact)
        #expect(await scripts.sources.first?.contains("tty of s is \"/dev/ttys004\"") == true)
    }

    @Test func goneSessionActivatesTheAppOnly() async {
        let activator = FakeActivator()
        let adapter = ITermAdapter(scripts: FakeScripts(.success("notfound")), activator: activator)
        #expect(await adapter.focus(locator, context: makeContext()) == .appOnly)
        #expect(await activator.calls.isEmpty)  // the script activated iTerm2 itself
    }

    @Test func notRunningOrOddOutputActivatesThroughWorkspace() async {
        for output in ["notrunning", nil, "weird"] as [String?] {
            let activator = FakeActivator()
            let adapter = ITermAdapter(scripts: FakeScripts(.success(output)), activator: activator)
            #expect(await adapter.focus(locator, context: makeContext()) == .appOnly)
            #expect(await activator.calls == [["com.googlecode.iterm2"]])
        }
    }

    @Test func permissionDeniedThrowsTypedErrorAfterActivating() async {
        let activator = FakeActivator()
        let adapter = ITermAdapter(
            scripts: FakeScripts(.failure(AppleScriptError(number: -1743, message: "Not authorized"))),
            activator: activator)

        await #expect(throws: TerminalFocusError.permissionRequired(.automation(bundleID: "com.googlecode.iterm2"))) {
            try await adapter.attemptFocus(locator, context: makeContext())
        }
        #expect(await activator.calls == [["com.googlecode.iterm2"]])
        #expect(await adapter.focus(locator, context: makeContext()) == .appOnly)
    }

    @Test func otherScriptErrorsFallBackToTheApp() async {
        let activator = FakeActivator()
        let adapter = ITermAdapter(
            scripts: FakeScripts(.failure(AppleScriptError(number: -2741, message: "Syntax"))), activator: activator)
        #expect((try? await adapter.attemptFocus(locator, context: makeContext())) == .appOnly)
        #expect(await activator.calls == [["com.googlecode.iterm2"]])
    }

    @Test func emptyLocatorSkipsTheScript() async {
        let scripts = FakeScripts(.success("found"))
        let adapter = ITermAdapter(scripts: scripts, activator: FakeActivator(available: false))
        let result = await adapter.focus(TerminalLocator(terminalID: "iterm", fields: [:]), context: makeContext())
        #expect(result == .failed(reason: "iTerm2 is not available"))
        #expect(await scripts.sources.isEmpty)
    }
}
