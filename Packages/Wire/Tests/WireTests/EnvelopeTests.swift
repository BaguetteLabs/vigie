import Foundation
import Testing

@testable import Wire

@Suite struct EnvelopeTests {
    static let sample = Envelope(
        topic: Topic.agentHook,
        sentAt: Date(timeIntervalSince1970: 1_793_000_000.125),
        payload: .object(["agent": .string("claude"), "n": .number(3)]))

    @Test func roundTripsThroughALine() throws {
        let line = try Self.sample.encodeLine()
        #expect(line.last == 0x0A)
        #expect(line.filter { $0 == 0x0A }.count == 1)
        let decoded = try Envelope.decodeLine(line)
        #expect(decoded == Self.sample)
    }

    @Test func wireKeysAreExact() throws {
        let line = try Self.sample.encodeLine()
        let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(Set(object.keys) == ["v", "topic", "sent_at", "payload"])
        #expect(object["v"] as? Int == 1)
        #expect(object["topic"] as? String == "agent.hook")
    }

    @Test func sentAtIsISO8601UTCWithFractionalSeconds() throws {
        let line = try Self.sample.encodeLine()
        let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        let stamp = try #require(object["sent_at"] as? String)
        #expect(stamp.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/) != nil)
        #expect(stamp == "2026-10-26T07:33:20.125Z")
    }

    @Test func decodingIgnoresUnknownFields() throws {
        let text = #"""
            {"v":1,"topic":"agent.hook","sent_at":"2026-11-07T09:41:12.345Z","payload":{"a":1},"extra":{"x":[1,2]},"z":"q"}
            """#
        let envelope = try Envelope.decodeLine(Data(text.utf8))
        #expect(envelope.topic == "agent.hook")
        #expect(envelope.payload == .object(["a": .number(1)]))
    }

    @Test func acceptsWholeSecondTimestamps() throws {
        let text = #"{"v":1,"topic":"t","sent_at":"2026-11-07T09:41:12Z","payload":null}"#
        let envelope = try Envelope.decodeLine(Data(text.utf8))
        #expect(envelope.sentAt == WireDate.date(from: "2026-11-07T09:41:12.000Z"))
    }

    @Test(arguments: [WireProtocol.version, WireProtocol.version - 1])
    func acceptsCurrentAndPreviousVersion(version: Int) throws {
        let line = try Envelope(v: version, topic: "t", sentAt: Date(), payload: .null).encodeLine()
        #expect(try Envelope.decodeLine(line).v == version)
    }

    @Test(arguments: [WireProtocol.version + 1, WireProtocol.version - 2, 99])
    func rejectsOtherVersions(version: Int) throws {
        let line = try Envelope(v: version, topic: "t", sentAt: Date(), payload: .null).encodeLine()
        #expect(throws: WireError.unsupportedVersion(version)) { try Envelope.decodeLine(line) }
    }

    @Test func rejectsBadTimestamp() {
        let text = #"{"v":1,"topic":"t","sent_at":"yesterday","payload":{}}"#
        #expect(throws: (any Error).self) { try Envelope.decodeLine(Data(text.utf8)) }
    }

    @Test func embeddedNewlinesAreEscaped() throws {
        let envelope = Envelope(topic: "t", sentAt: Date(), payload: .string("a\nb\r\nc"))
        let line = try envelope.encodeLine()
        #expect(line.filter { $0 == 0x0A }.count == 1)
        #expect(try Envelope.decodeLine(line).payload == .string("a\nb\r\nc"))
    }
}

@Suite struct JSONValueTests {
    @Test func roundTripsNestedStructures() throws {
        let text = #"""
            {"s":"é\"x","i":42,"neg":-7,"f":1.5,"big":1e300,"t":true,"f2":false,"n":null,
             "a":[1,"two",[3,{"four":4}],null],"o":{"deep":{"deeper":[{}]}}}
            """#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(value["i"] == .number(42))
        #expect(value["f"] == .number(1.5))
        #expect(value["t"] == .bool(true))
        #expect(value["n"] == .null)
        #expect(value["s"]?.stringValue == "é\"x")
        let again = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(again == value)
    }

    @Test func integralNumbersEncodeWithoutFraction() throws {
        let data = try JSONEncoder().encode(JSONValue.array([.number(3), .number(-2), .number(0.25)]))
        #expect(String(decoding: data, as: UTF8.self) == "[3,-2,0.25]")
    }

    @Test func booleansStayBooleans() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data("[true,1,0,false]".utf8))
        #expect(value == .array([.bool(true), .number(1), .number(0), .bool(false)]))
    }

    @Test func bridgesEncodableTypes() throws {
        let entry = ProcessInfoEntry(pid: 12, ppid: 1, name: "zsh", startTime: nil)
        let value = try JSONValue(encoding: entry)
        #expect(value == .object(["pid": .number(12), "ppid": .number(1), "name": .string("zsh")]))
        #expect(try value.decode(as: ProcessInfoEntry.self) == entry)
    }
}

@Suite struct HookPayloadTests {
    @Test func roundTripsThroughAnEnvelope() throws {
        let payload = HookPayload(
            agent: "claude",
            raw: .object(["session_id": .string("abc"), "hook_event_name": .string("Stop")]),
            tty: "/dev/ttys003",
            env: ["TERM_PROGRAM": "iTerm.app"],
            ancestors: [
                ProcessInfoEntry(
                    pid: 501, ppid: 400, name: "claude", startTime: Date(timeIntervalSince1970: 1_793_000_000.5))
            ])
        let envelope = Envelope(topic: Topic.agentHook, sentAt: Date(), payload: try JSONValue(encoding: payload))
        let decoded = try Envelope.decodeLine(envelope.encodeLine())
        #expect(try decoded.payload.decode(as: HookPayload.self) == payload)
        #expect(decoded.payload["ancestors"]?.array?.first?["start_time"] == .string("2026-10-26T07:33:20.500Z"))
    }

    @Test func environmentWhitelist() {
        let filtered = HookPayload.filterEnvironment([
            "TERM_PROGRAM": "WarpTerminal", "WARP_IS_LOCAL_SHELL_SESSION": "1", "ITERM_SESSION_ID": "w0t0p0:X",
            "HOME": "/Users/x", "PATH": "/bin", "ANTHROPIC_API_KEY": "secret", "TMUX": "/tmp/t,1,0",
            "GHOSTTY_BIN_DIR": "/g", "XWARP_": "no", "SHELL": "/bin/zsh", "PWD": "/w",
        ])
        #expect(
            Set(filtered.keys) == [
                "TERM_PROGRAM", "WARP_IS_LOCAL_SHELL_SESSION", "ITERM_SESSION_ID", "TMUX", "GHOSTTY_BIN_DIR",
                "SHELL", "PWD",
            ])
    }
}

extension JSONValue {
    fileprivate var array: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }
}

@Suite struct TopicTests {
    @Test func hostReadyTopicIsStable() {
        #expect(Topic.hostReady == "host.ready")
    }
}
