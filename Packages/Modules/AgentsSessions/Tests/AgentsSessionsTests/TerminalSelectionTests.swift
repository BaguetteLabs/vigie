import AgentKit
import Foundation
import ModuleKit
import Testing
import VigieUI
import os

@testable import AgentsSessions

/// Counts `capture` and `focus` calls; `attemptFocus` returns or throws what `outcomes` says, in order (the last
/// one repeats).
final class CountingTerminal: PermissionReportingTerminalAdapter, @unchecked Sendable {
    enum Outcome {
        case result(FocusResult)
        case permission(Permission)
    }

    let id: TerminalID
    let program: String?
    private let lock = NSLock()
    private var outcomes: [Outcome]
    private var _captures = 0
    private var _focused: [TerminalLocator] = []

    init(id: TerminalID, program: String?, outcomes: [Outcome] = [.result(.exact)]) {
        self.id = id
        self.program = program
        self.outcomes = outcomes
    }

    var captures: Int { lock.withLock { _captures } }
    var focused: [TerminalLocator] { lock.withLock { _focused } }
    var name: LocalizedStringResource { LocalizedStringResource(stringLiteral: "Term \(id.rawValue)") }
    var bundleIDs: [String] { [] }
    var requiredPermissions: Set<Permission> { [.automation(bundleID: "com.example.\(id.rawValue)")] }

    func matches(env: [String: String]) -> Bool { program != nil && env["TERM_PROGRAM"] == program }

    func capture(env: [String: String], pid: Int32?, tty: String?) -> TerminalLocator? {
        lock.withLock { _captures += 1 }
        var fields = ["program": env["TERM_PROGRAM"] ?? ""]
        if let tty { fields["tty"] = tty }
        return TerminalLocator(terminalID: id, fields: fields)
    }

    func attemptFocus(_ locator: TerminalLocator, context: any AdapterContext) async throws(TerminalFocusError)
        -> FocusResult
    {
        let outcome = lock.withLock {
            _focused.append(locator)
            return outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0]
        }
        switch outcome {
        case .result(let result): return result
        case .permission(let permission): throw .permissionRequired(permission)
        }
    }
}

struct DeniedPermissions: PermissionsService {
    let denied: Set<Permission>
    func status(of permission: Permission) async -> PermissionStatus {
        denied.contains(permission) ? .denied : .granted
    }
    func request(_ permission: Permission) async -> PermissionStatus { await status(of: permission) }
}

@MainActor @Suite struct TerminalSelectionTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let key = SessionKey(agentID: "fake", sessionID: "a")

    struct Setup {
        let module: AgentsSessionsModule
        let iterm: CountingTerminal
        let apple: CountingTerminal
        let fallback: CountingTerminal
        let notifier: RecordingNotifier
    }

    static func setup(
        terminalSetting: String? = nil, iterm: [CountingTerminal.Outcome] = [.result(.exact)]
    ) -> Setup {
        let itermAdapter = CountingTerminal(id: "iterm", program: "iTerm.app", outcomes: iterm)
        let apple = CountingTerminal(id: "terminal", program: "Apple_Terminal")
        let fallback = CountingTerminal(id: "generic", program: nil, outcomes: [.result(.appOnly)])
        let module = AgentsSessionsModule(
            adapters: AgentAdapters([FakeAdapter()]),
            terminals: TerminalAdapters([itermAdapter, apple], fallback: fallback), liveness: FakeLiveness())
        var values: [String: any SettingValue] = [:]
        if let terminalSetting { values["terminal"] = terminalSetting }
        module.settings = FakeSettings(values: values)
        let notifier = RecordingNotifier()
        module.notifier = notifier
        module.fallbackTerminalContext = AdapterContextBox(
            settings: DefaultsReadOnlySettings(descriptors: []), secrets: NoSecrets(), executables: NoExecutables(),
            http: URLSessionHTTPClient(), log: Logger(subsystem: "test", category: "selection"))
        return Setup(module: module, iterm: itermAdapter, apple: apple, fallback: fallback, notifier: notifier)
    }

    static func context(
        _ id: String = "a", program: String?, bundleID: String? = nil, at: Date = now
    ) -> AgentEventContext {
        let hint: TerminalHint? =
            program == nil && bundleID == nil
            ? nil : TerminalHint(program: program, sessionID: nil, warpFocusURL: nil, bundleID: bundleID)
        return AgentEventContext(
            sessionKey: SessionKey(agentID: "fake", sessionID: id),
            cwd: URL(fileURLWithPath: "/Users/me/www/\(id)"), tty: "/dev/ttys004", terminal: hint,
            agentProcess: nil, at: at)
    }

    // MARK: Selection

    @Test func selectsByMatchesAndCapturesOnce() async {
        let setup = Self.setup()
        let t = Self.now
        setup.module.apply(
            [
                .sessionStart(Self.context(program: "iTerm.app", at: t), model: nil),
                .promptSubmit(Self.context(program: "iTerm.app", at: t + 1)),
                .toolStart(Self.context(program: "iTerm.app", at: t + 2), tool: "Edit"),
                .turnEnd(Self.context(program: "iTerm.app", at: t + 3)),
            ], now: t + 3)
        let session = setup.module.store.table[Self.key]
        #expect(session?.terminalAdapterID == "iterm")
        #expect(
            session?.terminalLocator
                == TerminalLocator(
                    terminalID: "iterm", fields: ["program": "iTerm.app", "tty": "/dev/ttys004"]))
        #expect(setup.iterm.captures == 1, "capture runs once per session")
        #expect(setup.iterm.focused.isEmpty, "no focus (Apple Events) until the user asks")
        #expect(setup.apple.captures == 0 && setup.fallback.captures == 0)

        _ = await setup.module.focus(Self.key)
        _ = await setup.module.focus(Self.key)
        #expect(setup.iterm.captures == 1, "focus uses the stored locator")
        #expect(setup.iterm.focused == [session?.terminalLocator, session?.terminalLocator].compactMap { $0 })
    }

    @Test func envWithoutTerminalUsesTheTerminalSetting() {
        let setup = Self.setup(terminalSetting: "iterm")
        setup.module.apply([.sessionStart(Self.context(program: nil), model: nil)], now: Self.now)
        #expect(setup.module.store.table[Self.key]?.terminalAdapterID == "iterm")

        let defaulted = Self.setup()
        defaulted.module.apply([.sessionStart(Self.context(program: nil), model: nil)], now: Self.now)
        #expect(defaulted.module.store.table[Self.key]?.terminalAdapterID == "terminal", "default `terminal`")
    }

    @Test func unmatchedTerminalUsesTheFallback() {
        let setup = Self.setup(terminalSetting: "iterm")
        setup.module.apply([.sessionStart(Self.context(program: "ghostty"), model: nil)], now: Self.now)
        #expect(setup.module.store.table[Self.key]?.terminalAdapterID == "generic")
        #expect(setup.fallback.captures == 1)

        let unknownSetting = Self.setup(terminalSetting: "kitty")
        unknownSetting.module.apply([.sessionStart(Self.context(program: nil), model: nil)], now: Self.now)
        #expect(unknownSetting.module.store.table[Self.key]?.terminalAdapterID == "generic")
    }

    @Test func envArrivingLaterChoosesAgainOnce() {
        let setup = Self.setup()
        let t = Self.now
        let persisted = setup.module.apply([.sessionStart(Self.context(program: nil, at: t), model: nil)], now: t)
        #expect(persisted != nil)
        #expect(setup.module.store.table[Self.key]?.terminalAdapterID == "terminal")
        let again = setup.module.apply([.promptSubmit(Self.context(program: "iTerm.app", at: t + 1))], now: t + 1)
        #expect(again != nil)
        setup.module.apply([.toolStart(Self.context(program: "iTerm.app", at: t + 2), tool: "Bash")], now: t + 2)
        #expect(setup.module.store.table[Self.key]?.terminalAdapterID == "iterm")
        #expect(setup.apple.captures == 1)
        #expect(setup.iterm.captures == 1)
    }

    @Test func locatorPersistsThroughSessionsJSON() async throws {
        let setup = Self.setup()
        setup.module.apply([.sessionStart(Self.context(program: "iTerm.app"), model: nil)], now: Self.now)
        let storage = FakeStorage()
        try await storage.writeJSON(setup.module.store.snapshot, name: "sessions", schema: 1)

        let reloaded = Self.setup()
        let context = FakeModuleContext(storage: storage)
        try await reloaded.module.start(context: context)
        let session = reloaded.module.store.table[Self.key]
        #expect(session?.terminalAdapterID == "iterm")
        #expect(session?.terminalLocator == setup.module.store.table[Self.key]?.terminalLocator)
        #expect(reloaded.iterm.captures == 0, "a reloaded session keeps its locator")
        await reloaded.module.stop()
    }

    @Test func olderSessionsGetATerminalAtLoad() async throws {
        let old = Session(
            key: Self.key, status: .idle, statusSince: Self.now, lastEventAt: Self.now, tty: "/dev/ttys009",
            terminal: TerminalHint(program: "Apple_Terminal", sessionID: nil, warpFocusURL: nil, bundleID: nil))
        let storage = FakeStorage()
        try await storage.writeJSON([old], name: "sessions", schema: 1)
        let setup = Self.setup()
        try await setup.module.start(context: FakeModuleContext(storage: storage))
        #expect(setup.module.store.table[Self.key]?.terminalAdapterID == "terminal")
        #expect(setup.apple.captures == 1)
        let saved = try FakeStorage.decoder.decode(StateFile<[Session]>.self, from: storage.data("sessions") ?? Data())
        #expect(saved.value.first?.terminalLocator?.fields["tty"] == "/dev/ttys009")
        await setup.module.stop()
    }

    @Test func focusChoosesAgainWhenTheStoredAdapterIsGone() async {
        let stale = Session(
            key: Self.key, status: .idle, statusSince: Self.now, lastEventAt: Self.now, tty: "/dev/ttys009",
            terminal: TerminalHint(program: "iTerm.app", sessionID: nil, warpFocusURL: nil, bundleID: nil),
            terminalAdapterID: "kitty", terminalLocator: TerminalLocator(terminalID: "kitty", fields: [:]))
        let setup = Self.setup()
        setup.module.store.load([stale])
        #expect(await setup.module.focus(Self.key) == .exact)
        #expect(setup.module.store.table[Self.key]?.terminalAdapterID == "iterm")
        #expect(setup.iterm.focused.first?.fields["tty"] == "/dev/ttys009")
    }

    // MARK: Focus and permissions

    @Test func missingPermissionPostsOneSetupProblem() async throws {
        let automation = Permission.automation(bundleID: "com.example.iterm")
        let setup = Self.setup(iterm: [.permission(automation), .permission(automation), .result(.exact)])
        setup.module.apply(
            [.needsInput(Self.context(program: "iTerm.app"), reason: .permissionPrompt)], now: Self.now)
        let before = setup.module.store.table
        let alertsBefore = setup.notifier.events.count

        #expect(await setup.module.focus(Self.key) == .appOnly)
        #expect(await setup.module.focus(Self.key) == .appOnly)
        let posted = setup.notifier.events.dropFirst(alertsBefore).filter { $0.kind == "setup.problem" }
        #expect(posted.count == 1, "deduped while open")
        let event = try #require(posted.first)
        #expect(event.category == "PERMISSION")
        #expect(event.title == "Focus needs the Automation permission for Term iterm")
        #expect(event.body?.isEmpty == false)
        #expect(event.action == .openSettings(pane: "agents.sessions"))
        #expect(event.dedupeKey == "permission:iterm:automation:com.example.iterm")
        #expect(event.severity == .warn)
        #expect(setup.module.store.table == before, "Focus never changes session state")
        #expect(setup.notifier.openKinds.contains("setup.problem"))

        #expect(await setup.module.focus(Self.key) == .exact)
        #expect(!setup.notifier.openKinds.contains("setup.problem"), "resolved once focus goes through")
    }

    @Test func accessibilityVariantTitle() {
        let event = AgentsSessionsModule.permissionEvent(
            .accessibility, adapter: CountingTerminal(id: "warp", program: "WarpTerminal"))
        #expect(event.title == "Focus needs the Accessibility permission for Term warp")
        #expect(event.dedupeKey == "permission:warp:accessibility")
    }

    @Test func otherFailuresFallBackWithoutAlert() async {
        let setup = Self.setup(iterm: [.result(.appOnly)])
        setup.module.apply([.promptSubmit(Self.context(program: "iTerm.app"))], now: Self.now)
        let before = setup.module.store.table
        #expect(await setup.module.focus(Self.key) == .appOnly)
        #expect(setup.notifier.events.allSatisfy { $0.kind != "setup.problem" })
        #expect(setup.module.store.table == before)
    }

    @Test func manifestDeclaresSetupProblem() {
        #expect(AgentsSessionsModule.staticManifest.alertKinds.contains("setup.problem"))
    }

    @Test func permissionIssuesForTerminalsInUse() async {
        let setup = Self.setup()
        setup.module.permissions = DeniedPermissions(denied: [
            .automation(bundleID: "com.example.iterm"), .automation(bundleID: "com.example.terminal"),
        ])
        #expect(await setup.module.focusPermissionIssues().isEmpty, "no session, nothing in use")
        setup.module.apply([.promptSubmit(Self.context(program: "iTerm.app"))], now: Self.now)
        #expect(await setup.module.focusPermissionIssues() == ["iterm": [.automation(bundleID: "com.example.iterm")]])
    }
}
