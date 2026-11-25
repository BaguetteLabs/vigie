import Foundation
import ModuleKit
import Testing

@testable import Integrations

/// Copy diagnostics (Story 17.4): script ids and confirmation state only; secret values only for the scrub.
@MainActor struct DiagnosticsContributionTests {
    @Test func linesHoldIdsAndStateNeverSettingsOrCode() async throws {
        let module = IntegrationsModule()
        let definition = runnerDefinition(
            runnerScript(
                id: "github.prs", settings: [#"{ key: token, type: secret, label: "Token" }"#],
                code: "print('CODE-SENTINEL')"), name: "github.md", enabled: true)
        module.scripts = [definition]
        module.localStates = [definition.id: .confirmed]
        module.secrets = FakeSecretStore(["github.prs.token": "ghp_scriptSecretValue"])

        let sections = await module.diagnostics()
        #expect(
            sections == [
                ModuleDiagnostics(
                    section: .modules, lines: ["script github.prs  status=ok  enabled=true  confirmation=confirmed"])
            ])
        #expect(await module.diagnosticsSecretValues() == ["ghp_scriptSecretValue"])
        #expect(!sections.flatMap(\.lines).joined().contains("CODE-SENTINEL"))

        module.secrets = nil
        #expect(await module.diagnosticsSecretValues().isEmpty)
    }
}
