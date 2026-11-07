import Testing

@testable import AgentKit

@Suite struct SessionKeyParsingTests {
    @Test func roundTripsDescription() {
        let key = SessionKey(agentID: "claude", sessionID: "abc:def-1")
        #expect(SessionKey(key.description) == key)
    }

    @Test func rejectsInvalidForms() {
        #expect(SessionKey("claude") == nil)
        #expect(SessionKey("claude:") == nil)
        #expect(SessionKey("Claude:abc") == nil)
        #expect(SessionKey(":abc") == nil)
    }
}
