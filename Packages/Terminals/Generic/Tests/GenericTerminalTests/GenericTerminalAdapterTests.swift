import AgentKit
import Foundation
import Testing
import os

@testable import GenericTerminal

/// Records activations; `running` bundle ids and `apps` (pids with a regular app) succeed.
final class FakeWorkspace: TerminalWorkspace, @unchecked Sendable {
    private let lock = NSLock()
    private let running: Set<String>
    private let apps: Set<Int32>
    private var _calls: [String] = []

    init(running: Set<String> = [], apps: Set<Int32> = []) {
        self.running = running
        self.apps = apps
    }

    var calls: [String] { lock.withLock { _calls } }

    @MainActor func activateApp(bundleID: String) -> Bool {
        lock.withLock { _calls.append("bundle:\(bundleID)") }
        return running.contains(bundleID)
    }

    @MainActor func activateAncestorApp(of pid: Int32) -> Bool {
        lock.withLock { _calls.append("pid:\(pid)") }
        return apps.contains(pid)
    }
}

struct NoSecrets: SecretStore {
    func read(_ key: String) async throws -> String? { nil }
    func write(_ value: String?, for key: String) async throws {}
}

struct NoExecutables: ExecutableResolver {
    func resolve(_ name: String) async -> URL? { nil }
}

let context = AdapterContextBox(
    settings: DefaultsReadOnlySettings(descriptors: []), secrets: NoSecrets(), executables: NoExecutables(),
    http: URLSessionHTTPClient(), log: Logger(subsystem: "test", category: "generic"))

@Suite struct GenericTerminalAdapterTests {
    @Test func identity() {
        let adapter = GenericTerminalAdapter(workspace: FakeWorkspace())
        #expect(adapter.id == "generic")
        #expect(String(localized: adapter.name) == "Terminal app")
        #expect(adapter.bundleIDs.contains("com.apple.Terminal"))
        #expect(adapter.requiredPermissions.isEmpty)
    }

    @Test func capturesProgramBundleAndPid() throws {
        let adapter = GenericTerminalAdapter(workspace: FakeWorkspace())
        let locator = try #require(
            adapter.capture(
                env: ["TERM_PROGRAM": "ghostty", "__CFBundleIdentifier": "com.mitchellh.ghostty"], pid: 4242,
                tty: "/dev/ttys001"))
        #expect(locator.terminalID == "generic")
        #expect(locator.fields == ["program": "ghostty", "bundle_id": "com.mitchellh.ghostty", "pid": "4242"])
        #expect(adapter.capture(env: [:], pid: nil, tty: nil) == nil)
        #expect(adapter.capture(env: [:], pid: 7, tty: nil)?.fields == ["pid": "7"])
    }

    @Test func matchesAnyNamedTerminal() {
        let adapter = GenericTerminalAdapter(workspace: FakeWorkspace())
        #expect(adapter.matches(env: ["TERM_PROGRAM": "Tabby"]))
        #expect(adapter.matches(env: ["__CFBundleIdentifier": "org.alacritty"]))
        #expect(!adapter.matches(env: ["TERM_PROGRAM": "  "]))
    }

    @Test(arguments: [
        ("Apple_Terminal", "com.apple.Terminal"), ("iTerm.app", "com.googlecode.iterm2"),
        ("WarpTerminal", "dev.warp.Warp-Stable"), ("ghostty", "com.mitchellh.ghostty"),
        ("vscode", "com.microsoft.VSCode"),
    ])
    func focusActivatesTheKnownApp(program: String, bundleID: String) async {
        let workspace = FakeWorkspace(running: [bundleID])
        let adapter = GenericTerminalAdapter(workspace: workspace)
        let locator = TerminalLocator(terminalID: "generic", fields: ["program": program, "pid": "99"])
        #expect(await adapter.focus(locator, context: context) == .appOnly)
        #expect(workspace.calls == ["bundle:\(bundleID)"])
    }

    @Test func forwardedBundleIDWinsOverProgram() async {
        let workspace = FakeWorkspace(running: ["dev.warp.Warp-Preview"])
        let adapter = GenericTerminalAdapter(workspace: workspace)
        let locator = TerminalLocator(
            terminalID: "generic", fields: ["program": "WarpTerminal", "bundle_id": "dev.warp.Warp-Preview"])
        #expect(await adapter.focus(locator, context: context) == .appOnly)
        #expect(workspace.calls == ["bundle:dev.warp.Warp-Preview"])
    }

    @Test func unknownProgramFallsBackToTheAncestorApp() async {
        let workspace = FakeWorkspace(apps: [1234])
        let adapter = GenericTerminalAdapter(workspace: workspace)
        let locator = TerminalLocator(terminalID: "generic", fields: ["program": "Tabby", "pid": "1234"])
        #expect(await adapter.focus(locator, context: context) == .appOnly)
        #expect(workspace.calls == ["pid:1234"])
    }

    @Test func notRunningFallsThroughThenFails() async {
        let workspace = FakeWorkspace()
        let adapter = GenericTerminalAdapter(workspace: workspace)
        let locator = TerminalLocator(terminalID: "generic", fields: ["program": "ghostty", "pid": "55"])
        let result = await adapter.focus(locator, context: context)
        guard case .failed = result else {
            Issue.record("expected failed, got \(result)")
            return
        }
        #expect(workspace.calls == ["bundle:com.mitchellh.ghostty", "pid:55"])
    }

    /// Story 9.6: brings the first running known terminal forward; the command is left to the caller to copy.
    @Test func openTabActivatesARunningTerminal() async throws {
        let workspace = FakeWorkspace(running: ["com.googlecode.iterm2"])
        let adapter = GenericTerminalAdapter(workspace: workspace)
        #expect(!adapter.supportsTypedText)
        let outcome = try await adapter.openTab(argv: ["/bin/echo"], cwd: nil, typedText: nil, context: context)
        #expect(outcome == .commandNotRun)
        #expect(workspace.calls == ["bundle:com.apple.Terminal", "bundle:com.googlecode.iterm2"])
    }

    @Test func openTabWithNoTerminalStillAsksForTheCopy() async throws {
        let adapter = GenericTerminalAdapter(workspace: FakeWorkspace())
        let outcome = try await adapter.openTab(argv: ["/bin/echo"], cwd: nil, typedText: nil, context: context)
        #expect(outcome == .commandNotRun)
    }

    @Test func appNamesForTheTerminalColumn() {
        let adapter = GenericTerminalAdapter(workspace: FakeWorkspace())
        #expect(adapter.appName(env: ["TERM_PROGRAM": "WarpTerminal"]) == "Warp")
        #expect(adapter.appName(env: ["TERM_PROGRAM": "iTerm.app"]) == "iTerm2")
        #expect(adapter.appName(env: ["TERM_PROGRAM": "Apple_Terminal"]) == "Terminal")
        #expect(adapter.appName(env: ["TERM_PROGRAM": "ghostty"]) == "Ghostty")
        #expect(adapter.appName(env: ["__CFBundleIdentifier": "com.microsoft.VSCode"]) == "VS Code")
        #expect(adapter.appName(env: ["TERM_PROGRAM": "Tabby"]) == "Tabby")
        #expect(adapter.appName(env: [:]) == nil)
    }

    @Test func systemWorkspaceFindsOwnParent() {
        let parent = SystemTerminalWorkspace.parentPID(of: getpid())
        #expect(parent == getppid())
        #expect(SystemTerminalWorkspace.parentPID(of: 999_999) == nil)
    }
}
