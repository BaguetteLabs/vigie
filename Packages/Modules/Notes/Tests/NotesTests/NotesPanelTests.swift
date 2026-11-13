import AppKit
import Foundation
@_spi(Host) import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import Notes

/// The debounce wait under test control: each `sleep` waits until ``release()``.
final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var pending: Int { lock.withLock { waiters.count } }

    func sleep(_ duration: Duration) async throws {
        await withCheckedContinuation { continuation in lock.withLock { waiters.append(continuation) } }
    }

    func release() {
        let waiters = lock.withLock {
            let all = self.waiters
            self.waiters = []
            return all
        }
        for waiter in waiters { waiter.resume() }
    }
}

/// Story 15.3: the floating notes panel.
@MainActor @Suite struct NotesPanelTests {
    let temp = TempNotes()
    let key = SyncedKey.random()
    let sleeper = ManualSleeper()
    let opened = Date(timeIntervalSince1970: 1_800_000_000)

    func waitFor(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func start(
        ready: Bool = true, settings: [String: any SettingValue] = [:], ubiquitous: Bool = false
    ) async throws -> (NotesModule, FakeModuleContext) {
        try temp.create()
        let storage = FakeStorage()
        storage.folder = temp.folder
        let context = FakeModuleContext(
            settings: settings, storage: storage, notesKey: ready ? FakeSyncedKeyStore(key: key) : FakeSyncedKeyStore())
        let sleeper = sleeper
        let opened = opened
        let module = NotesModule(
            makeStore: { folder, key, _ in
                NoteStore(
                    folder: folder, key: key, io: NoteFileIO(deletion: .remove), watcher: nil, now: { opened })
            },
            isUbiquitous: { _ in ubiquitous },
            now: { opened },
            panelSleep: { try await sleeper.sleep($0) })
        try await module.start(context: context)
        return (module, context)
    }

    func intent() -> UserIntent { UserIntent(issuedAt: Date()) }

    // MARK: Hotkey

    @Test func theHotkeyIsNotesOpenWithTheSettingAsItsShortcut() async throws {
        let (module, context) = try await start(ready: false)
        #expect(context.fakeHotkeys.names == ["open"])
        #expect(context.fakeHotkeys.defaults == ["opt+cmd+n"])
        #expect(NotesModule.staticManifest.settings.first?.kind == .hotkey(default: "opt+cmd+n"))
        try await context.fakeSettings.set("ctrl+cmd+j", for: "hotkey")
        await waitFor { context.fakeHotkeys.names.count == 2 }
        #expect(context.fakeHotkeys.defaults.last == "ctrl+cmd+j")
        #expect(context.fakeHotkeys.cancelled == ["open"])
        try await context.fakeSettings.set("none", for: "hotkey")
        await waitFor { context.fakeHotkeys.names.count == 3 }
        #expect(context.fakeHotkeys.defaults.last == .some(nil))
        await module.stop()
        #expect(context.fakeHotkeys.cancelled.count == 3)
    }

    @Test func pressOpensThePanelWithTheIntentAndPressAgainClosesIt() async throws {
        let (module, context) = try await start()
        let host = context.fakeHost
        let press = intent()
        context.fakeHotkeys.press("open", intent: press)
        #expect(host.panelRequests.count == 1)
        #expect(host.panelRequests.first?.focus == press)
        #expect(host.panel?.id == "notes.panel")
        #expect(host.panel?.size == nil)  // the theme's components.notes-panel size
        #expect(module.isPanelOpen)
        #expect(module.panelSession != nil)
        context.fakeHotkeys.press("open", intent: intent())
        #expect(host.dismissCount == 1)
        #expect(host.panel == nil)
        #expect(!module.isPanelOpen)
        #expect(module.panelSession == nil)
        await module.stop()
    }

    @Test func aRefusedPanelLeavesNothingOpen() async throws {
        let (module, context) = try await start()
        context.fakeHost.refusesPanels = true
        module.togglePanel(focus: intent())
        #expect(!module.isPanelOpen)
        #expect(module.panelSession == nil)
        await module.stop()
    }

    @Test func escSavesTheNoteAndCloses() async throws {
        let (module, context) = try await start()
        module.togglePanel(focus: intent())
        let session = try #require(module.panelSession)
        session.draft = "Staging DB\nhost staging-db.internal"
        context.fakeHost.pressEscape()
        #expect(!module.isPanelOpen)
        await module.panelClose?.value
        let store = try #require(module.store)
        #expect(store.notes.count == 1)
        #expect(store.notes.first?.body == "Staging DB\nhost staging-db.internal")
        #expect(store.notes.first?.title == "Staging DB")
        await module.stop()
    }

    @Test func anEmptyNoteIsNeverWritten() async throws {
        let (module, context) = try await start()
        module.togglePanel(focus: intent())
        let session = try #require(module.panelSession)
        session.draft = "   \n"
        sleeper.release()
        await session.save()
        #expect(module.store?.notes.isEmpty == true)
        context.fakeHost.pressEscape()
        await module.panelClose?.value
        #expect(module.store?.notes.isEmpty == true)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: temp.folder.path).allSatisfy { !$0.hasSuffix(".vnote") }
        )
        await module.stop()
    }

    @Test func aClearedNoteIsDeletedOnClose() async throws {
        let (module, context) = try await start()
        module.togglePanel(focus: intent())
        let session = try #require(module.panelSession)
        session.draft = "x"
        await session.save()
        #expect(module.store?.notes.count == 1)
        session.draft = ""
        context.fakeHost.dismissFloatingPanel()
        await module.panelClose?.value
        #expect(module.store?.notes.isEmpty == true)
        await module.stop()
    }

    // MARK: Which note

    @Test func aRecentEmptyNoteIsReusedAndDeletedWhenStillEmpty() async throws {
        let (module, context) = try await start()
        let store = try #require(module.store)
        let empty = try await store.create(body: "")
        module.togglePanel(focus: intent())
        let session = try #require(module.panelSession)
        #expect(session.reusedNote)
        #expect(session.noteID == empty.id)
        context.fakeHost.pressEscape()
        await module.panelClose?.value
        #expect(store.notes.isEmpty)
        await module.stop()
    }

    @Test func theReuseRule() {
        let now = opened
        let empty = Note(body: "", created: now.addingTimeInterval(-60), modified: now.addingTimeInterval(-60))
        let old = Note(body: " ", created: now.addingTimeInterval(-121), modified: now)
        let full = Note(body: "text", created: now.addingTimeInterval(-10), modified: now)
        #expect(NotesPanelSession.reusableNote(in: [empty], now: now) == empty)
        #expect(NotesPanelSession.reusableNote(in: [old], now: now) == nil)
        // Only the most recently created note counts: a newer note with text means a new note.
        #expect(NotesPanelSession.reusableNote(in: [empty, full], now: now) == nil)
        #expect(NotesPanelSession.reusableNote(in: [], now: now) == nil)
    }

    @Test func aRecentNoteWithTextGivesANewNote() async throws {
        let (module, _) = try await start()
        try await module.store?.create(body: "keep me")
        module.togglePanel(focus: intent())
        let session = try #require(module.panelSession)
        #expect(session.noteID == nil)
        #expect(session.draft.isEmpty)
        await module.stop()
        #expect(module.store == nil)
    }

    // MARK: Autosave

    @Test func autosaveWaitsForTheDebounceAndWritesTheLastDraftOnce() async throws {
        let (module, _) = try await start()
        module.togglePanel(focus: intent())
        let session = try #require(module.panelSession)
        let store = try #require(module.store)
        session.draft = "a"
        session.draft = "ab"
        session.draft = "abc"
        await waitFor { sleeper.pending == 3 }
        try await Task.sleep(for: .milliseconds(20))
        #expect(store.notes.isEmpty)
        #expect(NotesPanelSession.saveDelay == .milliseconds(500))
        sleeper.release()
        await waitFor { !store.notes.isEmpty }
        #expect(store.notes.map(\.body) == ["abc"])
        #expect(session.lastEdited == opened)
        session.draft = "abcd"
        await waitFor { sleeper.pending == 1 }
        sleeper.release()
        await waitFor { store.notes.first?.body == "abcd" }
        #expect(store.notes.count == 1)
        await module.stop()
    }

    @Test func theTitleFollowsTheFirstLineLive() async throws {
        let session = NotesPanelSession(store: nil, now: opened, isSynced: false, sleep: { _ in })
        #expect(session.title.isEmpty)
        #expect(NotesPanelText.header(title: session.title) == "NOTES · UNTITLED")
        session.draft = "# Staging DB\nhost"
        #expect(session.title == "Staging DB")
        #expect(NotesPanelText.header(title: session.title) == "NOTES · STAGING DB")
        session.draft = "\n  Wi-Fi\n"
        #expect(session.title == "Wi-Fi")
    }

    // MARK: Copy

    @Test func headerMetaAndFooterStrings() throws {
        #expect(String(localized: NotesPanelText.meta(synced: true)) == "SYNCED · ENCRYPTED · ESC")
        #expect(String(localized: NotesPanelText.meta(synced: false)) == "ENCRYPTED · ESC")
        var calendar = Calendar(identifier: .gregorian)
        let utc = try #require(TimeZone(identifier: "UTC"))
        calendar.timeZone = utc
        let date = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 14, minute: 31)))
        #expect(NotesPanelText.edited(date, locale: Locale(identifier: "en_GB"), timeZone: utc) == "EDITED 14:31")
        for key in [
            "notes.panel.kicker", "notes.panel.separator", "notes.panel.header", "notes.panel.meta",
            "notes.panel.meta.synced", "notes.panel.edited", "notes.panel.editor",
        ] {
            #expect(NotesText.string(key) != key, "missing catalog entry \(key)")
        }
    }

    @Test func syncedFollowsTheFolderUbiquity() async throws {
        let (module, _) = try await start(ubiquitous: true)
        module.togglePanel(focus: intent())
        #expect(module.panelSession?.isSynced == true)
        await module.stop()
        let (other, _) = try await start(ubiquitous: false)
        other.togglePanel(focus: intent())
        #expect(other.panelSession?.isSynced == false)
        await other.stop()
    }

    // MARK: States

    @Test func withoutAReadyKeyThePanelOpensOnTheTabState() async throws {
        let (module, context) = try await start(ready: false)
        #expect(module.tabContent == .setup)
        module.togglePanel(focus: intent())
        #expect(module.isPanelOpen)
        #expect(module.panelSession == nil)
        let panel = try #require(context.fakeHost.panel)
        _ = panel.content()  // NotesPanelView falls back to NotesTabView's setup card
        await module.stop()
    }

    @Test func aStoreThatCannotWriteIsReadOnly() async throws {
        try temp.create()
        let store = NoteStore(folder: temp.folder, key: key, io: NoteFileIO(deletion: .remove), watcher: nil)
        // Never loaded: `notLoaded` blocks writes.
        #expect(!store.canWrite)
        let session = NotesPanelSession(store: store, now: opened, isSynced: false, sleep: { _ in })
        #expect(!session.canWrite)
        session.draft = "text"
        await session.save()
        await session.close()
        #expect(store.notes.isEmpty)
        #expect(session.noteID == nil)
    }

    // MARK: Privacy

    @Test func privacyDotsRenderAndTypingStillEdits() async throws {
        let session = NotesPanelSession(store: nil, now: opened, isSynced: false, sleep: { _ in })
        session.draft = "Staging DB\n\npassword k7#Qe9"
        let masked = PrivacyLineMask.masked(session.draft)
        #expect(masked == "\(PrivacyMask.text)\n\n\(PrivacyMask.text)")
        #expect(!masked.contains("Staging"))
        let theme = try ThemeLoader.loadBundled().resolve(themeID: "chrome-hologram", look: .dark).theme
        let view = PrivacyLineDots(text: session.draft)
            .privacyActive(true)
            .vigieTheme(theme)
            .frame(width: 460, height: 120)
        let renderer = ImageRenderer(content: view)
        #expect(renderer.nsImage != nil)
        // The binding the editor writes to still edits the note while masked.
        session.draft += "\nmore"
        #expect(session.title == "Staging DB")
        #expect(session.draft.hasSuffix("more"))
    }
}
