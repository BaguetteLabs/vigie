# Spike 1.5: focus a specific Warp tab

- **Story:** 1.5 (FR43 research, SPEC §7.1.1 / §14.1, AD-23 Terminals, Architecture Deferred "Warp technique")
- **Date:** 2026-11-07
- **Warp version tested:** `v0.2026.10.14.08.27.stable_01` (`dev.warp.Warp-Stable`, team `2BBY89MBSN`), macOS 26.5
- **Prototype:** `spikes/warp-focus/` (throwaway SwiftPM executable; `.build/` ignored by the root `.gitignore`)

## Decision

**(d) Undetermined, pending one manual check with the screen unlocked.** The evidence points strongly toward **(a) exact pane focus**, using a technique the spike plan did not expect: Warp's own per-session deep link, not the Accessibility API.

- Warp exports `WARP_FOCUS_URL=warp://session/<uuid>` and `WARP_TERMINAL_SESSION_UUID=<uuid>` into every local shell. The uuid is per **pane**, which is finer than per tab.
- Opening that URL makes Warp log `received url` → `dispatching action for "root_view:handle_pane_navigation_event"` → `PaneGroupAction::HandleFocusChange`. So Warp routes the URL to its own pane-focus handler.
- Opening a URL needs **no Accessibility grant and no Automation (Apple Events) grant**. It is a plain `NSWorkspace.open(URL)`.
- **What could not be confirmed:** that the visible tab actually changes. During the spike the Mac was locked (`CGSSessionScreenIsLocked = true`, frontmost app `loginwindow`). Warp's persisted state (`windows.active_tab_index` in `warp.sqlite`) did not change within 60 s, so it can't serve as an oracle; Warp seems to write it lazily. The AX route could not be tested either, because the process is not trusted (see below).

**Recommendation for Story 5.4, if the manual check passes:** Warp's `focus` opens `warp://session/<uuid>`, followed by `NSRunningApplication.activate()` on Warp as a safety net. If the URL path fails, the fallback is app-level focus (SPEC §14.1). The AX title-matching approach should be kept only as an investigated alternative. It needs a broad Accessibility grant and depends on Warp's AX tree, which Warp does not document (Warp renders its UI itself, so the tab bar may not be exposed at all; `dump` will show this once a grant exists).

**If the manual check fails** (Warp is activated but the tab does not switch), the decision becomes **(c) app-level focus only**, unless the AX `dump` after a grant shows pressable tab elements. In that case re-evaluate with `focus --title`.

## Evidence

### Environment observed inside a Warp tab

The spike ran in Claude Code (`claude`, pid 48474, `ttys007`) → login `-zsh` → `/Applications/Warp.app/Contents/MacOS/stable`. So these are exactly the variables a Claude Code hook process inherits: hooks are children of `claude`, the same as the spike's shell. Output of `warp-focus env`:

| Variable | Value observed | Identifies the tab? |
|---|---|---|
| `TERM_PROGRAM` | `WarpTerminal` | No: identifies the terminal. **Use it for `matches(env:)`.** |
| `TERM_PROGRAM_VERSION`, `WARP_CLIENT_VERSION` | `v0.2026.10.14.08.27.stable_01` | No: version only |
| `__CFBundleIdentifier` | `dev.warp.Warp-Stable` | No: identifies the channel (Stable vs Preview), useful to pick the app to activate |
| `WARP_TERMINAL_SESSION_UUID` | `dbb86f5d0ced4332a8feab247a908497` | **Yes, per pane.** It matches `terminal_panes.uuid` in Warp's `warp.sqlite`. A tab with two split panes has two uuids. It stays stable for the pane's lifetime, and Warp restores it with the session. |
| `WARP_FOCUS_URL` | `warp://session/dbb86f5d0ced4332a8feab247a908497` | **Yes.** Warp builds it from the uuid (the binary contains the format `://session/` + `WARP_TERMINAL_SESSION_UUID`). |
| `WARP_CLI_AGENT_PROTOCOL_VERSION` | `1` | No. It signals Warp's CLI-agent integration, which is likely why `WARP_FOCUS_URL` exists. |
| `WARP_IS_LOCAL_SHELL_SESSION` | `1` | No. It is `1` for local shells; over SSH the remote side may not get these variables. |
| `WARP_HONOR_PS1`, `WARP_USE_SSH_WRAPPER`, `WARP_SSH_REUSE_CONTROL_MASTER`, `WARP_PROMPT_NODE_VERSION_ENABLED` | settings flags | No |
| `TERM_SESSION_ID` | *(not set by Warp)* | n/a |
| `TERM` / `COLORTERM` | `xterm-256color` / `truecolor` | No |

Warp's persisted state (read-only copy of `~/Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite`) maps uuid → pane → tab → window (`terminal_panes.uuid`, `pane_nodes.tab_id`, `tabs.window_id`, `windows.active_tab_index`). Vigie must **not** depend on this private database. It was used only to confirm what the uuid means.

### URL handling

- `Info.plist` registers the `warp` scheme (`warppreview` for Preview builds).
- Documented URIs (docs.warp.dev "URI Scheme"): `warp://action/new_window?path=<dir>`, `warp://action/new_tab?path=<dir>`, `warp://launch/<launch_config_path>`, `warp://tab_config/<name>[?new_window=true]`, plus Drive and settings links. The docs say the scheme does **not** target or control an already-open tab, and does not run commands.
- `warp://session/<uuid>` is **undocumented**. Warp exports it as `WARP_FOCUS_URL`, and its log shows the pane-navigation dispatch. Warp issue #8929 ("Deeplink to focus/switch to an existing tab") is still open as a public request, which agrees with the route being internal and undocumented.
- Timing: `open warp://session/<uuid>` returned at once, and Warp logged handling in the same second. Activation time could not be measured while the screen was locked.

### Accessibility

- `AXIsProcessTrusted() = false`. `AXIsProcessTrustedWithOptions(prompt: true)` was called **once** and returned false. The screen was locked, so the user probably did not see the dialog.
- The TCC responsible process for the prototype is **Warp** (`dev.warp.Warp-Stable`), because the prototype runs as a descendant of a Warp tab. Granting Accessibility to Warp lets *every* program run from Warp drive any app's UI. That grant is broad; use it only to finish the spike, then remove it if not wanted.
- In production, the grant would be to Vigie.app itself (it calls AX from its own process). With the URL technique, Vigie needs no Accessibility for Warp at all.

## What `capture(env:pid:tty:)` stores for Warp

`capture` stays pure: env only.

```
TerminalLocator(terminal: "warp",
                payload: [
                  "sessionUUID": env["WARP_TERMINAL_SESSION_UUID"],   // 32 hex chars, per pane
                  "focusURL":    env["WARP_FOCUS_URL"],               // warp://session/<uuid>, kept verbatim
                  "bundleID":    env["__CFBundleIdentifier"] ?? "dev.warp.Warp-Stable",
                  "tty":         tty                                  // diagnostic only
                ])
```

- `matches(env:)`: `env["TERM_PROGRAM"] == "WarpTerminal"`, or `WARP_TERMINAL_SESSION_UUID` is present.
- Prefer `focusURL` as given (it already carries the right scheme for Stable vs Preview). Otherwise build it as `warp://session/<uuid>`, or `warppreview://session/<uuid>` when `bundleID` is the Preview channel. Validate the uuid as 32 hex chars before building a URL.
- If both variables are missing (an old Warp, SSH, tmux or another multiplexer stripping env), the locator holds `bundleID` only, and `focus` is app-level.

## `focus(_:)` for Warp (recommended, pending the manual check)

1. If the locator has a session URL: `NSWorkspace.shared.open(url)`. No TCC prompt, no Apple Events.
2. Then `NSRunningApplication(bundleIdentifier).activate()`, in case the URL switches the pane without raising the app.
3. If no URL, or `open` returns false: activate Warp only (app-level fallback, SPEC §7.1.1 "If focusing fails, activate the terminal app").
4. Success cannot be detected: Warp gives no callback. A closed pane has a stale uuid; Warp presumably just activates, which is the fallback anyway.

## `openTab(argv:cwd:)` for Warp

- `warp://action/new_tab?path=<cwd>` (percent-encode the path) opens a tab at `cwd`. It **cannot run a command**.
- To run `argv`, the documented route is a Tab Config or Launch Configuration file opened with `warp://tab_config/<name>` or `warp://launch/<path>`. That means writing a file into Warp's config directory, which this spike was not allowed to do and which edits user dotfiles. Not recommended for v1.
- Recommended for v1: `openTab` opens `new_tab?path=<cwd>` and puts the shell-quoted command on the pasteboard, or tells the user it can't auto-run. Alternatively, ship Warp's `openTab` as "open tab at cwd" only. AX keystroke injection is rejected: it is fragile, needs Accessibility, and types into the wrong place on races.

## Risks

- **Undocumented route:** `warp://session/` and `WARP_FOCUS_URL` can change or disappear in a Warp update. Mitigation: always fall back to app-level activation, and record the tested Warp version (above).
- **Pane granularity:** the uuid targets the pane where the agent was started. That is right for Focus, but a session restarted in another pane gets a new uuid (captured again on `session.start`).
- **Multiple windows:** handled by Warp's own navigation if the URL works. Unverified across windows and Spaces or full screen; include it in the manual check.
- **Env not inherited:** SSH sessions, `tmux`/`screen`, and `sudo`/`env -i` wrappers can strip or replace the variables. Then app-level only.
- **Stable vs Preview:** different bundle ids and URL schemes (`warp` vs `warppreview`).
- **AX route (if ever needed):** Warp draws its own UI, so the AX tree may expose no tabs. Tab titles collide (several "claude" tabs in the same repo). It needs a broad Accessibility grant, and Warp updates can reshape the tree.
- **URL opening is user-visible:** each `open` activates Warp. Call it only from a user action, which AD-23 already requires.

## How to re-run

From the repo worktree root:

```sh
cd spikes/warp-focus && swift build --build-system swiftbuild
BIN="$(swift build --build-system swiftbuild --show-bin-path)/warp-focus"

"$BIN" env                    # Warp/TERM vars seen by this process (run in each tab you want to target)
"$BIN" trust                  # AX trust state; add --prompt to show the system dialog once
```

**Manual check that settles the decision (screen unlocked, no grant needed):**

1. Open three Warp tabs (put one in a second Warp window). In each, run `echo $WARP_FOCUS_URL` and note the URLs.
2. From tab A, run `"$BIN" focus --session <uuid of tab C>` (or `open 'warp://session/<uuid>'`) and check that tab C comes to the front. Repeat from another app (for example, run the command from Terminal.app) so Warp starts in the background. Also target the tab in the second window, and a closed tab's uuid.
3. Result: if the tab comes to the front each time, change the decision to **(a)** with the URL technique. If only Warp activates, change it to **(c)**, or try AX (below).

**Optional AX check:** grant Accessibility to **Warp** in System Settings › Privacy & Security › Accessibility (the prototype's TCC responsible process). Then run:

```sh
"$BIN" dump --depth 12 > /tmp/warp-ax.txt   # windows / tab bar / tabs, if Warp exposes them
"$BIN" focus --title "<unique tab title>"
```

Remove the Warp Accessibility grant afterwards if you don't want it.

`"$BIN" open-tab --path <dir>` exercises `warp://action/new_tab?path=`.
