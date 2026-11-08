import AgentKit
import Foundation
import Testing

@testable import ClaudeAdapter

/// A temporary `~` with `.claude/projects`, removed when the value goes away.
final class TempHome {
    let url: URL
    var projects: URL { url.appendingPathComponent(".claude/projects", isDirectory: true) }

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-log-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ relative: String, _ text: String) throws -> URL {
        let file = projects.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        return file
    }

    func append(_ file: URL, _ text: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }
}

enum LogLine {
    static func assistant(
        session: String = "s1", message: String, request: String = "req_1", model: String = "claude-opus-5-5",
        at: String = "2026-11-07T10:00:00.000Z", cwd: String? = "/Users/me/app", input: Int = 10,
        output: Int = 20, cacheCreate: Int = 30, cacheRead: Int = 40
    ) -> String {
        let cwdField = cwd.map { #","cwd":"\#($0)""# } ?? ""
        return
            #"{"type":"assistant","timestamp":"\#(at)","sessionId":"\#(session)","requestId":"\#(request)"\#(cwdField),"message":{"id":"\#(message)","model":"\#(model)","role":"assistant","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(cacheCreate),"cache_read_input_tokens":\#(cacheRead)}}}"#
            + "\n"
    }

    static let user =
        #"{"type":"user","timestamp":"2026-11-07T09:59:00.000Z","sessionId":"s1","message":{"role":"user","content":"hi"}}"#
        + "\n"
    static let malformed = #"{"type":"assistant","message":{"id":"broken""# + "\n"
}

@Suite struct ClaudeLogReaderTests {
    @Test func parsesCompleteLinesAndStopsBeforeAPartialOne() async throws {
        let home = try TempHome()
        let complete =
            LogLine.user + LogLine.assistant(message: "m1") + LogLine.malformed
            + LogLine.assistant(message: "m0", model: "<synthetic>")
        let partial = String(LogLine.assistant(message: "m2").dropLast(15))
        let file = try home.write("-Users-me-app/s1.jsonl", complete + partial)
        let reader = ClaudeLogReader(homeDirectory: home.url)

        let chunk = try await reader.readUsage(from: file, offset: 0)
        #expect(chunk.records.map(\.messageID) == ["m1"])
        #expect(chunk.skippedLines == 2)
        #expect(chunk.malformedLines == 1)
        #expect(chunk.nextOffset == UInt64(Data(complete.utf8).count))

        let record = try #require(chunk.records.first)
        #expect(record.model == "claude-opus-5-5")
        #expect(record.project == "/Users/me/app")
        #expect(record.sessionID == "s1" && record.requestID == "req_1")
        let tokens: [Int] = [
            record.inputTokens, record.outputTokens, record.cacheCreationTokens, record.cacheReadTokens,
        ]
        #expect(tokens == [10, 20, 30, 40])
        #expect(record.at == ISO8601DateFormatter().date(from: "2026-11-07T10:00:00Z"))

        // The partial line completes: a read from the stored offset returns only it.
        try home.append(file, String(LogLine.assistant(message: "m2").suffix(15)))
        let next = try await reader.readUsage(from: file, offset: chunk.nextOffset)
        #expect(next.records.map(\.messageID) == ["m2"])
        #expect(next.skippedLines == 0 && next.malformedLines == 0)
        #expect(next.nextOffset == UInt64(try Data(contentsOf: file).count))

        // Nothing new: same offset, no records.
        let again = try await reader.readUsage(from: file, offset: next.nextOffset)
        #expect(again.records.isEmpty && again.nextOffset == next.nextOffset)
    }

    @Test func enumeratesNestedJSONLFilesOnly() async throws {
        let home = try TempHome()
        try home.write("-a/s1.jsonl", "")
        try home.write("-a/s1/subagents/agent-1.jsonl", "")
        try home.write("-b/s2.jsonl", "")
        try home.write("-b/notes.txt", "")
        let files = try await ClaudeLogReader(homeDirectory: home.url).logFiles()
        #expect(files.map(\.lastPathComponent) == ["s1.jsonl", "agent-1.jsonl", "s2.jsonl"])
    }

    @Test func missingRootIsEmpty() async throws {
        let reader = ClaudeLogReader(roots: [URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")])
        #expect(try await reader.logFiles().isEmpty)
    }

    @Test func projectFallsBackToTheProjectFolder() async throws {
        let home = try TempHome()
        let file = try home.write("-Users-me-tool/s9/subagents/a.jsonl", LogLine.assistant(message: "m", cwd: nil))
        let chunk = try await ClaudeLogReader(homeDirectory: home.url).readUsage(from: file, offset: 0)
        #expect(chunk.records.first?.project == "-Users-me-tool")
    }

    @Test func readSinceKeepsTheLastWritePerResponse() async throws {
        let home = try TempHome()
        try home.write(
            "-p/s1.jsonl",
            LogLine.assistant(message: "m1", output: 5) + LogLine.assistant(message: "m1", output: 50)
                + LogLine.assistant(message: "m2", at: "2026-11-07T11:00:00.000Z"))
        let reader = ClaudeLogReader(homeDirectory: home.url)
        let all = try await reader.read(since: nil)
        #expect(all.count == 2)
        guard case .object(let first) = all[0].raw else {
            Issue.record("not an object")
            return
        }
        #expect(first["output_tokens"] == .number(50))
        let later = try await reader.read(since: ISO8601DateFormatter().date(from: "2026-11-07T10:30:00Z"))
        #expect(later.count == 1)
    }

    @Test func adapterReadsUnderItsHome() async throws {
        let home = try TempHome()
        try home.write("-p/s1.jsonl", LogLine.assistant(message: "m1"))
        let reader = try #require(ClaudeAdapter(homeDirectory: home.url).logReader)
        #expect(try await reader.logFiles().count == 1)
    }
}
