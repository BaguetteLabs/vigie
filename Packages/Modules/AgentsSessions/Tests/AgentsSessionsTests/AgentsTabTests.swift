import AgentKit
import Foundation
import ModuleKit
import Testing
import VigieUI
import os

@testable import AgentsSessions

/// Records focus calls; `result` is what it returns.
final class FakeTerminal: TerminalAdapter, TerminalAppNaming, @unchecked Sendable {
    let id: TerminalID
    let program: String?
    let appName: String
    let result: FocusResult
    private let lock = NSLock()
    private var _focused: [TerminalLocator] = []

    init(id: TerminalID, program: String?, appName: String, result: FocusResult = .appOnly) {
        self.id = id
        self.program = program
        self.appName = appName
        self.result = result
    }

    var focused: [TerminalLocator] { lock.withLock { _focused } }
    var name: LocalizedStringResource { LocalizedStringResource(stringLiteral: appName) }
    var bundleIDs: [String] { [] }

    /// nil `program`: the fallback, matches nothing on its own.
    func matches(env: [String: String]) -> Bool { program != nil && env["TERM_PROGRAM"] == program }

    func capture(env: [String: String], pid: Int32?, tty: String?) -> TerminalLocator? {
        var fields = ["program": env["TERM_PROGRAM"] ?? ""]
        if let pid { fields["pid"] = String(pid) }
        return TerminalLocator(terminalID: id, fields: fields)
    }

    func focus(_ locator: TerminalLocator, context: any AdapterContext) async -> FocusResult {
        lock.withLock { _focused.append(locator) }
        return result
    }

    func appName(env: [String: String]) -> String? {
        program == nil ? env["TERM_PROGRAM"].map { "App(\($0))" } : nil
    }
}

final class RecordingActivity: ActivityLog, @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [ActivityEntry] = []
    var entries: [ActivityEntry] { lock.withLock { _entries } }
    func record(_ entry: ActivityEntry) { lock.withLock { _entries.append(entry) } }
}

@MainActor @Suite struct AgentsTabTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func context(
        _ id: String, program: String? = "WarpTerminal", pid: Int32? = nil, at: Date = now
    ) -> AgentEventContext {
        AgentEventContext(
            sessionKey: SessionKey(agentID: "fake", sessionID: id),
            cwd: URL(fileURLWithPath: "/Users/me/www/\(id)"),
            tty: "/dev/ttys00\(id.count)",
            terminal: program.map {
                TerminalHint(program: $0, sessionID: nil, warpFocusURL: nil, bundleID: nil)
            },
            agentProcess: pid.map { AgentProcessRef(pid: $0, startTime: nil) },
            at: at)
    }

    struct Setup {
        let module: AgentsSessionsModule
        let warp: FakeTerminal
        let fallback: FakeTerminal
        let activity: RecordingActivity
    }

    static func setup(adapters: [any AgentAdapter] = [FakeAdapter()], opened: OpenedPanes? = nil) -> Setup {
        let warp = FakeTerminal(id: "warp", program: "WarpTerminal", appName: "Warp", result: .exact)
        let fallback = FakeTerminal(id: "generic", program: nil, appName: "Terminal app")
        var open: (@MainActor @Sendable (String) -> Void)?
        if let opened {
            open = { pane in opened.panes.append(pane) }
        }
        let module = AgentsSessionsModule(
            adapters: AgentAdapters(adapters), terminals: TerminalAdapters([warp], fallback: fallback),
            liveness: FakeLiveness(), openSettings: open)
        let activity = RecordingActivity()
        module.activity = activity
        module.fallbackTerminalContext = AdapterContextBox(
            settings: DefaultsReadOnlySettings(descriptors: []), secrets: NoSecrets(), executables: NoExecutables(),
            http: URLSessionHTTPClient(), log: Logger(subsystem: "test", category: "tab"))
        return Setup(module: module, warp: warp, fallback: fallback, activity: activity)
    }

    @MainActor final class OpenedPanes {
        var panes: [String] = []
    }

    // MARK: Rows

    @Test func rowsMapSessionsInUrgencyOrder() {
        let setup = Self.setup()
        let module = setup.module
        module.apply(
            [
                .toolStart(Self.context("api", at: Self.now - 360), tool: "Edit"),
                .needsInput(Self.context("vigie", program: "ghostty", at: Self.now - 720), reason: .permissionPrompt),
            ], now: Self.now)
        let snapshot = module.tabSnapshot(now: Self.now)
        #expect(snapshot.empty == nil)
        #expect(snapshot.rows.map(\.id) == ["fake:vigie", "fake:api"])
        let blocked = snapshot.rows[0]
        #expect(blocked.glyphStatus == .blocked)
        #expect(blocked.agentName == "Fake")
        #expect(blocked.project == "vigie")
        #expect(blocked.terminalName == "App(ghostty)")
        #expect(blocked.statusLabel == "BLOCKED · 12M")
        #expect(blocked.isAlert)
        #expect(!blocked.canDismiss)
        #expect(blocked.accessibilityLabel.hasPrefix("vigie, blocked"))
        let working = snapshot.rows[1]
        #expect(working.lastAction == "Edit")
        #expect(working.terminalName == "Warp")
        #expect(working.statusLabel == "WORKING · 6M")
        #expect(snapshot.header == "SESSIONS · 2 · 1 ALERT")
        #expect(snapshot.showsTerminalColumn)
    }

    @Test func terminalColumnHiddenForOneApp() {
        let module = Self.setup().module
        module.apply(
            [
                .promptSubmit(Self.context("a")), .promptSubmit(Self.context("b")),
                .promptSubmit(Self.context("c", program: nil)),
            ],
            now: Self.now)
        let snapshot = module.tabSnapshot(now: Self.now)
        #expect(snapshot.rows.count == 3)
        #expect(!snapshot.showsTerminalColumn)
        #expect(snapshot.rows.first { $0.id == "fake:c" }?.terminalName == nil)
    }

    @Test func staleRowsTickWithTheClock() {
        let module = Self.setup().module
        module.apply([.toolStart(Self.context("a", at: Self.now), tool: "Bash")], now: Self.now)
        let later = Self.now + 18 * 60
        let row = module.tabSnapshot(now: later).rows[0]
        #expect(row.glyphStatus == .stale)
        #expect(row.statusLabel == "STALE · 18M")
    }

    @Test func failedRowShowsTheMessage() {
        let module = Self.setup().module
        module.apply([.sessionError(Self.context("a"), message: "Login required")], now: Self.now)
        #expect(module.tabSnapshot(now: Self.now).rows[0].lastAction == "Login required")
    }

    // MARK: Empty states

    @Test func emptyStates() {
        #expect(Self.setup(adapters: []).module.tabSnapshot(now: Self.now).empty == .noAgentConnected)
        #expect(Self.setup().module.tabSnapshot(now: Self.now).empty == .noActiveSessions)
        #expect(Self.setup().module.expandedView() != nil)
    }

    @Test func noAgentButtonOpensAgentsSettings() {
        let opened = OpenedPanes()
        let module = Self.setup(adapters: [], opened: opened).module
        module.openSettings?(AgentsSessionsModule.settingsPane)
        #expect(opened.panes == ["agents.sessions"])
    }

    // MARK: Focus

    @Test func focusUsesTheMatchingAdapter() async {
        let setup = Self.setup()
        setup.module.apply([.promptSubmit(Self.context("a", pid: 4242))], now: Self.now)
        let before = setup.module.store.table
        let result = await setup.module.focus(SessionKey(agentID: "fake", sessionID: "a"))
        #expect(result == .exact)
        #expect(setup.warp.focused.map(\.fields) == [["program": "WarpTerminal", "pid": "4242"]])
        #expect(setup.fallback.focused.isEmpty)
        #expect(setup.module.store.table == before, "Focus never changes session state")
        #expect(setup.activity.entries.map(\.outcome) == [.focusExact])
        #expect(setup.activity.entries.first?.adapter == "warp")
        #expect(setup.activity.entries.first?.category == .focus)
    }

    @Test func focusFallsBackToTheGenericAdapter() async {
        let setup = Self.setup()
        setup.module.apply(
            [.promptSubmit(Self.context("a", program: "ghostty")), .promptSubmit(Self.context("b", program: nil))],
            now: Self.now)
        #expect(await setup.module.focus(SessionKey(agentID: "fake", sessionID: "a")) == .appOnly)
        #expect(await setup.module.focus(SessionKey(agentID: "fake", sessionID: "b")) == .appOnly)
        #expect(setup.warp.focused.isEmpty)
        #expect(setup.fallback.focused.map { $0.fields["program"] } == ["ghostty", ""])
        #expect(setup.activity.entries.map(\.adapter) == ["generic", "generic"])
    }

    @Test func focusWithoutAdapterFails() async {
        let module = AgentsSessionsModule(
            adapters: AgentAdapters([FakeAdapter()]), terminals: TerminalAdapters([]), liveness: FakeLiveness())
        module.apply([.promptSubmit(Self.context("a"))], now: Self.now)
        guard case .failed = await module.focus(SessionKey(agentID: "fake", sessionID: "a")) else {
            Issue.record("expected failed")
            return
        }
        guard case .failed = await module.focus(SessionKey(agentID: "fake", sessionID: "zzz")) else {
            Issue.record("expected failed")
            return
        }
    }

    // MARK: Dismiss

    @Test func dismissOnlyForFailedWhoseProcessEnded() async {
        let setup = Self.setup()
        let module = setup.module
        let process = AgentProcessRef(pid: 77, startTime: nil)
        module.apply(
            [
                .sessionError(Self.context("a", pid: 77), message: "Login required"),
                .sessionError(Self.context("b"), message: "x"),
                .needsInput(Self.context("c", pid: 78), reason: .question),
            ], now: Self.now)
        let a = SessionKey(agentID: "fake", sessionID: "a")
        #expect(!module.canDismiss(a), "process still alive")
        #expect(module.canDismiss(SessionKey(agentID: "fake", sessionID: "b")), "no tracked process")
        #expect(!module.canDismiss(SessionKey(agentID: "fake", sessionID: "c")), "not failed")

        module.reconcile(now: Self.now, dead: [a: process])
        #expect(module.canDismiss(a))
        #expect(module.tabSnapshot(now: Self.now).rows.first { $0.id == "fake:a" }?.canDismiss == true)
        #expect(await module.dismiss(a))
        #expect(module.store.table[a] == nil)
        #expect(!module.endedProcesses.contains(a) || module.store.table[a] == nil)
    }
}
