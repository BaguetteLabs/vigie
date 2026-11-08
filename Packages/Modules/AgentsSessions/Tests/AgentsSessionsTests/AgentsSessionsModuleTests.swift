import AgentKit
import Foundation
import ModuleKit
import Testing
import VigieUI
import Wire

@testable import AgentsSessions

@MainActor @Suite struct AgentsSessionsModuleTests {
    static let fakeKey = SessionKey(agentID: "fake", sessionID: "s1")

    func makeModule() -> AgentsSessionsModule {
        AgentsSessionsModule(adapters: AgentAdapters([FakeAdapter()]), terminals: TerminalAdapters([]))
    }

    /// Ends the event stream and waits until the module applied (and persisted) everything sent.
    func drain(_ module: AgentsSessionsModule, _ context: FakeModuleContext) async {
        context.fakeEvents.finish()
        await module.eventTask?.value
    }

    func saved(_ context: FakeModuleContext) throws -> [Session]? {
        guard let data = context.fakeStorage.data("sessions") else { return nil }
        return try FakeStorage.decoder.decode(StateFile<[Session]>.self, from: data).value
    }

    @Test func manifest() {
        let module = AgentsSessionsModule(adapters: AgentAdapters([]), terminals: TerminalAdapters([]))
        #expect(module.manifest.id == "agents.sessions")
        #expect(module.manifest.defaultEnabled)
        #expect(module.state == .hidden)
        #expect(module.adapters.adapters.isEmpty)
        #expect(module.adapterContexts.isEmpty)
    }

    @Test func nameResolvesFromCatalog() {
        let name = String(localized: AgentsSessionsModule.staticManifest.name)
        #expect(name == "Agents")
    }

    @Test func settingsDeclared() {
        let settings = AgentsSessionsModule.staticManifest.settings
        #expect(
            settings.map(\.key) == [
                "done_to_idle", "terminal", "adapters", "stale_after", "ignored_paths",
                "ask_default_agent", "ask_cwd", "ask_alt_cwd",
            ])
        #expect(settings[0].kind == .duration(default: .seconds(900)))
        #expect(settings[0].scope == .synced)
        #expect(settings[1].scope == .local)
        #expect(settings[2].kind == .list(of: .string, default: ["claude"]))
        #expect(settings[3].kind == .duration(default: .seconds(600)))
        #expect(settings[3].scope == .synced)
        #expect(settings[4].kind == .list(of: .string, default: []))
        #expect(settings[4].scope == .synced)
        for setting in settings {
            #expect(!String(localized: setting.label).hasPrefix("agentsSessions."), "\(setting.key) label in catalog")
        }
    }

    @Test func startWithNothingSavedIsAmbientAndSubscribes() async throws {
        let module = makeModule()
        let context = FakeModuleContext()
        try await module.start(context: context)
        #expect(module.state == .ambient)
        #expect(module.sessions.isEmpty)
        #expect(context.fakeEvents.prefixes == ["agent.", "host.ready"])
        #expect(context.fakeScheduler.intervals == [.seconds(30), .seconds(10)])
        #expect(module.expandedView() != nil)
        #expect(module.leftWingItems().map(\.id) == ["empty"])
        #expect(module.wingEmptyState == .noActiveSessions)
        await module.stop()
    }

    @Test func fakeAdapterDrivesTheWholePath() async throws {
        let module = makeModule()
        let context = FakeModuleContext()
        try await module.start(context: context)
        let now = Date()
        context.fakeEvents.send(try Hook.message("session.start", at: now, cwd: "/Users/me/www/vigie"))
        context.fakeEvents.send(try Hook.message("prompt.submit", at: now + 1))
        context.fakeEvents.send(try Hook.message("tool.start", at: now + 2, tool: "Edit"))
        context.fakeEvents.send(try Hook.message("needs.input", at: now + 3))
        await drain(module, context)

        let session = try #require(module.sessions.first)
        #expect(session.key == Self.fakeKey)
        #expect(session.status == .blocked)
        #expect(session.statusSince == now + 3)
        #expect(session.lastAction == "Edit")
        #expect(session.projectName == "vigie")
        #expect(session.tty == "/dev/ttys003")
        #expect(session.terminal?.program == "WarpTerminal")
        #expect(session.model == "fake-1")
        #expect(session.blockReason == .permissionPrompt)
        #expect(module.state == .alert)
        // start, prompt (idle → working), needs.input (working → blocked); the tool heartbeat is not persisted.
        #expect(context.fakeStorage.writeCount("sessions") == 3)
        #expect(try saved(context)?.first?.status == .blocked)
    }

    @Test func persistenceRoundTrip() async throws {
        let storage = FakeStorage()
        let first = makeModule()
        let firstContext = FakeModuleContext(storage: storage)
        try await first.start(context: firstContext)
        // Whole seconds: the file keeps millisecond precision.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        firstContext.fakeEvents.send(try Hook.message("prompt.submit", at: now))
        firstContext.fakeEvents.send(try Hook.message("turn.end", session: "s2", at: now + 1))
        await drain(first, firstContext)
        await first.stop()

        let second = makeModule()
        let secondContext = FakeModuleContext(storage: storage)
        try await second.start(context: secondContext)
        #expect(second.sessions == first.sessions)
        #expect(second.sessions.map(\.status) == [.done, .working])
        #expect(second.state == .active)
        await second.stop()
    }

    @Test func sessionEndRemovesAndPersists() async throws {
        let module = makeModule()
        let context = FakeModuleContext()
        try await module.start(context: context)
        let now = Date()
        context.fakeEvents.send(try Hook.message("session.start", at: now))
        context.fakeEvents.send(try Hook.message("session.end", at: now + 1))
        await drain(module, context)
        #expect(module.sessions.isEmpty)
        #expect(module.state == .ambient)
        #expect(context.fakeStorage.writeCount("sessions") == 2)
        #expect(try saved(context) == [])
    }

    @Test func unknownAgentIsIgnored() async throws {
        let module = makeModule()
        let context = FakeModuleContext()
        try await module.start(context: context)
        context.fakeEvents.send(try Hook.message("prompt.submit", agent: "codex", at: Date()))
        context.fakeEvents.send(try Hook.message("prompt.submit", agent: "Not Valid", at: Date()))
        context.fakeEvents.send(
            EventMessage(topic: "agent.hook", payload: Data("{}".utf8), sentAt: Date()))
        context.fakeEvents.send(
            EventMessage(topic: "agent.generic", payload: Data("{}".utf8), sentAt: Date()))
        await drain(module, context)
        #expect(module.sessions.isEmpty)
        #expect(context.fakeStorage.writeCount("sessions") == 0)
    }

    @Test func replayedEventsConvergeToTheLiveState() async throws {
        let now = Date()
        let script: [(String, String, Double)] = [
            ("session.start", "s1", 0), ("prompt.submit", "s1", 1), ("tool.start", "s1", 2),
            ("session.start", "s2", 3), ("prompt.submit", "s2", 4), ("turn.end", "s1", 5),
            ("session.error", "s2", 6), ("prompt.submit", "s3", 7),
        ]

        func run(replayed: Bool) async throws -> [Session] {
            let module = makeModule()
            let context = FakeModuleContext()
            try await module.start(context: context)
            for (name, session, offset) in script {
                context.fakeEvents.send(try Hook.message(name, session: session, at: now + offset, replayed: replayed))
            }
            await drain(module, context)
            return module.sessions
        }

        let live = try await run(replayed: false)
        let replayed = try await run(replayed: true)
        #expect(replayed == live)
        #expect(live.map(\.status) == [.failed, .done, .working])
    }

    @Test func lateReplayedEventDoesNotRegressStatus() async throws {
        let module = makeModule()
        let context = FakeModuleContext()
        try await module.start(context: context)
        let now = Date()
        // Live turn.end arrives first; the spool then replays an older tool event.
        context.fakeEvents.send(try Hook.message("turn.end", at: now))
        context.fakeEvents.send(try Hook.message("tool.start", at: now - 10, tool: "Grep", replayed: true))
        await drain(module, context)
        #expect(module.sessions.first?.status == .done)
        #expect(module.sessions.first?.lastAction == "Grep")
        #expect(context.fakeStorage.writeCount("sessions") == 1)
    }

    @Test func doneToIdleRunsOnTheSchedulerWithTheSetting() async throws {
        let module = makeModule()
        let context = FakeModuleContext(settings: ["done_to_idle": Duration.seconds(1)])
        try await module.start(context: context)
        context.fakeEvents.send(try Hook.message("turn.end", at: Date().addingTimeInterval(-5)))
        await drain(module, context)
        #expect(module.sessions.first?.status == .done)
        #expect(module.state == .active)

        await context.fakeScheduler.fire()
        #expect(module.sessions.first?.status == .idle)
        #expect(module.state == .ambient)
        #expect(try saved(context)?.first?.status == .idle)
    }

    @Test func doneSessionsExpireAtLaunch() async throws {
        let storage = FakeStorage()
        let stale = Session(
            key: Self.fakeKey, status: .done, statusSince: Date().addingTimeInterval(-3600),
            lastEventAt: Date().addingTimeInterval(-3600))
        try await storage.writeJSON([stale], name: "sessions", schema: 1)
        let module = makeModule()
        let context = FakeModuleContext(storage: storage)
        try await module.start(context: context)
        #expect(module.sessions.first?.status == .idle)
        #expect(module.state == .ambient)
        #expect(try saved(context)?.first?.status == .idle)
        await module.stop()
    }
}
