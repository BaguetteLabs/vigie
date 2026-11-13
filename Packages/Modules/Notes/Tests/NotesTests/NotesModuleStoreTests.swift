import Foundation
import ModuleKit
import Testing

@testable import Notes

/// The module owns a `NoteStore` only while the key is ready (Story 15.2).
@MainActor @Suite struct NotesModuleStoreTests {
    let temp = TempNotes()
    let key = SyncedKey.random()

    func start(_ store: FakeSyncedKeyStore) async throws -> (NotesModule, FakeModuleContext) {
        let storage = FakeStorage()
        storage.folder = temp.folder
        let context = FakeModuleContext(storage: storage, notesKey: store)
        let module = NotesModule(makeStore: { folder, key, _ in
            NoteStore(folder: folder, key: key, io: NoteFileIO(deletion: .remove), watcher: nil)
        })
        try await module.start(context: context)
        return (module, context)
    }

    func waitFor(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func aReadyKeyCreatesTheStoreAndCountsNotes() async throws {
        let (module, _) = try await start(FakeSyncedKeyStore(key: key))
        let store = try #require(module.store)
        #expect(store.folder == temp.folder.standardizedFileURL)
        #expect(store.keyID == key.keyID)
        #expect(module.noteCount == 0)
        try await store.create(body: "one")
        try await store.create(body: "two")
        #expect(module.noteCount == 2)
        await module.refresh()
        #expect(module.store === store)
        await module.stop()
        #expect(module.store == nil)
        await #expect(throws: NoteStoreError.cannotWrite(.stopped)) { try await store.create(body: "x") }
    }

    @Test func noStoreWithoutAKeyAndLockedFilesAreCounted() async throws {
        try temp.writeNote("a", keyID: SyncedKey.random().keyID)
        try temp.writeNote("b", keyID: SyncedKey.random().keyID)
        let (module, _) = try await start(FakeSyncedKeyStore())
        #expect(module.store == nil)
        #expect(module.tabContent == .locked)
        #expect(module.lockedNoteCount == 2)
    }

    @Test func aForeignFileArrivingTearsTheStoreDownAndWritesNothing() async throws {
        let (module, _) = try await start(FakeSyncedKeyStore(key: key))
        let store = try #require(module.store)
        try await store.create(body: "mine")
        try temp.writeNote("theirs", keyID: SyncedKey.random().keyID)
        await store.reload()
        #expect(!store.canWrite)
        await waitFor { module.store == nil }
        #expect(module.keyState.isLocked)
        #expect(module.lockedNoteCount == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: temp.folder.path)
        #expect(names.filter { $0.hasSuffix(".vnote") }.count == 2)
    }

    @Test func aFolderSettingChangeReloadsFromTheNewFolder() async throws {
        let (module, context) = try await start(FakeSyncedKeyStore(key: key))
        try await #require(module.store).create(body: "in the first folder")
        let second = temp.root.appendingPathComponent("Elsewhere", isDirectory: true)
        let seeded = NoteStore(folder: second, key: key, io: NoteFileIO(deletion: .remove), watcher: nil)
        await seeded.start()
        try await seeded.create(body: "a")
        try await seeded.create(body: "b")

        context.fakeStorage.folder = second
        try await context.fakeSettings.set(second.path, for: "folder")
        await waitFor { module.store?.folder == second.standardizedFileURL && module.noteCount == 2 }
        #expect(module.store?.folder == second.standardizedFileURL)
        #expect(module.noteCount == 2)
    }
}
