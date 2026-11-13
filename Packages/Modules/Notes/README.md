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
  - `ready(keyID)`: the key is held (`module.key`). Tab: `NO NOTES` until Story 15.5.
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
