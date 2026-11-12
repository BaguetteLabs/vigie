import Foundation
import ModuleKit
import Testing
import Wire

@testable import VigieCore

/// Story 12.3: `context.scriptFolder.confirmations` keeps this Mac's script confirmations and declines in
/// `local.toml`, through ConfigStore (AD-8, AD-18), never in the synced `config.toml`.
@MainActor @Suite struct ScriptConfirmationsConfigTests {
    let path = "modules/github.md"
    let hash = String(repeating: "ab", count: 32)
    let other = String(repeating: "cd", count: 32)

    @Test func confirmAndDeclineRoundTripInLocalTomlOnly() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[general]\nopen_on_hover = false\n")
        let syncedBefore = try Data(contentsOf: fixture.configURL)
        let records = ConfigScriptConfirmations(store: store, tracker: RegistrationTracker())
        #expect(records.record(for: path) == .none)

        try await records.confirm(path, sha256: hash)
        var local = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(local.contains(#"[scripts.confirmations."modules/github.md"]"#))
        #expect(local.contains("sha256 = \"\(hash)\""))
        #expect(records.record(for: path) == ScriptConfirmationRecord(confirmedSHA256: hash))
        #expect(try Data(contentsOf: fixture.configURL) == syncedBefore)
        #expect(store.problems.isEmpty)

        // Declining replaces the confirmation; confirming again replaces the decline.
        try await records.decline(path, sha256: other)
        #expect(records.record(for: path) == ScriptConfirmationRecord(declinedSHA256: other))
        local = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(local.contains(#"[scripts.declined."modules/github.md"]"#))
        #expect(!local.contains(hash))
        try await records.confirm(path, sha256: hash)
        #expect(records.record(for: path) == ScriptConfirmationRecord(confirmedSHA256: hash))
        #expect(try Data(contentsOf: fixture.configURL) == syncedBefore)

        // The next launch reads the same record.
        let (reloaded, _) = try await fixture.makeStore()
        let again = ConfigScriptConfirmations(store: reloaded, tracker: RegistrationTracker())
        #expect(again.record(for: path) == ScriptConfirmationRecord(confirmedSHA256: hash))
        #expect(reloaded.problems.isEmpty)
        store.stop()
        reloaded.stop()
    }

    /// A synced `config.toml` (another Mac, a git pull) can never confirm a script on this Mac.
    @Test func aRecordInTheSyncedConfigIsIgnored() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(
            config: "[scripts.confirmations.\"modules/github.md\"]\nsha256 = \"\(hash)\"\n")
        let records = ConfigScriptConfirmations(store: store, tracker: RegistrationTracker())
        #expect(records.record(for: path) == .none)
        // An open table: no unknown-key problem.
        #expect(store.problems.isEmpty)
        store.stop()
    }

    @Test func anOutsideEditOfLocalTomlIsSeenAndTheStreamEndsOnStop() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(local: "")
        let tracker = RegistrationTracker()
        let records = ConfigScriptConfirmations(store: store, tracker: tracker)
        let counter = StreamCounter(records.changes())
        #expect(tracker.activeCount == 1)

        try fixture.writeLocal("[scripts.declined.\"modules/github.md\"]\nsha256 = \"\(hash)\"\n")
        await store.fireAndSettle(watcher)
        #expect(await eventually { counter.count >= 1 })
        #expect(records.record(for: path) == ScriptConfirmationRecord(declinedSHA256: hash))

        // A change elsewhere does not wake integrations.
        let seen = counter.count
        try fixture.writeLocal(
            "[scripts.declined.\"modules/github.md\"]\nsha256 = \"\(hash)\"\n[display]\ndisplay = \"main\"\n")
        await store.fireAndSettle(watcher)
        try await Task.sleep(for: .milliseconds(50))
        #expect(counter.count == seen)

        tracker.cancelAll()
        await counter.task.value
        store.stop()
    }

    @Test func factoryGivesIntegrationsTheConfigBackedRecords() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore()
        let factory = CoreModuleContextFactory(
            environment: fixture.environment, eventBus: InProcessEventBus(), configStore: store)
        let manifest = ModuleManifest(id: "integrations", name: "Integrations", icon: "puzzlepiece.extension")
        let context = factory.makeContext(for: manifest, tracker: RegistrationTracker())
        try await context.scriptFolder.confirmations.confirm(path, sha256: hash)
        #expect(context.scriptFolder.confirmations.record(for: path).confirmedSHA256 == hash)
        let local = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(local.contains(hash))
        store.stop()
    }

    @Test func withoutAConfigStoreNothingIsConfirmedAndWritesAreRefused() async throws {
        let records = NoScriptConfirmations()
        #expect(records.record(for: path) == .none)
        await #expect(throws: ModuleServiceError.notAvailable) { try await records.confirm(path, sha256: hash) }
    }

    /// Story 12.10: a declined update's hash lives in `local.toml` beside the file's records, survives a relaunch
    /// and leaves the confirmation alone.
    @Test func aDeclinedUpdateIsKeptInLocalTomlOnly() async throws {
        let fixture = ConfigFixture()
        let (store, _) = try await fixture.makeStore(config: "[general]\nopen_on_hover = false\n")
        let syncedBefore = try Data(contentsOf: fixture.configURL)
        let records = ConfigScriptConfirmations(store: store, tracker: RegistrationTracker())
        #expect(records.declinedUpdate(for: path) == nil)
        try await records.confirm(path, sha256: hash)
        try await records.declineUpdate(path, sha256: other.uppercased())
        #expect(records.declinedUpdate(for: path) == other)
        #expect(records.record(for: path) == ScriptConfirmationRecord(confirmedSHA256: hash))
        let local = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(local.contains(#"[scripts.declined_updates."modules/github.md"]"#))
        #expect(try Data(contentsOf: fixture.configURL) == syncedBefore)
        #expect(store.problems.isEmpty)

        let (reloaded, _) = try await fixture.makeStore()
        let again = ConfigScriptConfirmations(store: reloaded, tracker: RegistrationTracker())
        #expect(again.declinedUpdate(for: path) == other)
        #expect(reloaded.problems.isEmpty)
        #expect(NoScriptConfirmations().declinedUpdate(for: path) == nil)
        store.stop()
        reloaded.stop()
    }
}
