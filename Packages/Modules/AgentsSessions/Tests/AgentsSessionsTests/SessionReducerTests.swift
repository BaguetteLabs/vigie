import AgentKit
import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import AgentsSessions

/// Fixed dates: `t(n)` is n seconds after a fixed origin.
func t(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }

let keyA = SessionKey(agentID: "claude", sessionID: "a")
let keyB = SessionKey(agentID: "claude", sessionID: "b")

func ctx(_ key: SessionKey = keyA, at: Date, tty: String? = nil, cwd: String? = nil) -> AgentEventContext {
    AgentEventContext(sessionKey: key, cwd: cwd.map { URL(fileURLWithPath: $0) }, tty: tty, at: at)
}

/// One event of each SPEC name for `key` at `at`.
func event(_ name: AgentEvent.Name, _ key: SessionKey = keyA, at: Date) -> AgentEvent {
    let context = ctx(key, at: at)
    return switch name {
    case .sessionStart: .sessionStart(context, model: "opus")
    case .promptSubmit: .promptSubmit(context)
    case .toolStart: .toolStart(context, tool: "Edit")
    case .toolEnd: .toolEnd(context, tool: "Edit")
    case .subagentEnd: .subagentEnd(context)
    case .needsInput: .needsInput(context, reason: .question, message: "Which file?")
    case .turnEnd: .turnEnd(context)
    case .sessionError: .sessionError(context, message: "Connection lost")
    case .sessionEnd: .sessionEnd(context, reason: "prompt_input_exit")
    }
}

func session(_ status: SessionStatus, _ key: SessionKey = keyA, since: Date = t(0), last: Date? = nil) -> Session {
    Session(key: key, status: status, statusSince: since, lastEventAt: last ?? since)
}

@Suite struct SessionReducerTests {
    static let storedStatuses: [SessionStatus] = [.idle, .working, .done, .blocked, .failed]

    static let table: [(AgentEvent.Name, SessionStatus?)] = [
        (.sessionStart, .idle),
        (.promptSubmit, .working),
        (.toolStart, .working),
        (.toolEnd, .working),
        (.subagentEnd, .working),
        (.turnEnd, .done),
        (.needsInput, .blocked),
        (.sessionError, .failed),
        (.sessionEnd, nil),
    ]

    @Test(arguments: SessionReducerTests.table)
    func everyTransitionFromEveryStatus(name: AgentEvent.Name, expected: SessionStatus?) throws {
        for from in Self.storedStatuses {
            var sessions = [keyA: session(from, since: t(0))]
            let change = SessionReducer.apply(event(name, at: t(10)), to: &sessions)
            guard let expected else {
                #expect(sessions[keyA] == nil, "\(name) from \(from)")
                #expect(change == .removed(keyA, last: from))
                #expect(change.persists)
                continue
            }
            let after = try #require(sessions[keyA])
            #expect(after.status == expected, "\(name) from \(from)")
            #expect(after.lastEventAt == t(10))
            if from == expected {
                #expect(change == .metadataOnly(keyA))
                #expect(!change.persists)
                #expect(after.statusSince == t(0), "re-entering \(expected) keeps statusSince")
            } else {
                #expect(change == .status(keyA, from: from, to: expected))
                #expect(change.persists)
                #expect(after.statusSince == t(10), "statusSince is the entering event's sent_at")
            }
        }
    }

    @Test(arguments: SessionReducerTests.table)
    func unknownSessionIsCreatedInTheEventStatus(name: AgentEvent.Name, expected: SessionStatus?) {
        var sessions: [SessionKey: Session] = [:]
        let change = SessionReducer.apply(event(name, at: t(5)), to: &sessions)
        if let expected {
            #expect(change == .created(keyA, expected))
            #expect(sessions[keyA]?.status == expected)
            #expect(sessions[keyA]?.statusSince == t(5))
        } else {
            #expect(change == .none)
            #expect(sessions.isEmpty)
        }
    }

    @Test func outOfOrderEventKeepsStatusButFillsMetadata() throws {
        var sessions = [keyA: session(.done, since: t(100))]
        let late = AgentEvent.toolStart(ctx(at: t(50), tty: "/dev/ttys009", cwd: "/Users/me/www/vigie"), tool: "Bash")
        let change = SessionReducer.apply(late, to: &sessions)
        let after = try #require(sessions[keyA])
        #expect(change == .metadataOnly(keyA))
        #expect(after.status == .done)
        #expect(after.statusSince == t(100))
        #expect(after.lastEventAt == t(100))
        #expect(after.lastAction == "Bash")
        #expect(after.tty == "/dev/ttys009")
        #expect(after.projectName == "vigie")
    }

    @Test func outOfOrderEventNeverOverwritesNewerMetadata() {
        var sessions: [SessionKey: Session] = [:]
        SessionReducer.apply(.toolStart(ctx(at: t(100), tty: "/dev/new"), tool: "Edit"), to: &sessions)
        let change = SessionReducer.apply(.toolEnd(ctx(at: t(50), tty: "/dev/old"), tool: "Bash"), to: &sessions)
        #expect(change == .none)
        #expect(sessions[keyA]?.lastAction == "Edit")
        #expect(sessions[keyA]?.tty == "/dev/new")
    }

    @Test func lateSessionEndAndLateBlockAreIgnored() {
        var sessions = [keyA: session(.working, since: t(100))]
        #expect(SessionReducer.apply(event(.sessionEnd, at: t(90)), to: &sessions) == .none)
        #expect(SessionReducer.apply(event(.needsInput, at: t(90)), to: &sessions) == .none)
        #expect(sessions[keyA]?.status == .working)
        #expect(sessions[keyA]?.blockReason == nil)
    }

    @Test func sameTimestampIsInOrder() {
        var sessions = [keyA: session(.working, since: t(100))]
        SessionReducer.apply(event(.turnEnd, at: t(100)), to: &sessions)
        #expect(sessions[keyA]?.status == .done)
    }

    @Test func blockReasonAndMessageFollowTheStatus() {
        var sessions = [keyA: session(.working)]
        SessionReducer.apply(event(.needsInput, at: t(10)), to: &sessions)
        #expect(sessions[keyA]?.blockReason == .question)
        #expect(sessions[keyA]?.lastMessage == "Which file?")
        SessionReducer.apply(event(.promptSubmit, at: t(20)), to: &sessions)
        #expect(sessions[keyA]?.blockReason == nil)
        #expect(sessions[keyA]?.lastMessage == nil)
        SessionReducer.apply(event(.sessionError, at: t(30)), to: &sessions)
        #expect(sessions[keyA]?.lastMessage == "Connection lost")
    }

    @Test func metadataFromEvents() {
        var sessions: [SessionKey: Session] = [:]
        SessionReducer.apply(event(.sessionStart, at: t(0)), to: &sessions)
        #expect(sessions[keyA]?.model == "opus")
        SessionReducer.apply(.toolStart(ctx(at: t(1), cwd: "/tmp/proj"), tool: "Read"), to: &sessions)
        #expect(sessions[keyA]?.lastAction == "Read")
        #expect(sessions[keyA]?.cwd?.path == "/tmp/proj")
        // An event without a cwd keeps the known one.
        SessionReducer.apply(event(.toolEnd, at: t(2)), to: &sessions)
        #expect(sessions[keyA]?.cwd?.path == "/tmp/proj")
    }

    @Test func workingKeepsItsStartAcrossHeartbeats() {
        var sessions: [SessionKey: Session] = [:]
        SessionReducer.apply(event(.promptSubmit, at: t(0)), to: &sessions)
        for second in 1...5 {
            SessionReducer.apply(event(.toolStart, at: t(Double(second) * 60)), to: &sessions)
        }
        #expect(sessions[keyA]?.statusSince == t(0))
        #expect(sessions[keyA]?.lastEventAt == t(300))
    }

    // MARK: done_to_idle

    @Test func doneExpiresToIdleFromSentAt() {
        var sessions = [keyA: session(.done, since: t(0)), keyB: session(.working, keyB, since: t(0))]
        let delay = Duration.seconds(900)
        #expect(SessionReducer.expireDone(in: &sessions, now: t(899), doneToIdle: delay).isEmpty)
        #expect(sessions[keyA]?.status == .done)
        #expect(SessionReducer.expireDone(in: &sessions, now: t(900), doneToIdle: delay) == [keyA])
        #expect(sessions[keyA]?.status == .idle)
        #expect(sessions[keyA]?.statusSince == t(900))
        #expect(sessions[keyB]?.status == .working)
    }

    @Test func newPromptResetsTheDoneTimer() {
        var sessions: [SessionKey: Session] = [:]
        SessionReducer.apply(event(.turnEnd, at: t(0)), to: &sessions)
        SessionReducer.apply(event(.promptSubmit, at: t(600)), to: &sessions)
        SessionReducer.apply(event(.turnEnd, at: t(700)), to: &sessions)
        let delay = Duration.seconds(900)
        #expect(SessionReducer.expireDone(in: &sessions, now: t(1000), doneToIdle: delay).isEmpty)
        #expect(sessions[keyA]?.status == .done)
        #expect(SessionReducer.expireDone(in: &sessions, now: t(1600), doneToIdle: delay) == [keyA])
    }

    // MARK: Sorting and module state

    @Test func urgencyOrderWithTiesByRecency() {
        let blockedOld = session(.blocked, SessionKey(agentID: "claude", sessionID: "blocked-old"), since: t(10))
        let failedNew = session(.failed, SessionKey(agentID: "claude", sessionID: "failed-new"), since: t(50))
        let blockedNew = session(.blocked, SessionKey(agentID: "claude", sessionID: "blocked-new"), since: t(40))
        let doneOld = session(.done, SessionKey(agentID: "claude", sessionID: "done-old"), since: t(1))
        let doneNew = session(.done, SessionKey(agentID: "claude", sessionID: "done-new"), since: t(99))
        let working = session(.working, SessionKey(agentID: "claude", sessionID: "working"), since: t(200))
        let idle = session(.idle, SessionKey(agentID: "claude", sessionID: "idle"), since: t(300))
        let input = [idle, working, doneOld, blockedOld, doneNew, failedNew, blockedNew]
        let order = SessionReducer.sorted(input).map(\.key.sessionID)
        #expect(order == ["failed-new", "blocked-new", "blocked-old", "done-new", "done-old", "working", "idle"])
    }

    @Test func moduleStateMapping() {
        #expect(SessionReducer.moduleState(for: []) == .ambient)
        #expect(SessionReducer.moduleState(for: [session(.idle)]) == .ambient)
        #expect(SessionReducer.moduleState(for: [session(.idle), session(.done, keyB)]) == .active)
        #expect(SessionReducer.moduleState(for: [session(.working)]) == .active)
        #expect(SessionReducer.moduleState(for: [session(.working), session(.blocked, keyB)]) == .alert)
        #expect(SessionReducer.moduleState(for: [session(.idle), session(.failed, keyB)]) == .alert)
    }

    // MARK: Store

    @MainActor @Test func storeBumpsGenerationOnlyOnPersistedChanges() {
        let store = SessionStore()
        store.apply(event(.promptSubmit, at: t(0)))
        #expect(store.generation == 1)
        store.apply(event(.toolStart, at: t(1)))
        #expect(store.generation == 1)
        store.apply(event(.turnEnd, at: t(2)))
        #expect(store.generation == 2)
        #expect(store.state == .active)
        store.expireDone(now: t(2 + 900), doneToIdle: .seconds(900))
        #expect(store.generation == 3)
        #expect(store.sessions.map(\.status) == [.idle])
        #expect(store.state == .ambient)
    }

    @Test func sessionCodableRoundTrip() throws {
        var sessions: [SessionKey: Session] = [:]
        SessionReducer.apply(
            .needsInput(
                AgentEventContext(
                    sessionKey: SessionKey(agentID: "claude", sessionID: "x:y"),
                    cwd: URL(fileURLWithPath: "/tmp/p"), tty: "/dev/ttys1",
                    terminal: TerminalHint(program: "WarpTerminal", sessionID: "w", warpFocusURL: nil, bundleID: nil),
                    agentProcess: AgentProcessRef(pid: 42, startTime: t(0)), at: t(5)),
                reason: .permissionPrompt, message: "Allow Bash?"),
            to: &sessions)
        let original = Array(sessions.values)
        let data = try FakeStorage.encoder.encode(original)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"key\":\"claude:x:y\""))
        #expect(json.contains("\"status_since\""))
        let decoded = try FakeStorage.decoder.decode([Session].self, from: data)
        #expect(decoded == original)
    }
}
