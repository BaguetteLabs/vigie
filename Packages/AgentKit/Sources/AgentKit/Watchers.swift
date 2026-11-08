import Foundation

/// One line appended to an agent transcript file.
public struct TranscriptLine: Hashable, Sendable {
    public let path: URL
    public let text: String

    public init(path: URL, text: String) {
        self.path = path
        self.text = text
    }
}

/// Tier-2 integration: follows a transcript file as it is written (SPEC §8.3). Placeholder contract,
/// implemented by adapters in Epics 4/7.
public protocol TranscriptWatcher: Sendable {
    /// Lines appended to `path` from now on; the stream ends when the consumer cancels.
    func watch(path: URL) -> AsyncStream<TranscriptLine>
}

/// One usage-relevant record from an agent's local logs.
public struct LogEntry: Hashable, Sendable {
    public let at: Date
    public let sessionID: String?
    /// The record as parsed; interpretation stays in the adapter.
    public let raw: JSONValue

    public init(at: Date, sessionID: String?, raw: JSONValue) {
        self.at = at
        self.sessionID = sessionID
        self.raw = raw
    }
}

/// The one parser of an agent's log format, shared by both agent modules (AD-11, AD-23). `agents.usage` ingests
/// through `logFiles()` + `readUsage(from:offset:)` (Story 7.1).
public protocol AgentLogReader: Sendable {
    /// Entries newer than `since` (all when nil), oldest first.
    func read(since: Date?) async throws -> [LogEntry]

    /// Every log file the reader parses, under its roots (Story 7.1 incremental ingest). Default: none.
    func logFiles() async throws -> [URL]

    /// Pure parse of `file` from byte `offset` (Story 7.1, AD-11): the usage records of the complete lines after
    /// `offset`, and the offset to resume from. An incomplete last line (no trailing newline yet) is not consumed:
    /// `nextOffset` is the start of that line. Non-usage records and malformed lines are skipped and counted.
    /// Default: no records, `nextOffset == offset`.
    func readUsage(from file: URL, offset: UInt64) async throws -> UsageChunk
}

extension AgentLogReader {
    public func logFiles() async throws -> [URL] { [] }
    public func readUsage(from file: URL, offset: UInt64) async throws -> UsageChunk {
        UsageChunk(records: [], nextOffset: offset)
    }
}

/// One model response's token usage, as parsed from an agent's local logs (Story 7.1). Streaming writes may
/// repeat a response with growing counts; the last record for a (`sessionID`, `messageID`) pair wins.
public struct UsageRecord: Hashable, Sendable {
    public let at: Date
    /// The agent's model id, e.g. `claude-opus-5-5`.
    public let model: String
    /// The project the session ran in: its working folder, else the agent's project folder name.
    public let project: String
    public let sessionID: String
    public let messageID: String
    public let requestID: String?
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int

    public init(
        at: Date, model: String, project: String, sessionID: String, messageID: String, requestID: String?,
        inputTokens: Int, outputTokens: Int, cacheCreationTokens: Int, cacheReadTokens: Int
    ) {
        self.at = at
        self.model = model
        self.project = project
        self.sessionID = sessionID
        self.messageID = messageID
        self.requestID = requestID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
    }
}

/// The result of `AgentLogReader.readUsage(from:offset:)`.
public struct UsageChunk: Hashable, Sendable {
    public let records: [UsageRecord]
    /// Where the next read of the file starts: after the last complete line.
    public let nextOffset: UInt64
    /// Complete lines that are not usage records (other record types, synthetic responses).
    public let skippedLines: Int
    /// Complete lines that are not valid JSON or lack a required usage field.
    public let malformedLines: Int

    public init(records: [UsageRecord], nextOffset: UInt64, skippedLines: Int = 0, malformedLines: Int = 0) {
        self.records = records
        self.nextOffset = nextOffset
        self.skippedLines = skippedLines
        self.malformedLines = malformedLines
    }
}
