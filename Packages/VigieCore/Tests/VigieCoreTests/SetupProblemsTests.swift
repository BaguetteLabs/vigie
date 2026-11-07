import Foundation
import ModuleKit
import Synchronization
import Testing

@testable import VigieCore

final class SetupRecordingNotifier: Notifier {
    let posted = Mutex<[NotifierEvent]>([])
    let resolved = Mutex<Int>(0)
    func post(_ event: NotifierEvent) -> AlertHandle {
        posted.withLock { $0.append(event) }
        return AlertHandle { [weak self] in self?.resolved.withLock { $0 += 1 } }
    }
    var events: [NotifierEvent] { posted.withLock { $0 } }
    var resolveCount: Int { resolved.withLock { $0 } }
}

@MainActor
struct SetupProblemsTests {
    let fixture = ConfigFixture()
    let notifier = SetupRecordingNotifier()
    let hotkeys = HotkeyCenter(binding: FakeHotkeyBinding())

    func makeReporter(_ store: ConfigStore) -> SetupProblemReporter {
        SetupProblemReporter(configStore: store, hotkeys: hotkeys, notifier: notifier)
    }

    @Test func invalidFileTargetsGeneralOnce() async throws {
        let (store, _) = try await fixture.makeStore(config: "this is = = not toml")
        let reporter = makeReporter(store)
        reporter.refresh()
        reporter.refresh()
        #expect(notifier.events.count == 1)
        let event = try #require(notifier.events.first)
        #expect(event.kind == "setup.problem")
        #expect(event.action == .openSettings(pane: "general"))
        #expect(event.category == "CONFIG")
        #expect(event.dedupeKey == store.configURL.path)
        #expect(event.title == "config.toml can't be read")
    }

    @Test func unknownKeyUnderModuleTargetsItsPane() async throws {
        let (store, _) = try await fixture.makeStore(
            manifests: [DevSampleModule.staticManifest], config: "[modules.\"dev.sample\"]\nbogus = 1\n")
        let reporter = makeReporter(store)
        reporter.refresh()
        let event = try #require(notifier.events.first)
        #expect(event.action == .openSettings(pane: "dev.sample"))
        #expect(event.title.contains("bogus"))
    }

    @Test func paneMapping() {
        #expect(SetupProblemReporter.pane(forKey: "modules.\"dev.sample\".x") == "dev.sample")
        #expect(SetupProblemReporter.pane(forKey: "closed.tabs") == "closed")
        #expect(SetupProblemReporter.pane(forKey: "appearance.mode") == "general")
        #expect(SetupProblemReporter.pane(forKey: nil) == "general")
    }

    @Test func fixedProblemResolvesItsHandle() async throws {
        let (store, watcher) = try await fixture.makeStore(config: "this is = = not toml")
        let reporter = makeReporter(store)
        reporter.refresh()
        #expect(notifier.resolveCount == 0)
        try fixture.writeConfig("")
        await store.fireAndSettle(watcher)
        reporter.refresh()
        #expect(notifier.resolveCount == 1)
        reporter.refresh()
        #expect(notifier.resolveCount == 1)
        #expect(notifier.events.count == 1)
    }

    @Test func startObservesChanges() async throws {
        let (store, watcher) = try await fixture.makeStore(config: "")
        let reporter = makeReporter(store)
        reporter.start()
        #expect(notifier.events.isEmpty)
        try fixture.writeConfig("this is = = not toml")
        await store.fireAndSettle(watcher)
        for _ in 0..<100 where notifier.events.isEmpty { await Task.yield() }
        #expect(notifier.events.count == 1)
        reporter.stop()
    }

    @Test func hotkeyConflictNamesBothOwners() async throws {
        let (store, _) = try await fixture.makeStore()
        let first = try hotkeys.register(owner: .core, name: "expand", default: spec("opt+cmd+e"), handler: { _ in })
        let second = try hotkeys.register(
            owner: .module("agents.sessions"), name: "focus", default: spec("opt+cmd+e"), handler: { _ in })
        withExtendedLifetime((first, second)) {}
        let reporter = makeReporter(store)
        reporter.refresh()
        let event = try #require(notifier.events.first)
        #expect(event.category == "HOTKEY")
        #expect(event.title.contains("core.expand") && event.title.contains("agents.sessions.focus"))
        #expect(event.dedupeKey == "hotkey:agents.sessions.focus|core.expand")
    }
}
