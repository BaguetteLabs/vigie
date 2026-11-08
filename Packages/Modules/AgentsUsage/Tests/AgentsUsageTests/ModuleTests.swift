import AgentKit
import Foundation
import ModuleKit
import Testing

@testable import AgentsUsage

@MainActor @Suite struct ModuleTests {
    @Test func manifest() {
        let manifest = AgentsUsageModule.staticManifest
        #expect(manifest.id == "agents.usage")
        #expect(String(localized: manifest.name) == "Usage")
        #expect(manifest.alertKinds == ["setup.problem"])
    }

    @Test func startOwnsTheDatabaseInItsStorageFolderAndIngests() async throws {
        let sandbox = try Sandbox()
        let context = FakeModuleContext(directory: sandbox.storage)
        let module = AgentsUsageModule(adapters: AgentAdapters([LogAdapter(reader: sandbox.reader)]))
        try await module.start(context: context)
        await module.waitForInitialIngest()

        #expect(module.registry?.ids == ["claude"])
        #expect(module.lastIngest?.records == 5)
        #expect(context.fakeScheduler.intervals == [.seconds(60)])
        #expect(module.state == .hidden)

        // The database lives in the storage folder, and nowhere else.
        let stored = try FileManager.default.contentsOfDirectory(atPath: sandbox.storage.path)
        #expect(stored.contains(UsageStore.fileName))
        #expect(stored.allSatisfy { $0.hasPrefix(UsageStore.fileName) })
        let top = try FileManager.default.contentsOfDirectory(atPath: sandbox.root.path).sorted()
        #expect(top == ["home", "storage"])
        #expect(
            module.history?.store.url.deletingLastPathComponent().standardizedFileURL
                == sandbox.storage.standardizedFileURL)

        let series = try await module.history?.usage(
            since: Date(timeIntervalSince1970: 0), until: Date(timeIntervalSince1970: 4_000_000_000), bucket: .day)
        #expect(series?.total.records == 4)

        // The timer pass finds nothing new.
        await context.fakeScheduler.fire()
        #expect(module.lastIngest?.changedFiles == 0)
        await module.stop()
    }

    @Test func registryFollowsUsageProvidersAndLogReaders() {
        let reader = FixtureLogReader(root: URL(fileURLWithPath: "/nonexistent"))
        let adapters = AgentAdapters([
            LogAdapter(reader: reader, id: "claude"), LogAdapter(reader: reader, id: "codex"),
            LogAdapter(reader: reader, id: "gemini"), LogAdapter(reader: nil, id: "none"),
        ])
        let registry = UsageProviderRegistry(adapters: adapters) { adapter in
            switch adapter.id {
            case "codex": FixedSettings(values: ["usage_providers": ["plan"]])
            case "gemini": FixedSettings(values: ["usage_providers": ["local", "plan"]])
            default: FixedSettings(values: [:])
            }
        }
        #expect(registry.ids == ["claude", "gemini"])
        #expect(registry.source(for: "claude")?.id == "claude")
        #expect(registry.source(for: "codex") == nil)
    }
}
