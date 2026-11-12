import Foundation
import ModuleKit
import Testing

@testable import Integrations

/// Story 12.1: the `integrations` skeleton registers with its manifest and renders nothing yet. Story 12.2 adds
/// the `setup.problem` kind (one alert per errored script file).
@MainActor @Suite struct IntegrationsModuleTests {
    @Test func manifest() {
        let manifest = IntegrationsModule.staticManifest
        #expect(manifest.id == "integrations")
        #expect(String(localized: manifest.name) == "Scripts")  // the Settings › Scripts pane title (UX-DR74)
        // `[modules.integrations] update_checks`, default on (Story 12.10, SPEC §11).
        #expect(manifest.settings.map(\.key) == ["update_checks"])
        #expect(manifest.alertKinds == ["setup.problem"])
        #expect(manifest.permissions.isEmpty)
    }

    @Test func startsHiddenAndRendersNothing() async throws {
        let module = IntegrationsModule()
        try await module.start(context: FakeModuleContext())
        #expect(module.state == .hidden)
        #expect(module.homeCard() == nil)
        #expect(module.expandedView() == nil)
        #expect(module.leftWingItems().isEmpty)
        await module.stop()
    }
}
