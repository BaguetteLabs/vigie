import AgentKit
import Foundation
import ModuleKit
import Testing
import Wire

@testable import AgentsSessions

/// `agent.generic` from `vigie agent` (Story 4.13, AD-5, FR86).
@MainActor @Suite struct GenericAgentTests {
    /// Recent: liveness drops failed sessions 24 h after they failed.
    static let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    static let key = SessionKey(agentID: AgentID(generic: "mytool")!, sessionID: "t1")
    static let ancestors = [
        ProcessInfoEntry(pid: 300, ppid: 200, name: "bash", startTime: nil),
        ProcessInfoEntry(pid: 200, ppid: 150, name: "-zsh", startTime: nil),
        ProcessInfoEntry(pid: 150, ppid: 100, name: "mytool", startTime: Date(timeIntervalSince1970: 1_792_999_000)),
        ProcessInfoEntry(pid: 100, ppid: 1, name: "login", startTime: nil),
    ]

    static func payload(
        _ status: GenericStatus?, end: Bool = false, agent: String = "mytool", session: String = "t1",
        message: String? = nil, ancestors: [ProcessInfoEntry] = ancestors
    ) -> GenericAgentPayload {
        GenericAgentPayload(
            agent: agent, session: session, status: status, end: end, cwd: "/Users/me/www/vigie", message: message,
            tty: "/dev/ttys005", env: ["TERM_PROGRAM": "ghostty", "PWD": "/Users/me"], ancestors: ancestors)
    }

    static func message(
        _ payload: GenericAgentPayload, at: Date = now, replayed: Bool = false
    ) throws -> EventMessage {
        EventMessage(
            topic: Topic.agentGeneric, payload: try JSONEncoder().encode(payload), sentAt: at,
            receivedAt: at.addingTimeInterval(1), replayed: replayed)
    }

    static func pipeline() -> HookPipeline {
        HookPipeline(adapters: AgentAdapters([FakeAdapter()]), log: .init(subsystem: "test", category: "generic"))
    }

    // MARK: Mapping

    @Test(arguments: [
        (GenericStatus.working, AgentEvent.Name.promptSubmit),
        (.blocked, .needsInput),
        (.done, .turnEnd),
        (.failed, .sessionError),
        (.idle, .sessionStart),
    ])
    func everyStatusMaps(status: GenericStatus, expected: AgentEvent.Name) {
        let events = GenericAgentMapping.normalize(Self.payload(status), sentAt: Self.now)
        #expect(events.map(\.name) == [expected])
    }

    @Test func endMapsToSessionEndAndWinsOverStatus() {
        #expect(
            GenericAgentMapping.normalize(Self.payload(nil, end: true), sentAt: Self.now).map(\.name) == [.sessionEnd])
        #expect(
            GenericAgentMapping.normalize(Self.payload(.working, end: true), sentAt: Self.now).map(\.name)
                == [.sessionEnd])
    }

    @Test func contextCarriesIdentityAndCallerFacts() throws {
        let event = try #require(GenericAgentMapping.normalize(Self.payload(.working), sentAt: Self.now).first)
        let context = event.context
        #expect(context.sessionKey == Self.key)
        #expect(context.sessionKey.description == "generic.mytool:t1")
        #expect(context.cwd?.path == "/Users/me/www/vigie")
        #expect(context.tty == "/dev/ttys005")
        #expect(context.terminal?.program == "ghostty")
        #expect(context.at == Self.now)
        #expect(
            context.agentProcess == AgentProcessRef(pid: 150, startTime: Date(timeIntervalSince1970: 1_792_999_000)))
    }

    @Test func messagesBecomeDetails() {
        let blocked = GenericAgentMapping.normalize(Self.payload(.blocked, message: "Needs approval"), sentAt: Self.now)
        #expect(blocked == [.needsInput(blocked[0].context, reason: .permissionPrompt, message: "Needs approval")])
        let failed = GenericAgentMapping.normalize(Self.payload(.failed, message: "exit 3"), sentAt: Self.now)
        #expect(failed == [.sessionError(failed[0].context, message: "exit 3")])
        let empty = GenericAgentMapping.normalize(Self.payload(.failed, message: ""), sentAt: Self.now)
        #expect(empty == [.sessionError(empty[0].context, message: nil)])
    }

    @Test func invalidAgentOrSessionYieldsNothing() {
        #expect(GenericAgentMapping.normalize(Self.payload(.working, agent: "My Tool"), sentAt: Self.now).isEmpty)
        #expect(GenericAgentMapping.normalize(Self.payload(.working, agent: ""), sentAt: Self.now).isEmpty)
        #expect(GenericAgentMapping.normalize(Self.payload(.working, session: ""), sentAt: Self.now).isEmpty)
        #expect(GenericAgentMapping.normalize(Self.payload(nil), sentAt: Self.now).isEmpty)
    }

    @Test func sessionIDWithColonsKeepsItsIdentity() throws {
        let event = try #require(
            GenericAgentMapping.normalize(Self.payload(.working, session: "a:b:c"), sentAt: Self.now).first)
        let key = event.context.sessionKey
        #expect(key.description == "generic.mytool:a:b:c")
        #expect(SessionKey(key.description) == key)
    }

    // MARK: Agent process

    @Test(arguments: ["zsh", "-zsh", "bash", "-bash", "sh", "fish", "nu", "/bin/zsh", "dash"])
    func shellsAreSkipped(name: String) {
        #expect(GenericAgentMapping.isShell(name))
    }

    @Test(arguments: ["mytool", "node", "python3", "login", "zshell", "Terminal"])
    func nonShellsAreKept(name: String) {
        #expect(!GenericAgentMapping.isShell(name))
    }

    @Test func agentProcessIsFirstNonShellAncestor() {
        #expect(GenericAgentMapping.agentProcess(in: Self.ancestors)?.pid == 150)
        let direct = [ProcessInfoEntry(pid: 9, ppid: 8, name: "mytool", startTime: nil)] + Self.ancestors
        #expect(GenericAgentMapping.agentProcess(in: direct)?.pid == 9)
        let shellsOnly = [ProcessInfoEntry(pid: 9, ppid: 8, name: "zsh", startTime: nil)]
        #expect(GenericAgentMapping.agentProcess(in: shellsOnly) == nil)
        #expect(GenericAgentMapping.agentProcess(in: []) == nil)
    }

    // MARK: Pipeline

    @Test func pipelineMapsGenericWithoutAdapterOrSupportGate() throws {
        let pipeline = Self.pipeline()
        // No support was ever set: hooks would be gated, generic reports are not.
        let events = pipeline.normalize(try Self.message(Self.payload(.working)))
        #expect(events.map(\.name) == [.promptSubmit])
        #expect(events.first?.context.sessionKey == Self.key)
    }

    @Test func pipelineIgnoresUndecodablePayloads() {
        let pipeline = Self.pipeline()
        let bad = #"{"agent":"mytool","session":"t1","status":"sleeping"}"#
        #expect(
            pipeline.normalize(EventMessage(topic: "agent.generic", payload: Data(bad.utf8), sentAt: Self.now)).isEmpty)
        #expect(
            pipeline.normalize(EventMessage(topic: "agent.generic", payload: Data("{}".utf8), sentAt: Self.now)).isEmpty
        )
    }

    // MARK: Module

    func run(_ messages: [EventMessage]) async throws -> AgentsSessionsModule {
        // The tool process (pid 150) is alive; otherwise the start-up liveness pass would remove the sessions.
        let module = AgentsSessionsModule(
            adapters: AgentAdapters([FakeAdapter()]), terminals: TerminalAdapters([]),
            liveness: FakeLiveness(alive: [AgentProcessRef(Self.ancestors[2])]))
        let context = FakeModuleContext()
        try await module.start(context: context)
        for message in messages { context.fakeEvents.send(message) }
        context.fakeEvents.finish()
        await module.eventTask?.value
        return module
    }

    @Test func moduleTracksAGenericSession() async throws {
        let module = try await run([
            try Self.message(Self.payload(.working), at: Self.now),
            try Self.message(Self.payload(.blocked, message: "Needs approval"), at: Self.now + 1),
        ])
        let session = try #require(module.sessions.first)
        #expect(session.key == Self.key)
        #expect(session.status == .blocked)
        #expect(session.lastMessage == "Needs approval")
        #expect(session.projectName == "vigie")
        #expect(session.agentProcess?.pid == 150)
        #expect(module.agentName(session.agentID) == "mytool")
        #expect(module.tabSnapshot(now: Self.now + 2).rows.first?.id == "generic.mytool:t1")
        await module.stop()
    }

    @Test func idleReEntryAfterWork() async throws {
        let module = try await run([
            try Self.message(Self.payload(.idle), at: Self.now),
            try Self.message(Self.payload(.working), at: Self.now + 1),
            try Self.message(Self.payload(.done), at: Self.now + 2),
            try Self.message(Self.payload(.idle), at: Self.now + 3),
        ])
        let session = try #require(module.sessions.first)
        #expect(session.status == .idle)
        #expect(session.statusSince == Self.now + 3)
        await module.stop()
    }

    @Test func endRemovesTheSession() async throws {
        let module = try await run([
            try Self.message(Self.payload(.working), at: Self.now),
            try Self.message(Self.payload(nil, end: true), at: Self.now + 1),
        ])
        #expect(module.sessions.isEmpty)
        await module.stop()
    }

    @Test func replayedReportsConvergeToTheLiveState() async throws {
        let script: [(GenericStatus?, Bool, String, Double)] = [
            (.idle, false, "a", 0), (.working, false, "a", 1), (.working, false, "b", 2), (.failed, false, "b", 3),
            (.done, false, "a", 4), (.working, false, "c", 5), (nil, true, "c", 6), (.blocked, false, "d", 7),
        ]
        func play(replayed: Bool) async throws -> [Session] {
            let module = try await run(
                try script.map { status, end, session, offset in
                    try Self.message(
                        Self.payload(status, end: end, session: session), at: Self.now + offset, replayed: replayed)
                })
            defer { Task { await module.stop() } }
            return module.sessions
        }
        let live = try await play(replayed: false)
        let replayed = try await play(replayed: true)
        #expect(replayed == live)
        #expect(live.map(\.status) == [.blocked, .failed, .done])
    }
}
