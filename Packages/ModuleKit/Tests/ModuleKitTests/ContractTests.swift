@_spi(Host) import ModuleKit
import Observation
import SwiftUI
import Testing

@MainActor @Observable
final class MinimalModule: NotchModule {
    let manifest = ModuleManifest(id: "test.minimal", name: "Minimal", icon: "circle")
    var state: ModuleState = .hidden

    func start(context: any ModuleContext) async throws {}
    func stop() async {}
}

@Suite struct ContractTests {
    @Test func moduleStateIsOrdered() {
        #expect(ModuleState.hidden < .ambient)
        #expect(ModuleState.ambient < .active)
        #expect(ModuleState.active < .alert)
        #expect(ModuleState.allCases.sorted() == [.hidden, .ambient, .active, .alert])
        #expect([ModuleState.alert, .hidden, .active].max() == .alert)
    }

    @Test(arguments: ["agents.sessions", "shelf", "dev.sample", "a1.b_c-d", "calendar"])
    func acceptsValidModuleIDs(_ raw: String) {
        #expect(ModuleID(raw)?.rawValue == raw)
    }

    @Test(arguments: [
        "", "Shelf", "agents.Sessions", "my module", " shelf", "shelf\n", "a..b", ".a", "a.", "1abc", "a/b",
    ])
    func rejectsInvalidModuleIDs(_ raw: String) {
        #expect(ModuleID(raw) == nil)
    }

    @Test func moduleIDCodableRoundTripAndRejection() throws {
        let data = try JSONEncoder().encode(ModuleID("agents.usage"))
        #expect(String(decoding: data, as: UTF8.self) == "\"agents.usage\"")
        #expect(try JSONDecoder().decode(ModuleID.self, from: data) == "agents.usage")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ModuleID.self, from: Data("\"Bad Id\"".utf8)) }
    }

    @Test @MainActor func conformerCompilesWithDefaults() {
        let module = MinimalModule()
        #expect(module.compactView(size: .wide) == nil)
        #expect(module.homeCard() == nil)
        #expect(module.expandedView() == nil)
        #expect(module.dropZones.isEmpty)
        #expect(module.leftWingItems().isEmpty)
        #expect(module.settingsView() == nil)
        #expect(module.manifest.defaultEnabled)
        #expect(module.manifest.alertKinds.isEmpty)
    }

    @Test func settingDescriptorScopeDefaultsToSynced() {
        let descriptor = SettingDescriptor(key: "show_cost", label: "Show cost", kind: .bool(default: true))
        #expect(descriptor.scope == .synced)
        #expect(descriptor.help == nil)
        let local = SettingDescriptor(key: "folder", label: "Folder", kind: .path(default: nil), scope: .local)
        #expect(local.scope == .local)
    }

    @Test func settingDescriptorDefaults() {
        #expect(
            SettingDescriptor(key: "a", label: "A", kind: .int(default: 3, min: 0, max: 10)).defaultValue as? Int == 3)
        #expect(
            SettingDescriptor(key: "b", label: "B", kind: .duration(default: .seconds(300))).defaultValue as? Duration
                == .seconds(300))
        #expect(SettingDescriptor(key: "c", label: "C", kind: .secret).defaultValue == nil)
        #expect(
            SettingDescriptor(key: "d", label: "D", kind: .list(of: .path, default: ["~/x"])).defaultValue as? [String]
                == ["~/x"])
    }

    @Test func registrationTokenCancelsAndComparesByID() {
        final class Box: @unchecked Sendable { var count = 0 }
        let box = Box()
        let token = RegistrationToken { box.count += 1 }
        token.cancel()
        #expect(box.count == 1)
        #expect(token == RegistrationToken(id: token.id) {})
    }

    @Test func userIntentIsMintableWithHostSPI() {
        let a = UserIntent()
        let b = UserIntent()
        #expect(a != b)
    }
}

/// Story 6.5: a context without an updates service fetches nothing.
@Suite struct NoUpdatesServiceTests {
    @Test func pricesOffAndNoLocation() {
        let updates = NoUpdatesService()
        #expect(!updates.pricesEnabled)
        #expect(updates.priceTable == nil)
        #expect(updates.checkInterval == .seconds(24 * 3600))
    }
}
