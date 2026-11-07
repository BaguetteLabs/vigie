# WarpTerminal

Warp terminal adapter (SPEC §7.1.1, §14.1, AD-23, PRD FR-24). Depends on AgentKit only. Technique and evidence:
`docs/decisions/spike-warp-focus.md` (Story 1.5, tested on Warp `v0.2026.10.14.08.27.stable_01`).

## How it works

- `matches(env:)`: `TERM_PROGRAM == "WarpTerminal"`, or `WARP_FOCUS_URL` / `WARP_TERMINAL_SESSION_UUID` present.
- `capture` (pure, env only) stores `focusURL` (verbatim), `sessionUUID` (per pane), `bundleID`
  (`__CFBundleIdentifier` if it is a Warp id, else `dev.warp.Warp-Stable`), `tty` and `version`.
- `focus`: opens `warp://session/<uuid>` (or `warppreview://` for Preview) through `URLOpening`, then activates
  Warp through `WarpAppActivating` and reports `.exact`. No usable URL, or the open is refused: activate the running
  Warp (captured channel first, then `dev.warp.Warp-Stable`, `dev.warp.Warp`, `dev.warp.Warp-Preview`), else
  launch it, and report `.appOnly`. No Accessibility or Automation grant is needed.
- `openTab`: not supported. Warp's `warp://action/new_tab?path=` opens a tab at a folder but cannot run a command
  (see the spike record).

## Flipping the decision

The visual check in the spike record ("Manual check that settles the decision") is pending. Until then
`WarpAdapter.focusLevelStatement` (shown on Settings › Agents) reads "Warp: tab focus via session URL
(unverified)". After the check, change one line in `WarpAdapter.swift`:

- the tab comes forward (outcome a): `decisionConfirmed = true` → "Warp: tab focus via session URL";
- only Warp activates (outcome c): `decision: WarpFocusDecision = .appLevelOnly` → "Warp: app-level focus only",
  and focus never opens the URL (SM-6 is then measured on iTerm2 and Ghostty, PRD FR-24).

The session URL is undocumented Warp behavior: re-run the check when a Warp update lands, and record the version.
