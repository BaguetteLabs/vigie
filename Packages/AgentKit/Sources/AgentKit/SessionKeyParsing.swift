import Foundation

extension SessionKey {
    /// Parses the `description` form `<adapter id>:<native session id>` (AD-5), e.g. as stored in
    /// `sessions.json`. The adapter id never contains `:`; the native id may. Nil for an invalid adapter id or
    /// an empty native id.
    public init?(_ description: String) {
        guard let colon = description.firstIndex(of: ":"),
            let agentID = AgentID(String(description[..<colon]))
        else { return nil }
        let sessionID = String(description[description.index(after: colon)...])
        guard !sessionID.isEmpty else { return nil }
        self.init(agentID: agentID, sessionID: sessionID)
    }
}
