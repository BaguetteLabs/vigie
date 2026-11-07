import ModuleKit
import Testing

@testable import VigieCore

@MainActor
struct HotkeyConfigBridgeTests {
    private let moduleManifest = ModuleManifest(
        id: "dev.keys", name: "Keys", icon: "keyboard",
        settings: [SettingDescriptor(key: "jump", label: "Jump", kind: .hotkey(default: nil))])

    @Test func defaultAndConfiguredExpandHotkey() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(manifests: [moduleManifest])
        let binding = FakeHotkeyBinding()
        let center = HotkeyCenter(binding: binding)
        _ = try CoreHotkeys.registerDefaults(in: center, actions: CoreHotkeyActions(expand: { _ in }))
        let bridge = HotkeyConfigBridge(store: store, center: center, manifests: [moduleManifest])
        bridge.start()
        defer { bridge.stop() }
        #expect(center.effectiveShortcut(for: "core.expand") == (try spec("cmd+shift+space")))

        try fixture.writeConfig("[general]\nexpand_hotkey = \"ctrl+opt+space\"\n")
        await store.fireAndSettle(watcher)
        try await waitUntil { center.effectiveShortcut(for: "core.expand") == (try? spec("ctrl+opt+space")) }
    }

    @Test func moduleHotkeyKeyIsMapped() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(
            manifests: [moduleManifest],
            config: "[modules.\"dev.keys\"]\njump = \"cmd+opt+j\"\n")
        let center = HotkeyCenter(binding: FakeHotkeyBinding())
        _ = try center.register(owner: .module("dev.keys"), name: "jump", default: nil, handler: { _ in })
        let bridge = HotkeyConfigBridge(store: store, center: center, manifests: [moduleManifest])
        bridge.start()
        defer { bridge.stop() }
        #expect(center.effectiveShortcut(for: "dev.keys.jump") == (try spec("cmd+opt+j")))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
}
