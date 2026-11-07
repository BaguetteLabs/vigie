import Testing

@testable import ModuleKit

@Suite struct ModuleKitTests {
    @Test func localizedSampleResolvesFromCatalog() {
        let value = ModuleKit.localizedSampleName
        #expect(!value.isEmpty)
        #expect(value != "modulekit.sample.name")
    }
}
