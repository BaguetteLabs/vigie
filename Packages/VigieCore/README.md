# VigieCore

The core of Vigie: ConfigStore, the Notch Host, Notifier, the Module Registry and the services modules receive
through `ModuleContext`. This file documents behavior that is not obvious from one type.

## Config folder relocation (Story 16.1)

The config folder holds what may be shared or committed: `config.toml`, `themes/` and `modules/` (script
modules). Everything machine-specific (`local.toml`, the activity log, the socket, drops) stays in Application
Support (AD-8, AD-17).

**Where the folder comes from at launch** (`AppEnvironment`, in this order):

1. the `configFolderOverride` init parameter (tests);
2. `VIGIE_CONFIG_DIR` (dev builds only);
3. `[config] folder` in `local.toml`, `~` for the home folder;
4. the default, `~/.config/vigie`.

A recorded folder that is missing (or a relative path) falls back to the default. ConfigStore logs the problem at
start and Settings › General › Config folder shows a line about it. The record is kept, so the folder is used again
once it is back (an unmounted volume, for example).

**Changing it** goes only through `ConfigStore.relocate(to:)` (AD-12). It runs after any queued reload or write
and returns:

- `.adopted` when the chosen folder already has a `config.toml`. Vigie reads that file from now on and leaves the
  previous folder untouched. Observers hear about every key whose resolved value changed.
- `.moved` otherwise. `config.toml`, `themes/` and `modules/` are copied into the folder (created when missing),
  each copy is compared with its original, the location is recorded, and only then are the originals removed. A
  failed copy removes the partial copies (and the folder, if the move created it), and nothing else changes. Values
  are the same, so observers stay silent. If removing an original fails, the copy is already in use and the leftover
  is logged.

It refuses (`ConfigRelocationError`, catalog text) the current folder itself, a folder inside it or containing it,
the Application Support folder or anything inside it, a file, a folder Vigie cannot write to, and, for a move, a
folder that already has `themes/` or `modules/` without a `config.toml` (no merging). `planRelocation(to:)` runs the
same checks without touching anything; Settings uses it to say "use" or "move" before confirming.

The location is written to `local.toml` through the config writer (one line, atomic). Choosing the default folder
removes the key. Afterwards the watchers point at the new folder, `ConfigStore.configFolderURL` and
`ConfigStore.location` change, and `context.scriptFolder` follows `location`: its `url` is the new `modules/` and
its `changes()` stream yields once, so the integrations module rescans.

`relocate(to:)` is reused by the iCloud sync toggle (Story 16.2, below).

## iCloud sync (Story 16.2)

**Where.** `AppEnvironment.iCloudDriveFolderURL` is the user-visible iCloud Drive,
`~/Library/Mobile Documents/com~apple~CloudDocs`. Vigie is not sandboxed and has no iCloud container entitlement, so
that folder is the only route; `isICloudDriveAvailable` is true when it exists as a folder. The sync root is
`<iCloud Drive>/Vigie` (`Vigie Dev` for the dev build, named like the Application Support folder), with `config/`
(the config folder) and `Notes/` (the notes folder) inside.

**What moves.** The config folder (`config.toml`, `themes/`, `modules/`) and the notes folder (encrypted `.vnote`
files and the key marker). Never `local.toml` (Application Support: machine-specific settings, script confirmations,
the two location records, `[sync] icloud` itself) and never secrets (Keychain; ConfigStore refuses to write a
`secret` setting). A test sets every `.local` key, turns sync on and checks that nothing under the iCloud root holds
them or a secret.

**`SyncController`** (`@MainActor @Observable`, created by `SettingsController` on its `ConfigStore`):

- `isOn` mirrors `[sync] icloud` (local). `planTurnOn()` / `planTurnOff()` check both moves without touching
  anything and return a `SyncPlan` (adopt flags for the confirmation); `turnOn()` / `turnOff()` / `apply(_:)` run it.
- Turning on: refused with `SyncError.iCloudDriveUnavailable` when iCloud Drive is off. Then the config folder moves
  through `relocate(to:)`, then the notes folder through `ConfigStore.relocateUserFolder(_:)`; if the notes step fails
  the config folder is moved back; `icloud = true` is written last (if that write fails, both are moved back).
- Turning off: both move back to their local defaults (the default config folder; `~/Notes/Vigie`, or
  `~/Notes/Vigie Dev` for the dev build so it never takes the release build's notes), the records are removed (the
  dev build records its own notes folder), then `icloud = false`. It refuses while any file of the two folders is
  still dataless (`downloadsPending`, downloads started): nothing leaves iCloud half-downloaded. Moving out of iCloud
  Drive removes the files from iCloud, so other Macs with sync on stop receiving them; the confirmation says so.
- Nothing restarts: ConfigStore re-arms its watchers on the new folder, `context.scriptFolder` rescans, and the Notes
  module recomputes on its `folder` setting.

**User folder relocation.** `planUserFolderRelocation(setting:from:to:record:)` + `relocateUserFolder(_:)` move the
folder named by a module's `.local` `path` setting (here `[modules.notes] folder`): copy each item (except
`.DS_Store`), verify, write the setting through `set`/`remove` (so the module's observer fires), then remove the
originals; the emptied folder stays. A missing source folder only changes the setting. Same refusals as 16.1 for
same/nested folders, files and unwritable places.

**Second Mac (Story 16.3).** When `<root>/config/config.toml` exists, the config folder is **adopted** (like 16.1:
observers hear every changed key, this Mac's own folder is left as it was). When `<root>/Notes` has contents, it is
adopted too; this Mac's local notes stay in `~/Notes/Vigie` and are not merged. Script files arriving this way show
as awaiting confirmation (per-Mac records live in `local.toml`). See `docs/sync-two-mac-check.md`.

**Dataless files (AD-12).** `CoordinatedFileReader` (actor) checks `ubiquitousItemDownloadingStatus` (or an
old-style `.<name>.icloud` placeholder) through an injectable `UbiquitousItemStatusProviding`. A dataless file is
not read: `startDownloadingUbiquitousItem` is called and the caller gets `nil` / `.pending`. Anything else is read
through `NSFileCoordinator`, off the main actor. ConfigStore reads `config.toml` and `local.toml` with it, keeps the
last good document while a download is pending (logged once per wait), and retries the reload every 2 s until the
content lands (the watcher reloads too when it sees the change). ConfigWriter reads through the same rule and refuses
to write a file that is not downloaded. Script files: `CoreScriptFolder` only lists names; the files themselves are
read by the integrations module through ModuleKit, which this story does not change, so a dataless script is read
by the system on access (a blocking download) rather than deferred.

## Symlinks and git checkouts

Every write resolves symlinks (`resolvingSymlinksInPath`), patches the file's current text with `TOMLPatcher` and
writes a temp file in the resolved file's own folder, then renames it over the file. A symlinked config folder, or a
`config.toml` that links into a dotfiles repo, keeps its link, and `git diff` shows only the changed line. When
`config.toml` itself is a symlink into another folder, that folder is watched too.
