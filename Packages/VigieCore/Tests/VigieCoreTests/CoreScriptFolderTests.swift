import Foundation
import ModuleKit
import Testing
import Wire

@testable import VigieCore

/// Story 12.2: `context.scriptFolder`, the folder, built-in ids, `enabled` and the folder watch integrations uses.
@MainActor @Suite struct CoreScriptFolderTests {
    @Test func factoryGivesTheConfigFoldersModulesFolderAndTheBuiltInIDs() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(
            manifests: [testManifest, ModuleManifest(id: "dev.sample", name: "Sample", icon: "star")],
            config: "[modules.\"github.prs\"]\nenabled = false\n")
        let factory = CoreModuleContextFactory(
            environment: fixture.environment, eventBus: InProcessEventBus(), configStore: store)
        let manifest = ModuleManifest(id: "integrations", name: "Integrations", icon: "puzzlepiece.extension")
        let context = factory.makeContext(for: manifest, tracker: RegistrationTracker())
        let folder = context.scriptFolder

        #expect(folder.url == fixture.configFolder.appendingPathComponent("modules", isDirectory: true))
        #expect(folder.url == fixture.environment.scriptModulesFolderURL)
        // The modules App assembly gave ConfigStore, plus the SPEC ids not shipped yet.
        #expect(folder.builtInModuleIDs.isSuperset(of: ["agents.sessions", "dev.sample", "calendar", "notes"]))
        // `[modules."<id>"] enabled` for an id no manifest declares.
        #expect(folder.isEnabled("github.prs") == false)
        #expect(folder.isEnabled("other.script") == nil)
        // Registered later (a dynamic script module, Story 12.5) does not become built-in.
        store.register(manifest: ModuleManifest(id: "github.prs", name: "PRs", icon: "star"))
        #expect(!factory.builtInModuleIDs.contains("github.prs"))
        // Nothing created.
        #expect(!FileManager.default.fileExists(atPath: fixture.environment.scriptModulesFolderURL.path))
    }

    @Test func changesFollowTheWatcherAndEndWhenTheModuleStops() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folderURL = root.appendingPathComponent("modules", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folderURL.appendingPathComponent("a.md"))
        let watcher = ManualDirectoryWatcher()
        let tracker = RegistrationTracker()
        let service = CoreScriptFolder(
            url: folderURL, builtInModuleIDs: [], enablement: nil, tracker: tracker, makeWatcher: { watcher })

        let counter = StreamCounter(service.changes())
        #expect(watcher.watchedDirectories == [folderURL.standardizedFileURL])
        #expect(tracker.activeCount == 1)

        watcher.fire()
        #expect(await eventually { counter.counter.count == 1 })
        // Re-armed after the event (fresh file hints), still one watch.
        #expect(watcher.watchedDirectories.count == 1)
        watcher.fire()
        #expect(await eventually { counter.counter.count == 2 })

        tracker.cancelAll()
        await counter.task.value
        #expect(await eventually { watcher.watchedDirectories.isEmpty })
    }

    @Test func noFolderMeansAFinishedStream() async {
        let service = CoreScriptFolder(
            url: nil, builtInModuleIDs: [], enablement: nil, tracker: RegistrationTracker(),
            makeWatcher: { ManualDirectoryWatcher() })
        for await _ in service.changes() { Issue.record("no change expected") }
    }

    @Test func markdownHintsListOnlyMarkdownFiles() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["b.md", "a.MD", "c.txt"] { try Data().write(to: root.appendingPathComponent(name)) }
        #expect(FolderWatch.markdownFiles(in: root) == ["a.MD", "b.md"])
        #expect(FolderWatch.markdownFiles(in: root.appendingPathComponent("missing")) == [])
    }
}
