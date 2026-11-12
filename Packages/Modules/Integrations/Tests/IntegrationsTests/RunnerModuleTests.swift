import Foundation
import ModuleKit
import Testing

@testable import Integrations

/// The module's runner hooks: started with the module, fed by each scan, eligibility seam, Refresh, stop.
@MainActor @Suite struct RunnerModuleTests {
    @Test func theModuleRunsScannedScriptsAndStopsThem() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "integrations-runner-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("modules", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try runnerScript(id: "one.script").write(to: folder.appendingPathComponent("one.md"))
        try runnerScript(id: "two.script").write(to: folder.appendingPathComponent("two.md"))

        let scriptFolder = FakeScriptFolder(url: folder, enabled: ["two.script": false])
        let context = FakeModuleContext(scriptFolder: scriptFolder)
        let module = IntegrationsModule()
        try await module.start(context: context)
        let runner = try #require(module.runner)
        await runner.waitForIdle()
        // Nothing runs before a confirmation on this Mac (Story 12.3).
        #expect(runner.states.isEmpty)
        for script in module.scripts { try await module.confirm(script) }
        await runner.waitForIdle()

        // Confirmed and enabled scripts only. The fake context resolves nothing.
        #expect(Set(runner.states.keys) == ["one.md"])
        #expect(runner.states["one.md"]?.records.first?.outcome == .runtimeNotFound("python3"))
        #expect(context.fakeScheduler.liveOneShots.count == 1)

        module.refresh(scriptID: "one.md")
        await runner.waitForIdle()
        #expect(runner.states["one.md"]?.records.count == 2)
        module.refreshAll()
        await runner.waitForIdle()
        #expect(runner.states["one.md"]?.records.count == 3)

        module.isScriptEligible = { _ in false }
        module.updateRunner()
        #expect(runner.states.isEmpty)

        await module.stop()
        #expect(module.runner == nil)
        #expect(context.fakeScheduler.liveOneShots.isEmpty)
    }
}
