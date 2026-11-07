import Foundation
import Testing

@testable import VigieCore

@MainActor @Suite struct HostConfigBridgeTests {
    @Test func displayKeysReloadThePlacement() {
        for key in [
            CoreSettings.path("display", "display"), CoreSettings.path("virtual_notch", "width"),
            CoreSettings.path("virtual_notch", "style"), CoreSettings.path("closed", "max_side_width"),
            CoreSettings.path("general", "hide_in_fullscreen"),
        ] {
            #expect(HostConfigBridge.actions(for: [key]) == .init(reloadDisplays: true, rearbitrate: false))
        }
    }

    @Test func slotsRearbitrate() {
        #expect(
            HostConfigBridge.actions(for: [CoreSettings.path("closed", "slots")])
                == .init(reloadDisplays: false, rearbitrate: true))
    }

    @Test func otherKeysDoNothing() {
        #expect(HostConfigBridge.actions(for: [CoreSettings.path("general", "open_on_hover")]) == .init())
    }

    @Test func followsTheChangeStream() async throws {
        let (stream, continuation) = AsyncStream.makeStream(of: Set<ConfigKeyPath>.self)
        var reloads = 0
        var rearbitrations = 0
        let bridge = HostConfigBridge(
            changes: stream, reloadDisplays: { reloads += 1 }, rearbitrate: { rearbitrations += 1 })
        bridge.start()
        continuation.yield([CoreSettings.path("virtual_notch", "idle"), CoreSettings.path("closed", "slots")])
        continuation.yield([CoreSettings.path("appearance", "theme")])
        for _ in 0..<50 where reloads == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(reloads == 1)
        #expect(rearbitrations == 1)
        bridge.stop()
    }

    @Test func promptRecordPersistsDone() {
        let suite = "vigie.tests.prompt.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let record = DisplayPromptRecord(suiteName: suite)
        #expect(record.isPending)
        record.markDone()
        #expect(!DisplayPromptRecord(suiteName: suite).isPending)
    }
}
