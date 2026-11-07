import Foundation

/// Errors raised while decoding wire messages.
public enum WireError: Error, Equatable, Sendable {
    /// The envelope's `v` is neither `WireProtocol.version` nor the one before it (AD-7).
    case unsupportedVersion(Int)
    /// `sent_at` is not an ISO 8601 UTC timestamp.
    case invalidDate(String)
}

/// Topic names carried in `Envelope.topic`.
public enum Topic {
    /// A native agent hook event sent by `vigie hook <agent>`; payload is `HookPayload`.
    public static let agentHook = "agent.hook"
    /// A generic agent report sent by `vigie agent` (AD-5).
    public static let agentGeneric = "agent.generic"
}

/// ISO 8601 UTC timestamps with fractional seconds, as used on the wire (AD-7).
public enum WireDate {
    private static var fractional: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt)
    }

    private static var whole: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(timeZone: .gmt)
    }

    /// `2026-11-07T09:41:12.345Z`.
    public static func string(from date: Date) -> String {
        date.formatted(fractional)
    }

    /// Parses a timestamp with or without fractional seconds.
    public static func date(from string: String) -> Date? {
        (try? fractional.parse(string)) ?? (try? whole.parse(string))
    }
}

/// One socket message or spool line: `{ "v", "topic", "sent_at", "payload" }` (AD-7).
///
/// The payload stays an uninterpreted `JSONValue`; agent modules decode it with the
/// Wire type for the topic (for `agent.hook`, `HookPayload`). Unknown fields are ignored.
public struct Envelope: Codable, Sendable, Equatable {
    public var v: Int
    public var topic: String
    public var sentAt: Date
    public var payload: JSONValue

    enum CodingKeys: String, CodingKey {
        case v
        case topic
        case sentAt = "sent_at"
        case payload
    }

    public init(v: Int = WireProtocol.version, topic: String, sentAt: Date, payload: JSONValue) {
        self.v = v
        self.topic = topic
        self.sentAt = sentAt
        self.payload = payload
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decode(Int.self, forKey: .v)
        topic = try container.decode(String.self, forKey: .topic)
        let stamp = try container.decode(String.self, forKey: .sentAt)
        guard let date = WireDate.date(from: stamp) else { throw WireError.invalidDate(stamp) }
        sentAt = date
        payload = try container.decodeIfPresent(JSONValue.self, forKey: .payload) ?? .null
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(v, forKey: .v)
        try container.encode(topic, forKey: .topic)
        try container.encode(WireDate.string(from: sentAt), forKey: .sentAt)
        try container.encode(payload, forKey: .payload)
    }

    /// Versions the app accepts: the current one and the one before it (AD-7).
    public static var acceptedVersions: ClosedRange<Int> {
        (WireProtocol.version - 1)...WireProtocol.version
    }

    /// Decodes one line (a trailing newline is allowed) and enforces the accepted versions.
    public static func decodeLine(_ data: Data) throws -> Envelope {
        var line = data
        while let last = line.last, last == 0x0A || last == 0x0D { line.removeLast() }
        let envelope = try JSONDecoder().decode(Envelope.self, from: line)
        guard acceptedVersions.contains(envelope.v) else { throw WireError.unsupportedVersion(envelope.v) }
        return envelope
    }

    /// One JSON line terminated by `\n`. `JSONEncoder` never emits raw newlines
    /// (they are escaped inside strings), so the result holds exactly one.
    public func encodeLine() throws -> Data {
        var data = try JSONEncoder().encode(self)
        data.append(0x0A)
        return data
    }
}
