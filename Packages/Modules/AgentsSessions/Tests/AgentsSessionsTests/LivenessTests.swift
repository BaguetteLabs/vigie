import AgentKit
import Foundation
import ModuleKit
import Testing
import VigieUI
import Wire

@testable import AgentsSessions

@MainActor @Suite struct LivenessTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let start = Date(timeIntervalSince1970: 1_799_990_000)

    static func key(_ id: String) -> SessionKey { SessionKey(agentID: "fake", sessionID: id) }
    static func process(_ pid: Int32) -> AgentProcessRef { AgentProcessRef(pid: pid, startTime: start) }

    static func session(
        _ id: String, _ status: SessionStatus, since: Date = t0, lastEvent: Date? = nil, pid: Int32? = nil,
        cwd: String? = nil, action: String? = nil
    ) -> Session {
        Session(
            key: key(id), status: status, statusSince: since, lastEventAt: lastEvent ?? since, lastAction: action,
            cwd: cwd.map { URL(fileURLWithPath: $0) }, agentProcess: pid.map(process))
    }

    func makeModule(liveness: FakeLiveness, home: String = "/Users/me") -> AgentsSessionsModule {
        AgentsSessionsModule(
            adapters: AgentAdapters([FakeAdapter()]), terminals: TerminalAdapters([]), liveness: liveness,
            homeDirectory: URL(fileURLWithPath: home))
    }

    func saved(_ context: FakeModuleContext) throws -> [Session]? {
        guard let data = context.fakeStorage.data("sessions") else { return nil }
        return try FakeStorage.decoder.decode(StateFile<[Session]>.self, from: data).value
    }

    // MARK: Reducer

    @Test func deadProcessRemovesEveryStatusButFailed() {
        var table: [SessionKey: Session] = [:]
        for (id, status) in [("i", SessionStatus.idle), ("w", .working), ("d", .done), ("b", .blocked), ("f", .failed)]
        {
            table[Self.key(id)] = Self.session(id, status, pid: 42)
        }
        table[Self.key("n")] = Self.session("n", .working)  // no agent process: left alone
        let removed = SessionReducer.reconcile(in: &table, now: Self.t0 + 60) { _, _ in true }
        #expect(removed.map(\.sessionID).sorted() == ["b", "d", "i", "w"])
        #expect(Set(table.keys.map(\.sessionID)) == ["f", "n"])
    }

    @Test func liveProcessesStay() {
        var table = [Self.key("w"): Self.session("w", .working, pid: 42)]
        let removed = SessionReducer.reconcile(in: &table, now: Self.t0 + 60) { _, _ in false }
        #expect(removed.isEmpty)
        #expect(table.count == 1)
    }

    @Test func failedSessionsGoAfter24Hours() {
        var table = [
            Self.key("f"): Self.session("f", .failed, since: Self.t0, pid: 42),
            Self.key("g"): Self.session("g", .failed, since: Self.t0 + 10),
        ]
        let day: TimeInterval = 24 * 3600
        #expect(SessionReducer.reconcile(in: &table, now: Self.t0 + day - 1) { _, _ in true }.isEmpty)
        #expect(SessionReducer.reconcile(in: &table, now: Self.t0 + day) { _, _ in true } == [Self.key("f")])
        #expect(SessionReducer.reconcile(in: &table, now: Self.t0 + day + 10) { _, _ in false } == [Self.key("g")])
        #expect(table.isEmpty)
    }

    // MARK: Module

    @Test func livenessTickRemovesDeadSessionsAndKeepsFailed() async throws {
        let liveness = FakeLiveness(alive: [Self.process(1), Self.process(2), Self.process(3)])
        let storage = FakeStorage()
        let now = Date()
        try await storage.writeJSON(
            [
                Self.session("a", .working, since: now, pid: 1),
                Self.session("b", .blocked, since: now, pid: 2),
                Self.session("f", .failed, since: now, pid: 3),
            ], name: "sessions", schema: 1)
        let module = makeModule(liveness: liveness)
        let context = FakeModuleContext(storage: storage)
        try await module.start(context: context)
        #expect(context.fakeScheduler.intervals.contains(.seconds(10)))
        #expect(module.sessions.count == 3)

        liveness.kill(Self.process(2))
        liveness.kill(Self.process(3))
        await context.fakeScheduler.fire()
        #expect(module.sessions.map(\.key.sessionID).sorted() == ["a", "f"])
        #expect(try saved(context)?.map(\.key.sessionID).sorted() == ["a", "f"])
        #expect(module.state == .alert)

        liveness.kill(Self.process(1))
        await module.runLiveness()
        #expect(module.sessions.map(\.key.sessionID) == ["f"])
        await module.stop()
    }

    @Test func startTimeMismatchCountsAsDead() async throws {
        // Same pid, different start time: the pid was recycled by another process.
        let liveness = FakeLiveness(alive: [AgentProcessRef(pid: 7, startTime: Self.start + 100)])
        let storage = FakeStorage()
        try await storage.writeJSON([Self.session("a", .working, since: Date(), pid: 7)], name: "sessions", schema: 1)
        let module = makeModule(liveness: liveness)
        try await module.start(context: FakeModuleContext(storage: storage))
        #expect(module.sessions.isEmpty)
        await module.stop()
    }

    @Test func reconcileRunsAtStartOverPersistedSessions() async throws {
        let liveness = FakeLiveness(alive: [Self.process(1)])
        let storage = FakeStorage()
        let now = Date()
        try await storage.writeJSON(
            [Self.session("live", .idle, since: now, pid: 1), Self.session("dead", .done, since: now, pid: 9)],
            name: "sessions", schema: 1)
        let module = makeModule(liveness: liveness)
        let context = FakeModuleContext(storage: storage)
        try await module.start(context: context)
        #expect(module.sessions.map(\.key.sessionID) == ["live"])
        #expect(try saved(context)?.map(\.key.sessionID) == ["live"])
        #expect(context.fakeEvents.prefixes.contains("host.ready"))
        await module.stop()
    }

    @Test func hostReadyRunsAReconcile() async throws {
        let liveness = FakeLiveness(alive: [Self.process(1)])
        let storage = FakeStorage()
        try await storage.writeJSON([Self.session("a", .idle, since: Date(), pid: 1)], name: "sessions", schema: 1)
        let module = makeModule(liveness: liveness)
        let context = FakeModuleContext(storage: storage)
        try await module.start(context: context)
        #expect(module.sessions.count == 1)
        liveness.kill(Self.process(1))
        context.fakeEvents.send(EventMessage(topic: "host.ready", payload: Data(), sentAt: Date()))
        context.fakeEvents.finish()
        await module.readyTask?.value
        #expect(module.sessions.isEmpty)
    }

    @Test func dismissRemovesOnlyFailedSessions() async throws {
        let module = makeModule(liveness: FakeLiveness())
        let context = FakeModuleContext()
        try await module.start(context: context)
        let now = Date()
        context.fakeEvents.send(try Hook.message("session.error", session: "f", at: now))
        context.fakeEvents.send(try Hook.message("needs.input", session: "b", at: now))
        context.fakeEvents.finish()
        await module.eventTask?.value
        #expect(module.sessions.count == 2)

        #expect(await module.dismiss(Self.key("b")) == false)
        #expect(await module.dismiss(Self.key("f")))
        #expect(await module.dismiss(Self.key("f")) == false)
        #expect(module.sessions.map(\.key.sessionID) == ["b"])
        #expect(try saved(context)?.map(\.key.sessionID) == ["b"])
    }

    // MARK: Stale

    @Test func staleAfterTenMinutesWithoutEvent() {
        let working = Self.session("w", .working, since: Self.t0 - 3600, lastEvent: Self.t0)
        let limit = Session.defaultStaleAfter
        #expect(limit == .seconds(600))
        #expect(!working.isStale(now: Self.t0 + 599, staleAfter: limit))
        #expect(working.displayStatus(now: Self.t0 + 599) == .working)
        #expect(working.isStale(now: Self.t0 + 600, staleAfter: limit))
        #expect(working.displayStatus(now: Self.t0 + 600) == .stale)
        // Only working sessions turn stale.
        for status in [SessionStatus.idle, .done, .blocked, .failed] {
            #expect(Self.session("x", status).displayStatus(now: Self.t0 + 7200) == status)
        }
    }

    @Test func staleSortsAfterIdleAndCountsAsAmbient() {
        let now = Self.t0 + 1200
        let sessions = [
            Self.session("stale", .working, since: Self.t0, lastEvent: Self.t0),
            Self.session("idle", .idle, since: Self.t0 - 600),
            Self.session("work", .working, since: Self.t0 + 1000, lastEvent: Self.t0 + 1100),
            Self.session("done", .done, since: Self.t0 - 900),
        ]
        let sorted = SessionReducer.sorted(sessions) { $0.displayStatus(now: now) }
        #expect(sorted.map(\.key.sessionID) == ["done", "work", "idle", "stale"])
        #expect(SessionReducer.moduleState(statuses: [.stale, .idle]) == .ambient)
        #expect(SessionReducer.moduleState(statuses: [.stale, .working]) == .active)
    }

    @Test func moduleDerivesStaleFromTheSetting() async throws {
        let module = makeModule(liveness: FakeLiveness())
        let context = FakeModuleContext(settings: ["stale_after": Duration.seconds(60)])
        try await module.start(context: context)
        let now = Date()
        context.fakeEvents.send(try Hook.message("prompt.submit", session: "w", at: now - 120))
        context.fakeEvents.send(try Hook.message("session.start", session: "i", at: now - 300))
        context.fakeEvents.finish()
        await module.eventTask?.value
        #expect(module.displayStatus(of: Self.key("w")) == .stale)
        #expect(module.displaySessions.map(\.key.sessionID) == ["i", "w"])
        #expect(module.sessions.first?.status == .working)  // stored status unchanged
        #expect(module.state == .ambient)

        // A new event returns it to its real state.
        _ = module.apply(
            [.toolStart(AgentEventContext(sessionKey: Self.key("w"), at: now), tool: "Edit")], now: now + 1)
        #expect(module.displayStatus(of: Self.key("w")) == .working)
        #expect(module.state == .active)
    }

    @Test func staleRowTextAndAccessibilityLabel() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let text = SessionRowText(timeZone: utc)
        // 2027-01-15 14:30 UTC.
        let lastEvent = Date(timeIntervalSince1970: 1_800_023_400)
        let session = Self.session(
            "w", .working, since: lastEvent - 600, lastEvent: lastEvent, cwd: "/Users/me/www/vigie", action: "Edit")
        let now = lastEvent + 18 * 60 + 20
        #expect(text.statusLabel(session, now: now) == "STALE · 18M")
        #expect(text.lastActionLine(session, now: now) == "LAST EVENT 14:30 · Edit")
        #expect(text.accessibilityLabel(session, now: now) == "vigie, stale, no event for 18 minutes")

        var noAction = session
        noAction.lastAction = nil
        #expect(text.lastActionLine(noAction, now: now) == "LAST EVENT 14:30")

        // Not stale yet: the real status, timed from statusSince.
        let fresh = lastEvent + 60
        #expect(text.statusLabel(session, now: fresh) == "WORKING · 11M")
        #expect(text.lastActionLine(session, now: fresh) == "Edit")
        #expect(text.accessibilityLabel(session, now: fresh) == "vigie, working, 11 minutes")
        #expect(text.accessibilityLabel(Self.session("i", .idle, cwd: "/tmp/x"), now: fresh) == "x, idle")
    }

    // MARK: Ignored paths

    @Test func ignoredPathsExpandTildeAndMatchWholeComponents() {
        let ignored = IgnoredPaths(
            ["~/scratch", "/opt/tmp/", "relative", "~"], home: URL(fileURLWithPath: "/Users/me"))
        #expect(ignored.paths == ["/Users/me/scratch", "/opt/tmp", "/Users/me"])
        let narrow = IgnoredPaths(["~/scratch/"], home: URL(fileURLWithPath: "/Users/me"))
        #expect(narrow.contains(URL(fileURLWithPath: "/Users/me/scratch")))
        #expect(narrow.contains(URL(fileURLWithPath: "/Users/me/scratch/a/b")))
        #expect(!narrow.contains(URL(fileURLWithPath: "/Users/me/scratchpad")))
        #expect(!narrow.contains(URL(fileURLWithPath: "/Users/me")))
        #expect(!narrow.contains(nil))
        #expect(!IgnoredPaths([], home: URL(fileURLWithPath: "/Users/me")).contains(URL(fileURLWithPath: "/x")))
    }

    @Test func sessionUnderIgnoredPathIsNeverTracked() async throws {
        let module = makeModule(liveness: FakeLiveness())
        let context = FakeModuleContext(settings: ["ignored_paths": ["~/scratch"]])
        try await module.start(context: context)
        let now = Date()
        context.fakeEvents.send(
            try Hook.message("session.start", session: "x", at: now, cwd: "/Users/me/scratch/demo"))
        context.fakeEvents.send(try Hook.message("needs.input", session: "x", at: now + 1))  // no cwd
        context.fakeEvents.send(try Hook.message("session.start", session: "y", at: now, cwd: "/Users/me/www/vigie"))
        context.fakeEvents.finish()
        await module.eventTask?.value
        #expect(module.sessions.map(\.key.sessionID) == ["y"])
        #expect(module.state == .ambient)
        #expect(module.ignoredKeys.contains(Self.key("x")))
    }

    @Test func ignoredKeysAreBounded() {
        var keys = IgnoredKeys()
        for index in 0..<(IgnoredKeys.capacity + 10) { keys.insert(Self.key("s\(index)")) }
        #expect(keys.count == IgnoredKeys.capacity)
        #expect(!keys.contains(Self.key("s0")))
        #expect(keys.contains(Self.key("s\(IgnoredKeys.capacity + 9)")))
        keys.remove(Self.key("s\(IgnoredKeys.capacity + 9)"))
        #expect(keys.count == IgnoredKeys.capacity - 1)
    }

    @Test func reconcileDropsSessionsNowUnderAnIgnoredPath() async throws {
        let storage = FakeStorage()
        try await storage.writeJSON(
            [Self.session("x", .idle, since: Date(), cwd: "/Users/me/scratch/a")], name: "sessions", schema: 1)
        let module = makeModule(liveness: FakeLiveness())
        try await module.start(context: FakeModuleContext(settings: ["ignored_paths": ["~/scratch"]], storage: storage))
        #expect(module.sessions.isEmpty)
        await module.stop()
    }
}
