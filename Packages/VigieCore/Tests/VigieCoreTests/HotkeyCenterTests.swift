import Foundation
import ModuleKit
import Testing

@testable import VigieCore

@MainActor
@Suite struct HotkeyCenterTests {
    let binding = FakeHotkeyBinding()
    let center: HotkeyCenter

    init() {
        center = HotkeyCenter(binding: binding)
    }

    @Test func namesAreNamespacedByOwner() throws {
        _ = try center.register(owner: .core, name: "expand", default: spec("cmd+shift+space")) { _ in }
        _ = try center.register(owner: .module("agents.sessions"), name: "focus", default: spec("ctrl+opt+k")) { _ in }
        #expect(center.registeredNames == ["core.expand", "agents.sessions.focus"])
        #expect(binding.bound["core.expand"] == (try spec("cmd+shift+space")))
        #expect(binding.bound["agents.sessions.focus"] == (try spec("ctrl+opt+k")))
    }

    @Test func duplicateFullNameThrows() throws {
        _ = try center.register(owner: .module("notes"), name: "new", default: spec("opt+cmd+n")) { _ in }
        #expect(throws: HotkeyError.duplicateName("notes.new")) {
            try center.register(owner: .module("notes"), name: "new", default: nil) { _ in }
        }
    }

    @Test func invalidNameThrows() {
        #expect(throws: HotkeyError.invalidName("")) {
            try center.register(owner: .core, name: "", default: nil) { _ in }
        }
        #expect(throws: HotkeyError.invalidName("a b")) {
            try center.register(owner: .core, name: "a b", default: nil) { _ in }
        }
    }

    @Test func conflictEarlierWinsLaterUnboundProblemRecorded() throws {
        var fired: [String] = []
        _ = try center.register(owner: .module("alpha"), name: "go", default: spec("cmd+shift+k")) { _ in
            fired.append("alpha")
        }
        _ = try center.register(owner: .module("beta"), name: "go", default: spec("shift+cmd+K")) { _ in
            fired.append("beta")
        }
        #expect(binding.bound.keys.sorted() == ["alpha.go"])
        #expect(center.bound["beta.go"] == nil)
        #expect(
            center.problems == [HotkeyProblem(kind: .conflict, name: "beta.go", conflictingWith: "alpha.go")]
        )
        #expect(!binding.press("beta.go"))
        binding.press("alpha.go")
        #expect(fired == ["alpha"])
    }

    @Test func unregisteringTheWinnerDoesNotAutoBindTheLoser() throws {
        let first = try center.register(owner: .module("alpha"), name: "go", default: spec("cmd+shift+k")) { _ in }
        _ = try center.register(owner: .module("beta"), name: "go", default: spec("cmd+shift+k")) { _ in }
        first.cancel()
        #expect(binding.bound.isEmpty)
        #expect(center.problems.count == 1)
        // The next config reload re-runs detection and binds it.
        center.applyConfig([:])
        #expect(binding.bound.keys.sorted() == ["beta.go"])
        #expect(center.problems.isEmpty)
    }

    @Test func cancelUnbindsAndIsIdempotent() throws {
        let token = try center.register(owner: .core, name: "expand", default: spec("cmd+shift+space")) { _ in }
        token.cancel()
        token.cancel()
        #expect(binding.bound.isEmpty)
        #expect(binding.unbindCount == 1)
        #expect(center.registeredNames.isEmpty)
        // The name can be registered again.
        _ = try center.register(owner: .core, name: "expand", default: spec("cmd+shift+space")) { _ in }
        #expect(binding.bound.keys.sorted() == ["core.expand"])
    }

    @Test func noDefaultMeansUnboundUntilConfigured() throws {
        _ = try center.register(owner: .module("calendar"), name: "open", default: nil) { _ in }
        #expect(binding.bound.isEmpty)
        center.applyConfig(["calendar.open": "ctrl+cmd+c"])
        #expect(binding.bound["calendar.open"] == (try spec("ctrl+cmd+c")))
    }

    @Test func applyConfigOverridesDefault() throws {
        _ = try center.register(owner: .core, name: "expand", default: spec("cmd+shift+space")) { _ in }
        center.applyConfig(["core.expand": "ctrl+opt+space"])
        #expect(binding.bound["core.expand"] == (try spec("ctrl+opt+space")))
        #expect(center.effectiveShortcut(for: "core.expand") == (try spec("ctrl+opt+space")))
        // Removing the override restores the default.
        center.applyConfig([:])
        #expect(binding.bound["core.expand"] == (try spec("cmd+shift+space")))
    }

    @Test func applyConfigInvalidKeepsDefaultAndRecordsProblem() throws {
        _ = try center.register(owner: .core, name: "expand", default: spec("cmd+shift+space")) { _ in }
        center.applyConfig(["core.expand": "opt+space", "notes.new": "cmd+banana"])
        #expect(binding.bound["core.expand"] == (try spec("cmd+shift+space")))
        #expect(
            center.problems == [
                HotkeyProblem(kind: .invalid, name: "core.expand", value: "opt+space"),
                HotkeyProblem(kind: .invalid, name: "notes.new", value: "cmd+banana"),
            ]
        )
        center.applyConfig([:])
        #expect(center.problems.isEmpty)
    }

    @Test func applyConfigEmptyTurnsHotkeyOff() throws {
        _ = try center.register(owner: .core, name: "expand", default: spec("cmd+shift+space")) { _ in }
        center.applyConfig(["core.expand": ""])
        #expect(binding.bound.isEmpty)
        center.applyConfig(["core.expand": "none"])
        #expect(binding.bound.isEmpty)
    }

    @Test func applyConfigReRunsConflictDetectionInRegistrationOrder() throws {
        _ = try center.register(owner: .module("alpha"), name: "go", default: spec("cmd+shift+a")) { _ in }
        _ = try center.register(owner: .module("beta"), name: "go", default: spec("cmd+shift+b")) { _ in }
        // Beta moves onto alpha's combination: alpha (earlier) keeps it.
        center.applyConfig(["beta.go": "cmd+shift+a"])
        #expect(binding.bound.keys.sorted() == ["alpha.go"])
        #expect(center.problems == [HotkeyProblem(kind: .conflict, name: "beta.go", conflictingWith: "alpha.go")])
        // Alpha moves onto the same combination too: still alpha's.
        center.applyConfig(["alpha.go": "cmd+shift+a", "beta.go": "cmd+shift+a"])
        #expect(binding.bound.keys.sorted() == ["alpha.go"])
        // Alpha moves away: beta is bound.
        center.applyConfig(["alpha.go": "cmd+shift+z", "beta.go": "cmd+shift+a"])
        #expect(binding.bound == ["alpha.go": try spec("cmd+shift+z"), "beta.go": try spec("cmd+shift+a")])
        #expect(center.problems.isEmpty)
    }

    @Test func overrideAppliesToLaterRegistration() throws {
        center.applyConfig(["notes.new": "ctrl+cmd+n"])
        _ = try center.register(owner: .module("notes"), name: "new", default: spec("opt+cmd+n")) { _ in }
        #expect(binding.bound["notes.new"] == (try spec("ctrl+cmd+n")))
    }

    @Test func applyConfigDoesNotRebindUnchanged() throws {
        _ = try center.register(owner: .core, name: "expand", default: spec("cmd+shift+space")) { _ in }
        let binds = binding.bindCount
        center.applyConfig(["core.expand": "cmd+shift+space"])
        #expect(binding.bindCount == binds)
    }

    @Test func eachFireMintsAFreshIntent() throws {
        var intents: [UserIntent] = []
        _ = try center.register(owner: .core, name: "expand", default: spec("cmd+shift+space")) { intents.append($0) }
        binding.press("core.expand")
        binding.press("core.expand")
        #expect(intents.count == 2)
        #expect(intents[0].id != intents[1].id)
    }
}

@MainActor
@Suite struct HotkeyRegistryTests {
    @Test func moduleRegistryNamespacesAndTrackerCancelsOnStop() throws {
        let binding = FakeHotkeyBinding()
        let center = HotkeyCenter(binding: binding)
        let tracker = RegistrationTracker()
        let registry = CoreHotkeyRegistry(moduleID: "notes", center: center, tracker: tracker)
        var received: [UserIntent] = []
        _ = try registry.register(name: "new", default: "opt+cmd+n") { received.append($0) }
        #expect(binding.bound["notes.new"] == (try spec("opt+cmd+n")))
        #expect(tracker.activeCount == 1)
        binding.press("notes.new")
        #expect(received.count == 1)

        tracker.cancelAll()  // what the Registry does when the module stops
        #expect(binding.bound.isEmpty)
        #expect(center.registeredNames.isEmpty)
    }

    @Test func moduleRegistryRejectsInvalidDefault() {
        let center = HotkeyCenter(binding: FakeHotkeyBinding())
        let registry = CoreHotkeyRegistry(moduleID: "notes", center: center, tracker: RegistrationTracker())
        #expect(throws: HotkeyError.optionOnlyModifier) {
            try registry.register(name: "new", default: "opt+n") { _ in }
        }
    }

    @Test func contextFactoryUsesTheSharedCenter() throws {
        let binding = FakeHotkeyBinding()
        let center = HotkeyCenter(binding: binding)
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let factory = CoreModuleContextFactory(
            environment: makeEnvironment(root), eventBus: InProcessEventBus(), hotkeyCenter: center)
        let manifest = ModuleManifest(id: "dev.sample", name: "Sample", icon: "circle")
        let tracker = RegistrationTracker()
        let context = factory.makeContext(for: manifest, tracker: tracker)
        _ = try context.hotkeys.register(name: "ping", default: "ctrl+cmd+p") { _ in }
        #expect(binding.bound.keys.sorted() == ["dev.sample.ping"])
        tracker.cancelAll()
        #expect(binding.bound.isEmpty)
    }
}

@MainActor
@Suite struct CoreHotkeysTests {
    @Test func expandDefaultsToCmdShiftSpace() throws {
        let binding = FakeHotkeyBinding()
        let center = HotkeyCenter(binding: binding)
        var expanded: [UserIntent] = []
        let tokens = try CoreHotkeys.registerDefaults(
            in: center, actions: CoreHotkeyActions(expand: { expanded.append($0) }))
        #expect(tokens.count == 1)
        #expect(binding.bound[CoreHotkeys.expandName]?.description == "cmd+shift+space")
        binding.press(CoreHotkeys.expandName)
        #expect(expanded.count == 1)
    }

    @Test func expandIsEditableInConfig() throws {
        let binding = FakeHotkeyBinding()
        let center = HotkeyCenter(binding: binding)
        _ = try CoreHotkeys.registerDefaults(in: center, actions: CoreHotkeyActions(expand: { _ in }))
        center.applyConfig([CoreHotkeys.expandName: "ctrl+cmd+space"])
        #expect(binding.bound[CoreHotkeys.expandName]?.description == "ctrl+cmd+space")
    }

    @Test func noDefaultUsesOptionOnlyModifiers() throws {
        for (_, value) in CoreHotkeys.defaults {
            let parsed = try HotkeySpec(parsing: value)
            #expect(parsed.modifiers.contains(.command) || parsed.modifiers.contains(.control))
        }
    }
}
