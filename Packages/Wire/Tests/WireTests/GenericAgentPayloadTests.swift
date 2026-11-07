import Foundation
import Testing

@testable import Wire

@Suite struct GenericAgentPayloadTests {
    static let sample = GenericAgentPayload(
        agent: "mytool", session: "t1", status: .blocked, cwd: "/Users/me/www/vigie", message: "Needs approval",
        tty: "/dev/ttys003", env: ["TERM_PROGRAM": "ghostty"],
        ancestors: [
            ProcessInfoEntry(pid: 42, ppid: 41, name: "zsh", startTime: Date(timeIntervalSince1970: 1_793_000_000.5))
        ])

    @Test func topicName() {
        #expect(Topic.agentGeneric == "agent.generic")
    }

    @Test func roundTripsThroughAnEnvelope() throws {
        let envelope = Envelope(
            topic: Topic.agentGeneric, sentAt: Date(timeIntervalSince1970: 1_793_000_001),
            payload: try JSONValue(encoding: Self.sample))
        let decoded = try Envelope.decodeLine(try envelope.encodeLine())
        #expect(try decoded.payload.decode(as: GenericAgentPayload.self) == Self.sample)
    }

    @Test func wireKeysAreExact() throws {
        let data = try JSONEncoder().encode(Self.sample)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(
            Set(object.keys) == ["agent", "session", "status", "end", "cwd", "message", "tty", "env", "ancestors"])
        #expect(object["status"] as? String == "blocked")
        #expect(object["end"] as? Bool == false)
        let ancestor = try #require((object["ancestors"] as? [[String: Any]])?.first)
        #expect(ancestor["start_time"] as? String != nil)
    }

    @Test func endWithoutStatusDecodes() throws {
        let json = #"{"agent":"mytool","session":"t1","end":true}"#
        let payload = try JSONDecoder().decode(GenericAgentPayload.self, from: Data(json.utf8))
        #expect(payload.end)
        #expect(payload.status == nil)
        #expect(payload.env.isEmpty)
        #expect(payload.ancestors.isEmpty)
    }

    @Test func unknownStatusIsRejected() {
        let json = #"{"agent":"mytool","session":"t1","status":"sleeping","end":false}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GenericAgentPayload.self, from: Data(json.utf8))
        }
    }

    @Test func everyStatusRoundTrips() throws {
        for status in GenericStatus.allCases {
            let payload = GenericAgentPayload(agent: "mytool", session: "t1", status: status)
            let data = try JSONEncoder().encode(payload)
            #expect(try JSONDecoder().decode(GenericAgentPayload.self, from: data) == payload)
        }
    }

    @Test func reservedAgentIDs() {
        #expect(ReservedAgentIDs.contains("claude"))
        #expect(ReservedAgentIDs.contains("codex"))
        #expect(ReservedAgentIDs.contains("gemini"))
        #expect(!ReservedAgentIDs.contains("mytool"))
    }
}
