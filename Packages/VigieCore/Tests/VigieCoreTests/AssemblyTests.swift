import AppKit
import Foundation
import ModuleKit
import Synchronization
import Testing
import VigieUI
import os

@testable import VigieCore

@MainActor
struct ConfigNotifyRulesTests {
    private let config = """
        [notify]
        min_severity = "warn"
        cooldown = "30s"
        quiet_hours = "22:00-08:00"

        [modules."dev.sample".notify."done"]
        mute = true
        min_working_time = "5m"
        outputs = ["peek"]
        """

    @Test func mergesGlobalAndKindTables() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: config)
        let rules = ConfigNotifyRules(store: store)
        rules.start()
        defer { rules.stop() }

        let quiet = try #require(QuietHours("22:00-08:00"))
        #expect(rules.global.defaults == NotifyRule(minSeverity: .warn, quietHours: quiet, cooldown: .seconds(30)))

        let done = rules.rule(module: "dev.sample", kind: "done")
        #expect(done.muted == true)
        #expect(done.minSeverity == .warn)
        #expect(done.cooldown == .seconds(30))
        #expect(done.quietHours == quiet)
        #expect(done.outputs == [.peek])
        #expect(done.conditions == [.minMetric(name: RuleCondition.workingDurationMetric, value: 300)])

        let other = rules.rule(module: "dev.sample", kind: "other")
        #expect(other == rules.global.defaults)
        #expect(!other.isMuted)
        #expect(other.outputs == nil)
        #expect(other.conditions == nil)
    }

    @Test func configChangeEmitsOnChanges() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(config: config)
        let rules = ConfigNotifyRules(store: store)
        rules.start()
        defer { rules.stop() }
        let counter = StreamCounter(rules.changes)
        // The first read in `start()` already yielded once (defaults to the file's rules).
        #expect(await eventually { counter.count == 1 })

        try fixture.writeConfig(
            config.replacingOccurrences(of: "min_severity = \"warn\"", with: "min_severity = \"critical\"")
                .replacingOccurrences(of: "mute = true", with: "mute = false"))
        await store.fireAndSettle(watcher)

        #expect(await eventually { counter.count == 2 })
        #expect(rules.global.defaults.minSeverity == .critical)
        #expect(rules.rule(module: "dev.sample", kind: "done").muted == false)
    }

    @Test func kindOnlyEditIsPickedUp() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(config: config)
        let rules = ConfigNotifyRules(store: store)
        rules.start()
        defer { rules.stop() }

        try fixture.writeConfig(config.replacingOccurrences(of: "outputs = [\"peek\"]", with: "outputs = []"))
        await store.fireAndSettle(watcher)
        #expect(await eventually { rules.rule(module: "dev.sample", kind: "done").outputs == [] })
    }

    @Test func invalidKindFieldsAreIgnored() {
        let rule = ConfigNotifyRules.rule(from: [
            "mute": .string("yes"), "cooldown": .string("soon"), "outputs": .array([.string("peek"), .int(1)]),
            "min_tokens": .int(10), "reminder": .string("2m"),
        ])
        #expect(rule.muted == nil)
        #expect(rule.cooldown == nil)
        #expect(rule.outputs == [.peek])
        #expect(rule.reminder == .seconds(120))
        #expect(rule.conditions == [.minMetric(name: "tokens", value: 10)])
    }
}

@MainActor
struct ExecutableOverridesTests {
    @Test func readsExecutablesTableFromLocalOnly() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(
            config: "[executables]\ncodex = \"/synced/codex\"\n",
            local: "[executables]\nclaude = \"~/bin/claude\"\ncount = 3\n")
        let overrides = ExecutableOverrides(store: store)
        overrides.start()
        defer { overrides.stop() }
        #expect(overrides.current == ["claude": "~/bin/claude"])

        try fixture.writeLocal("[executables]\nclaude = \"/opt/claude\"\n")
        await store.fireAndSettle(watcher)
        #expect(await eventually { overrides.current == ["claude": "/opt/claude"] })
    }

    @Test func missingTableIsEmpty() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(local: "[display]\ndisplay = \"notched\"\n")
        #expect(ExecutableOverrides(store: store).current.isEmpty)
    }
}

@MainActor
struct AppTopicsTests {
    @Test func reloadAndExpandAreDispatched() async {
        let bus = InProcessEventBus()
        let reloads = Counter()
        let expands = Counter()
        let topics = AppTopics(
            bus: bus, logger: Logger(subsystem: "test", category: "app"),
            onReload: { reloads.increment() }, onExpand: { _ in expands.increment() })
        topics.start()
        defer { topics.stop() }
        bus.publish(EventMessage(topic: "app.reload", payload: Data(), sentAt: Date()))
        bus.publish(EventMessage(topic: "app.expand", payload: Data(), sentAt: Date()))
        bus.publish(EventMessage(topic: "app.other", payload: Data(), sentAt: Date()))
        #expect(await eventually { reloads.count == 1 && expands.count == 1 })
    }
}

@MainActor
struct ConfigStoreRawTests {
    @Test func rawReadsMergeWithLocalWinning() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(
            config: "[executables]\na = \"/synced/a\"\nb = \"/synced/b\"\n",
            local: "[executables]\nb = \"/local/b\"\n")
        #expect(store.rawValue(at: "executables.b") == .string("/local/b"))
        #expect(store.rawValue(at: "executables.b", in: .synced) == .string("/synced/b"))
        #expect(store.rawTable(at: "executables") == ["a": .string("/synced/a"), "b": .string("/local/b")])
        #expect(store.rawTable(at: "executables", in: .local) == ["b": .string("/local/b")])
        #expect(store.rawTable(at: "missing") == nil)
    }

    @Test func unknownTableEditEmitsOnChangesAndBumpsRevision() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(config: "[modules.\"dev.x\".notify.done]\nmute = true\n")
        let sets = Mutex<[Set<ConfigKeyPath>]>([])
        let counter = StreamCounter(store.changes) { set in sets.withLock { $0.append(set) } }
        let revision = store.revision

        try fixture.writeConfig("[modules.\"dev.x\".notify.done]\nmute = false\n")
        await store.fireAndSettle(watcher)
        #expect(await eventually { counter.count == 1 })
        #expect(sets.withLock { $0 } == [[ConfigKeyPath(["modules", "dev.x", "notify", "done", "mute"])]])
        #expect(store.revision == revision + 1)
        #expect(store.rawValue(at: ConfigKeyPath(["modules", "dev.x", "notify", "done", "mute"])) == .bool(false))
    }

    @Test func schemaKeyEditResolvingToSameValueStaysSilent() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(config: "[closed]\n")
        let counter = StreamCounter(store.changes)
        try fixture.writeConfig("[closed]\nslots = 3\n")  // the default
        await store.fireAndSettle(watcher)
        try await Task.sleep(for: .milliseconds(50))
        #expect(counter.count == 0)
    }
}

@MainActor
struct AssemblyPeekCategoryTests {
    @Test func setupProblemKickerCarriesTheCategory() throws {
        let theme = ThemeController(library: try ThemeLoader.loadBundled()).theme
        let alert = ActiveAlert(
            id: UUID(), module: "core",
            event: NotifierEvent(
                kind: "setup.problem", severity: .warn, title: "t", action: .openSettings(pane: "general"),
                category: "CONFIG"),
            outputs: [.peek], postedAt: Date())
        #expect(PeekContentMapper.content(for: alert, theme: theme).kicker == "Setup · CONFIG")
    }
}

@MainActor
struct AssemblyPeekAnchorTests {
    @Test func hostAnchorsPeeksOnThePointerDisplayElseMain() {
        let fixture = ExpandedFixture()
        let main = IslandAnchor(
            screenFrame: ExpandedFixture.screen, islandFrame: ExpandedFixture.island, notchRect: ExpandedFixture.notch)
        let second = IslandAnchor(
            screenFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
            islandFrame: CGRect(x: 2252, y: 1046, width: 440, height: 34),
            notchRect: CGRect(x: 2372, y: 1048, width: 200, height: 32))
        fixture.host.anchorsOverride = [main, second]
        let provider: any PeekAnchorProvider = fixture.host

        let onSecond = provider.anchor(forDisplayUnder: NSPoint(x: 2000, y: 500))
        #expect(onSecond == PeekAnchor(screenFrame: second.screenFrame, notchRect: second.notchRect, bandHeight: 34))
        let offScreen = provider.anchor(forDisplayUnder: NSPoint(x: -500, y: -500))
        #expect(offScreen?.screenFrame == main.screenFrame)
        #expect(provider.anchor(forDisplayUnder: nil)?.notchRect == main.notchRect)

        fixture.host.anchorsOverride = []
        #expect(provider.anchor(forDisplayUnder: nil) == nil)
    }
}
