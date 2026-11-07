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

/// The one parser of an agent's log format, shared by both agent modules (AD-11, AD-23). Placeholder contract,
/// implemented by adapters in Epics 4/7.
public protocol AgentLogReader: Sendable {
    /// Entries newer than `since` (all when nil), oldest first.
    func read(since: Date?) async throws -> [LogEntry]
}
