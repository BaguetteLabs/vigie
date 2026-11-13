# Two-Mac sync check (Story 16.3, Flow 5)

A manual check Romain runs with two Macs signed in to the same Apple Account, iCloud Drive on for both. Vigie
release builds (or both dev builds: they sync under `iCloud Drive/Vigie Dev`, never mixed with the release one).
Nothing here is automated. Mac A = MacBook, Mac B = Mac Studio.

## Setup

1. On Mac A: Settings › Sync, turn **iCloud** on, confirm. The status reads `ON · ~/Library/Mobile Documents/com~apple~CloudDocs/Vigie`.
   `Reveal in Finder` shows `Vigie/config/config.toml`, `themes/`, `modules/` and `Vigie/Notes/`.
2. Check `~/.config/vigie/` and `~/Notes/Vigie/` on Mac A are now empty, and `local.toml` (Application Support)
   has `[config] folder` and `[modules.notes.local] folder` pointing into iCloud Drive.
3. Wait until Finder shows `Vigie/config/config.toml` on Mac B (no cloud badge, or click it to download).
4. On Mac B: Settings › Sync, turn **iCloud** on. The confirmation says Mac B will use the config and notes already
   there. Confirm. Mac B's own `~/.config/vigie/` and `~/Notes/Vigie/` are left untouched (not merged).

## Personalization applies live (AC 1)

5. On Mac A: change the theme (Appearance) and one status color (`[appearance.colors]` in `config.toml`).
6. On Mac B, without relaunching: the theme and the color change within a few seconds of iCloud delivering the file.
7. On Mac B, check Displays, Virtual notch and the Agents terminal settings are unchanged (they live in Mac B's
   `local.toml`).
8. `grep -E 'display|virtual_notch|terminal|privacy|launch_at_login' "~/Library/Mobile Documents/com~apple~CloudDocs/Vigie/config/config.toml"`
   finds nothing machine-specific.

## Scripts and secrets (AC 2, AC 3)

9. On Mac A: add a script module with a `secret` setting (for example a GitHub token), confirm it, enter the token.
10. On Mac B, once `modules/<file>.md` has synced: the script shows **awaiting confirmation**, does not run, and its
    token field is empty. Grep the synced folder for the token: no match.
11. On Mac B: confirm it; it asks for the token there. Enter it; it runs.
12. On Mac A: decline (or disable) the script. On Mac B it keeps running.

## Dataless files

13. On Mac B, in Finder, right-click `Vigie/config` › **Remove Download**. Vigie keeps its values (Console: subsystem
    `fr.baguettelabs.vigie`, category `config`: "config.toml is downloading from iCloud; keeping the last values",
    once). Change a value on Mac A: Mac B downloads and applies it.

## Notes

14. Set up notes on Mac A (recovery key saved). On Mac B the Notes tab waits for the key through iCloud Keychain or
    asks for the recovery key; it never offers to create a second key.

## Turning off

15. On Mac B: Settings › Sync, turn off, confirm. Files move to Mac B's defaults, the `local.toml` records are gone,
    status `OFF`. Note: this removes them from iCloud Drive, so Mac A now runs on its last values and, at next
    launch, falls back to its default folder with a "recorded folder is missing" line in Settings › General. Turn
    sync off on Mac A too (or on again on Mac B) to settle.
16. With iCloud Drive turned off in System Settings, the Sync row reads `UNAVAILABLE · iCloud Drive is off` and the
    toggle cannot be turned on.

Record the result (pass/fail per step, macOS versions, build numbers) in `PROGRESS.md`.
