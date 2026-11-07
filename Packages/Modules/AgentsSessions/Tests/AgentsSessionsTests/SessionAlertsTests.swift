import AgentKit
import Foundation
import ModuleKit
import Testing
import VigieUI
import os

@testable import AgentsSessions

/// Records posted events and which handles were resolved.
final class RecordingNotifier: Notifier, @unchecked Sendable {
    private let lock = NSLock()
    private var _posted: [(id: UUID, event: NotifierEvent)] = []
    private var _resolved: [UUID] = []

    var events: [NotifierEvent] { lock.withLock { _posted.map(\.event) } }
    /// Kinds of the posted alerts still open.
    var openKinds: [String] {
        lock.withLock { _posted.filter { !_resolved.contains($0.id) }.map(\.event.kind) }
    }
    var resolvedCount: Int { lock.withLock { _resolved.count } }

    func post(_ event: NotifierEvent) -> AlertHandle {
        let id = UUID()
        lock.withLock { _posted.append((id, event)) }
        return AlertHandle(id: id) { [weak self] in
            guard let self else { return }
            self.lock.withLock { self._resolved.append(id) }
        }
    }
}

@MainActor @Suite struct SessionAlertsTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let key = SessionKey(agentID: "fake", sessionID: "a")

    static func context(_ at: Date, id: String = "a", pid: Int32? = nil) -> AgentEventContext {
        AgentEventContext(
            sessionKey: SessionKey(agentID: "fake", sessionID: id), cwd: URL(fileURLWithPath: "/Users/me/www/vigie"),
            terminal: TerminalHint(program: "WarpTerminal", sessionID: nil, warpFocusURL: nil, bundleID: nil),
            agentProcess: pid.map { AgentProcessRef(pid: $0, startTime: nil) }, at: at)
    }

    func makeModule() -> (AgentsSessionsModule, RecordingNotifier, AgentsTabTests.Setup) {
        let setup = AgentsTabTests.setup()
        let notifier = RecordingNotifier()
        setup.module.notifier = notifier
        return (setup.module, notifier, setup)
    }

    @Test func manifestDeclaresItsKinds() {
        let kinds = AgentsSessionsModule.staticManifest.alertKinds
        #expect(kinds == ["session.blocked", "session.done", "session.failed", "setup.problem"])
        for kind in AgentsSessionsModule.AlertKind.allCases {
            #expect(!String(localized: kind.label).hasPrefix("agentsSessions."), "\(kind) label in catalog")
        }
        #expect(String(localized: AgentsSessionsModule.AlertKind.done.label) == "Finished session")
    }

    @Test func blockedPostsOnceWithCopyDedupeAndAction() throws {
        let (module, notifier, _) = makeModule()
        let t = Self.now
        module.apply([.promptSubmit(Self.context(t)), .toolStart(Self.context(t + 1), tool: "Bash")], now: t + 1)
        #expect(notifier.events.isEmpty)
        module.apply(
            [.needsInput(Self.context(t + 2), reason: .permissionPrompt, message: "Claude needs your permission")],
            now: t + 2)
        // A heartbeat while blocked does not re-post.
        module.apply(
            [.needsInput(Self.context(t + 3), reason: .permissionPrompt, message: "Claude needs your permission")],
            now: t + 3)
        let events = notifier.events
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.kind == "session.blocked")
        #expect(event.severity == .critical)
        #expect(event.title == "www / vigie")
        #expect(event.body == "Fake wants to run Bash")
        #expect(event.category == "NEEDS INPUT")
        #expect(event.dedupeKey == "fake:a")
        #expect(event.action == .module(id: "agents.sessions", actionID: "focus", payload: Data("fake:a".utf8)))
        #expect(event.metrics.isEmpty)
    }

    @Test func blockedWithoutToolUsesTheMessage() throws {
        let (module, notifier, _) = makeModule()
        module.apply([.needsInput(Self.context(Self.now), reason: .question, message: "Which branch?")], now: Self.now)
        #expect(notifier.events.first?.body == "Which branch?")
        module.apply([.needsInput(Self.context(Self.now, id: "b"), reason: .question)], now: Self.now)
        #expect(notifier.events.last?.body == "Fake asks a question")
    }

    @Test func doneCarriesTheWorkingDuration() throws {
        let (module, notifier, _) = makeModule()
        let t = Self.now
        module.apply(
            [
                .promptSubmit(Self.context(t)), .toolStart(Self.context(t + 10), tool: "Edit"),
                .turnEnd(Self.context(t + 42)),
            ], now: t + 42)
        let event = try #require(notifier.events.first)
        #expect(notifier.events.count == 1)
        #expect(event.kind == "session.done")
        #expect(event.severity == .info)
        #expect(event.body == "Fake · Turn ended")
        #expect(event.category == nil)
        #expect(event.metrics["working_duration"] == 42)
    }

    @Test func doneWithoutWorkingReportsZero() {
        let (module, notifier, _) = makeModule()
        module.apply([.turnEnd(Self.context(Self.now))], now: Self.now)
        #expect(notifier.events.first?.metrics["working_duration"] == 0)
    }

    @Test func failedPostsTheReason() throws {
        let (module, notifier, _) = makeModule()
        module.apply([.sessionError(Self.context(Self.now), message: "Login required")], now: Self.now)
        let event = try #require(notifier.events.first)
        #expect(event.kind == "session.failed")
        #expect(event.severity == .critical)
        #expect(event.body == "Fake · Login required")
        #expect(event.category == "ERROR")
        module.apply([.sessionError(Self.context(Self.now, id: "b"))], now: Self.now)
        #expect(notifier.events.last?.body == "Fake · Session error")
    }

    @Test func leavingTheStateResolves() {
        let (module, notifier, _) = makeModule()
        let t = Self.now
        module.apply([.needsInput(Self.context(t), reason: .permissionPrompt)], now: t)
        #expect(notifier.openKinds == ["session.blocked"])
        module.apply([.toolEnd(Self.context(t + 1), tool: "Bash")], now: t + 1)
        #expect(notifier.openKinds.isEmpty)
        module.apply([.turnEnd(Self.context(t + 2))], now: t + 2)
        #expect(notifier.openKinds == ["session.done"])
        // done → idle after done_to_idle resolves too.
        module.expireDone(settings: FakeSettings(values: [:]), now: t + 2 + 15 * 60)
        #expect(notifier.openKinds.isEmpty)
        #expect(notifier.resolvedCount == 2)
    }

    @Test func removalAndDismissResolve() async {
        let (module, notifier, _) = makeModule()
        let t = Self.now
        module.apply(
            [
                .needsInput(Self.context(t), reason: .permissionPrompt),
                .sessionError(Self.context(t, id: "b"), message: "x"),
            ], now: t)
        #expect(notifier.openKinds.sorted() == ["session.blocked", "session.failed"])
        module.apply([.sessionEnd(Self.context(t + 1))], now: t + 1)
        #expect(notifier.openKinds == ["session.failed"])
        #expect(await module.dismiss(SessionKey(agentID: "fake", sessionID: "b")))
        #expect(notifier.openKinds.isEmpty)
    }

    @Test func blockedToFailedSwapsTheAlert() {
        let (module, notifier, _) = makeModule()
        module.apply([.needsInput(Self.context(Self.now), reason: .permissionPrompt)], now: Self.now)
        module.apply([.sessionError(Self.context(Self.now + 1), message: "x")], now: Self.now + 1)
        #expect(notifier.events.map(\.kind) == ["session.blocked", "session.failed"])
        #expect(notifier.openKinds == ["session.failed"])
    }

    @Test func oldReplayedTransitionsDoNotPost() {
        let (module, notifier, _) = makeModule()
        let sent = Self.now - 6 * 60
        module.apply([.needsInput(Self.context(sent), reason: .permissionPrompt)], replayed: true, now: Self.now)
        #expect(module.store.table[Self.key]?.status == .blocked, "state still updates")
        #expect(notifier.events.isEmpty)
    }

    @Test func freshReplayedTransitionsPost() {
        let (module, notifier, _) = makeModule()
        let sent = Self.now - 4 * 60
        module.apply([.needsInput(Self.context(sent), reason: .permissionPrompt)], replayed: true, now: Self.now)
        #expect(notifier.events.map(\.kind) == ["session.blocked"])
        // An old event that was not replayed still alerts (only replays are suppressed).
        module.apply([.sessionError(Self.context(Self.now - 3600, id: "b"))], now: Self.now)
        #expect(notifier.events.map(\.kind) == ["session.blocked", "session.failed"])
    }

    @Test func aStateLeftWithinTheBatchDoesNotPost() {
        let (module, notifier, _) = makeModule()
        let t = Self.now
        module.apply(
            [.needsInput(Self.context(t), reason: .permissionPrompt), .toolEnd(Self.context(t + 1), tool: "Bash")],
            now: t + 1)
        #expect(notifier.events.isEmpty)
    }

    @Test func workingAndIdleNeverAlert() {
        let (module, notifier, _) = makeModule()
        module.apply(
            [.sessionStart(Self.context(Self.now)), .promptSubmit(Self.context(Self.now + 1))], now: Self.now + 1)
        // Going stale is display-only and never alerts.
        module.reconcile(now: Self.now + 3600, dead: [:])
        #expect(module.displayStatus(of: Self.key) == .stale)
        #expect(notifier.events.isEmpty)
    }

    @Test func focusActionRoutesToTheTerminal() async {
        let (module, _, setup) = makeModule()
        module.apply([.needsInput(Self.context(Self.now, pid: 9), reason: .permissionPrompt)], now: Self.now)
        let before = module.store.table
        module.handleAlertAction("focus", payload: Data("fake:a".utf8), intent: nil)
        _ = await module.alertActionTask?.value
        #expect(setup.warp.focused.count == 1)
        #expect(module.store.table == before, "Focus never changes session state")
        module.alertActionTask = nil
        module.handleAlertAction("other", payload: Data("fake:a".utf8), intent: nil)
        module.handleAlertAction("focus", payload: Data("not a key".utf8), intent: nil)
        #expect(module.alertActionTask == nil)
        #expect(setup.warp.focused.count == 1)
        // Through the protocol, as `ModuleAlertActions.deliver` calls it.
        let handler: any AlertActionHandler = module
        handler.handleAlertAction("focus", payload: Data("fake:a".utf8), intent: nil)
        _ = await module.alertActionTask?.value
        #expect(setup.warp.focused.count == 2)
    }

    @Test func eventPathPassesReplayedDown() async throws {
        let notifier = RecordingNotifier()
        let module = AgentsSessionsModule(
            adapters: AgentAdapters([FakeAdapter()]), terminals: TerminalAdapters([]), liveness: FakeLiveness())
        let context = FakeModuleContext(notifier: notifier)
        try await module.start(context: context)
        let now = Date()
        context.fakeEvents.send(try Hook.message("needs.input", at: now - 600, replayed: true))
        context.fakeEvents.send(try Hook.message("session.error", session: "s2", at: now - 60, replayed: true))
        context.fakeEvents.finish()
        await module.eventTask?.value
        #expect(notifier.events.map(\.kind) == ["session.failed"])
        await module.stop()
        #expect(notifier.openKinds.isEmpty, "stop resolves open alerts")
    }
}
