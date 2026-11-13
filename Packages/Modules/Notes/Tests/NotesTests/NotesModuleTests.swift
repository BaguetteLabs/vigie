import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import Notes

/// A temp `Notes/Vigie` folder under the test's own temp dir (never the real `~/Notes`).
struct TempNotes {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notes-tests-\(UUID().uuidString)")
    var folder: URL { root.appendingPathComponent("Notes/Vigie", isDirectory: true) }

    func create() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// A note file with a header for `keyID`, followed by bytes that stand for ciphertext.
    func writeNote(_ name: String, keyID: String, in folder: URL? = nil) throws {
        let folder = folder ?? self.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var data = NoteFileHeader(keyID: keyID).encoded()
        data.append(Data(repeating: 0xAB, count: 64))
        try data.write(to: folder.appendingPathComponent("\(name).vnote"))
    }

    func marker() -> NoteFileHeader? {
        (try? Data(contentsOf: folder.appendingPathComponent(NotesFolder.markerName))).flatMap(NoteFileHeader.parse)
    }
}

@MainActor @Suite struct NotesModuleTests {
    let temp = TempNotes()

    func start(
        _ store: FakeSyncedKeyStore = FakeSyncedKeyStore(), settings: [String: any SettingValue] = [:]
    ) async throws -> (NotesModule, FakeModuleContext) {
        let storage = FakeStorage()
        storage.folder = temp.folder
        let context = FakeModuleContext(settings: settings, storage: storage, notesKey: store)
        let module = NotesModule()
        try await module.start(context: context)
        return (module, context)
    }

    func waitFor(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: Manifest

    @Test func manifestDeclaresTheSettingsAndStaysHidden() async throws {
        let manifest = NotesModule.staticManifest
        #expect(manifest.id == "notes")
        #expect(!manifest.defaultEnabled)
        #expect(manifest.settings.map(\.key) == ["hotkey", "folder", "clipboard_clear"])
        let folder = try #require(manifest.settings.first { $0.key == "folder" })
        #expect(folder.kind == .path(default: "~/Notes/Vigie"))
        #expect(folder.scope == .local)
        #expect(manifest.settings[0].kind == .hotkey(default: "opt+cmd+n"))
        #expect(manifest.settings[2].kind == .duration(default: .seconds(30)))
        let (module, _) = try await start()
        #expect(module.state == .hidden)
        #expect(module.leftWingItems().isEmpty)
        #expect(module.compactView(size: .wide) == nil)
        #expect(module.expandedView() != nil)
        #expect(module.settingsView() != nil)
    }

    // MARK: Setup

    @Test func setupCreatesOneKeyAndShowsARecoveryKeyThatRoundTrips() async throws {
        let store = FakeSyncedKeyStore()
        let (module, context) = try await start(store)
        #expect(module.keyState == .noKey)
        #expect(module.tabContent == .setup)

        #expect(await module.setUpNotes() == .created)
        #expect(store.createCount == 1)
        let key = try #require(store.key)
        let recovery = try #require(module.pendingRecoveryKey)
        #expect(try RecoveryKey.parse(recovery) == key)
        #expect(module.keyState == .ready(keyID: key.keyID))
        #expect(module.key == key)
        #expect(module.tabContent == .recoveryKey)
        #expect(temp.marker()?.keyID == key.keyID)

        module.copyRecoveryKey()
        #expect(context.fakeClipboard.copies.map(\.text) == [recovery])
        #expect(context.fakeClipboard.copies.first?.clearAfter == .seconds(30))

        module.confirmRecoveryKeySaved()
        #expect(module.pendingRecoveryKey == nil)
        #expect(module.tabContent == .ready)
        // Never a second key.
        #expect(await module.setUpNotes() == .refused)
        #expect(store.createCount == 1)
    }

    @Test func setupIsRefusedWhenTheFolderHasNoteFiles() async throws {
        try temp.writeNote("a", keyID: "0011223344556677")
        let store = FakeSyncedKeyStore()
        let (module, _) = try await start(store)
        #expect(module.keyState == .waiting(keyIDs: ["0011223344556677"]))
        #expect(module.tabContent == .locked)
        #expect(await module.setUpNotes() == .refused)
        #expect(store.createCount == 0)
        #expect(store.key == nil)
    }

    @Test func notDownloadedOrHeaderlessNotesAndTheMarkerAlsoBlockSetup() async throws {
        try temp.create()
        try Data().write(to: temp.folder.appendingPathComponent(".b.vnote.icloud"))
        let (module, _) = try await start()
        #expect(module.keyState == .waiting(keyIDs: []))

        let other = TempNotes()
        try other.create()
        try await NotesFolder.writeMarker(keyID: "8899aabbccddeeff", in: other.folder)
        let storage = FakeStorage()
        storage.folder = other.folder
        let second = NotesModule()
        try await second.start(context: FakeModuleContext(storage: storage))
        #expect(second.keyState == .waiting(keyIDs: ["8899aabbccddeeff"]))
        #expect(await second.setUpNotes() == .refused)
    }

    @Test func setupAdoptsAKeyTheStoreAlreadyHolds() async throws {
        let store = FakeSyncedKeyStore()
        let (module, _) = try await start(store)
        #expect(module.keyState == .noKey)
        let synced = SyncedKey.random()
        store.arrive(synced, notify: false)
        #expect(await module.setUpNotes() == .adopted)
        #expect(store.createCount == 0)
        #expect(module.pendingRecoveryKey == nil)
        #expect(module.keyState == .ready(keyID: synced.keyID))
    }

    @Test func aKeyAlreadyInTheStoreIsReadyWithoutSetup() async throws {
        let synced = SyncedKey.random()
        let store = FakeSyncedKeyStore(key: synced)
        let (module, _) = try await start(store)
        #expect(module.keyState == .ready(keyID: synced.keyID))
        #expect(module.tabContent == .ready)
        #expect(await module.setUpNotes() == .refused)
        #expect(store.createCount == 0)
    }

    @Test func failedSetupIsReported() async throws {
        let store = FakeSyncedKeyStore()
        store.failWrites = true
        let (module, _) = try await start(store)
        #expect(await module.setUpNotes() == .failed)
        #expect(module.setupFailed)
        #expect(module.keyState == .noKey)
    }

    // MARK: Waiting and recovery

    @Test func filesWithAnUnknownKeyIDAreTheWaitingStateAndWriteNothing() async throws {
        let foreign = SyncedKey.random()
        try temp.writeNote("a", keyID: foreign.keyID)
        let held = SyncedKey.random()
        let (module, _) = try await start(FakeSyncedKeyStore(key: held))
        #expect(module.keyState == .mismatch(keyIDs: [foreign.keyID]))
        #expect(module.keyState.isLocked)
        #expect(module.tabContent == .locked)
        #expect(module.key == nil)
        #expect(temp.marker() == nil)
    }

    @Test func theRightRecoveryKeyUnlocksAndImports() async throws {
        let key = SyncedKey.random()
        try temp.writeNote("a", keyID: key.keyID)
        let store = FakeSyncedKeyStore()
        let (module, _) = try await start(store)
        #expect(module.keyState == .waiting(keyIDs: [key.keyID]))
        let typed = RecoveryKey.encode(key).lowercased().replacingOccurrences(of: "-", with: " ")
        #expect(await module.enterRecoveryKey(typed))
        #expect(store.imports == [key])
        #expect(module.keyState == .ready(keyID: key.keyID))
        #expect(!module.keyIsSessionOnly)
        #expect(module.recoveryError == nil)
    }

    @Test func aWrongOrMistypedRecoveryKeyIsRefused() async throws {
        let key = SyncedKey.random()
        try temp.writeNote("a", keyID: key.keyID)
        let store = FakeSyncedKeyStore()
        let (module, _) = try await start(store)

        #expect(!(await module.enterRecoveryKey(RecoveryKey.encode(SyncedKey.random()))))
        #expect(module.recoveryError == .wrongKey)
        #expect(
            String(localized: RecoveryEntryError.wrongKey.message) == "This recovery key does not match your notes.")

        var typo = Array(RecoveryKey.encode(key))
        typo[10] = typo[10] == "7" ? "8" : "7"
        #expect(!(await module.enterRecoveryKey(String(typo))))
        #expect(module.recoveryError == .invalid)
        #expect(
            String(localized: RecoveryEntryError.invalid.message)
                == "This recovery key has a typo. Check it and try again.")
        #expect(store.imports.isEmpty)
        #expect(module.keyState == .waiting(keyIDs: [key.keyID]))
    }

    @Test func aKeyArrivingThroughTheChangeStreamUnlocks() async throws {
        let key = SyncedKey.random()
        try temp.writeNote("a", keyID: key.keyID)
        let store = FakeSyncedKeyStore()
        let (module, _) = try await start(store)
        #expect(module.keyState == .waiting(keyIDs: [key.keyID]))
        await waitFor { store.listeners > 0 }
        store.arrive(key)
        await waitFor { module.keyState == .ready(keyID: key.keyID) }
        #expect(module.keyState == .ready(keyID: key.keyID))
        await module.stop()
    }

    // MARK: Unavailable

    @Test func anUnavailableStoreIsTheUnavailableStateAndNeverCrashes() async throws {
        let store = FakeSyncedKeyStore(availability: .unavailable(.noSigningTeam))
        let (module, _) = try await start(store)
        #expect(module.keyState == .unavailable(.noSigningTeam))
        #expect(module.tabContent == .unavailable)
        #expect(await module.setUpNotes() == .refused)
        #expect(
            NotesText.string("notes.unavailable.label") == "KEYCHAIN UNAVAILABLE IN THIS BUILD")

        // A recovery key still unlocks, held for the session only.
        let key = SyncedKey.random()
        #expect(await module.enterRecoveryKey(RecoveryKey.encode(key)))
        #expect(module.keyState == .ready(keyID: key.keyID))
        #expect(module.keyIsSessionOnly)
        #expect(store.imports.isEmpty)
    }

    // MARK: iCloud Keychain statement

    @Test func settingsStateTheRecoveryKeyIsTheOnlyRouteUnlessICloudKeychainIsOn() async throws {
        for (status, shown) in [(ICloudKeychainStatus.unknown, true), (.off, true), (.on, false)] {
            let (module, _) = try await start(FakeSyncedKeyStore(iCloud: status))
            #expect(module.showsRecoveryOnlyStatement == shown)
        }
        #expect(
            NotesText.string("notes.icloud.statement")
                == "If iCloud Keychain is off, your recovery key is the only way to read your notes on another Mac.")
    }

    // MARK: Dev build folder

    @Test func aDevBuildWithItsOwnKeyUsesItsOwnFolder() async throws {
        // Release notes exist in the default folder; the dev build must not see them.
        try temp.writeNote("release", keyID: "0011223344556677")
        let store = FakeSyncedKeyStore(scope: .ownBuild(folderName: "Vigie Dev"))
        let (module, _) = try await start(store)
        let devFolder = temp.root.appendingPathComponent("Notes/Vigie Dev", isDirectory: true)
        #expect(module.folder?.standardizedFileURL == devFolder.standardizedFileURL)
        #expect(module.usesOwnFolder)
        #expect(module.keyState == .noKey)
        #expect(await module.setUpNotes() == .created)
        #expect(FileManager.default.fileExists(atPath: devFolder.appendingPathComponent("notes-key.json").path))
        #expect(temp.marker() == nil)
    }

    @Test func aDevBuildSharingTheReleaseKeyUsesTheConfiguredFolder() async throws {
        let (module, _) = try await start(FakeSyncedKeyStore(scope: .shared))
        #expect(module.folder == temp.folder)
        #expect(!module.usesOwnFolder)
    }

    @Test func anExplicitFolderIsKeptInTheDevBuild() async throws {
        let store = FakeSyncedKeyStore(scope: .ownBuild(folderName: "Vigie Dev"))
        let (module, _) = try await start(store, settings: ["folder": "~/Elsewhere"])
        #expect(module.folder == temp.folder)
        #expect(!module.usesOwnFolder)
    }

    // MARK: Copy

    @Test func catalogStringsResolve() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Notes/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        for key in strings.keys {
            #expect(NotesText.string(key) != key, "\(key) does not resolve")
        }
        for descriptor in NotesModule.staticManifest.settings {
            #expect(!String(localized: descriptor.label).hasPrefix("notes."), "\(descriptor.key) label")
        }
        #expect(String(localized: NotesModule.staticManifest.name) == "Notes")
        #expect(
            NotesSettingsView.statusLine(.ready(keyID: "66687aadf862bd77"), sessionOnly: false)
                == "Notes key ready (key id 66687aadf862bd77).")
        #expect(
            NotesSettingsView.statusLine(.waiting(keyIDs: []), sessionOnly: false)
                == "Waiting for iCloud Keychain, or enter your recovery key.")
        #expect(String(localized: VigieCopy.notesLocked.label) == "NOTES LOCKED")
    }
}
