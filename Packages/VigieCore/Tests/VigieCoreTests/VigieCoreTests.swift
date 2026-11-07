import Testing
import Wire
@testable import VigieCore

@Suite struct VigieCoreTests {
    @Test func tracksWireProtocolVersion() {
        #expect(VigieCore.wireProtocolVersion == WireProtocol.version)
    }

    @Test func localizedHostNameResolvesFromCatalog() {
        let value = VigieCore.localizedHostName
        #expect(!value.isEmpty)
        #expect(value != "vigiecore.sample.hostName")
    }
}
