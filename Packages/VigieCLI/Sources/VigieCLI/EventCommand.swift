import Foundation
import Wire

/// `vigie event <topic> [json]`: sends one v1 envelope to the app (SPEC §8, FR8).
///
/// Unlike `hook`, this command is user-facing: a bad topic or bad JSON is a usage error
/// (exit 2, one line on stderr). Delivery uses the same socket-else-spool path and budget
/// as `hook`; the command exits 0 whether the line was sent or spooled.
public struct EventCommand: Sendable {
    /// Longest accepted topic.
    public static let maxTopicLength = 64

    /// Why the arguments were rejected.
    public enum ArgumentError: Error, Equatable, Sendable {
        case missingTopic
        case invalidTopic(String)
        case invalidJSON
        case unexpectedArgument(String)
    }

    public var topic: String
    public var payload: JSONValue
    public var now: @Sendable () -> Date

    public init(topic: String, payload: JSONValue, now: @escaping @Sendable () -> Date = { Date() }) {
        self.topic = topic
        self.payload = payload
        self.now = now
    }

    /// `[a-z0-9_.-]+`, at most `maxTopicLength` characters.
    public static func isValidTopic(_ topic: String) -> Bool {
        guard !topic.isEmpty, topic.utf8.count <= maxTopicLength else { return false }
        return topic.utf8.allSatisfy { byte in
            (0x61...0x7A).contains(byte) || (0x30...0x39).contains(byte) || byte == 0x5F || byte == 0x2E
                || byte == 0x2D
        }
    }

    /// Parses `JSON` text; blank text is `{}`.
    public static func parsePayload(_ data: Data) throws(ArgumentError) -> JSONValue {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return .object([:]) }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw .invalidJSON }
        return value
    }

    /// Builds the command from the arguments after `event`.
    ///
    /// The payload is the JSON argument if given; otherwise `readStdin()` (which returns `nil`
    /// when stdin is a terminal); otherwise `{}`.
    public static func parse(
        arguments: [String],
        readStdin: () -> Data?,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws(ArgumentError) -> EventCommand {
        guard let topic = arguments.first else { throw .missingTopic }
        guard isValidTopic(topic) else { throw .invalidTopic(topic) }
        if arguments.count > 2 { throw .unexpectedArgument(arguments[2]) }
        let payload: JSONValue
        if arguments.count == 2 {
            payload = try parsePayload(Data(arguments[1].utf8))
        } else if let input = readStdin() {
            payload = try parsePayload(input)
        } else {
            payload = .object([:])
        }
        return EventCommand(topic: topic, payload: payload, now: now)
    }

    public func makeEnvelope() -> Envelope {
        Envelope(topic: topic, sentAt: now(), payload: payload)
    }

    /// Delivers the envelope; `.dropped` when it could not be encoded, sent or spooled.
    public func run(through delivery: Delivery) -> Delivery.Outcome {
        guard let line = try? makeEnvelope().encodeLine() else { return .dropped }
        return delivery.deliver(line)
    }
}
