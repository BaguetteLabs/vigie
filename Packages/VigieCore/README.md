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

`relocate(to:)` is meant to be reused by the iCloud sync toggle (Story 16.2), which moves the folder into
`iCloud Drive/Vigie/` and back.

## Symlinks and git checkouts

Every write resolves symlinks (`resolvingSymlinksInPath`), patches the file's current text with `TOMLPatcher` and
writes a temp file in the resolved file's own folder, then renames it over the file. A symlinked config folder, or a
`config.toml` that links into a dotfiles repo, keeps its link, and `git diff` shows only the changed line. When
`config.toml` itself is a symlink into another folder, that folder is watched too.
