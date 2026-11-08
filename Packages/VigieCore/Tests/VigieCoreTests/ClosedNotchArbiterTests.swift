import AppKit
import ModuleKit
import Observation
import SwiftUI
import Testing
import VigieUI

@testable import VigieCore

private func item(
    _ id: String, _ priority: Int, state: ModuleState? = nil, order: Int = 0,
    sizes: Set<CompactSize> = Set(CompactSize.allCases)
) -> LeftWingItem {
    LeftWingItem(id: id, priority: priority, state: state, order: order) { size in
        sizes.contains(size) ? AnyView(Text(verbatim: id)) : nil
    }
}

private func snap(_ id: ModuleID, _ state: ModuleState, _ items: [LeftWingItem]) -> ArbiterModuleSnapshot {
    ArbiterModuleSnapshot(moduleID: id, state: state, items: items)
}

extension SideLayout {
    /// `module/item` ids, `transient` for a readout.
    fileprivate var ids: [String] { shown.map(\.id) }
}

@Suite struct ClosedNotchArbiterTests {
    @Test func ordersByStateDescendingThenPriorityAscending() {
        let layout = ClosedNotchArbiter.leading(
            [
                snap("time", .ambient, [item("clock", 10)]),
                snap("agents.usage", .active, [item("claude", 30), item("codex", 20)]),
                snap("scripts", .alert, [item("api", 90)]),
            ], slots: 4)
        #expect(layout.ids == ["scripts/api", "agents.usage/codex", "agents.usage/claude", "time/clock"])
        #expect(layout.overflowCount == 0)
    }

    @Test func tiesBreakByOrderThenModuleAndItemID() {
        let layout = ClosedNotchArbiter.leading(
            [
                snap("agents.usage", .active, [item("gemini", 20, order: 2), item("claude", 20, order: 0)]),
                snap("scripts", .active, [item("b", 20, order: 1), item("a", 20, order: 1)]),
            ], slots: 4)
        #expect(layout.ids == ["agents.usage/claude", "scripts/a", "scripts/b", "agents.usage/gemini"])
    }

    @Test func hiddenModulesAndHiddenItemsAreExcluded() {
        let layout = ClosedNotchArbiter.leading(
            [
                snap("time", .hidden, [item("clock", 1, state: .alert)]),
                snap("scripts", .active, [item("off", 1, state: .hidden), item("on", 2)]),
            ], slots: 3)
        #expect(layout.ids == ["scripts/on"])
    }

    @Test func perItemStateOverrideOutranksSiblings() {
        let layout = ClosedNotchArbiter.leading(
            [
                snap(
                    "agents.usage", .ambient,
                    [item("claude", 10), item("codex", 20, state: .alert), item("gemini", 30)]),
                snap("time", .active, [item("clock", 5)]),
            ], slots: 2)
        #expect(layout.ids == ["agents.usage/codex", "time/clock"])
        #expect(layout.overflowCount == 2)
    }

    @Test(arguments: [(0, 1), (1, 1), (2, 2), (3, 3), (4, 4), (9, 4), (-3, 1)])
    func overflowCountsAndClamping(slots: Int, expectedShown: Int) {
        let items = (0..<6).map { item("i\($0)", $0) }
        let layout = ClosedNotchArbiter.leading([snap("scripts", .active, items)], slots: slots)
        #expect(ClosedNotchArbiter.clampSlots(slots) == expectedShown)
        #expect(layout.shown.count == expectedShown)
        #expect(layout.overflowCount == 6 - expectedShown)
        #expect(layout.ids == (0..<expectedShown).map { "scripts/i\($0)" })
    }

    @Test func alertIsNeverHiddenWhileALowerStateIsVisible() {
        var rng = SeededGenerator(seed: 0x5EED)
        let states = ModuleState.allCases
        for _ in 0..<200 {
            let snapshots = (0..<Int.random(in: 1...4, using: &rng)).map { m in
                snap(
                    ModuleID("m\(m)")!, states.randomElement(using: &rng)!,
                    (0..<Int.random(in: 0...4, using: &rng)).map { i in
                        item(
                            "i\(i)", Int.random(in: 0...100, using: &rng),
                            state: Bool.random(using: &rng) ? states.randomElement(using: &rng) : nil,
                            order: Int.random(in: 0...3, using: &rng))
                    })
            }
            let slots = Int.random(in: 1...4, using: &rng)
            let transient: TransientReadout? = Bool.random(using: &rng) ? .copied(lines: 2) : nil
            let lane = ClosedNotchArbiter.leadingLane(snapshots)
            let layout = ClosedNotchArbiter.layout(lane: lane, slots: slots, transient: transient)
            let shownIDs = Set(layout.ids)
            let shownStates = layout.shown.compactMap { entry -> ModuleState? in
                if case .item(let lane) = entry { return lane.state }
                return nil
            }
            let hidden = lane.filter { !shownIDs.contains($0.id) }
            #expect(hidden.count == layout.overflowCount)
            for overflowed in hidden {
                #expect(shownStates.allSatisfy { $0 >= overflowed.state })
            }
            #expect(!lane.contains { $0.state == .hidden })
        }
    }

    @Test func itemThatRendersAtNoSizeYieldsItsSlot() {
        let blank = item("blank", 1, sizes: [])
        let layout = ClosedNotchArbiter.leading(
            [snap("scripts", .active, [blank, item("a", 2), item("b", 3), item("c", 4)])],
            slots: 2,
            isRenderable: { item in item.id != "blank" })
        #expect(layout.ids == ["scripts/a", "scripts/b"])
        #expect(layout.overflowCount == 1)  // c; the unrenderable item is not counted
    }

    @MainActor @Test func rendererCanRenderMatchesCompactViews() {
        #expect(!LaneRenderer.canRender(item("blank", 1, sizes: [])))
        #expect(LaneRenderer.canRender(item("icon", 1, sizes: [.icon])))
        let layout = ClosedNotchArbiter.leading(
            [snap("scripts", .active, [item("blank", 1, sizes: []), item("icon", 2, sizes: [.icon])])],
            slots: 1, isRenderable: LaneRenderer.canRender)
        #expect(layout.ids == ["scripts/icon"])
    }

    @MainActor @Test func sizeFallbackStartsWideWhenAloneElseShort() {
        #expect(LaneRenderer.sizes(entryCount: 1) == [.wide, .short, .icon])
        #expect(LaneRenderer.sizes(entryCount: 3) == [.short, .icon, .wide])
        var asked: [CompactSize] = []
        let probe = LeftWingItem(id: "p", priority: 0) { size in
            MainActor.assumeIsolated { asked.append(size) }
            return size == .icon ? AnyView(EmptyView()) : nil
        }
        #expect(LaneRenderer.view(for: probe, entryCount: 1) != nil)
        #expect(asked == [.wide, .short, .icon])
        #expect(LaneRenderer.view(for: item("w", 0, sizes: [.wide]), entryCount: 2) != nil)
        #expect(LaneRenderer.view(for: item("none", 0, sizes: []), entryCount: 2) == nil)
    }

    @Test func emptySides() {
        #expect(ClosedNotchArbiter.leading([], slots: 3).isEmpty)
        #expect(ClosedNotchArbiter.trailing([], slots: 3).isEmpty)
        #expect(ClosedNotchArbiter.leading([snap("scripts", .active, [])], slots: 3).isEmpty)
        #expect(ClosedNotchArbiter.trailing([snap("agents.sessions", .hidden, [item("s", 1)])], slots: 3).isEmpty)
    }

    @Test func trailingSideAcceptsOnlySessions() {
        let snapshots = [
            snap(
                "agents.sessions", .active, [item("s1", 2), item("s2", 1, state: .alert), item("s3", 3), item("s4", 4)]),
            snap("scripts", .alert, [item("api", 0)]),
        ]
        let trailing = ClosedNotchArbiter.trailing(snapshots, slots: 3)
        #expect(trailing.ids == ["agents.sessions/s2", "agents.sessions/s1", "agents.sessions/s3"])
        #expect(trailing.overflowCount == 1)
        let leading = ClosedNotchArbiter.leading(snapshots, slots: 3)
        #expect(leading.ids == ["scripts/api"])
        #expect(ClosedNotchArbiter.trailing([snap("scripts", .alert, [item("api", 0)])], slots: 3).isEmpty)
    }

    @Test func transientSitsAfterTheFirstItemAndBumpsTheLastIntoOverflow() {
        let snapshots = [snap("scripts", .active, (0..<4).map { item("i\($0)", $0) })]
        let plain = ClosedNotchArbiter.leading(snapshots, slots: 3)
        #expect(plain.ids == ["scripts/i0", "scripts/i1", "scripts/i2"])
        #expect(plain.overflowCount == 1)
        let copied = ClosedNotchArbiter.leading(snapshots, slots: 3, transient: .copied(lines: 3))
        #expect(copied.ids == ["scripts/i0", "transient", "scripts/i1"])
        #expect(copied.overflowCount == 2)

        let one = ClosedNotchArbiter.leading(snapshots, slots: 1, transient: .noTextFound)
        #expect(one.ids == ["scripts/i0", "transient"])
        #expect(one.overflowCount == 3)

        let alone = ClosedNotchArbiter.leading([], slots: 3, transient: .copied(lines: 1))
        #expect(alone.ids == ["transient"])
        #expect(alone.overflowCount == 0)
        #expect(!alone.isEmpty)
    }
}

/// A small deterministic generator for the property-style test.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A module whose left-wing items tests can change.
@MainActor @Observable
final class LaneModule: NotchModule {
    let manifest: ModuleManifest
    var state: ModuleState = .hidden
    var items: [LeftWingItem] = []

    init(_ id: ModuleID) {
        manifest = ModuleManifest(id: id, name: "Lane", icon: "circle")
    }

    func leftWingItems() -> [LeftWingItem] { items }
    func start(context: any ModuleContext) async throws {}
    func stop() async {}
}

@MainActor @Suite struct NotchHostArbitrationTests {
    @MainActor struct Fixture {
        let modules: [ModuleID: LaneModule]
        let registry: ModuleRegistry
        let host: NotchHost
        let clock = TestClock()

        init(ids: [ModuleID], slots: Int = 3) {
            let clock = clock
            var modules: [ModuleID: LaneModule] = [:]
            for id in ids { modules[id] = LaneModule(id) }
            let made = modules
            registry = ModuleRegistry(
                descriptors: ids.map { id in
                    ModuleDescriptor(manifest: ModuleManifest(id: id, name: "Lane", icon: "circle")) { made[id]! }
                },
                enablement: TestEnablement(),
                contextFactory: CoreModuleContextFactory(
                    environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus()),
                logger: testLogger)
            self.modules = modules
            let library = try! ThemeLoader.loadBundled()
            host = NotchHost(
                themeController: ThemeController(library: library), registry: registry,
                contextMenu: NotchContextMenu(), closedSlots: { slots }, displays: { [] }, clock: clock,
                logger: testLogger)
        }
    }

    @Test func rearbitratesWhenAModuleStateChanges() async {
        let f = Fixture(ids: ["time", "scripts", "agents.sessions"], slots: 1)
        f.modules["time"]!.items = [item("clock", 10)]
        f.modules["scripts"]!.items = [item("api", 50)]
        f.modules["agents.sessions"]!.items = [item("s1", 0)]
        await f.registry.start()
        f.host.rearbitrate()
        #expect(f.host.leadingLayout.isEmpty)  // every module still hidden

        f.modules["time"]!.state = .ambient
        f.modules["scripts"]!.state = .ambient
        #expect(await eventually { f.host.leadingLayout.ids == ["time/clock"] })
        #expect(f.host.leadingLayout.overflowCount == 1)

        f.modules["scripts"]!.state = .alert
        #expect(await eventually { f.host.leadingLayout.ids == ["scripts/api"] })

        f.modules["agents.sessions"]!.state = .active
        #expect(await eventually { f.host.trailingLayout.ids == ["agents.sessions/s1"] })
        #expect(f.host.leadingLayout.ids == ["scripts/api"])
        await f.registry.shutdown()
        #expect(await eventually { f.host.leadingLayout.isEmpty && f.host.trailingLayout.isEmpty })
    }

    @Test func transientReadoutLastsItsDurationThenLeaves() async {
        let f = Fixture(ids: ["scripts"], slots: 2)
        f.modules["scripts"]!.items = [item("a", 1), item("b", 2)]
        f.modules["scripts"]!.state = .active
        await f.registry.start()
        f.host.rearbitrate()
        #expect(f.host.leadingLayout.ids == ["scripts/a", "scripts/b"])

        f.host.showTransient(.copied(lines: 3), duration: .milliseconds(50))
        #expect(f.host.transient == .copied(lines: 3))
        #expect(f.host.leadingLayout.ids == ["scripts/a", "transient"])
        #expect(f.host.leadingLayout.overflowCount == 1)
        #expect(await eventually { f.clock.sleeperCount == 1 })
        f.clock.advance(by: .milliseconds(49))
        await Task.yield()
        #expect(f.host.transient == .copied(lines: 3), "still showing before its duration")
        f.clock.advance(by: .milliseconds(1))
        #expect(await eventually { f.host.leadingLayout.ids == ["scripts/a", "scripts/b"] })
        #expect(f.host.transient == nil)
        await f.registry.shutdown()
    }

    @Test func defaultTransientDurationIsTheConfirmReadoutToken() throws {
        let theme = try ThemeController(library: ThemeLoader.loadBundled()).islandTheme
        #expect(theme.motion(.confirmReadout) == .seconds(2))
    }
}
