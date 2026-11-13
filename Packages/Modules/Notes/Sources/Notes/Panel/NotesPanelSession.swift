import Foundation
import Observation

/// One opening of the floating notes panel (Story 15.3): the note being written and its autosave.
///
/// - **Which note.** "Jot a note": a new, empty note, unless the most recently created note was created less than
///   ``reuseWindow`` (2 min) ago and is still empty, which is reused instead of piling up empty notes.
/// - **An empty note is never written.** The note file is created on the first save whose body has text; a blank
///   draft never creates one. A note that is blank when the panel closes (a reused empty note, or one the user
///   cleared) is deleted (Trash).
/// - **Autosave.** Each edit restarts a ``saveDelay`` (500 ms) debounce; Esc and close save at once. Saves run one
///   after the other, so a create is never doubled.
/// - Nothing is written while the store cannot write (`canWrite == false`): the panel is then read-only.
@MainActor @Observable
public final class NotesPanelSession {
    /// The autosave debounce.
    public nonisolated static let saveDelay: Duration = .milliseconds(500)
    /// How recent an empty note must be to be reused.
    public nonisolated static let reuseWindow: TimeInterval = 120

    /// The note written so far; nil until the first save with text (or the reused empty note).
    public private(set) var noteID: UUID?
    /// The editor text (Markdown source). Each change schedules a save.
    public var draft: String {
        didSet {
            guard draft != oldValue, !isClosed else { return }
            scheduleSave()
        }
    }
    /// When the note was last written (the footer's `EDITED HH:MM`); nil before the first save of a new note.
    public private(set) var lastEdited: Date?
    /// True when the notes folder is in iCloud Drive (checked once, when the panel opens): the header then reads
    /// `SYNCED · ENCRYPTED · ESC`.
    public let isSynced: Bool
    public private(set) var isClosed = false
    /// True when the reused note was found at open (tests).
    public let reusedNote: Bool

    @ObservationIgnored private weak var store: NoteStore?
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var lastSave: Task<Void, Never>?

    /// - Parameters:
    ///   - store: the module's store (nil: nothing is written).
    ///   - now: the open time, for the reuse rule.
    ///   - sleep: the debounce wait (tests drive it).
    public init(
        store: NoteStore?, now: Date, isSynced: Bool,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.store = store
        self.isSynced = isSynced
        self.sleep = sleep
        if let store, let note = Self.reusableNote(in: store.notes, now: now) {
            noteID = note.id
            draft = note.body
            lastEdited = note.modified
            reusedNote = true
        } else {
            draft = ""
            reusedNote = false
        }
    }

    /// The title derived live from the draft (first non-empty line); empty for a blank draft.
    public var title: String { Note.title(of: draft) }

    /// False while the store refuses writes (or there is none): the editor is read-only.
    public var canWrite: Bool { store?.canWrite ?? false }

    /// The most recently created note when it is blank and was created less than ``reuseWindow`` before `now`.
    static func reusableNote(in notes: [Note], now: Date) -> Note? {
        guard let latest = notes.max(by: { $0.created < $1.created }) else { return nil }
        let age = now.timeIntervalSince(latest.created)
        guard age >= 0, age < reuseWindow, isBlank(latest.body) else { return nil }
        return latest
    }

    static func isBlank(_ body: String) -> Bool {
        body.allSatisfy(\.isWhitespace)
    }

    // MARK: Saving

    private func scheduleSave() {
        debounce?.cancel()
        let sleep = sleep
        debounce = Task { @MainActor [weak self] in
            do {
                try await sleep(Self.saveDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// Saves now (Esc), after any save already running.
    public func save() async {
        debounce?.cancel()
        debounce = nil
        let previous = lastSave
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.write()
        }
        lastSave = task
        await task.value
    }

    /// The panel closed: saves the draft, then deletes the note if it is blank. Later edits are ignored.
    public func close() async {
        isClosed = true
        await save()
        guard let noteID, Self.isBlank(draft), let store, store.canWrite, store.note(noteID) != nil else { return }
        try? await store.delete(noteID)
        self.noteID = nil
    }

    private func write() async {
        guard let store, store.canWrite else { return }
        let body = draft
        if let noteID {
            // Deleted elsewhere meanwhile: nothing to update.
            guard store.note(noteID) != nil else { return }
            if let note = try? await store.update(noteID, body: body), note.body == body {
                lastEdited = note.modified
            }
        } else {
            guard !Self.isBlank(body) else { return }
            if let note = try? await store.create(body: body) {
                noteID = note.id
                lastEdited = note.modified
            }
        }
    }
}
