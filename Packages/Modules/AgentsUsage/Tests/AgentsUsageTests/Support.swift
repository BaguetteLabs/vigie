import AgentKit
import Foundation
import ModuleKit

@testable import AgentsUsage

/// A minimal JSONL usage reader over Claude-format fixtures (modules never import adapters, AD-1). The real
/// parser is `ClaudeLogReader`, tested in the Claude adapter package; this one follows the same contract
/// (complete lines only, assistant records only, counts skipped and malformed lines).
struct FixtureLogReader: AgentLogReader {
    let root: URL

    func read(since: Date?) async throws -> [LogEntry] { [] }

    func logFiles() async throws -> [URL] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "jsonl" { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }

    func readUsage(from file: URL, offset: UInt64) async throws -> UsageChunk {
        let data = try Data(contentsOf: file)
        guard offset < UInt64(data.count) else { return UsageChunk(records: [], nextOffset: offset) }
        var records: [UsageRecord] = []
        var skipped = 0
        var malformed = 0
        var start = data.index(data.startIndex, offsetBy: Int(offset))
        while let newline = data[start...].firstIndex(of: 0x0A) {
            let line = data[start..<newline]
            start = data.index(after: newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                malformed += 1
                continue
            }
            guard object["type"] as? String == "assistant",
                let message = object["message"] as? [String: Any],
                let model = message["model"] as? String, model != "<synthetic>"
            else {
                skipped += 1
                continue
            }
            guard let usage = message["usage"] as? [String: Any], let id = message["id"] as? String,
                let session = object["sessionId"] as? String, let stamp = object["timestamp"] as? String,
                let at = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(stamp)
            else {
                malformed += 1
                continue
            }
            records.append(
                UsageRecord(
                    at: at, model: model, project: object["cwd"] as? String ?? "?", sessionID: session,
                    messageID: id, requestID: object["requestId"] as? String,
                    inputTokens: usage["input_tokens"] as? Int ?? 0, outputTokens: usage["output_tokens"] as? Int ?? 0,
                    cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
                    cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0))
        }
        return UsageChunk(
            records: records, nextOffset: UInt64(data.distance(from: data.startIndex, to: start)),
            skippedLines: skipped, malformedLines: malformed)
    }
}

/// A logReader-only adapter.
struct LogAdapter: AgentAdapter {
    let reader: (any AgentLogReader)?
    var id: AgentID = "claude"
    var name: LocalizedStringResource { "Claude" }
    var capabilities: Set<AgentCapability> { [.logReader] }
    var logReader: (any AgentLogReader)? { reader }
    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] { [] }
}

/// Settings view with fixed values.
struct FixedSettings: ReadOnlySettings {
    let values: [String: any SettingValue]
    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? { values[key] as? T }
}

/// A temp folder with a copy of `Fixtures/projects` and a separate storage folder; removed on deinit.
final class Sandbox {
    let root: URL
    var projects: URL { root.appendingPathComponent("home/.claude/projects", isDirectory: true) }
    var storage: URL { root.appendingPathComponent("storage/modules/agents.usage", isDirectory: true) }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agents-usage-\(UUID().uuidString)", isDirectory: true)
        let fixtures = try require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        try FileManager.default.createDirectory(
            at: projects.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("projects"), to: projects)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func file(_ relative: String) -> URL { projects.appendingPathComponent(relative) }

    func append(_ relative: String, _ text: String) throws {
        let handle = try FileHandle(forWritingTo: file(relative))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    var reader: FixtureLogReader { FixtureLogReader(root: projects) }
    var registry: UsageProviderRegistry { UsageProviderRegistry(sources: [UsageSource(id: "claude", reader: reader)]) }
}

/// `#require` outside a test function.
func require<T>(_ value: T?, _ message: String = "missing") throws -> T {
    guard let value else { throw RequireError(message: message) }
    return value
}

struct RequireError: Error {
    let message: String
}
