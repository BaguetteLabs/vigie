import Foundation
import ModuleKit
import Observation
import SwiftUI
import VigieUI
import os

/// Where the notes key stands (Story 15.1, AD-10).
public enum NotesKeyState: Hashable, Sendable {
    /// Before the first check.
    case checking
    /// The notes key store cannot be used in this build (`KEYCHAIN UNAVAILABLE IN THIS BUILD`). A recovery key
    /// can still be entered: it is then held in memory for the session (``ready(keyID:)`` with
    /// ``NotesModule/keyIsSessionOnly``).
    case unavailable(SyncedKeyUnavailableReason)
    /// No key anywhere and the folder shows none: `Set up notes`.
    case noKey
    /// No key held, but the folder holds note files or a key marker (`key_id`s, empty when none could be read
    /// yet): the key exists on another Mac. `NOTES LOCKED`, waiting for iCloud Keychain or a recovery key.
    case waiting(keyIDs: Set<String>)
    /// A key is held but the folder carries other `key_id`s: shown as the waiting state; nothing is written.
    case mismatch(keyIDs: Set<String>)
    /// The key is held; notes can be read and written (Story 15.2).
    case ready(keyID: String)

    /// The locked surfaces (`NOTES LOCKED` + recovery entry).
    public var isLocked: Bool {
        switch self {
        case .waiting, .mismatch: true
        default: false
        }
    }
}

/// What `Set up notes` did.
public enum NotesSetupOutcome: Hashable, Sendable {
    /// A new key was created; the recovery key is in ``NotesModule/pendingRecoveryKey``.
    case created
    /// A key already stored (synced from another Mac) was adopted; no new key.
    case adopted
    /// The folder shows an existing key, or the state is not `noKey`: nothing created (AD-10).
    case refused
    /// The store failed.
    case failed
}

/// Why an entered recovery key was refused.
public enum RecoveryEntryError: Hashable, Sendable {
    /// Malformed or a typo (length, character or checksum).
    case invalid
    /// A valid recovery key whose `key_id` does not match the notes folder.
    case wrongKey
    /// The key could not be stored in the Keychain.
    case keychain

    var message: LocalizedStringResource {
        switch self {
        case .invalid: NotesText.resource("notes.recovery.error.invalid")
        case .wrongKey: NotesText.resource("notes.recovery.error.wrongKey")
        case .keychain: NotesText.resource("notes.recovery.error.keychain")
        }
    }
}

/// `notes` (SPEC §7.6, Epic 15). Story 15.1: the notes key (setup, waiting, recovery) and its surfaces.
///
/// Off by default. No closed-notch presence: the state is always `hidden`. The key comes from `context.notesKey`
/// (AD-9); the folder from `context.storage.userFolder(setting: "folder")` (AD-11), or, when this build is a dev
/// build that cannot read the release key, a sibling folder named after the build (`~/Notes/Vigie Dev`) while
/// `folder` keeps its default. The folder is read for note headers and the key marker only, never contents
/// (``NotesFolder``). Nothing here logs a key or note text.
///
/// AD-10: a key is created only by ``setUpNotes()`` (an explicit user action), never while the folder shows a key
/// (note files or the marker), and never when the store already holds one (it is adopted).
@MainActor @Observable
public final class NotesModule: NotchModule {
    nonisolated static let bundle = NotesText.bundle

    /// The Settings pane id (the module id).
    public nonisolated static let settingsPane = "notes"
    /// `[modules.notes] folder` default (SPEC §11).
    public nonisolated static let defaultFolder = "~/Notes/Vigie"
    /// `[modules.notes] hotkey` default (SPEC §11, A30): ⌥⌘N.
    public nonisolated static let defaultHotkey = "opt+cmd+n"
    /// `[modules.notes] clipboard_clear` default (SPEC §11).
    public nonisolated static let defaultClipboardClear: Duration = .seconds(30)

    public nonisolated static let staticManifest = ModuleManifest(
        id: "notes",
        name: LocalizedStringResource("notes.module.name", bundle: bundle),
        icon: "note.text",
        settings: [
            SettingDescriptor(
                key: "hotkey",
                label: LocalizedStringResource("notes.setting.hotkey", bundle: bundle),
                kind: .hotkey(default: defaultHotkey),
                help: LocalizedStringResource("notes.setting.hotkey.help", bundle: bundle)),
            SettingDescriptor(
                key: "folder",
                label: LocalizedStringResource("notes.setting.folder", bundle: bundle),
                kind: .path(default: defaultFolder),
                scope: .local,
                help: LocalizedStringResource("notes.setting.folder.help", bundle: bundle)),
            SettingDescriptor(
                key: "clipboard_clear",
                label: LocalizedStringResource("notes.setting.clipboardClear", bundle: bundle),
                kind: .duration(default: defaultClipboardClear),
                help: LocalizedStringResource("notes.setting.clipboardClear.help", bundle: bundle)),
        ],
        defaultEnabled: false
    )

    public let manifest = NotesModule.staticManifest
    public let state: ModuleState = .hidden
    public private(set) var keyState: NotesKeyState = .checking
    /// The recovery key of the key just created, shown once until ``confirmRecoveryKeySaved()``.
    public private(set) var pendingRecoveryKey: String?
    /// The last refused recovery entry.
    public private(set) var recoveryError: RecoveryEntryError?
    /// The last failed setup.
    public private(set) var setupFailed = false
    public private(set) var iCloudKeychain: ICloudKeychainStatus = .unknown
    public private(set) var scope: SyncedKeyScope = .shared
    /// The notes folder in use (nil before the first check or without a folder).
    public private(set) var folder: URL?
    /// True when this dev build uses its own folder instead of the configured one (AD-10).
    public private(set) var usesOwnFolder = false
    /// The key is held in memory only (entered while the store is unavailable).
    public private(set) var keyIsSessionOnly = false
    public private(set) var isRunning = false
    /// The notes of ``folder`` while the key state is ready (Story 15.2); nil otherwise.
    public private(set) var store: NoteStore?
    /// Note files of the folder this Vigie cannot open with the key it holds (locked states), from the last scan.
    public private(set) var scannedLockedNotes = 0

    /// The held key, when ``keyState`` is ready (Story 15.2 encrypts with it). Never logged or shown.
    @ObservationIgnored public private(set) var key: SyncedKey?
    /// A key entered as a recovery key while the store could not keep it.
    @ObservationIgnored private var sessionKey: SyncedKey?
    @ObservationIgnored let openSettings: (@MainActor @Sendable (String) -> Void)?
    @ObservationIgnored var context: (any ModuleContext)?
    @ObservationIgnored var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored let makeStore: (@MainActor (URL, SyncedKey, any ModuleContext) -> NoteStore)?

    // Floating panel (Story 15.3, NotesModule+Panel.swift).
    /// The panel's note while the panel is open and the key is ready.
    public internal(set) var panelSession: NotesPanelSession?
    /// True from a presented panel until its `onClose`.
    public internal(set) var isPanelOpen = false
    @ObservationIgnored var panelHotkey: RegistrationToken?
    @ObservationIgnored var panelClose: Task<Void, Never>?
    @ObservationIgnored let isUbiquitous: @Sendable (URL) -> Bool
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let panelSleep: @Sendable (Duration) async throws -> Void

    /// - Parameters:
    ///   - openSettings: opens a Settings pane by id (the tab's `Open settings`).
    ///   - makeStore: builds the note store for a folder and key (tests inject fakes); nil = ``defaultStore``.
    ///   - isUbiquitous: whether the notes folder is in iCloud Drive (`FileManager.isUbiquitousItem(at:)`).
    ///   - now: the clock of the panel's reuse rule.
    ///   - panelSleep: the panel's autosave wait (tests drive it).
    public init(
        openSettings: (@MainActor @Sendable (String) -> Void)? = nil,
        makeStore: (@MainActor (URL, SyncedKey, any ModuleContext) -> NoteStore)? = nil,
        isUbiquitous: @escaping @Sendable (URL) -> Bool = { FileManager.default.isUbiquitousItem(at: $0) },
        now: @escaping @Sendable () -> Date = { Date() },
        panelSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.openSettings = openSettings
        self.makeStore = makeStore
        self.isUbiquitous = isUbiquitous
        self.now = now
        self.panelSleep = panelSleep
    }

    /// The production store: real file I/O (Trash on delete, `NSFileVersion` conflicts), kqueue watcher, the
    /// module logger (messages carry ids and counts only).
    public static func defaultStore(folder: URL, key: SyncedKey, context: any ModuleContext) -> NoteStore {
        let logger = context.log
        return NoteStore(folder: folder, key: key, log: { logger.info("\($0, privacy: .public)") })
    }

    // MARK: Lifecycle

    public func start(context: any ModuleContext) async throws {
        self.context = context
        isRunning = true
        let keyChanges = context.notesKey.changes()
        tasks.append(
            Task { @MainActor [weak self] in
                for await _ in keyChanges {
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            })
        let folderChanges = context.settings.observe("folder")
        tasks.append(
            Task { @MainActor [weak self] in
                for await _ in folderChanges {
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            })
        startPanelHotkey(context)
        await refresh()
    }

    public func stop() async {
        for task in tasks { task.cancel() }
        tasks = []
        await stopPanel()
        isRunning = false
        generation += 1
        tearDownStore()
        key = nil
        sessionKey = nil
        pendingRecoveryKey = nil
    }

    // MARK: Key state

    /// Reads the store and the folder again and recomputes ``keyState``. Never creates or writes anything.
    public func refresh() async {
        guard isRunning, let store = context?.notesKey else { return }
        generation += 1
        let current = generation
        let availability = await store.availability()
        let scope = await store.scope()
        let iCloud = await store.iCloudKeychainStatus()
        let folder = resolvedFolder(scope: scope)
        let scan = await Self.scan(folder)
        var stored: SyncedKey?
        var storeError: SyncedKeyUnavailableReason?
        if availability == .available {
            do {
                stored = try await store.readKey()
            } catch let error as SyncedKeyError {
                if case .unavailable(let reason) = error { storeError = reason }
            } catch {}
        }
        guard current == generation, isRunning else { return }
        self.scope = scope
        self.iCloudKeychain = iCloud
        self.folder = folder
        usesOwnFolder = folder != nil && folder != context?.storage.userFolder(setting: "folder")
        let held = stored ?? sessionKey
        key = nil
        keyIsSessionOnly = stored == nil && sessionKey != nil
        scannedLockedNotes = scan.noteFiles - (held.flatMap { scan.keyIDCounts[$0.keyID] } ?? 0)
        if let held {
            let foreign = scan.keyIDs.subtracting([held.keyID])
            if foreign.isEmpty {
                key = held
                keyState = .ready(keyID: held.keyID)
            } else {
                keyState = .mismatch(keyIDs: foreign)
            }
        } else if case .unavailable(let reason) = availability {
            keyState = .unavailable(reason)
        } else if let storeError {
            keyState = .unavailable(storeError)
        } else if scan.showsExistingKey {
            keyState = .waiting(keyIDs: scan.keyIDs)
        } else {
            keyState = .noKey
        }
        await syncStore()
    }

    // MARK: Store

    /// Notes readable now (0 without a store).
    public var noteCount: Int { store?.notes.count ?? 0 }

    /// Note files that cannot be opened with the held key: the store's locked files when ready, otherwise the
    /// scan's.
    public var lockedNoteCount: Int {
        if let store { return store.lockedFiles.count }
        return keyState.isLocked ? scannedLockedNotes : 0
    }

    /// Creates the store when the key is ready (or recreates it for a new folder or key); tears it down in every
    /// other state, so nothing is written while the folder carries a key this Vigie does not hold (AD-10).
    private func syncStore() async {
        guard isRunning, case .ready(let keyID) = keyState, let key, let folder, let context else {
            tearDownStore()
            return
        }
        if let store, store.folder == folder.standardizedFileURL, store.keyID == keyID { return }
        tearDownStore()
        let store = makeStore?(folder, key, context) ?? Self.defaultStore(folder: folder, key: key, context: context)
        store.onForeignKey = { [weak self] in
            Task { await self?.refresh() }
        }
        self.store = store
        await store.start()
    }

    private func tearDownStore() {
        store?.stop()
        store = nil
    }

    /// `Set up notes` (explicit user action only). Re-checks first; creates a key only when the store holds none
    /// and the folder shows none (AD-10), then writes the key marker and shows the recovery key once.
    @discardableResult
    public func setUpNotes() async -> NotesSetupOutcome {
        setupFailed = false
        let before = keyState
        await refresh()
        if before == .noKey, case .ready = keyState, let key, !keyIsSessionOnly {
            // The key arrived (iCloud Keychain) since the last check: adopt it, create nothing.
            await writeMarker(key)
            return .adopted
        }
        guard keyState == .noKey, let store = context?.notesKey else { return .refused }
        let created: SyncedKey
        do {
            created = try await store.createKey()
        } catch SyncedKeyError.alreadyExists {
            await refresh()
            if let key { await writeMarker(key) }
            return .adopted
        } catch {
            context?.log.error("Notes key setup failed: \(String(describing: error), privacy: .public)")
            setupFailed = true
            return .failed
        }
        pendingRecoveryKey = RecoveryKey.encode(created)
        await writeMarker(created)
        await refresh()
        return .created
    }

    /// `Enter recovery key`: parses `text`, checks it against the folder's `key_id`s, stores it (or holds it for
    /// the session when the store is unavailable) and unlocks. Returns whether it was accepted; on refusal
    /// ``recoveryError`` says why.
    @discardableResult
    public func enterRecoveryKey(_ text: String) async -> Bool {
        guard isRunning, let store = context?.notesKey else { return false }
        let recovered: SyncedKey
        do {
            recovered = try RecoveryKey.parse(text)
        } catch {
            recoveryError = .invalid
            return false
        }
        let folder = resolvedFolder(scope: await store.scope())
        let scan = await Self.scan(folder)
        guard scan.keyIDs.subtracting([recovered.keyID]).isEmpty else {
            recoveryError = .wrongKey
            return false
        }
        if await store.availability() == .available {
            do {
                try await store.importKey(recovered)
            } catch {
                context?.log.error("Notes key import failed: \(String(describing: error), privacy: .public)")
                recoveryError = .keychain
                return false
            }
            sessionKey = nil
        } else {
            sessionKey = recovered
        }
        recoveryError = nil
        await writeMarker(recovered)
        await refresh()
        return true
    }

    /// Copies the shown recovery key; the clipboard clears after `clipboard_clear` (AD-19).
    public func copyRecoveryKey() {
        guard let pendingRecoveryKey, let context else { return }
        context.clipboard.copy(pendingRecoveryKey, clearAfter: clipboardClear)
    }

    /// `I saved it`: the recovery key is never shown again.
    public func confirmRecoveryKeySaved() {
        pendingRecoveryKey = nil
    }

    public func clearRecoveryError() {
        recoveryError = nil
    }

    /// The tab's `Open settings`.
    public func openNotesSettings() {
        openSettings?(Self.settingsPane)
    }

    var clipboardClear: Duration {
        context?.settings.value("clipboard_clear", as: Duration.self) ?? Self.defaultClipboardClear
    }

    /// True when Settings must state that the recovery key is the only way to read notes on another Mac:
    /// iCloud Keychain is off or cannot be told (always, with the production store).
    public var showsRecoveryOnlyStatement: Bool { iCloudKeychain != .on }

    // MARK: Folder

    /// The folder in use: `folder` (expanded by the storage service), or, for a dev build with its own key,
    /// `<parent of the default>/<build name>` while `folder` keeps its default.
    func resolvedFolder(scope: SyncedKeyScope) -> URL? {
        guard let context, let base = context.storage.userFolder(setting: "folder") else { return nil }
        guard case .ownBuild(let name) = scope else { return base }
        let configured = context.settings.value("folder", as: String.self)
        guard configured == nil || configured == Self.defaultFolder else { return base }
        return base.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
    }

    private static func scan(_ folder: URL?) async -> NotesFolderScan {
        guard let folder else { return NotesFolderScan() }
        return await NotesFolder.scan(folder)
    }

    private func writeMarker(_ key: SyncedKey) async {
        guard let folder else { return }
        do {
            try await NotesFolder.writeMarker(keyID: key.keyID, in: folder)
        } catch {
            context?.log.error("Notes key marker not written: \(String(describing: error), privacy: .public)")
        }
    }
}
