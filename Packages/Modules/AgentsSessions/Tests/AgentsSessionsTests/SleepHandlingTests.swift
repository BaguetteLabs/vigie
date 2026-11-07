import AgentKit
import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import AgentsSessions

/// Counts keep-awake requests; `send` drives `sleepWake`.
final class FakePower: PowerService, @unchecked Sendable {
    private let lock = NSLock()
    private var open: Set<UUID> = []
    private var _requests = 0
    private var continuations: [AsyncStream<SleepWakeEvent>.Continuation] = []

    /// Requests not cancelled yet.
    var held: Int { lock.withLock { open.count } }
    /// Every request ever made.
    var requests: Int { lock.withLock { _requests } }

    func preventIdleSleep(reason: String) -> RegistrationToken {
        let id = UUID()
        lock.withLock {
            open.insert(id)
            _requests += 1
        }
        return RegistrationToken(id: id) { [weak self] in
            guard let self else { return }
            _ = self.lock.withLock { self.open.remove(id) }
        }
    }

    var sleepWake: AsyncStream<SleepWakeEvent> {
        let (stream, continuation) = AsyncStream<SleepWakeEvent>.makeStream()
        lock.withLock { continuations.append(continuation) }
        return stream
    }

    var subscribers: Int { lock.withLock { continuations.count } }

    func send(_ event: SleepWakeEvent) {
        for continuation in lock.withLock({ continuations }) { continuation.yield(event) }
    }
}

/// Records `openOwnTab` calls.
final class RecordingHost: HostControl, @unchecked Sendable {
    private let lock = NSLock()
    private var _openedTab = 0
    var openedTab: Int { lock.withLock { _openedTab } }

    func requestPeek() {}
    func expand(focus: UserIntent?) {}
    func openOwnTab(focus: UserIntent?) { lock.withLock { _openedTab += 1 } }
    func registerDynamicModule(_ module: any NotchModule) throws -> RegistrationToken { RegistrationToken {} }
}

@MainActor @Suite struct SleepHandlingTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let sleptAt = now + 60
    static let wokeAt = now + 3600

    static func context(_ id: String, at: Date, pid: Int32? = nil) -> AgentEventContext {
        AgentEventContext(
            sessionKey: key(id), cwd: URL(fileURLWithPath: "/Users/me/www/\(id)"),
            terminal: TerminalHint(program: "WarpTerminal", sessionID: nil, warpFocusURL: nil, bundleID: nil),
            agentProcess: pid.map { AgentProcessRef(pid: $0, startTime: nil) }, at: at)
    }

    static func key(_ id: String) -> SessionKey { SessionKey(agentID: "fake", sessionID: id) }

    struct Setup {
        let module: AgentsSessionsModule
        let notifier: RecordingNotifier
        let power: FakePower
        let liveness: FakeLiveness
    }

    static func setup(alive: Set<AgentProcessRef> = []) -> Setup {
        let liveness = FakeLiveness(alive: alive)
        let module = AgentsSessionsModule(
            adapters: AgentAdapters([FakeAdapter()]),
            terminals: TerminalAdapters([], fallback: FakeTerminal(id: "generic", program: nil, appName: "App")),
            liveness: liveness)
        let notifier = RecordingNotifier()
        let power = FakePower()
        module.notifier = notifier
        module.power = power
        return Setup(module: module, notifier: notifier, power: power, liveness: liveness)
    }

    // MARK: Keep-awake

    @Test func holdsOneTokenWhileAnySessionWorks() {
        let s = Self.setup()
        let t = Self.now
        s.module.apply([.sessionStart(Self.context("a", at: t), model: nil)], now: t)
        #expect(s.power.requests == 0)
        s.module.apply([.promptSubmit(Self.context("a", at: t + 1))], now: t + 1)
        #expect(s.power.held == 1)
        s.module.apply([.toolStart(Self.context("b", at: t + 2), tool: "Edit")], now: t + 2)
        s.module.apply([.toolEnd(Self.context("a", at: t + 3), tool: "Edit")], now: t + 3)
        #expect(s.power.held == 1)
        #expect(s.power.requests == 1)
        s.module.apply([.turnEnd(Self.context("a", at: t + 4))], now: t + 4)
        #expect(s.power.held == 1)
        s.module.apply([.needsInput(Self.context("b", at: t + 5), reason: .question)], now: t + 5)
        #expect(s.power.held == 0)
        s.module.apply([.promptSubmit(Self.context("b", at: t + 6))], now: t + 6)
        #expect(s.power.held == 1)
        #expect(s.power.requests == 2)
    }

    @Test func staleSessionsDoNotKeepTheMacAwake() {
        let s = Self.setup()
        s.module.apply([.promptSubmit(Self.context("a", at: Self.now))], now: Self.now)
        #expect(s.power.held == 1)
        s.module.syncState(now: Self.now + 11 * 60)
        #expect(s.module.displayStatus(of: Self.key("a")) == .stale)
        #expect(s.power.held == 0)
    }

    @Test func stopReleasesTheToken() async throws {
        let power = FakePower()
        let context = FakeModuleContext(power: power)
        let module = AgentsSessionsModule(
            adapters: AgentAdapters([FakeAdapter()]),
            terminals: TerminalAdapters([], fallback: FakeTerminal(id: "generic", program: nil, appName: "App")),
            liveness: FakeLiveness())
        try await module.start(context: context)
        module.apply([.promptSubmit(Self.context("a", at: Self.now))], now: Self.now)
        #expect(power.held == 1)
        await module.stop()
        #expect(power.held == 0)
    }

    // MARK: Wake

    /// a: working (Bash), b: idle, c: done, d: blocked.
    static func seed(_ module: AgentsSessionsModule, working: [String] = ["a"]) {
        let t = now
        var events: [AgentEvent] = [
            .sessionStart(context("b", at: t), model: nil),
            .turnEnd(context("c", at: t)),
            .needsInput(context("d", at: t), reason: .question),
        ]
        for (index, id) in working.enumerated() {
            events.append(.toolStart(context(id, at: t + Double(index), pid: 100 + Int32(index)), tool: "Bash"))
        }
        module.apply(events, now: t + 10)
    }

    @Test func oneInterruptedSessionFailsWithTheUsualAlert() async throws {
        let s = Self.setup()
        Self.seed(s.module)
        let before = s.notifier.events.count
        await s.module.handleSleepWake(.willSleep, now: Self.sleptAt)
        await s.module.handleSleepWake(.didWake, now: Self.wokeAt)

        let session = try #require(s.module.store.table[Self.key("a")])
        #expect(session.status == .failed)
        #expect(session.failureReason == .hostSlept)
        #expect(session.statusSince == Self.wokeAt)
        #expect(session.lastAction == "Bash")
        #expect(s.module.store.table[Self.key("b")]?.status == .idle)
        #expect(s.module.store.table[Self.key("c")]?.status == .done)
        #expect(s.module.store.table[Self.key("d")]?.status == .blocked)
        #expect(s.module.store.table[Self.key("d")]?.failureReason == nil)

        let posted = Array(s.notifier.events.dropFirst(before))
        #expect(posted.count == 1)
        let alert = try #require(posted.first)
        #expect(alert.kind == "session.failed")
        #expect(alert.category == "HOST SLEPT")
        #expect(alert.body == "Run interrupted during Bash")
        #expect(alert.title == "www / a")
        #expect(alert.action == .module(id: "agents.sessions", actionID: "focus", payload: Data("fake:a".utf8)))

        let row = try #require(s.module.tabSnapshot(now: Self.wokeAt + 120).rows.first { $0.id == "fake:a" })
        #expect(row.statusLabel == "FAILED · HOST SLEPT")
        #expect(row.lastAction == "Run interrupted during Bash")
        #expect(row.glyphStatus == .failed)
        #expect(s.power.held == 0)
    }

    @Test func severalInterruptedSessionsPostOneSummary() async throws {
        let s = Self.setup()
        let host = RecordingHost()
        s.module.host = host
        Self.seed(s.module, working: ["a", "e", "f"])
        let before = s.notifier.events.count
        await s.module.handleSleepWake(.willSleep, now: Self.sleptAt)
        await s.module.handleSleepWake(.didWake, now: Self.wokeAt)

        for id in ["a", "e", "f"] {
            let session = try #require(s.module.store.table[Self.key(id)])
            #expect(session.status == .failed)
            #expect(session.failureReason == .hostSlept)
            #expect(session.statusSince == Self.wokeAt)
            #expect(session.lastAction == "Bash")
        }
        #expect(s.module.store.table[Self.key("b")]?.status == .idle)
        #expect(s.module.store.table[Self.key("c")]?.status == .done)

        let posted = Array(s.notifier.events.dropFirst(before))
        #expect(posted.count == 1)
        let alert = try #require(posted.first)
        #expect(alert.kind == "session.failed")
        #expect(alert.severity == .critical)
        #expect(alert.title == "3 sessions interrupted by sleep")
        #expect(alert.body == nil)
        #expect(alert.category == "HOST SLEPT")
        #expect(alert.dedupeKey == "host_slept")
        #expect(alert.action == .module(id: "agents.sessions", actionID: "open-agents", payload: Data()))
        let rows = s.module.tabSnapshot(now: Self.wokeAt).rows.filter { $0.statusLabel == "FAILED · HOST SLEPT" }
        #expect(rows.count == 3)

        s.module.handleAlertAction("open-agents", payload: Data(), intent: nil)
        #expect(host.openedTab == 1)

        // The summary stays open until every covered session has left failed.
        let resolved = s.notifier.resolvedCount
        s.module.apply([.promptSubmit(Self.context("a", at: Self.wokeAt + 1))], now: Self.wokeAt + 1)
        s.module.apply([.sessionEnd(Self.context("e", at: Self.wokeAt + 1))], now: Self.wokeAt + 1)
        #expect(s.notifier.resolvedCount == resolved)
        _ = await s.module.dismiss(Self.key("f"))
        #expect(s.notifier.resolvedCount == resolved + 1)
    }

    @Test func aNewEventAfterWakeReturnsTheSessionToWorking() async throws {
        let s = Self.setup()
        Self.seed(s.module)
        await s.module.handleSleepWake(.willSleep, now: Self.sleptAt)
        await s.module.handleSleepWake(.didWake, now: Self.wokeAt)
        #expect(s.power.held == 0)
        s.module.apply([.toolEnd(Self.context("a", at: Self.wokeAt + 5), tool: "Bash")], now: Self.wokeAt + 5)
        let session = try #require(s.module.store.table[Self.key("a")])
        #expect(session.status == .working)
        #expect(session.failureReason == nil)
        #expect(
            s.module.tabSnapshot(now: Self.wokeAt + 5).rows.first { $0.id == "fake:a" }?.statusLabel
                == "WORKING · 0M")
        #expect(s.notifier.openKinds.contains("session.failed") == false)
        #expect(s.power.held == 1)
    }

    @Test func aSessionWithAnEventAfterTheSleepIsNotMarked() async throws {
        let s = Self.setup(alive: [AgentProcessRef(pid: 100, startTime: nil)])
        Self.seed(s.module)
        await s.module.handleSleepWake(.willSleep, now: Self.sleptAt)
        s.module.apply([.toolStart(Self.context("a", at: Self.sleptAt + 1), tool: "Edit")], now: Self.wokeAt)
        let before = s.notifier.events.count
        await s.module.handleSleepWake(.didWake, now: Self.wokeAt)
        #expect(s.module.store.table[Self.key("a")]?.status == .working)
        #expect(s.notifier.events.count == before)
    }

    @Test func wakeWithoutSleepMarksNothing() async {
        let s = Self.setup(alive: [AgentProcessRef(pid: 100, startTime: nil)])
        Self.seed(s.module)
        await s.module.handleSleepWake(.didWake, now: Self.wokeAt)
        #expect(s.module.store.table[Self.key("a")]?.status == .working)
    }

    @Test func livenessIsPausedDuringSleepAndResumesAfterTheMarking() async throws {
        // The working session's process is gone at wake: marked failed first, so liveness keeps it (AD-5).
        let s = Self.setup(alive: [AgentProcessRef(pid: 999, startTime: nil)])
        Self.seed(s.module)
        await s.module.handleSleepWake(.willSleep, now: Self.sleptAt)
        let checks = s.liveness.checks
        await s.module.runLiveness(now: Self.sleptAt + 10)
        #expect(s.liveness.checks == checks)
        #expect(s.module.store.table[Self.key("a")] != nil)

        await s.module.handleSleepWake(.didWake, now: Self.wokeAt)
        #expect(s.liveness.checks > checks)
        let session = try #require(s.module.store.table[Self.key("a")])
        #expect(session.status == .failed)
        #expect(s.module.endedProcesses.contains(Self.key("a")))
    }

    @Test func sleepWakeEventsArriveThroughContextPower() async throws {
        let power = FakePower()
        let notifier = RecordingNotifier()
        let storage = FakeStorage()
        let context = FakeModuleContext(storage: storage, notifier: notifier, power: power)
        let module = AgentsSessionsModule(
            adapters: AgentAdapters([FakeAdapter()]),
            terminals: TerminalAdapters([], fallback: FakeTerminal(id: "generic", program: nil, appName: "App")),
            liveness: FakeLiveness())
        try await module.start(context: context)
        #expect(power.subscribers == 1)
        module.apply([.toolStart(Self.context("a", at: Date() - 60), tool: "Bash")])
        power.send(.willSleep)
        try await Task.sleep(for: .milliseconds(50))
        power.send(.didWake)
        for _ in 0..<100 where module.store.table[Self.key("a")]?.status != .failed {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(module.store.table[Self.key("a")]?.status == .failed)
        #expect(module.store.table[Self.key("a")]?.failureReason == .hostSlept)
        #expect(notifier.events.last?.category == "HOST SLEPT")
        await module.stop()
        // Persisted with its reason.
        let saved = try #require(
            try await storage.readJSON(AgentsSessionsModule.storageName, as: [Session].self, schema: 1))
        #expect(saved.first?.failureReason == .hostSlept)
    }

    // MARK: Reducer

    @Test func reducerMarksOnlyWorkingSessions() {
        let t = Self.now
        var table: [SessionKey: Session] = [:]
        SessionReducer.apply(.toolStart(Self.context("a", at: t), tool: "Bash"), to: &table)
        SessionReducer.apply(.turnEnd(Self.context("b", at: t)), to: &table)
        let changes = SessionReducer.markHostSlept(
            keys: [Self.key("a"), Self.key("b"), Self.key("zz")], at: t + 100, in: &table)
        #expect(changes == [.status(Self.key("a"), from: .working, to: .failed)])
        #expect(table[Self.key("a")]?.lastEventAt == t)
        #expect(table[Self.key("b")]?.status == .done)
        // A later session.error keeps failed but drops the host-slept reason.
        SessionReducer.apply(.sessionError(Self.context("a", at: t + 200), message: "boom"), to: &table)
        #expect(table[Self.key("a")]?.failureReason == nil)
        #expect(table[Self.key("a")]?.lastMessage == "boom")
    }
}
