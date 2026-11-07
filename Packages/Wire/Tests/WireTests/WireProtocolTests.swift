import Testing
@testable import Wire

@Suite struct WireProtocolTests {
    @Test func protocolVersionIsOne() {
        #expect(WireProtocol.version == 1)
    }

    @Test func localizedNameResolvesFromCatalog() {
        let name = WireProtocol.localizedName
        #expect(!name.isEmpty)
        #expect(name != "wire.sample.protocolName")
    }
}
