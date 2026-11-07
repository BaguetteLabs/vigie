import Foundation
import ModuleKit
import Observation
import Testing

@testable import VigieCore

enum SpyError: Error { case boom }

@MainActor @Observable
final class SpyModule: NotchModule {
    let manifest: ModuleManifest
    var state: ModuleState = .hidden
    var startCount = 0
    var stopCount = 0
    var loadedState: String?
    var eventStreamEnded = false
    @ObservationIgnored let ticks = Counter()
    @ObservationIgnored private let shouldThrow: Bool

    init(manifest: ModuleManifest, shouldThrow: Bool) {
        self.manifest = manifest
        self.shouldThrow = shouldThrow
    }

    func start(context: any ModuleContext) async throws {
        startCount += 1
        let ticks = ticks
        _ = context.scheduler.every(.milliseconds(20)) { ticks.increment() }
        _ = try context.hotkeys.register(name: "toggle", default: nil) { _ in }
        _ = context.power.preventIdleSleep(reason: "test")
        let stream = context.events.subscribe(topicPrefix: "agent.")
        Task { [weak self] in
            for await _ in stream {}
            self?.eventStreamEnded = true
        }
        loadedState = try await context.storage.readJSON("state", as: String.self, schema: 1)
        if shouldThrow { throw SpyError.boom }
        state = .ambient
    }

    func stop() async {
        stopCount += 1
        state = .hidden
    }
}

/// Counts instantiations per module id.
@MainActor final class SpyFactory {
    var made: [ModuleID: [SpyModule]] = [:]
    var throwing: Set<ModuleID> = []

    func descriptor(_ id: ModuleID, defaultEnabled: Bool = true) -> ModuleDescriptor {
        let manifest = ModuleManifest(id: id, name: "Spy", icon: "circle", defaultEnabled: defaultEnabled)
        return ModuleDescriptor(manifest: manifest) { [unowned self] in
            let module = SpyModule(manifest: manifest, shouldThrow: self.throwing.contains(id))
            self.made[id, default: []].append(module)
            return module
        }
    }

    func last(_ id: ModuleID) -> SpyModule? { made[id]?.last }
}

/// Wraps the production factory and records each tracker.
@MainActor final class SpyContextFactory: ModuleContextFactory {
    let base: CoreModuleContextFactory
    var trackers: [ModuleID: [RegistrationTracker]] = [:]

    init(base: CoreModuleContextFactory) { self.base = base }

    func makeContext(for manifest: ModuleManifest, tracker: RegistrationTracker) -> any ModuleContext {
        trackers[manifest.id, default: []].append(tracker)
        return base.makeContext(for: manifest, tracker: tracker)
    }
}

@MainActor
struct Harness {
    let root = makeTempDirectory()
    let bus = InProcessEventBus()
    let spies: SpyFactory
    let contexts: SpyContextFactory
    let enablement: TestEnablement
    let registry: ModuleRegistry

    init(ids: [ModuleID], enabled: [ModuleID: Bool] = [:], throwing: Set<ModuleID> = []) {
        let spies = SpyFactory()
        spies.throwing = throwing
        self.spies = spies
        contexts = SpyContextFactory(base: CoreModuleContextFactory(environment: makeEnvironment(root), eventBus: bus))
        enablement = TestEnablement(enabled)
        registry = ModuleRegistry(
            descriptors: ids.map { spies.descriptor($0) },
            enablement: enablement,
            contextFactory: contexts,
            logger: testLogger)
    }
}

@MainActor @Suite struct ModuleRegistryTests {
    @Test func disabledModuleIsNeverInstantiatedOrStarted() async {
        let h = Harness(ids: ["shelf", "dev.sample"], enabled: ["dev.sample": false])
        await h.registry.start()

        #expect(h.spies.made["dev.sample"] == nil)
        #expect(h.contexts.trackers["dev.sample"] == nil)
        #expect(h.registry.status(of: "dev.sample") == .disabled)
        #expect(h.registry.module("dev.sample") == nil)
        // Only shelf's subscription exists; no timer or subscription for the disabled module.
        #expect(h.bus.subscriberCount == 1)
        #expect(h.spies.last("shelf")?.startCount == 1)
        #expect(h.registry.status(of: "shelf") == .running)
        await h.registry.shutdown()
    }

    @Test func manifestDefaultAppliesWhenConfigHasNoKey() async {
        let spies = SpyFactory()
        let registry = ModuleRegistry(
            descriptors: [spies.descriptor("calendar", defaultEnabled: false)],
            enablement: TestEnablement(),
            contextFactory: CoreModuleContextFactory(
                environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus()),
            logger: testLogger)
        await registry.start()
        #expect(spies.made["calendar"] == nil)
        #expect(registry.status(of: "calendar") == .disabled)
    }

    @Test func enablingAtRuntimeStartsOnceAndTracksRegistrations() async throws {
        let h = Harness(ids: ["dev.sample"], enabled: ["dev.sample": false])
        await h.registry.start()
        #expect(h.spies.made["dev.sample"] == nil)

        h.enablement.set("dev.sample", true)
        #expect(await eventually { h.registry.status(of: "dev.sample") == .running })
        h.enablement.set("dev.sample", true)  // a repeated change is not a second start
        await h.registry.settle()

        let module = try #require(h.spies.last("dev.sample"))
        #expect(h.spies.made["dev.sample"]?.count == 1)
        #expect(module.startCount == 1)
        let tracker = try #require(h.contexts.trackers["dev.sample"]?.last)
        #expect(tracker.activeCount == 4)  // scheduler job, hotkey, power assertion, event subscription
        #expect(h.bus.subscriberCount == 1)
        await h.registry.shutdown()
    }

    @Test func disablingStopsAndRemovesEveryRegistration() async throws {
        let h = Harness(ids: ["dev.sample"], enabled: ["dev.sample": true])
        await h.registry.start()
        let module = try #require(h.spies.last("dev.sample"))
        let tracker = try #require(h.contexts.trackers["dev.sample"]?.last)
        #expect(await eventually { module.ticks.count > 0 })

        h.enablement.set("dev.sample", false)
        #expect(await eventually { h.registry.status(of: "dev.sample") == .disabled })

        #expect(module.stopCount == 1)
        #expect(tracker.activeCount == 0)
        #expect(tracker.isClosed)
        #expect(h.bus.subscriberCount == 0)
        #expect(await eventually { module.eventStreamEnded })
        let ticks = module.ticks.count
        try await Task.sleep(for: .milliseconds(100))
        #expect(module.ticks.count == ticks)
        #expect(h.registry.module("dev.sample") == nil)
    }

    @Test func shutdownStopsEveryModule() async throws {
        let h = Harness(ids: ["shelf", "time"])
        await h.registry.start()
        await h.registry.shutdown()
        for id: ModuleID in ["shelf", "time"] {
            #expect(h.spies.last(id)?.stopCount == 1)
            #expect(h.registry.status(of: id) == .stopped)
            #expect(h.contexts.trackers[id]?.last?.activeCount == 0)
        }
        #expect(h.bus.subscriberCount == 0)
        #expect(h.registry.runningModules.isEmpty)
    }

    @Test func throwingStartIsErroredAndOthersKeepRunning() async throws {
        let h = Harness(ids: ["shelf", "time", "notes"], throwing: ["time"])
        await h.registry.start()

        guard case .errored = h.registry.status(of: "time") else {
            Issue.record("expected errored, got \(h.registry.status(of: "time"))")
            return
        }
        #expect(h.registry.status(of: "shelf") == .running)
        #expect(h.registry.status(of: "notes") == .running)
        #expect(h.registry.runningModules.count == 2)
        // Registrations made before the throw are removed.
        #expect(h.contexts.trackers["time"]?.last?.activeCount == 0)
        #expect(h.bus.subscriberCount == 2)

        // Switching it off and on retries the start.
        h.spies.throwing = []
        h.enablement.set("time", false)
        #expect(await eventually { h.registry.status(of: "time") == .disabled })
        h.enablement.set("time", true)
        #expect(await eventually { h.registry.status(of: "time") == .running })
        await h.registry.shutdown()
    }

    @Test func unreadableStateFileIsSetAsideAndModuleStartsEmpty() async throws {
        let h = Harness(ids: ["shelf"])
        let folder = ModuleStorageImpl.directory(for: "shelf", applicationSupportURL: h.root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: folder.appendingPathComponent("state.json"))

        await h.registry.start()

        #expect(h.registry.status(of: "shelf") == .running)
        #expect(h.spies.last("shelf")?.loadedState == nil)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("state.json.corrupt").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("state.json").path))
        await h.registry.shutdown()
    }
}
