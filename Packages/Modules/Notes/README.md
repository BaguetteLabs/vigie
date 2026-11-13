# Notes

`notes` module (SPEC §7.6, Epic 15). Story 15.1: the notes key, its setup and its recovery. Encrypted note files
(15.2), the floating panel (15.3), secrets (15.4) and the real Notes tab (15.5) build on it.

- **Off by default.** No closed-notch presence: the state is always `hidden`.
- **Settings** (`[modules.notes]`): `hotkey` (default `opt+cmd+n`, registered by Story 15.3), `folder` (default
  `~/Notes/Vigie`, `.local`, generated path row; read through `context.storage.userFolder(setting: "folder")`,
  AD-11), `clipboard_clear` (default `30s`; also clears a copied recovery key).
- **The key.** `context.notesKey` (`SyncedKeyStore`, ModuleKit; `KeychainSyncedKeyStore` in VigieCore) holds the
  one notes key: 32 random bytes, a synchronizable item in `<TeamID>.<release bundle id>.notes`, account `notes`
  (AD-9). Only the `notes` module's context has a working store. `key_id` = the first 8 bytes of SHA-256 of the
  key, in lowercase hex (`SyncedKey.keyID`).
- **Key states** (`NotesKeyState`):
  - `unavailable(reason)`: the build cannot use the store (ad-hoc dev builds: no team; or no entitlement). The tab
    shows `KEYCHAIN UNAVAILABLE IN THIS BUILD`; a recovery key can still be entered and is then held in memory
    until Vigie quits (`keyIsSessionOnly`). Setup is refused.
  - `noKey`: no stored key and the folder shows none. Tab: setup card with `Set up notes` and `Enter recovery key`.
  - `waiting(keyIDs)`: no key held, but the folder has note files or the key marker (a key exists on another Mac).
    Tab: `NOTES LOCKED` · "Waiting for iCloud Keychain, or enter your recovery key." and the recovery field.
  - `mismatch(keyIDs)`: a key is held but the folder carries other `key_id`s. Shown as the waiting state; nothing
    is written.
  - `ready(keyID)`: the key is held (`module.key`); the module owns a `NoteStore` (below). Tab: `NO NOTES` or
    `N NOTES` (with `N LOCKED` / `N DOWNLOADING` when any) until Story 15.5's list. Locked states show
    `N LOCKED` under `NOTES LOCKED`. Settings › Notes adds "N notes in this folder."
  The state is recomputed at start, on the store's change stream (local writes, and a 30 s poll while the module
  listens, so a key arriving through iCloud Keychain unlocks), on `folder` changes and when the tab or pane
  appears. Recomputing never writes.
- **Setup** (`setUpNotes()`, explicit user action only, AD-10): re-checks; adopts a key the store already holds;
  refuses while the folder shows a key; otherwise creates the key, writes the key marker and shows the recovery
  key once (tab card and Settings, `Copy` and `I saved it`). It is never shown again.
- **Recovery** (`enterRecoveryKey(_:)`): format in `docs/notes-recovery-key.md`. A malformed or mistyped key is
  refused ("This recovery key has a typo…"); a valid key whose `key_id` is not the folder's is refused ("This
  recovery key does not match your notes."). Accepted: imported into the store (replacing what it holds) and the
  marker is written.
- **Folder evidence** (`NotesFolder`): note files are `*.vnote` (iCloud placeholders `.<name>.vnote.icloud`
  count as notes with an unknown key). Each starts with the plaintext header line
  `{"format":1,"key_id":"<16 hex>"}` (`NoteFileHeader`) followed by ciphertext (Story 15.2). Only that line is
  read (at most 512 bytes, coordinated read off the main actor); contents are never read or logged. The key marker
  `notes-key.json` holds the same line alone: written at setup and recovery so that another Mac with an empty
  folder still sees that a key exists and waits instead of creating a second one.
- **Vigie Dev.** When the dev build cannot read the release key (the store's scope is `.ownBuild`), it keeps its
  own key (its own access group `<TeamID>.<dev bundle id>`, service `<dev bundle id>.notes`) and uses its own
  folder, `~/Notes/Vigie Dev` (the build's display name next to the default), while `folder` keeps its default.
  An explicit `folder` in the dev build's `local.toml` is respected. Settings shows the folder in use.
- **iCloud Keychain.** macOS has no public API to tell whether it is on, so the status is `unknown` and
  Settings › Notes always states: "If iCloud Keychain is off, your recovery key is the only way to read your
  notes on another Mac." When it is off the item simply stays on this Mac.
- **Never logged:** key bytes, recovery keys, note content. Logs carry `key_id`s and Keychain statuses only.

## Encrypted storage (Story 15.2)

Byte layout: `docs/notes-file-format.md`.

| | |
| --- | --- |
| File | `<id>.vnote`, one per note, name stable across title edits |
| Header | plaintext line `{"format":1,"key_id":"<16 hex>"}\n` (`NoteFileHeader`) |
| Body | `ChaChaPoly` sealed box (`combined`: nonce ‖ ciphertext ‖ tag) of the JSON payload `{id, title, body, created, modified, format}`, header line as authenticated data |
| Write | `NoteFileIO` actor: coordinated write (`.forReplacing`), temp file `.<name>.<uuid>.tmp` in the same folder renamed over the note; folder created on first write |
| Delete | coordinated, `FileManager.trashItem` (recoverable in the Trash) |
| Read | coordinated read off the main actor; header first; unknown `key_id` → locked, never decrypted |

- **`NoteStore`** (`@MainActor @Observable`, `module.store`, created when the key state becomes `ready`, stopped
  and dropped in every other state, and recreated when `folder` or the key changes): `notes` (modified
  descending), `note(_:)`, `load()`, `reload()`, `create(body:)`, `update(_:body:)` (title = first non-empty line,
  leading `#` removed, ≤ 120 characters; `modified` = now; unchanged body writes nothing), `delete(_:)`;
  `lockedFiles`, `foreignKeyIDs`, `downloadingFiles`, `unreadableFiles`, `unresolvedConflictFiles`, `canWrite` /
  `writeBlock` (`notLoaded`, `foreignKey`, `stopped`).
- **Locked files (AD-10).** A note file or key marker with another `key_id` blocks every write (`canWrite ==
  false`, nothing in the folder is touched) and asks the module to re-check the key; the module then shows the
  locked state and drops the store.
- **Unreadable files** (tampered, truncated, header changed, newer format) are listed by name and left alone; the
  other notes stay writable.
- **Watcher** (`NotesFolderWatcher`): a kqueue `DispatchSource` on the folder (or, while it does not exist, on its
  nearest existing ancestor, re-armed on every event), debounced 250 ms. A reload re-reads only files whose
  modification date or size changed, and skips files whose SHA-256 is the one this store wrote last, so its own
  writes are not decrypted again. Files gone from the listing leave the list.
- **iCloud.** A note not downloaded yet (`.<name>.icloud` placeholder, or `ubiquitousItemDownloadingStatus` not
  current) is in `downloadingFiles`; `startDownloadingUbiquitousItem` is called and the last decrypted value stays
  in `notes` meanwhile. The sync toggle is Story 16.2.
- **Conflicts (AD-10 as amended 2026-11-07).** After each read, for every readable note, `NSFileVersion`'s
  unresolved conflict versions (`ConflictVersionsProviding`, real `FileVersionConflicts`) are read through a
  coordinated read and opened with the key; each becomes a new note titled `<title> (conflict)` (catalog
  `notes.conflict.title`; `Untitled (conflict)` without a title) with the version's body, `created` and
  `modified` = now. Only after that note is written is the version marked resolved (coordinated write).
  `removeOtherVersionsOfItem` is never called: macOS keeps the history. The current version stays in place. A
  version with an unknown key, unreadable, or whose copy fails to save stays unresolved and is retried on the next
  change. The copy's id derives from the file name and the version, so a retry never makes a second copy.
- **Never logged:** titles and bodies. `Note`'s `description`, `debugDescription` and mirror show the id and the
  body length only; store log lines carry file names, ids and counts.
