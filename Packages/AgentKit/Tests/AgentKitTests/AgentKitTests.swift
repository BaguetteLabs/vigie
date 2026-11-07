import Testing
import Wire
@testable import AgentKit

@Suite struct AgentKitTests {
    @Test func tracksWireProtocolVersion() {
        #expect(AgentKit.wireProtocolVersion == WireProtocol.version)
    }

    @Test func localizedSampleResolvesFromCatalog() {
        let value = AgentKit.localizedSampleName
        #expect(!value.isEmpty)
        #expect(value != "agentkit.sample.name")
    }
}
