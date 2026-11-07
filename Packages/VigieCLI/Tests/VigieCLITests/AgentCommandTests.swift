import Foundation
import Synchronization
import Testing
import Wire

@testable import VigieCLI

@Suite struct AgentCommandTests {
    static let fixedDate = Date(timeIntervalSince1970: 1_793_000_000.5)
    static let ancestors = (0..<10).map {
        ProcessInfoEntry(pid: 100 + Int32($0), ppid: 101 + Int32($0), name: $0 == 0 ? "zsh" : "p\($0)", startTime: nil)
    }
    static let caller = AgentCommand.Caller(
        tty: "/dev/ttys004",
        environment: ["TERM_PROGRAM": "ghostty", "PWD": "/tmp/x", "SECRET_TOKEN": "nope", "WARP_X": "1"],
        ancestors: ancestors,
        currentDirectory: "/Users/me/www")

    struct Run {
        var status: Int32
        var output: [String]
        var errors: [String]
        var logs: [String]
    }

    /// Runs the CLI against a scratch socket path (nothing listens) and spool.
    static func run(_ arguments: [String], in folder: URL) -> Run {
        var output: [String] = []
        var errors: [String] = []
        var logs: [String] = []
        let delivery = Delivery(
            socketPath: folder.appendingPathComponent("s.sock").path,
            spoolURL: folder.appendingPathComponent("spool/spool.jsonl"),
            deadline: .now.advanced(by: HookCommand.budget))
        let status = CLI.run(
            arguments: ["agent"] + arguments, delivery: delivery, agentCaller: { caller },
            log: { logs.append($0) }, now: { fixedDate }, errorOutput: { errors.append($0) },
            output: { output.append($0) })
        return Run(status: status, output: output, errors: errors, logs: logs)
    }

    static func spooled(in folder: URL) throws -> [Envelope] {
        let url = folder.appendingPathComponent("spool/spool.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Data(contentsOf: url).split(separator: 0x0A).map { try Envelope.decodeLine(Data($0)) }
    }

    // MARK: Parsing

    @Test(arguments: [
        (
            ["--agent", "mytool", "--session", "t1", "--status", "working", "--cwd", "/w"],
            AgentCommand.Options(agent: "mytool", session: "t1", status: .working, cwd: "/w")
        ),
        (
            ["--status", "blocked", "--message", "Needs approval", "--session", "a:b", "--agent", "my-tool_2"],
            AgentCommand.Options(agent: "my-tool_2", session: "a:b", status: .blocked, message: "Needs approval")
        ),
        (
            ["--agent=mytool", "--session=t1", "--end"],
            AgentCommand.Options(agent: "mytool", session: "t1", status: nil, end: true)
        ),
        (
            ["--agent", "mytool", "--session", "t1", "--status", "done", "--cwd", "", "--message", ""],
            AgentCommand.Options(agent: "mytool", session: "t1", status: .done)
        ),
        (
            ["--agent", "mytool", "--session", "t1", "--status=failed"],
            AgentCommand.Options(agent: "mytool", session: "t1", status: .failed)
        ),
        (
            ["--agent", "mytool", "--session", "t1", "--status", "idle"],
            AgentCommand.Options(agent: "mytool", session: "t1", status: .idle)
        ),
    ])
    func parsesValidFlags(arguments: [String], expected: AgentCommand.Options) throws {
        #expect(try AgentCommand.parse(arguments: arguments) == expected)
    }

    @Test(arguments: [
        (["--session", "t1", "--status", "working"], AgentCommand.ArgumentError.missingAgent),
        (["--agent", "", "--session", "t1", "--status", "working"], .missingAgent),
        (["--agent", "mytool", "--status", "working"], .missingSession),
        (["--agent", "mytool", "--session", "", "--status", "working"], .missingSession),
        (["--agent", "mytool", "--session", "t1"], .missingStatus),
        (["--agent", "mytool", "--session", "t1", "--status", "working", "--end"], .statusAndEnd),
        (["--agent", "mytool", "--session", "t1", "--status", "sleeping"], .invalidStatus("sleeping")),
        (["--agent", "mytool", "--session", "t1", "--status", "Working"], .invalidStatus("Working")),
        (["--agent", "MyTool", "--session", "t1", "--status", "working"], .invalidAgent("MyTool")),
        (["--agent", "generic.x", "--session", "t1", "--status", "working"], .invalidAgent("generic.x")),
        (["--agent", "mytool", "--session", "t1", "--status"], .missingValue("--status")),
        (["--agent", "mytool", "--agent", "x", "--session", "t1", "--end"], .duplicateFlag("--agent")),
        (["--agent", "mytool", "--session", "t1", "--end", "--end"], .duplicateFlag("--end")),
        (["--agent", "mytool", "--session", "t1", "--end", "--pid", "3"], .unknownFlag("--pid")),
        (["--agent", "mytool", "--session", "t1", "--end", "extra"], .unknownFlag("extra")),
    ])
    func rejectsInvalidFlags(arguments: [String], expected: AgentCommand.ArgumentError) {
        #expect(throws: expected) { try AgentCommand.parse(arguments: arguments) }
    }

    @Test func usageErrorIsOneStderrLineAndExitTwo() throws {
        let folder = try HookCommandTests.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = Self.run(["--agent", "mytool", "--session", "t1", "--status", "nope"], in: folder)
        #expect(result.status == CLI.usageErrorStatus)
        #expect(result.output.isEmpty)
        #expect(result.errors.count == 1)
        let line = try #require(result.errors.first)
        #expect(!line.contains("\n"))
        #expect(line.contains("“nope”"))
        #expect(line.contains("--status working|blocked|done|failed|idle | --end"))
        #expect(!line.contains("cli.agent."))
        #expect(try Self.spooled(in: folder).isEmpty)
    }

    @Test func everyErrorHasACatalogMessage() {
        let errors: [AgentCommand.ArgumentError] = [
            .unknownFlag("x"), .missingValue("--cwd"), .duplicateFlag("--agent"), .missingAgent, .missingSession,
            .invalidAgent("X"), .invalidStatus("s"), .missingStatus, .statusAndEnd,
        ]
        for error in errors {
            let line = CLI.message(for: error)
            #expect(!line.contains("cli.agent."), "\(error)")
            #expect(line.hasPrefix("vigie agent: "), "\(error)")
        }
    }

    @Test func usageMentionsAgent() {
        #expect(CLI.usage.contains("agent --agent <id> --session <id>"))
    }

    // MARK: Payload

    @Test func payloadCarriesFlagsAndCallerContext() throws {
        let options = AgentCommand.Options(
            agent: "mytool", session: "t1", status: .blocked, cwd: "proj/../vigie", message: "Needs approval")
        let command = AgentCommand(options: options, caller: Self.caller, now: { Self.fixedDate })
        let envelope = try command.makeEnvelope()
        #expect(envelope.topic == Topic.agentGeneric)
        #expect(envelope.sentAt == Self.fixedDate)
        let payload = try envelope.payload.decode(as: GenericAgentPayload.self)
        #expect(payload.agent == "mytool")
        #expect(payload.session == "t1")
        #expect(payload.status == .blocked)
        #expect(!payload.end)
        #expect(payload.cwd == "/Users/me/www/vigie")
        #expect(payload.message == "Needs approval")
        #expect(payload.tty == "/dev/ttys004")
        #expect(payload.env == ["TERM_PROGRAM": "ghostty", "PWD": "/tmp/x", "WARP_X": "1"])
        #expect(payload.ancestors == Array(Self.ancestors.prefix(HookPayload.maxAncestors)))
    }

    @Test func absoluteCwdIsKept() {
        let options = AgentCommand.Options(agent: "mytool", session: "t1", status: .working, cwd: "/a/b")
        #expect(AgentCommand(options: options, caller: Self.caller).makePayload().cwd == "/a/b")
    }

    // MARK: Delivery

    @Test func deliversOneLineThroughTheGivenDelivery() throws {
        let options = AgentCommand.Options(agent: "mytool", session: "t1", status: nil, end: true)
        let command = AgentCommand(options: options, caller: Self.caller, now: { Self.fixedDate })
        let lines = Mutex<[Data]>([])
        let outcome = command.run(
            deliver: { line in
                lines.withLock { $0.append(line) }
                return .sent
            }, log: { _ in Issue.record("no log on a normal send") })
        #expect(outcome == .sent)
        let sent = lines.withLock { $0 }
        #expect(sent.count == 1)
        let envelope = try Envelope.decodeLine(try #require(sent.first))
        #expect(envelope.topic == "agent.generic")
        #expect(try envelope.payload.decode(as: GenericAgentPayload.self).end)
    }

    @Test func reservedAgentIDIsLoggedAndDropped() throws {
        for agent in ["claude", "codex", "gemini"] {
            let options = AgentCommand.Options(agent: agent, session: "t1", status: .working)
            let command = AgentCommand(options: options, caller: Self.caller)
            var logs: [String] = []
            let outcome = command.run(
                deliver: { _ in
                    Issue.record("reserved id delivered")
                    return .sent
                }, log: { logs.append($0) })
            #expect(outcome == .dropped)
            #expect(logs.count == 1)
            #expect(logs.first?.contains(agent) == true)
        }
    }

    @Test func reservedAgentIDThroughCLIIsSilentExitZeroAndNotSpooled() throws {
        let folder = try HookCommandTests.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = Self.run(["--agent", "claude", "--session", "t1", "--status", "working"], in: folder)
        #expect(result.status == 0)
        #expect(result.output.isEmpty)
        #expect(result.errors.isEmpty)
        #expect(result.logs.count == 1)
        #expect(try Self.spooled(in: folder).isEmpty)
    }

    @Test func successIsSilentExitZeroAndSpooledWithoutApp() throws {
        let folder = try HookCommandTests.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = Self.run(
            ["--agent", "mytool", "--session", "t1", "--status", "working", "--cwd", "/Users/me/www/vigie"],
            in: folder)
        #expect(result.status == 0)
        #expect(result.output.isEmpty)
        #expect(result.errors.isEmpty)
        #expect(result.logs.isEmpty)
        let envelopes = try Self.spooled(in: folder)
        #expect(envelopes.count == 1)
        let envelope = try #require(envelopes.first)
        #expect(envelope.topic == "agent.generic")
        #expect(envelope.sentAt == Self.fixedDate)
        let payload = try envelope.payload.decode(as: GenericAgentPayload.self)
        #expect(payload.status == .working)
        #expect(payload.cwd == "/Users/me/www/vigie")
        #expect(payload.tty == "/dev/ttys004")
    }

    @Test func failedDeliveryIsStillSilentExitZero() throws {
        var output: [String] = []
        var errors: [String] = []
        // Spool under a regular file: the directory cannot be created, so the line is dropped.
        let folder = try HookCommandTests.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let blocker = folder.appendingPathComponent("file")
        try Data().write(to: blocker)
        let delivery = Delivery(
            socketPath: folder.appendingPathComponent("s.sock").path,
            spoolURL: blocker.appendingPathComponent("spool.jsonl"), deadline: .now)
        let status = CLI.run(
            arguments: ["agent", "--agent", "mytool", "--session", "t1", "--end"], delivery: delivery,
            agentCaller: { Self.caller }, log: { _ in }, errorOutput: { errors.append($0) },
            output: { output.append($0) })
        #expect(status == 0)
        #expect(output.isEmpty)
        #expect(errors.isEmpty)
    }
}
