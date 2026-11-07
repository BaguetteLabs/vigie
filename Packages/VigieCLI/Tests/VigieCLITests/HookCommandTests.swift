import Darwin
import Foundation
import Testing
import Wire

@testable import VigieCLI

@Suite struct HookCommandTests {
    static let claudeStop = Data(
        #"""
        {"session_id":"9b1c","transcript_path":"/Users/romain/.claude/projects/p/9b1c.jsonl","cwd":"/Users/romain/p",
         "permission_mode":"default","hook_event_name":"Stop","stop_hook_active":false}
        """#.utf8)

    static let fixedDate = Date(timeIntervalSince1970: 1_793_000_000.25)

    /// A short, unique scratch folder (socket paths must fit in 104 bytes).
    static func scratch() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/vt-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func command(
        stdin: Data = claudeStop, environment: [String: String] = [:], in folder: URL,
        deadline: ContinuousClock.Instant = .now.advanced(by: HookCommand.budget)
    ) -> HookCommand {
        HookCommand(
            agent: "claude", stdin: stdin, environment: environment, tty: "/dev/ttys009",
            ancestors: [ProcessInfoEntry(pid: 42, ppid: 41, name: "claude", startTime: fixedDate)],
            socketPath: folder.appendingPathComponent("s.sock").path,
            spoolURL: folder.appendingPathComponent("spool/spool.jsonl"),
            now: { fixedDate }, deadline: deadline)
    }

    static func spoolLines(in folder: URL) throws -> [Data] {
        let data = try Data(contentsOf: folder.appendingPathComponent("spool/spool.jsonl"))
        return data.split(separator: 0x0A, omittingEmptySubsequences: false).dropLast().map { Data($0) }
    }

    @Test func buildsEnvelopeFromClaudeStdin() throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let envelope = try Self.command(environment: ["TERM_PROGRAM": "iTerm.app", "HOME": "/x"], in: folder)
            .makeEnvelope()
        #expect(envelope.v == WireProtocol.version)
        #expect(envelope.topic == "agent.hook")
        #expect(envelope.sentAt == Self.fixedDate)
        let payload = try envelope.payload.decode(as: HookPayload.self)
        #expect(payload.agent == "claude")
        #expect(payload.raw["hook_event_name"] == .string("Stop"))
        #expect(payload.raw["stop_hook_active"] == .bool(false))
        #expect(payload.tty == "/dev/ttys009")
        #expect(payload.env == ["TERM_PROGRAM": "iTerm.app"])
        #expect(payload.ancestors.map(\.name) == ["claude"])
    }

    @Test func emptyStdinIsNull() {
        #expect(HookCommand.parseRaw(Data()) == .null)
        #expect(HookCommand.parseRaw(Data(" \n".utf8)) == .null)
    }

    @Test func garbageStdinIsKeptAsString() {
        #expect(HookCommand.parseRaw(Data("not json {".utf8)) == .string("not json {"))
    }

    @Test func fallsBackToSpoolWhenSocketIsMissing() throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(Self.command(in: folder).run() == .spooled)
        let lines = try Self.spoolLines(in: folder)
        #expect(lines.count == 1)
        let envelope = try Envelope.decodeLine(try #require(lines.first))
        #expect(try envelope.payload.decode(as: HookPayload.self).raw["session_id"] == .string("9b1c"))
        let attributes = try FileManager.default.attributesOfItem(
            atPath: folder.appendingPathComponent("spool/spool.jsonl").path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test func spoolAppendsOneLinePerRun() throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        for _ in 0..<3 { Self.command(in: folder).run() }
        #expect(try Self.spoolLines(in: folder).count == 3)
    }

    @Test func truncatesLinesAboveOneMiB() throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let big = String(repeating: "x", count: HookCommand.maxLineBytes + 10)
        let raw: JSONValue = .object([
            "session_id": .string("s1"), "hook_event_name": .string("PostToolUse"), "cwd": .string("/w"),
            "tool_response": .string(big),
        ])
        let line = try Self.command(stdin: JSONEncoder().encode(raw), in: folder).makeLine()
        #expect(line.count < 4096)
        let payload = try Envelope.decodeLine(line).payload.decode(as: HookPayload.self)
        #expect(
            payload.raw
                == .object([
                    "truncated": .bool(true), "session_id": .string("s1"),
                    "hook_event_name": .string("PostToolUse"), "cwd": .string("/w"),
                ]))
        #expect(payload.agent == "claude")
    }

    @Test func smallLinesAreNotTruncated() throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let payload = try Envelope.decodeLine(Self.command(in: folder).makeLine()).payload
        #expect(payload["raw"]?["truncated"] == nil)
    }

    @Test func sendsToListeningSocket() async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = try TestServer(path: folder.appendingPathComponent("s.sock").path)
        let received = Task.detached { server.acceptOneLine() }
        #expect(Self.command(in: folder).run() == .sent)
        let line = try #require(await received.value)
        #expect(try Envelope.decodeLine(line).topic == "agent.hook")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("spool/spool.jsonl").path))
    }

    @Test func stalledListenerTimesOutAndSpools() async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = try TestServer(path: folder.appendingPathComponent("s.sock").path)
        // Accepted but never read: a line larger than the socket buffer cannot be written in time.
        let held = Task.detached { server.acceptAndHold(for: .milliseconds(400)) }
        let big = try JSONEncoder().encode(
            JSONValue.object(["session_id": .string("s"), "pad": .string(String(repeating: "y", count: 900_000))]))
        let start = ContinuousClock.now
        let outcome = Self.command(stdin: big, in: folder, deadline: start.advanced(by: .milliseconds(60))).run()
        let elapsed = start.duration(to: .now)
        #expect(outcome == .spooled)
        #expect(elapsed < .milliseconds(150))
        #expect(try Self.spoolLines(in: folder).count == 1)
        await held.value
    }

    @Test func hookCommandNeverWritesOutputAndExitsZero() {
        let arguments: [[String]] = [["hook", "claude"], ["hook"], ["hook", ""], ["hook", "claude", "extra"]]
        for args in arguments {
            var lines: [String] = []
            let status = CLI.run(arguments: args, hookRunner: { _, _ in }, output: { lines.append($0) })
            #expect(status == 0)
            #expect(lines.isEmpty)
        }
    }

    @Test func garbageStdinStillDeliversAndExitsZero() throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let command = Self.command(stdin: Data([0xFF, 0x00, 0x7B]), in: folder)
        var lines: [String] = []
        let status = CLI.run(
            arguments: ["hook", "claude"], hookRunner: { _, _ in command.run() }, output: { lines.append($0) })
        #expect(status == 0)
        #expect(lines.isEmpty)
        #expect(try Self.spoolLines(in: folder).count == 1)
    }

    @Test func ancestorsOfThisProcessAreBoundedAndLinked() {
        let chain = ProcessInspector.ancestors(of: getpid())
        #expect(!chain.isEmpty)
        #expect(chain.count <= HookPayload.maxAncestors)
        #expect(chain.first?.pid == getpid())
        for (child, parent) in zip(chain, chain.dropFirst()) { #expect(child.ppid == parent.pid) }
        #expect(chain.allSatisfy { $0.pid > 1 && !$0.name.isEmpty && $0.startTime != nil })
    }

    @Test func claudeFixturesBuildValidEnvelopes() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/claude")
        let files =
            FileManager.default.enumerator(at: fixtures, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "json" } ?? []
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        var events: Set<String> = []
        for file in files {
            // `<event>.json` or `<event>.<variant>.json`
            let event = String(file.lastPathComponent.prefix { $0 != "." })
            let data = try Data(contentsOf: file)
            let payload = try Envelope.decodeLine(Self.command(stdin: data, in: folder).makeLine())
                .payload.decode(as: HookPayload.self)
            #expect(payload.raw["hook_event_name"]?.stringValue == event)
            #expect(payload.raw["session_id"]?.stringValue != nil)
            #expect(payload.raw == (try JSONDecoder().decode(JSONValue.self, from: data)))
            events.insert(event)
        }
        #expect(
            events == [
                "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop",
                "SubagentStop", "SessionEnd",
            ])
    }
}

/// Minimal blocking AF_UNIX server for one connection.
final class TestServer: Sendable {
    let fd: Int32

    init(path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 4) == 0 else { throw POSIXError(.EADDRINUSE) }
    }

    deinit { close(fd) }

    func acceptAndHold(for duration: Duration) {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        Thread.sleep(
            forTimeInterval: Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
        close(client)
    }

    func acceptOneLine() -> Data? {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return nil }
        defer { close(client) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
            if data.last == 0x0A { break }
        }
        return data
    }
}
