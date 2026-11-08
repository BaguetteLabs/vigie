import AgentKit
import Foundation
import Wire

/// The one parser of Claude Code's local logs (AD-23, Story 7.1): `<root>/**/*.jsonl` under
/// `~/.claude/projects`, one JSON record per line. Only `assistant` records carry usage
/// (`message.usage.input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`).
/// Streaming writes repeat one response (same `sessionId` + `message.id`) with growing counts; consumers keep the
/// last one. Pure parsing and file enumeration: no database, no network, no state.
public struct ClaudeLogReader: AgentLogReader {
    /// The folders searched for `*.jsonl` files.
    public let roots: [URL]
    /// Bytes read from disk per step; records are kept, raw bytes are not.
    static let blockSize = 4 << 20
    /// Lines without this byte sequence are skipped without being parsed (the logs are compact JSON).
    static let assistantMarker = Data(#""type":"assistant""#.utf8)
    /// Claude Code's placeholder model for responses it made up locally (errors, interruptions).
    static let syntheticModel = "<synthetic>"

    public init(roots: [URL]) {
        self.roots = roots
    }

    /// `<home>/.claude/projects`.
    public init(homeDirectory: URL) {
        self.init(roots: [homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)])
    }

    public func logFiles() async throws -> [URL] {
        var files: [URL] = []
        for root in roots {
            guard
                let enumerator = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            else { continue }
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "jsonl",
                    (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                else { continue }
                files.append(url.standardizedFileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    public func readUsage(from file: URL, offset: UInt64) async throws -> UsageChunk {
        try Self.parse(file: file, offset: offset, fallbackProject: projectFolder(of: file))
    }

    /// Every record newer than `since`, last write per response, oldest first.
    public func read(since: Date?) async throws -> [LogEntry] {
        var latest: [String: UsageRecord] = [:]
        for file in try await logFiles() {
            for record in try await readUsage(from: file, offset: 0).records {
                latest[record.sessionID + "\u{1F}" + record.messageID] = record
            }
        }
        return latest.values
            .filter { record in since.map { record.at > $0 } ?? true }
            .sorted { $0.at < $1.at }
            .map { LogEntry(at: $0.at, sessionID: $0.sessionID, raw: Self.raw($0)) }
    }

    /// The Claude project folder a log file sits in (first path component under its root), e.g.
    /// `-Users-me-code-app`; used when a record has no `cwd`.
    func projectFolder(of file: URL) -> String {
        let path = file.standardizedFileURL.path
        for root in roots {
            let prefix = root.standardizedFileURL.path + "/"
            if path.hasPrefix(prefix), let first = path.dropFirst(prefix.count).split(separator: "/").first {
                return String(first)
            }
        }
        return file.deletingLastPathComponent().lastPathComponent
    }

    // MARK: Parsing

    static func parse(file: URL, offset: UInt64, fallbackProject: String) throws -> UsageChunk {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        var consumed = offset
        var pending = Data()
        var records: [UsageRecord] = []
        var skipped = 0
        var malformed = 0
        while let block = try handle.read(upToCount: blockSize), !block.isEmpty {
            pending.append(block)
            var start = pending.startIndex
            while let newline = pending[start...].firstIndex(of: 0x0A) {
                switch classify(pending[start..<newline], fallbackProject: fallbackProject) {
                case .record(let record): records.append(record)
                case .skipped: skipped += 1
                case .malformed: malformed += 1
                case .blank: break
                }
                start = pending.index(after: newline)
            }
            consumed += UInt64(pending.distance(from: pending.startIndex, to: start))
            pending = Data(pending[start...])
        }
        return UsageChunk(records: records, nextOffset: consumed, skippedLines: skipped, malformedLines: malformed)
    }

    enum LineResult: Equatable {
        case record(UsageRecord)
        case skipped
        case malformed
        case blank
    }

    static func classify(_ line: Data, fallbackProject: String) -> LineResult {
        if line.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) { return .blank }
        guard line.range(of: assistantMarker) != nil else { return .skipped }
        guard let decoded = try? JSONDecoder().decode(Line.self, from: line) else { return .malformed }
        guard decoded.type == "assistant" else { return .skipped }
        guard let message = decoded.message, let model = message.model else { return .malformed }
        if model == syntheticModel { return .skipped }
        guard let usage = message.usage, let messageID = message.id, let sessionID = decoded.sessionId,
            let stamp = decoded.timestamp, let at = WireDate.date(from: stamp)
        else { return .malformed }
        let cwd = decoded.cwd.flatMap { $0.isEmpty ? nil : $0 }
        return .record(
            UsageRecord(
                at: at, model: model, project: cwd ?? fallbackProject, sessionID: sessionID, messageID: messageID,
                requestID: decoded.requestId, inputTokens: usage.inputTokens ?? 0,
                outputTokens: usage.outputTokens ?? 0,
                cacheCreationTokens: usage.cacheCreationInputTokens ?? 0,
                cacheReadTokens: usage.cacheReadInputTokens ?? 0))
    }

    static func raw(_ record: UsageRecord) -> JSONValue {
        var object: [String: JSONValue] = [
            "model": .string(record.model), "project": .string(record.project),
            "message_id": .string(record.messageID), "input_tokens": .number(Double(record.inputTokens)),
            "output_tokens": .number(Double(record.outputTokens)),
            "cache_creation_input_tokens": .number(Double(record.cacheCreationTokens)),
            "cache_read_input_tokens": .number(Double(record.cacheReadTokens)),
        ]
        if let requestID = record.requestID { object["request_id"] = .string(requestID) }
        return .object(object)
    }

    /// The log record shape; every other field is ignored.
    struct Line: Decodable {
        let type: String?
        let timestamp: String?
        let sessionId: String?
        let requestId: String?
        let cwd: String?
        let message: Message?
    }

    struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }
}
