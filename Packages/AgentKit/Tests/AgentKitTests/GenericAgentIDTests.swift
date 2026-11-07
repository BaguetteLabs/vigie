import Foundation
import Testing

@testable import AgentKit

@Suite struct GenericAgentIDTests {
    /// A runtime string: `AgentID("literal")` would use the trapping literal initializer.
    func parse(_ value: String) -> AgentID? { AgentID(value) }

    @Test func genericIDsAreValidAgentIDs() throws {
        let id = try #require(AgentID(generic: "mytool"))
        #expect(id.rawValue == "generic.mytool")
        #expect(id.isGeneric)
        #expect(id.genericAgentName == "mytool")
        #expect(parse("generic.my-tool_2")?.genericAgentName == "my-tool_2")
    }

    @Test func adapterIDsAreNotGeneric() {
        #expect(parse("claude")?.isGeneric == false)
        #expect(parse("claude")?.genericAgentName == nil)
    }

    @Test func rejectsMalformedGenericIDs() {
        #expect(parse("generic.") == nil)
        #expect(parse("generic.MyTool") == nil)
        #expect(parse("generic.a.b") == nil)
        #expect(parse("generic.a:b") == nil)
        #expect(parse("other.mytool") == nil)
        #expect(AgentID(generic: "1tool") == nil)
        #expect(TerminalID(String("generic.mytool")) == nil)
    }

    @Test func sessionKeyParsesGenericIdentity() throws {
        let key = try #require(SessionKey("generic.mytool:t1:with:colons"))
        #expect(key.agentID.rawValue == "generic.mytool")
        #expect(key.sessionID == "t1:with:colons")
        #expect(SessionKey(key.description) == key)
        #expect(key.description == "generic.mytool:t1:with:colons")
    }

    @Test func genericSessionKeyRoundTripsThroughJSON() throws {
        let key = SessionKey(agentID: try #require(AgentID(generic: "mytool")), sessionID: "t1")
        let data = try JSONEncoder().encode(key)
        #expect(try JSONDecoder().decode(SessionKey.self, from: data) == key)
    }
}
