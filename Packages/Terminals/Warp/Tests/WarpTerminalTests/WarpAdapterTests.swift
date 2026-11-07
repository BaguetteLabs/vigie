import AgentKit
import Foundation
import Testing
import os

@testable import WarpTerminal

// MARK: - Fakes

/// Records every system call; answers from fixed tables.
final class FakeSystem: URLOpening, WarpAppActivating, @unchecked Sendable {
    enum Call: Equatable {
        case open(URL)
        case activate(String)
        case launch(String)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    let openSucceeds: Bool
    let running: Set<String>
    let installed: Set<String>

    init(openSucceeds: Bool = true, running: Set<String> = [], installed: Set<String> = []) {
        self.openSucceeds = openSucceeds
        self.running = running
        self.installed = installed
    }

    var calls: [Call] { lock.withLock { _calls } }

    @MainActor func open(_ url: URL) -> Bool {
        lock.withLock { _calls.append(.open(url)) }
        return openSucceeds
    }

    @MainActor func activateRunning(bundleID: String) -> Bool {
        lock.withLock { _calls.append(.activate(bundleID)) }
        return running.contains(bundleID)
    }

    @MainActor func launch(bundleID: String) async -> Bool {
        lock.withLock { _calls.append(.launch(bundleID)) }
        return installed.contains(bundleID)
    }
}

struct NoSettings: ReadOnlySettings {
    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? { nil }
}

struct NoSecrets: SecretStore {
    func read(_ key: String) async throws -> String? { nil }
    func write(_ value: String?, for key: String) async throws {}
}

struct NoResolver: ExecutableResolver {
    func resolve(_ name: String) async -> URL? { nil }
}

struct NoHTTP: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

func makeContext() -> AdapterContextBox {
    AdapterContextBox(
        settings: NoSettings(), secrets: NoSecrets(), executables: NoResolver(), http: NoHTTP(),
        log: Logger(subsystem: "fr.baguettelabs.vigie.tests", category: "warp"))
}

let uuid = "dbb86f5d0ced4332a8feab247a908497"

/// The env a hook inherits inside a Warp tab (spike record, "Environment observed inside a Warp tab").
let warpEnv: [String: String] = [
    "TERM_PROGRAM": "WarpTerminal",
    "TERM_PROGRAM_VERSION": "v0.2026.10.14.08.27.stable_01",
    "WARP_CLIENT_VERSION": "v0.2026.10.14.08.27.stable_01",
    "__CFBundleIdentifier": "dev.warp.Warp-Stable",
    "WARP_TERMINAL_SESSION_UUID": uuid,
    "WARP_FOCUS_URL": "warp://session/\(uuid)",
    "TERM": "xterm-256color",
]

func locator(_ fields: [String: String]) -> TerminalLocator {
    TerminalLocator(terminalID: "warp", fields: fields)
}

// MARK: - matches / capture

@Suite struct MatchingTests {
    let adapter = WarpAdapter(urlOpener: FakeSystem(), activator: FakeSystem())

    @Test func matchesWarpEnv() {
        #expect(adapter.matches(env: warpEnv))
        #expect(adapter.matches(env: ["TERM_PROGRAM": "WarpTerminal"]))
        #expect(adapter.matches(env: ["WARP_FOCUS_URL": "warp://session/\(uuid)"]))
        #expect(adapter.matches(env: ["WARP_TERMINAL_SESSION_UUID": uuid]))
    }

    @Test func rejectsOtherTerminals() {
        #expect(!adapter.matches(env: [:]))
        #expect(!adapter.matches(env: ["TERM_PROGRAM": "Apple_Terminal", "TERM_SESSION_ID": "w0t0p0:ABC"]))
        #expect(!adapter.matches(env: ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t0p0:ABC"]))
        #expect(!adapter.matches(env: ["TERM_PROGRAM": "ghostty"]))
    }

    @Test func identity() {
        #expect(adapter.id == "warp")
        #expect(adapter.bundleIDs == ["dev.warp.Warp-Stable", "dev.warp.Warp", "dev.warp.Warp-Preview"])
        #expect(adapter.requiredPermissions.isEmpty)
        #expect(String(localized: adapter.name) == "Warp")
    }
}

@Suite struct CaptureTests {
    @Test func storesSpikeFieldsVerbatimWithoutIO() {
        let system = FakeSystem()
        let adapter = WarpAdapter(urlOpener: system, activator: system)
        let captured = adapter.capture(env: warpEnv, pid: 48474, tty: "/dev/ttys007")
        #expect(
            captured
                == locator([
                    "sessionUUID": uuid,
                    "focusURL": "warp://session/\(uuid)",
                    "bundleID": "dev.warp.Warp-Stable",
                    "tty": "/dev/ttys007",
                    "version": "v0.2026.10.14.08.27.stable_01",
                ]))
        #expect(system.calls.isEmpty)
    }

    @Test func isDeterministic() {
        let adapter = WarpAdapter(urlOpener: FakeSystem(), activator: FakeSystem())
        #expect(adapter.capture(env: warpEnv, pid: 1, tty: "t") == adapter.capture(env: warpEnv, pid: 1, tty: "t"))
    }

    @Test func strippedEnvKeepsBundleOnly() {
        let adapter = WarpAdapter(urlOpener: FakeSystem(), activator: FakeSystem())
        let captured = adapter.capture(env: ["TERM_PROGRAM": "WarpTerminal"], pid: nil, tty: nil)
        #expect(captured == locator(["bundleID": "dev.warp.Warp-Stable"]))
    }

    @Test func previewBundleIsKeptForeignBundleIsNot() {
        let adapter = WarpAdapter(urlOpener: FakeSystem(), activator: FakeSystem())
        var env = warpEnv
        env["__CFBundleIdentifier"] = "dev.warp.Warp-Preview"
        #expect(adapter.capture(env: env, pid: nil, tty: nil)?.fields["bundleID"] == "dev.warp.Warp-Preview")
        env["__CFBundleIdentifier"] = "com.apple.Terminal"
        #expect(adapter.capture(env: env, pid: nil, tty: nil)?.fields["bundleID"] == "dev.warp.Warp-Stable")
    }

    @Test func nonWarpEnvCapturesNothing() {
        let adapter = WarpAdapter(urlOpener: FakeSystem(), activator: FakeSystem())
        #expect(adapter.capture(env: ["TERM_PROGRAM": "Apple_Terminal"], pid: 1, tty: "/dev/ttys001") == nil)
    }
}

// MARK: - focus

@Suite struct FocusTests {
    @Test func opensFocusURLVerbatimThenActivatesWarp() async {
        let system = FakeSystem(running: ["dev.warp.Warp-Stable"])
        let adapter = WarpAdapter(urlOpener: system, activator: system, decision: .tabViaURL)
        let captured = adapter.capture(env: warpEnv, pid: nil, tty: nil)!
        let result = await adapter.focus(captured, context: makeContext())
        #expect(result == .exact)
        #expect(
            system.calls == [.open(URL(string: "warp://session/\(uuid)")!), .activate("dev.warp.Warp-Stable")])
    }

    @Test func urlOpenedWhileWarpNotRunningStillExact() async {
        let system = FakeSystem()
        let adapter = WarpAdapter(urlOpener: system, activator: system, decision: .tabViaURL)
        let result = await adapter.focus(
            locator(["focusURL": "warp://session/\(uuid)", "bundleID": "dev.warp.Warp-Stable"]),
            context: makeContext())
        #expect(result == .exact)
        #expect(!system.calls.contains { if case .launch = $0 { true } else { false } })
    }

    @Test func buildsURLFromUUIDWhenFocusURLMissing() async {
        let system = FakeSystem(running: ["dev.warp.Warp-Preview"])
        let adapter = WarpAdapter(urlOpener: system, activator: system, decision: .tabViaURL)
        _ = await adapter.focus(
            locator(["sessionUUID": uuid, "bundleID": "dev.warp.Warp-Preview"]), context: makeContext())
        #expect(system.calls.first == .open(URL(string: "warppreview://session/\(uuid)")!))
        #expect(system.calls.dropFirst().first == .activate("dev.warp.Warp-Preview"))
    }

    @Test(arguments: [
        "warp://action/new_tab?path=/tmp",
        "warp://session/not-a-uuid",
        "warp://session/\(uuid)?x=1",
        "https://session/\(uuid)",
        "warp://other/\(uuid)",
        "",
    ])
    func invalidFocusURLFallsBackToApp(raw: String) async {
        let system = FakeSystem(running: ["dev.warp.Warp-Stable"])
        let adapter = WarpAdapter(urlOpener: system, activator: system, decision: .tabViaURL)
        let result = await adapter.focus(
            locator(["focusURL": raw, "bundleID": "dev.warp.Warp-Stable"]), context: makeContext())
        #expect(result == .appOnly)
        #expect(system.calls == [.activate("dev.warp.Warp-Stable")])
    }

    @Test func missingURLActivatesAppOnly() async {
        let system = FakeSystem(running: ["dev.warp.Warp-Stable"])
        let adapter = WarpAdapter(urlOpener: system, activator: system, decision: .tabViaURL)
        let result = await adapter.focus(locator(["bundleID": "dev.warp.Warp-Stable"]), context: makeContext())
        #expect(result == .appOnly)
        #expect(system.calls == [.activate("dev.warp.Warp-Stable")])
    }

    @Test func refusedOpenFallsBackToApp() async {
        let system = FakeSystem(openSucceeds: false, running: ["dev.warp.Warp-Stable"])
        let adapter = WarpAdapter(urlOpener: system, activator: system, decision: .tabViaURL)
        let result = await adapter.focus(adapter.capture(env: warpEnv, pid: nil, tty: nil)!, context: makeContext())
        #expect(result == .appOnly)
        #expect(
            system.calls == [.open(URL(string: "warp://session/\(uuid)")!), .activate("dev.warp.Warp-Stable")])
    }

    @Test func appLevelDecisionNeverOpensURL() async {
        let system = FakeSystem(running: ["dev.warp.Warp-Stable"])
        let adapter = WarpAdapter(urlOpener: system, activator: system, decision: .appLevelOnly)
        let result = await adapter.focus(adapter.capture(env: warpEnv, pid: nil, tty: nil)!, context: makeContext())
        #expect(result == .appOnly)
        #expect(system.calls == [.activate("dev.warp.Warp-Stable")])
    }

    @Test func warpNotRunningIsLaunched() async {
        let system = FakeSystem(installed: ["dev.warp.Warp-Stable"])
        let adapter = WarpAdapter(urlOpener: system, activator: system, decision: .appLevelOnly)
        let result = await adapter.focus(locator(["bundleID": "dev.warp.Warp-Stable"]), context: makeContext())
        #expect(result == .appOnly)
        #expect(
            system.calls == [
                .activate("dev.warp.Warp-Stable"), .activate("dev.warp.Warp"), .activate("dev.warp.Warp-Preview"),
                .launch("dev.warp.Warp-Stable"),
            ])
    }

    @Test func otherChannelRunningIsActivated() async {
        let system = FakeSystem(running: ["dev.warp.Warp"])
        let adapter = WarpAdapter(urlOpener: system, activator: system)
        let result = await adapter.focus(locator([:]), context: makeContext())
        #expect(result == .appOnly)
        #expect(system.calls == [.activate("dev.warp.Warp-Stable"), .activate("dev.warp.Warp")])
    }

    @Test func notInstalledFails() async {
        let system = FakeSystem()
        let adapter = WarpAdapter(urlOpener: system, activator: system, decision: .appLevelOnly)
        let result = await adapter.focus(locator([:]), context: makeContext())
        guard case .failed = result else {
            Issue.record("expected .failed, got \(result)")
            return
        }
        #expect(system.calls.filter { if case .launch = $0 { true } else { false } }.count == 3)
    }

    @Test func openTabIsUnsupported() async {
        let adapter = WarpAdapter(urlOpener: FakeSystem(), activator: FakeSystem())
        await #expect(throws: AdapterError.notSupported) {
            try await adapter.openTab(argv: ["/bin/echo"], cwd: nil, context: makeContext())
        }
    }
}

// MARK: - helpers and decision

@Suite struct DecisionTests {
    @Test func shippedDecision() {
        #expect(WarpAdapter.decision == .tabViaURL)
        #expect(!WarpAdapter.decisionConfirmed)
        #expect(String(localized: WarpAdapter.focusLevelStatement) == "Warp: tab focus via session URL (unverified)")
    }

    @Test func statements() {
        #expect(
            String(localized: WarpAdapter.statement(decision: .tabViaURL, confirmed: true))
                == "Warp: tab focus via session URL")
        #expect(
            String(localized: WarpAdapter.statement(decision: .appLevelOnly, confirmed: false))
                == "Warp: app-level focus only")
    }

    @Test func activationOrderPutsCapturedFirst() {
        #expect(
            WarpAdapter.activationOrder(preferred: "dev.warp.Warp-Preview")
                == ["dev.warp.Warp-Preview", "dev.warp.Warp-Stable", "dev.warp.Warp"])
        #expect(WarpAdapter.activationOrder(preferred: "com.example") == WarpAdapter.bundleIDCandidates)
        #expect(WarpAdapter.activationOrder(preferred: nil) == WarpAdapter.bundleIDCandidates)
    }

    @Test func uuidValidation() {
        #expect(WarpAdapter.isSessionUUID(uuid))
        #expect(WarpAdapter.isSessionUUID(uuid.uppercased()))
        #expect(!WarpAdapter.isSessionUUID(String(uuid.dropLast())))
        #expect(!WarpAdapter.isSessionUUID(String(uuid.dropLast()) + "g"))
        #expect(!WarpAdapter.isSessionUUID("dbb86f5d-0ced-4332-a8fe-ab247a908497"))
    }

    @Test func adapterListAcceptsWarp() {
        let list = TerminalAdapters([WarpAdapter(urlOpener: FakeSystem(), activator: FakeSystem())])
        #expect(list.matching(env: warpEnv)?.id == "warp")
        #expect(list.matching(env: ["TERM_PROGRAM": "Apple_Terminal"]) == nil)
    }
}
