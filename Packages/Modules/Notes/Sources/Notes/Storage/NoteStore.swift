import CryptoKit
import Foundation
import ModuleKit
import Observation

/// Why ``NoteStore`` writes nothing.
public enum NoteWriteBlock: Hashable, Sendable {
    /// The folder has not been read yet.
    case notLoaded
    /// The folder carries `key_id`s this Vigie does not hold (AD-10): no file is touched.
    case foreignKey(keyIDs: Set<String>)
    /// The store was stopped (key locked, folder changed, module stopped).
    case stopped
}

/// Why a ``NoteStore`` call failed. Never carries note text.
public enum NoteStoreError: Error, Hashable, Sendable {
    case cannotWrite(NoteWriteBlock)
    case notFound
    /// The file could not be written, moved or encrypted.
    case ioFailed
}

/// The notes of one folder, decrypted in memory (Story 15.2, AD-10, AD-12). Owned by ``NotesModule`` while the key
/// state is `ready`.
///
/// - One file per note, `<id>.vnote` (``NoteFile``), written atomically through ``NoteFileIO`` off the main actor.
/// - The folder is watched (``NotesFolderWatching``); a change re-reads only files whose modification date or size
///   changed, and skips files whose bytes are the ones this store just wrote.
/// - A file with a `key_id` this Vigie does not hold is counted as locked, never decrypted, and blocks every
///   write (``canWrite``) until the module re-checks the key.
/// - iCloud files not downloaded yet are listed in ``downloadingFiles``; the last decrypted value stays meanwhile.
/// - Sync conflicts: each unresolved `NSFileVersion` of a note becomes a new note `<title> (conflict)`; only then
///   is the version marked resolved. The current version stays in place.
///
/// Logs carry file names, ids and counts only, never titles or bodies.
@MainActor @Observable
public final class NoteStore {
    public let folder: URL
    public let keyID: String

    /// Readable notes, most recently modified first.
    public private(set) var notes: [Note] = []
    /// Note files encrypted with a key this Vigie does not hold (never decrypted).
    public private(set) var lockedFiles: Set<String> = []
    /// The foreign `key_id`s seen (note headers and the key marker).
    public private(set) var foreignKeyIDs: Set<String> = []
    /// Note files iCloud has not downloaded yet.
    public private(set) var downloadingFiles: Set<String> = []
    /// Note files with our key that do not open (tampered, truncated, unknown format).
    public private(set) var unreadableFiles: Set<String> = []
    /// Note files with conflict versions left unresolved (unknown key, unreadable, or the copy failed).
    public private(set) var unresolvedConflictFiles: Set<String> = []
    public private(set) var isLoaded = false
    private var isStopped = false

    /// Nil when notes can be written.
    public var writeBlock: NoteWriteBlock? {
        if isStopped { return .stopped }
        if !isLoaded { return .notLoaded }
        if !foreignKeyIDs.isEmpty { return .foreignKey(keyIDs: foreignKeyIDs) }
        return nil
    }

    public var canWrite: Bool { writeBlock == nil }

    @ObservationIgnored private let key: SyncedKey
    @ObservationIgnored private let io: NoteFileIO
    @ObservationIgnored private let watcher: (any NotesFolderWatching)?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let log: @MainActor (String) -> Void
    /// Called when a foreign `key_id` first appears (the module re-checks the key state).
    @ObservationIgnored var onForeignKey: (@MainActor () -> Void)?

    private struct CachedFile {
        enum Content {
            case note(Note)
            case locked(keyID: String)
            case unreadable
        }

        var stamp: NoteFileStamp
        var content: Content
    }

    @ObservationIgnored private var cache: [String: CachedFile] = [:]
    @ObservationIgnored private var fileNames: [UUID: String] = [:]
    @ObservationIgnored private var reloading = false
    @ObservationIgnored private var reloadAgain = false
    @ObservationIgnored private var writtenDuringReload: Set<String> = []
    /// Files decrypted successfully so far (tests check that own writes are not re-read).
    @ObservationIgnored private(set) var decryptCount = 0

    public init(
        folder: URL, key: SyncedKey, io: NoteFileIO = NoteFileIO(),
        watcher: (any NotesFolderWatching)? = NotesFolderWatcher(),
        now: @escaping @Sendable () -> Date = { Date() },
        log: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.folder = folder.standardizedFileURL
        self.key = key
        self.keyID = key.keyID
        self.io = io
        self.watcher = watcher
        self.now = now
        self.log = log
    }

    // MARK: Lifecycle

    /// Loads the folder and starts watching it.
    public func start() async {
        watcher?.start(folder) { [weak self] in
            Task { await self?.reload() }
        }
        await load()
    }

    /// Stops watching; nothing is written after this.
    public func stop() {
        isStopped = true
        watcher?.stop()
    }

    /// Reads every file again.
    public func load() async {
        cache = [:]
        await reload()
    }

    /// Re-reads the files whose stamp changed since the last read, then handles sync conflicts.
    public func reload() async {
        guard !isStopped else { return }
        if reloading {
            reloadAgain = true
            return
        }
        reloading = true
        defer { reloading = false }
        repeat {
            reloadAgain = false
            await reloadOnce()
        } while reloadAgain && !isStopped
    }

    // MARK: Reading

    /// The note with `id`.
    public func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    private func reloadOnce() async {
        writtenDuringReload = []
        let (entries, markerKeyID) = await io.list(folder)
        guard !isStopped else { return }
        var seen: Set<String> = []
        var downloading: Set<String> = []
        for entry in entries {
            seen.insert(entry.name)
            switch entry.kind {
            case .downloading:
                downloading.insert(entry.name)
            case .file(let stamp):
                if let cached = cache[entry.name], cached.stamp.modified == stamp.modified,
                    cached.stamp.size == stamp.size
                {
                    continue
                }
                let url = folder.appendingPathComponent(entry.name)
                guard let data = try? await io.read(url), !isStopped else { continue }
                guard !writtenDuringReload.contains(entry.name) else { continue }
                var fresh = stamp
                fresh.digest = NoteFileIO.digest(data)
                if let cached = cache[entry.name], cached.stamp.digest == fresh.digest {
                    cache[entry.name]?.stamp = fresh
                    continue
                }
                cache[entry.name] = CachedFile(stamp: fresh, content: open(data, name: entry.name))
            }
        }
        for name in cache.keys where !seen.contains(name) && !writtenDuringReload.contains(name) {
            cache[name] = nil
        }
        downloadingFiles = downloading
        var foreign = Set(cache.values.compactMap { if case .locked(let id) = $0.content { id } else { nil } })
        if let markerKeyID, markerKeyID != keyID { foreign.insert(markerKeyID) }
        let wasBlocked = !foreignKeyIDs.isEmpty
        foreignKeyIDs = foreign
        isLoaded = true
        rebuild()
        log(
            "Notes folder read: \(notes.count) notes, \(lockedFiles.count) locked, \(downloadingFiles.count) downloading, \(unreadableFiles.count) unreadable"
        )
        if !foreign.isEmpty {
            if !wasBlocked {
                log("Notes writes stopped: foreign key_id \(foreign.sorted().joined(separator: ","))")
            }
            onForeignKey?()
            return
        }
        await resolveConflicts()
    }

    private func open(_ data: Data, name: String) -> CachedFile.Content {
        do {
            let note = try NoteFile.open(data, key: key)
            decryptCount += 1
            return .note(note)
        } catch .unknownKey(let keyID) {
            return .locked(keyID: keyID)
        } catch {
            log("Note file \(name) not opened: \(error)")
            return .unreadable
        }
    }

    private func rebuild() {
        var byID: [UUID: (name: String, note: Note)] = [:]
        var locked: Set<String> = []
        var unreadable: Set<String> = []
        for (name, file) in cache {
            switch file.content {
            case .note(let note):
                if let other = byID[note.id], other.note.modified >= note.modified { continue }
                byID[note.id] = (name, note)
            case .locked: locked.insert(name)
            case .unreadable: unreadable.insert(name)
            }
        }
        fileNames = byID.mapValues(\.name)
        notes = byID.values.map(\.note).sorted {
            $0.modified != $1.modified ? $0.modified > $1.modified : $0.id.uuidString < $1.id.uuidString
        }
        lockedFiles = locked
        unreadableFiles = unreadable
    }

    // MARK: Writing

    /// Creates a note from `body` (title = its first line) and writes it.
    @discardableResult
    public func create(body: String) async throws(NoteStoreError) -> Note {
        if let writeBlock { throw .cannotWrite(writeBlock) }
        let date = now()
        let note = Note(body: body, created: date, modified: date)
        try await write(note)
        return note
    }

    /// Replaces the body of note `id`; the title follows its first line, `modified` becomes now. The file name
    /// stays `<id>.vnote`. An unchanged body writes nothing.
    @discardableResult
    public func update(_ id: UUID, body: String) async throws(NoteStoreError) -> Note {
        if let writeBlock { throw .cannotWrite(writeBlock) }
        guard var note = note(id) else { throw .notFound }
        guard note.body != body else { return note }
        note.body = body
        note.title = Note.title(of: body)
        note.modified = now()
        try await write(note)
        return note
    }

    /// Moves the note's file to the Trash (recoverable from Finder).
    public func delete(_ id: UUID) async throws(NoteStoreError) {
        if let writeBlock { throw .cannotWrite(writeBlock) }
        guard let name = fileNames[id] else { throw .notFound }
        do {
            try await io.delete(folder.appendingPathComponent(name))
        } catch {
            log("Note \(id.uuidString.lowercased()) not deleted: \(String(describing: type(of: error)))")
            throw .ioFailed
        }
        cache[name] = nil
        writtenDuringReload.insert(name)
        rebuild()
        log("Note \(id.uuidString.lowercased()) moved to the Trash")
    }

    private func write(_ note: Note) async throws(NoteStoreError) {
        let name = fileNames[note.id] ?? Note.fileName(for: note.id)
        let stamp: NoteFileStamp
        do {
            let data = try NoteFile.seal(note, key: key)
            stamp = try await io.write(data, to: folder.appendingPathComponent(name))
        } catch {
            log("Note \(note.id.uuidString.lowercased()) not written: \(String(describing: type(of: error)))")
            throw .ioFailed
        }
        cache[name] = CachedFile(stamp: stamp, content: .note(note))
        writtenDuringReload.insert(name)
        rebuild()
        log("Note \(note.id.uuidString.lowercased()) written")
    }

    // MARK: Conflicts

    /// For every readable note with unresolved conflict versions: saves each version as a new note
    /// `<title> (conflict)`, then marks it resolved. A version that cannot be opened or copied stays unresolved
    /// (retried on the next change). The copy's id derives from the version, so a retry never duplicates it.
    private func resolveConflicts() async {
        var unresolved: Set<String> = []
        let names = cache.compactMap { name, file -> String? in
            if case .note = file.content { name } else { nil }
        }
        for name in names.sorted() {
            guard canWrite else { return }
            let url = folder.appendingPathComponent(name)
            for version in await io.unresolvedConflicts(of: url) {
                guard canWrite else { return }
                if await !saveConflict(version, of: name) { unresolved.insert(name) }
            }
        }
        unresolvedConflictFiles = unresolved
    }

    private func saveConflict(_ version: ConflictVersion, of name: String) async -> Bool {
        let url = folder.appendingPathComponent(name)
        let versionNote: Note
        do {
            versionNote = try NoteFile.open(try await io.read(version, of: url), key: key)
        } catch {
            log("Conflict version of \(name) left unresolved: \(error)")
            return false
        }
        let id = Self.conflictID(name: name, version: version.id)
        let copyName = Note.fileName(for: id)
        if cache[copyName] == nil, await !io.exists(folder.appendingPathComponent(copyName)) {
            let date = now()
            let copy = Note(
                id: id, title: Self.conflictTitle(versionNote.title), body: versionNote.body, created: date,
                modified: date)
            do {
                try await write(copy)
            } catch {
                log("Conflict copy of \(name) not written; version left unresolved")
                return false
            }
        }
        do {
            try await io.resolve(version, of: url)
        } catch {
            log("Conflict version of \(name) not marked resolved: \(String(describing: type(of: error)))")
            return false
        }
        log("Conflict version of \(name) saved as note \(id.uuidString.lowercased()) and resolved")
        return true
    }

    /// `<title> (conflict)` (catalog format), `Untitled (conflict)` for an empty title.
    static func conflictTitle(_ title: String) -> String {
        NotesText.format("notes.conflict.title", title.isEmpty ? NotesText.string("notes.untitled") : title)
    }

    /// A UUID derived from the note file and the version (the first 16 bytes of SHA-256, version 5 bits set).
    static func conflictID(name: String, version: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("\(name)\n\(version)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
                bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}
