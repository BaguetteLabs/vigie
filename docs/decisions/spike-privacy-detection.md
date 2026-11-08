# Spike 21.1: detect screen sharing and recording

- **Story:** 21.1 (PRD FR-55, PRD §9 Q2, addendum §2, AD-20 as amended 2026-11-06, AD-24, A88)
- **Date:** 2026-11-08
- **Mac:** macOS 26.5.2 (25F84), two displays, Vigie unsigned/ad-hoc. Screen Recording **not** granted to the
  test binaries (`CGPreflightScreenCaptureAccess() == false`). The screen was locked during the spike
  (`CGSSessionScreenIsLocked = 1`), so no conference, recording or screenshot could be started.
- **No macOS 15 machine was available.** Every macOS 15 row below comes from Apple's documentation and public
  developer reports and is marked *unverified*.
- **Method:** desk research on the public APIs, and a prototype that runs the queries without any
  conference: `PrivacyDetectionProbe` (`Packages/VigieCore/Sources/VigieCore/Privacy/ScreenSharingDetection.swift`)
  behind the `ScreenSharingDetecting` protocol, tested on fixtures and run once on the real window list
  (`VIGIE_PRIVACY_PROBE=1 swift test --build-system swiftbuild --filter PrivacyDetectionProbeTests`). The
  sharing scenarios are left to Romain: see the checklist at the end.

## Decision

| macOS | Method | Default | Permission |
|---|---|---|---|
| 15.x | **Manual only** (`Force on`). Optional heuristic: window titles of known sharing bars (method 3b) | Manual; the heuristic is **off** and offered only once the checklist confirms it | Heuristic needs Screen Recording |
| 26.x (current) | Same | Same | Same |

1. **No method detects sharing or recording reliably without a new permission.** There is no public "the
   screen is being captured" signal on any supported macOS version. Privacy mode therefore ships as
   **manual only** in 21.2/21.3: the user forces it on (General › Privacy mode › `Force on`), and Settings says
   "Screen sharing can't be detected on this macOS version." (UX-DR98, FR-55 "If detection is not possible on a
   macOS version, Settings says so and offers the manual toggle").
2. **Optional automatic detection = window-title heuristic (3b), off by default (A88)**, only if Romain's
   checklist shows it catches the common cases. It needs Screen Recording, which AD-20 allows only while
   automatic detection is turned on: turning `Automatic (when sharing or recording)` on requests the permission;
   turning it off stops polling (the TCC grant itself cannot be revoked by the app). Until the checklist is done,
   21.3 offers `Force on` only and keeps the detector at `NoScreenSharingDetection`.
3. **Rejected:** the private CGS/SkyLight call (method 2), the owner-name heuristic without permission (3a,
   false positives) and ScreenCaptureKit (method 4, no signal).
4. **Complement, not detection:** setting Vigie's windows to `sharingType = .none` (method 1) is worth a
   separate, explicit option later (it hides Vigie from *every* capture, including the user's own screenshots),
   but it cannot be the Privacy mode mechanism: recent macOS versions reportedly ignore it for ScreenCaptureKit
   captures (addendum §2), and it does not touch macOS notifications.

`PrivacyService` (Story 21.2) holds one `ScreenSharingDetecting`; 21.2 plugs in `NoScreenSharingDetection`
(always `.notDetected`). 21.3 swaps in `PrivacyDetectionProbe(mode: .titleHeuristic)` behind the Automatic
setting if the checklist passes, polling every 2 s (the query costs ~40 ms for ~70 windows) so a share is
caught well within the AC's update budget.

## Candidates

### 1. Exclude Vigie's windows from capture: `NSWindow.sharingType = .none`

- **What it does:** asks the window server not to hand the window's contents to other processes. Legacy
  captures (`CGWindowListCreateImage`, `CGDisplayStream`, `screencapture`) leave the window out; the window
  stays visible on the user's own screen.
- **Not detection.** Vigie learns nothing; the state cannot drive the dots, the peek redaction or the macOS
  notification text (notifications are drawn by Notification Center, not by Vigie's windows).
- **macOS 15+:** `CGWindowListCreateImage` and `CGDisplayStream` are obsoleted for new apps in favour of
  ScreenCaptureKit. Public developer reports (and the PRD addendum) say ScreenCaptureKit captures, which is
  what Zoom, Meet in Chrome, Teams, OBS and the screenshot toolbar use today, may include `.none` windows on
  macOS 15. Some report the opposite for the Screenshot app. *Unverified on both versions* (checklist rows
  "sharingType none").
- **Cost:** none (no permission). **Side effect:** Vigie disappears from the user's own screenshots and
  recordings, which is not what Privacy mode promises (glyphs, rings and numbers stay visible).
- **Verdict:** complement only, out of scope for 21.x. The probe recorded `kCGWindowSharingState`: without
  Screen Recording every other app's window reads 0, only the Window Server menu bar and the Dock wallpaper read 1.

### 2. System screen-recording indicator state

- The purple/orange menu-bar indicator (Control Center's "Screen & System Audio Recording" item, macOS 15+) has
  **no public API**, on 15 or 26. `NSScreen`, `CGDisplay*`, `NSWorkspace` and ScreenCaptureKit expose no
  "being captured" state.
- Private API exists: `CGSIsScreenWatcherPresent()` / `SLSIsScreenWatcherPresent()` are exported (checked with
  `dlsym` on 26.5.2; `CGSSessionScreenIsShared` is not). Called once at rest: `false`, 30 ms on the first call.
  It is undocumented, its semantics are unknown (screen watchers include accessibility zoom, AirPlay, Sidecar)
  and it can disappear in any update.
- The public `CGSessionCopyCurrentDictionary()` has no sharing key (only lock state, user, console, secure
  input pid).
- A no-permission variant would watch Control Center's status-item windows (layer 25, 26 per display at rest,
  bounds readable, names blank) for a new item. The window carries no name or owner detail that identifies it
  as the recording indicator; any new menu-bar extra would match. *To test by Romain* only as a curiosity.
- **Verdict:** rejected (private API = fragile; AD-24 wants one honest method). Last resort only, and not
  without a new AD.

### 3. Known conferencing apps sharing the screen (`CGWindowListCopyWindowInfo`)

What is readable **without** Screen Recording (recorded at rest, 71 on-screen windows, query ~40 ms):

| Key | Other apps' windows | Notes |
|---|---|---|
| `kCGWindowOwnerName`, `kCGWindowOwnerPID` | yes | `Warp`, `Brave Browser`, `Finder`, `Centre de contrôle`... |
| `kCGWindowBounds`, `kCGWindowLayer`, `kCGWindowAlpha`, `kCGWindowNumber`, `kCGWindowIsOnscreen`, `kCGWindowMemoryUsage`, `kCGWindowStoreType` | yes | |
| `kCGWindowSharingState` | reads 0 | only system windows read 1 |
| `kCGWindowName` | **no** (blank since macOS 10.15) | 2 of 71 named, both the Window Server's `Menubar`; with `.optionAll`, 4 of 205 (`Menubar`, `Wallpaper-…`) |

- **3a. Owner heuristic (no permission):** "possibly sharing" when a layer-0 window belongs to `zoom.us`,
  `Microsoft Teams`, `Webex`, `OBS`, `QuickTime Player`, `Slack`... It cannot tell "Zoom is open" from "Zoom is
  sharing", and cannot see Meet at all (it is a browser tab). At rest it returned `notDetected` (none of those
  apps running). **False positives whenever such an app has any window**: Privacy mode would stay on for a whole
  workday with Slack open. Rejected.
- **3b. Title heuristic (needs Screen Recording):** with the permission, window titles become readable.
  Candidate sharing indicators (from public reports, *unverified*): Zoom's `zoom share toolbar window` /
  `zoom share statusbar window`; Chromium browsers' bar `<site> is sharing your screen.` / `… is sharing a
  window` / `… is sharing this tab`; Teams' sharing control bar; Slack huddle window titles; OBS's main window
  while recording. At rest without permission the probe returns `unavailable` (it never prompts; it checks
  `CGPreflightScreenCaptureAccess()`). Expected delay: one poll interval. Expected misses: QuickTime and the
  screenshot toolbar (their recording UI is a menu-bar item or an untitled panel), Safari/FaceTime sharing,
  any app whose bar is untitled. Expected false positives: a document whose title contains one of the fragments.

### 4. ScreenCaptureKit / CGWindow capture queries

- `SCShareableContent` lists displays, apps and windows **available to capture**; it needs Screen Recording and
  says nothing about who else is capturing. `SCContentSharingPicker` (macOS 14+) is the picker for the
  capturing app itself. `SCStream` has no "other streams" API.
- `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` are the public permission calls;
  preflight never prompts (used by the probe).
- **Verdict:** no signal; only useful for its permission plumbing (AD-20 `.screenRecording`).

### 5. macOS 15+ specifics

- macOS 15 re-prompts apps that use Screen Recording outside the system picker ("… is requesting to bypass the
  system private window picker", first monthly, later relaxed in 15.x updates). An app holding the
  permission only to read window titles may still see that prompt: one more reason to keep the heuristic off by
  default. *Exact cadence on 15.x vs 26 unverified* (checklist row).
- The Sequoia "Screen & System Audio Recording" Control Center indicator, and the per-app list in it, have no
  API (see 2).
- `NSScreen` and `CGDisplayStream` expose no capture state on 15 or 26.

## Results summary

| Method | Reliability | Delay | False positives | Permission |
|---|---|---|---|---|
| 1. `sharingType = .none` | not detection; SCK may ignore it on 15+ (*unverified*) | n/a | n/a | none |
| 2. Indicator state (private CGS) | unknown semantics, fragile | ~instant | unknown (Sidecar, AirPlay, Zoom accessibility?) | none, but private API |
| 3a. Owner heuristic | fires whenever a conferencing app is open | 1 poll | very high | none |
| 3b. Title heuristic | catches apps that title their sharing bar (*to test*) | 1 poll (2 s planned) | low (document titles) | Screen Recording |
| 4. ScreenCaptureKit query | no signal | n/a | n/a | Screen Recording |

## Checklist for Romain (to run on macOS 26 and, if one is reachable, macOS 15)

Before: grant Screen Recording to the test runner (Terminal or Warp) in System Settings › Privacy & Security ›
Screen & System Audio Recording, then for each row start the scenario and run, from `Packages/VigieCore`:

```sh
VIGIE_PRIVACY_PROBE=1 swift test --build-system swiftbuild --filter PrivacyDetectionProbeTests/probeRunsOnTheRealWindowList
```

Note for each row: `title=` (possiblySharing with which evidence, or notDetected), `owner=`, how many seconds after
the share started it first matched, and whether it clears after the share stops. For the false-positive column,
also run it with the app open but **not** sharing.

| # | Scenario | title= while sharing | title= open, not sharing | owner= open, not sharing | Window title seen (paste) |
|---|---|---|---|---|---|
| 1 | Zoom: share screen | | | | |
| 2 | Zoom: share one window | | | | |
| 3 | Google Meet in Chrome/Brave: present entire screen | | | | |
| 4 | Google Meet: present a tab | | | | |
| 5 | Microsoft Teams: share screen | | | | |
| 6 | Slack huddle: share screen | | | | |
| 7 | QuickTime Player: File › New Screen Recording, recording | | | | |
| 8 | Screenshot toolbar (⇧⌘5): record entire screen | | | | |
| 9 | OBS: display capture, recording | | | | |
| 10 | OBS: display capture, preview only (not recording) | | | | |

Extra rows:

- **sharingType none:** while sharing in Zoom/Meet and recording with QuickTime and ⇧⌘5, open a small test
  window with `sharingType = .none` (e.g. the Vigie Debug build after setting it on the island panel) and note
  whether it appears in the shared/recorded image, on macOS 26 and 15.
- **Re-prompt:** with Screen Recording granted, note whether macOS shows the "bypass the private window picker"
  prompt for the runner, and when.
- **Indicator (curiosity):** note whether the total window count printed by the probe grows by one while
  recording (Control Center's indicator is one more untitled layer-25 window; at rest 26 per display).

If rows 1, 3, 5 and 6 match while sharing and stay `notDetected` when not sharing, 21.3 may offer
`Automatic (when sharing or recording)` with the title heuristic, off by default, requesting Screen Recording
when turned on. Otherwise Privacy mode stays manual only.

## Live results (2026-11-08, Romain, macOS 26.5, Google Meet in Brave, entire screen)

Probe (`PrivacyDetectionProbe`, Screen Recording granted to the terminal): `owner=notDetected title=notDetected` both while sharing and after — the shipped patterns had no entry for Meet in a Chromium browser. A raw `CGWindowListCopyWindowInfo` dump taken while sharing and again after stopping differs by exactly three windows:

| Only while sharing | Layer | Owner | Title |
|---|---|---|---|
| Share banner | 25 | Brave Browser | `Votre écran est partagé par le b… l'application meet.google.com.` (localized; English builds say "… is sharing your screen") |
| Meet helper window | 3 | Brave Browser | `Meet – <meeting code>` |
| Cursor overlay | 2147483630 | Window Server | `Cursor` |

Both Brave windows disappear immediately when sharing stops; the Meet tab window (layer 0) stays. The system `StatusIndicator` windows (4) did not change count, so the menu-bar indicator is not observable this way.

**Signals derived:**
- **Title heuristic (needs Screen Recording):** a Chromium-family browser window whose title contains the shared origin's host (`meet.google.com`) or the localized "sharing your screen" phrase. Locale-dependent on the phrase, locale-independent on the host.
- **Layer heuristic (no permission needed):** `kCGWindowOwnerName` and `kCGWindowLayer` are readable without Screen Recording. A window owned by a Chromium-family browser (Chrome, Brave, Edge, Arc, Vivaldi, Chromium) at **layer 25** existed only during the share. If Chromium uses layer 25 only for the screen-share banner, Automatic detection for browser-based sharing needs **no permission** and no locale handling. **To verify** before relying on it: dump windows while a download bubble, a permission prompt, a fullscreen "press Esc" toast and a tab-sharing (not screen) session are shown.

**Still untested:** Zoom, Teams, Slack huddle, QuickTime, ⇧⌘5 recording, OBS, and macOS 15. Decision stays manual-only by default; Story 21.3's `Automatic` may be offered once the layer-25 check above holds, with the title heuristic as the permission-gated fallback for native apps.

