import Foundation
import ModuleKit
import Testing

@testable import Notes

/// `NSFileVersion` stand-in: conflict versions per note file name, their bytes in the test's temp folder.
final class FakeConflicts: ConflictVersionsProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var versions: [String: [ConflictVersion]] = [:]
    private var resolvedIDs: [String] = []

    var resolved: [String] { lock.withLock { resolvedIDs } }

    func add(_ version: ConflictVersion, for name: String) {
        lock.withLock { versions[name, default: []].append(version) }
    }

    func unresolvedConflicts(of url: URL) -> [ConflictVersion] {
        lock.withLock { versions[url.lastPathComponent] ?? [] }
    }

    func read(_ version: ConflictVersion, of url: URL) throws -> Data { try Data(contentsOf: version.url) }

    func resolve(_ version: ConflictVersion, of url: URL) throws {
        lock.withLock {
            versions[url.lastPathComponent]?.removeAll { $0 == version }
            resolvedIDs.append(version.id)
        }
    }
}

/// Every log line of the stores of a test.
@MainActor final class LogBox {
    var lines: [String] = []
}

@MainActor @Suite struct NoteStoreTests {
    let temp = TempNotes()
    let key = SyncedKey.random()
    let conflicts = FakeConflicts()
    let logs = LogBox()
    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    func makeStore(
        key: SyncedKey? = nil, watcher: (any NotesFolderWatching)? = nil, now: Date = fixedDate
    ) -> NoteStore {
        let logs = logs
        return NoteStore(
            folder: temp.folder, key: key ?? self.key, io: NoteFileIO(conflicts: conflicts, deletion: .remove),
            watcher: watcher, now: { now }, log: { logs.lines.append($0) })
    }

    func started(key: SyncedKey? = nil, watcher: (any NotesFolderWatching)? = nil) async -> NoteStore {
        let store = makeStore(key: key, watcher: watcher)
        await store.start()
        return store
    }

    func files() -> [String: Data] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: temp.folder.path)) ?? []
        return Dictionary(
            uniqueKeysWithValues: names.map {
                ($0, (try? Data(contentsOf: temp.folder.appendingPathComponent($0))) ?? Data())
            })
    }

    func waitFor(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<600 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func expectNoTextInLogs(_ texts: [String]) {
        for line in logs.lines {
            for text in texts { #expect(!line.contains(text), "log line leaks note text: \(line)") }
        }
    }

    // MARK: Format

    @Test func createWritesOneEncryptedFileThatAFreshStoreReads() async throws {
        let store = await started()
        let note = try await store.create(body: "# Groceries\nmilk and eggs")
        #expect(note.title == "Groceries")
        #expect(note.created == Self.fixedDate && note.modified == Self.fixedDate)

        let all = files()
        #expect(Array(all.keys) == ["\(note.id.uuidString.lowercased()).vnote"])
        let data = try #require(all.values.first)
        let header = try #require(NoteFileHeader.parse(data))
        #expect(header == NoteFileHeader(format: 1, keyID: key.keyID))
        let firstLine = String(decoding: data.prefix { $0 != 0x0A }, as: UTF8.self)
        #expect(firstLine == "{\"format\":1,\"key_id\":\"\(key.keyID)\"}")
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("milk") && !text.contains("Groceries"))
        // Header line + 12-byte nonce + ciphertext + 16-byte tag.
        #expect(data.count > firstLine.utf8.count + 1 + 12 + 16)

        let fresh = await started()
        #expect(fresh.notes == [note])
        #expect(fresh.canWrite)
        expectNoTextInLogs(["milk", "Groceries"])
    }

    @Test func tamperedOrHeaderSwappedFilesAreUnreadableNotFatal() async throws {
        let store = await started()
        let good = try await store.create(body: "keep me")
        let tampered = try await store.create(body: "tamper me")
        let swapped = try await store.create(body: "swap my header")
        let truncated = try await store.create(body: "cut me")
        func url(_ note: Note) -> URL { temp.folder.appendingPathComponent(Note.fileName(for: note.id)) }

        var bytes = try Data(contentsOf: url(tampered))
        bytes[bytes.count - 20] ^= 0xFF
        try bytes.write(to: url(tampered))

        // Same header fields, other bytes: the authenticated header no longer matches.
        let original = try Data(contentsOf: url(swapped))
        var reordered = Data("{\"key_id\":\"\(key.keyID)\",\"format\":1}\n".utf8)
        reordered.append(original.drop { $0 != 0x0A }.dropFirst())
        try reordered.write(to: url(swapped))

        try Data(try Data(contentsOf: url(truncated)).prefix(60)).write(to: url(truncated))

        let fresh = await started()
        #expect(fresh.notes.map(\.id) == [good.id])
        #expect(
            fresh.unreadableFiles
                == Set([tampered, swapped, truncated].map { Note.fileName(for: $0.id) }))
        #expect(fresh.canWrite)
        #expect(throws: NoteFileError.corrupt) { try NoteFile.open(reordered, key: key) }
    }

    @Test func aNewerFormatIsUnreadable() async throws {
        try temp.create()
        var data = NoteFileHeader(format: 2, keyID: key.keyID).encoded()
        data.append(Data(repeating: 1, count: 40))
        try data.write(to: temp.folder.appendingPathComponent("future.vnote"))
        #expect(throws: NoteFileError.unsupportedFormat(2)) { try NoteFile.open(data, key: key) }
        let store = await started()
        #expect(store.unreadableFiles == ["future.vnote"])
        #expect(store.notes.isEmpty)
    }

    // MARK: Unknown key

    @Test func aFileWithAnUnknownKeyIsLockedAndNothingIsWritten() async throws {
        let other = SyncedKey.random()
        let mine = await started()
        let ours = try await mine.create(body: "ours")
        mine.stop()
        let foreignStore = await started(key: other)
        #expect(!foreignStore.canWrite)
        // Another Mac with another key writes a note (a store with that key would itself refuse here).
        var foreignBytes = NoteFileHeader(keyID: other.keyID).encoded()
        foreignBytes.append(Data(repeating: 7, count: 48))
        try foreignBytes.write(to: temp.folder.appendingPathComponent("theirs.vnote"))

        let before = files()
        var foreignSignals = 0
        let store = makeStore()
        store.onForeignKey = { foreignSignals += 1 }
        await store.start()
        #expect(store.lockedFiles.count == 1)
        #expect(store.foreignKeyIDs == [other.keyID])
        #expect(store.notes == [ours])
        #expect(!store.canWrite)
        #expect(store.writeBlock == .foreignKey(keyIDs: [other.keyID]))
        #expect(foreignSignals == 1)
        await #expect(throws: NoteStoreError.cannotWrite(.foreignKey(keyIDs: [other.keyID]))) {
            try await store.create(body: "new")
        }
        await #expect(throws: NoteStoreError.self) { try await store.update(ours.id, body: "changed") }
        await #expect(throws: NoteStoreError.self) { try await store.delete(ours.id) }
        #expect(files() == before)
    }

    @Test func aForeignKeyMarkerAlsoBlocksWrites() async throws {
        try await NotesFolder.writeMarker(keyID: SyncedKey.random().keyID, in: temp.folder)
        let before = files()
        let store = await started()
        #expect(!store.canWrite)
        await #expect(throws: NoteStoreError.self) { try await store.create(body: "x") }
        #expect(files() == before)
    }

    @Test func aStoppedStoreWritesNothing() async throws {
        let store = await started()
        store.stop()
        await #expect(throws: NoteStoreError.cannotWrite(.stopped)) { try await store.create(body: "x") }
        #expect(files().isEmpty)
    }

    // MARK: Update and delete

    @Test func updateChangesTitleAndModifiedAndKeepsTheFileName() async throws {
        let created = await started()
        let note = try await created.create(body: "first title\nbody")
        let later = Self.fixedDate.addingTimeInterval(60)
        let store = makeStore(now: later)
        await store.start()
        let updated = try await store.update(note.id, body: "\n  ## second title  \nmore")
        #expect(updated.id == note.id)
        #expect(updated.title == "second title")
        #expect(updated.created == note.created)
        #expect(updated.modified == later)
        #expect(Array(files().keys) == [Note.fileName(for: note.id)])
        #expect(await started().note(note.id) == updated)
        #expect(try await store.update(note.id, body: updated.body) == updated)
        await #expect(throws: NoteStoreError.notFound) { try await store.update(UUID(), body: "x") }
    }

    @Test func titlesAreTheFirstLineTrimmedAndCapped() {
        #expect(Note.title(of: "") == "")
        #expect(Note.title(of: "\n \n  hello  \nworld") == "hello")
        #expect(Note.title(of: "# Heading") == "Heading")
        #expect(Note.title(of: String(repeating: "a", count: 300)).count == 120)
    }

    @Test func notesAreSortedByModifiedDescending() async throws {
        var date = Self.fixedDate
        for body in ["old", "mid", "new"] {
            let store = makeStore(now: date)
            await store.start()
            try await store.create(body: body)
            date.addTimeInterval(10)
        }
        #expect(await started().notes.map(\.title) == ["new", "mid", "old"])
    }

    @Test func deleteRemovesTheFile() async throws {
        let store = await started()
        let note = try await store.create(body: "bye")
        let other = try await store.create(body: "stay")
        try await store.delete(note.id)
        #expect(store.notes == [other])
        #expect(Array(files().keys) == [Note.fileName(for: other.id)])
        await #expect(throws: NoteStoreError.notFound) { try await store.delete(note.id) }
    }

    // MARK: Watcher

    @Test func anExternalWriteReloadsAndOwnWritesAreNotReread() async throws {
        try temp.create()
        let watched = await started(watcher: NotesFolderWatcher(debounce: .milliseconds(20)))
        let other = await started()
        let external = try await other.create(body: "from another Mac")
        await waitFor { watched.notes.count == 1 }
        #expect(watched.notes == [external])

        let decrypted = watched.decryptCount
        try await watched.create(body: "mine")
        try await Task.sleep(for: .milliseconds(100))
        await watched.reload()
        #expect(watched.notes.count == 2)
        #expect(watched.decryptCount == decrypted)

        let edited = try await other.update(external.id, body: "edited elsewhere")
        await waitFor { watched.note(external.id)?.body == edited.body }
        #expect(watched.note(external.id) == edited)

        try await other.delete(external.id)
        await waitFor { watched.notes.count == 1 }
        #expect(watched.note(external.id) == nil)
        watched.stop()
    }

    @Test func aFolderCreatedLaterIsWatched() async throws {
        let watched = await started(watcher: NotesFolderWatcher(debounce: .milliseconds(20)))
        #expect(watched.notes.isEmpty && watched.isLoaded)
        let other = await started()
        let note = try await other.create(body: "first note")
        await waitFor { watched.notes.count == 1 }
        #expect(watched.notes == [note])
        watched.stop()
    }

    @Test func aFolderCreatedBeforeTheRegistrationIsWatched() async throws {
        let watcher = NotesFolderWatcher(debounce: .milliseconds(20))
        var created = false
        // The folder appears after the ancestor was chosen, before the kernel watch exists: no event says so.
        watcher.beforeResume = { [temp] _ in
            guard !created else { return }
            created = true
            try? temp.create()
        }
        var calls = 0
        watcher.start(temp.folder) { calls += 1 }
        await waitFor { watcher.watchesFolder }
        #expect(watcher.watchesFolder)
        try temp.writeNote("late", keyID: "k")
        await waitFor { calls > 0 }
        #expect(calls > 0)
        watcher.stop()
    }

    @Test func aFileWrittenBeforeTheRegistrationReachesTheHandler() async throws {
        try temp.create()
        let watcher = NotesFolderWatcher(debounce: .milliseconds(20))
        watcher.beforeResume = { [temp] _ in try? temp.writeNote("early", keyID: "k") }
        var calls = 0
        watcher.start(temp.folder) { calls += 1 }
        await waitFor { calls > 0 }
        #expect(calls > 0)
        watcher.stop()
    }

    @Test func stoppingBeforeTheRegistrationLeavesNothingArmed() async throws {
        try temp.create()
        let watcher = NotesFolderWatcher(debounce: .milliseconds(20))
        var calls = 0
        watcher.start(temp.folder) { calls += 1 }
        watcher.stop()
        #expect(!watcher.watchesFolder)
        await waitFor { watcher.openDescriptors == 0 }
        try await Task.sleep(for: .milliseconds(100))
        try temp.writeNote("after", keyID: "k")
        try await Task.sleep(for: .milliseconds(100))
        #expect(calls == 0 && watcher.openDescriptors == 0)
    }

    @Test func aWatcherDroppedWithoutStopIsDeallocated() async throws {
        try temp.create()
        weak var weakWatcher: NotesFolderWatcher?
        do {
            let watcher = NotesFolderWatcher(debounce: .milliseconds(20))
            weakWatcher = watcher
            watcher.start(temp.folder) {}
            try await Task.sleep(for: .milliseconds(50))
        }
        await waitFor { weakWatcher == nil }
        #expect(weakWatcher == nil)
    }

    @Test func repeatedArmAndStopLeakNoDescriptor() async throws {
        try temp.create()
        let watcher = NotesFolderWatcher(debounce: .milliseconds(20))
        for _ in 0..<50 {
            watcher.start(temp.folder) {}
            watcher.stop()
        }
        watcher.start(temp.folder) {}
        try temp.writeNote("one", keyID: "k")
        try temp.writeNote("two", keyID: "k")
        await waitFor { watcher.openDescriptors == 1 }
        #expect(watcher.openDescriptors == 1)
        watcher.stop()
        await waitFor { watcher.openDescriptors == 0 }
        #expect(watcher.openDescriptors == 0)
    }

    // MARK: iCloud placeholders

    @Test func datalessPlaceholdersAreDownloadingAndKeepTheLastGoodValue() async throws {
        let store = await started()
        let note = try await store.create(body: "synced")
        try temp.create()
        try Data().write(to: temp.folder.appendingPathComponent(".abc.vnote.icloud"))
        await store.reload()
        #expect(store.downloadingFiles == ["abc.vnote"])

        // The note's file is evicted: its placeholder replaces it; the decrypted note stays.
        let name = Note.fileName(for: note.id)
        try FileManager.default.moveItem(
            at: temp.folder.appendingPathComponent(name),
            to: temp.folder.appendingPathComponent(".\(name).icloud"))
        await store.reload()
        #expect(store.downloadingFiles == ["abc.vnote", name])
        #expect(store.notes == [note])
        #expect(store.canWrite)
    }

    // MARK: Conflicts

    func versionFile(_ note: Note, key: SyncedKey? = nil) throws -> ConflictVersion {
        let dir = temp.root.appendingPathComponent("versions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(UUID().uuidString)
        try NoteFile.seal(note, key: key ?? self.key).write(to: url)
        return ConflictVersion(id: url.path, url: url)
    }

    @Test func conflictVersionsBecomeConflictNotesAndAreResolved() async throws {
        let first = await started()
        let current = try await first.create(body: "Groceries\ncurrent text")
        first.stop()
        let name = Note.fileName(for: current.id)
        let v1 = try versionFile(Note(id: current.id, body: "Groceries\nversion one", created: .now, modified: .now))
        let v2 = try versionFile(Note(id: current.id, body: "Shopping\nversion two", created: .now, modified: .now))
        conflicts.add(v1, for: name)
        conflicts.add(v2, for: name)

        let later = Self.fixedDate.addingTimeInterval(120)
        let store = makeStore(now: later)
        await store.start()
        #expect(store.notes.count == 3)
        #expect(store.note(current.id) == current)
        let copies = store.notes.filter { $0.id != current.id }
        #expect(Set(copies.map(\.title)) == ["Groceries (conflict)", "Shopping (conflict)"])
        #expect(Set(copies.map(\.body)) == ["Groceries\nversion one", "Shopping\nversion two"])
        #expect(copies.allSatisfy { $0.created == later })
        #expect(Set(conflicts.resolved) == [v1.id, v2.id])
        #expect(store.unresolvedConflictFiles.isEmpty)
        #expect(files().count == 3)

        await store.reload()
        #expect(store.notes.count == 3)
        #expect(await started().notes.count == 3)
        expectNoTextInLogs(["current text", "version one", "version two", "Groceries", "Shopping"])
    }

    @Test func aFailedConflictCopyLeavesTheVersionUnresolvedUntilItWorks() async throws {
        let first = await started()
        let current = try await first.create(body: "current")
        first.stop()
        let name = Note.fileName(for: current.id)
        let version = try versionFile(Note(id: current.id, body: "other", created: .now, modified: .now))
        conflicts.add(version, for: name)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: temp.folder.path)
        let store = await started()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.folder.path)
        #expect(conflicts.resolved.isEmpty)
        #expect(store.unresolvedConflictFiles == [name])
        #expect(store.notes == [current])

        await store.reload()
        #expect(conflicts.resolved == [version.id])
        #expect(store.unresolvedConflictFiles.isEmpty)
        #expect(store.notes.count == 2)
    }

    @Test func aConflictVersionWithAnUnknownKeyIsLeftUnresolved() async throws {
        let first = await started()
        let current = try await first.create(body: "current")
        first.stop()
        let name = Note.fileName(for: current.id)
        let version = try versionFile(
            Note(id: current.id, body: "x", created: .now, modified: .now), key: SyncedKey.random())
        conflicts.add(version, for: name)
        let store = await started()
        #expect(conflicts.resolved.isEmpty)
        #expect(store.unresolvedConflictFiles == [name])
        #expect(store.notes == [current])
    }

    @Test func conflictCopyIDsAreStablePerVersion() {
        let a = NoteStore.conflictID(name: "x.vnote", version: "/v/1")
        #expect(a == NoteStore.conflictID(name: "x.vnote", version: "/v/1"))
        #expect(a != NoteStore.conflictID(name: "x.vnote", version: "/v/2"))
    }

    // MARK: Privacy

    @Test func descriptionsNeverShowTitleOrBody() {
        let note = Note(body: "Bank\npassword hunter2", created: .now, modified: .now)
        for text in [String(describing: note), String(reflecting: note), "\(note)", dumped(note)] {
            #expect(!text.contains("hunter2") && !text.contains("Bank"), "\(text)")
            #expect(text.contains(note.id.uuidString.lowercased()) || text.contains(note.id.uuidString))
        }
    }

    func dumped(_ note: Note) -> String {
        var text = ""
        dump(note, to: &text)
        return text
    }

    @Test func conflictTitleComesFromTheCatalog() {
        #expect(NoteStore.conflictTitle("Groceries") == "Groceries (conflict)")
        #expect(NoteStore.conflictTitle("") == "Untitled (conflict)")
        #expect(String(localized: NotesText.noteCount(1)) == "1 NOTE")
        #expect(String(localized: NotesText.noteCount(3)) == "3 NOTES")
        #expect(String(localized: NotesText.lockedCount(2)) == "2 LOCKED")
        #expect(String(localized: NotesText.downloadingCount(2)) == "2 DOWNLOADING")
        #expect(String(localized: NotesText.folderCount(1)) == "1 note in this folder.")
        #expect(String(localized: NotesText.folderCount(4)) == "4 notes in this folder.")
    }
}
