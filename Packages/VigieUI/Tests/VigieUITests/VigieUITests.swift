import Testing

@testable import VigieUI

@Suite struct VigieUITests {
    @Test func localizedAppNameResolvesFromCatalog() {
        let value = VigieUI.localizedAppName
        #expect(!value.isEmpty)
        #expect(value != "vigieui.sample.appName")
    }
}
