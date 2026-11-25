---
name: Vigie
status: final
sources:
  - ../../SPEC.md
  - ../../prds/prd-vigie-2026-11-06/prd.md
updated: 2026-11-07
---

# Vigie — Experience Spine

Product scope, module system, adapters, config format and roadmap live in `SPEC.md` and are cited by section (§). Requirements and user journeys live in the PRD (`prds/prd-vigie-2026-11-06/prd.md`, FR-n, UJ-n); its glossary terms are used verbatim here. This file holds the experience decisions. Where it contradicts `SPEC.md`, this file wins for UX; every conflict is listed in **SPEC.md impacts** at the end.

**Mockups** live in `mockups/` and are linked from the sections they illustrate. Where a mockup disagrees with this file or `DESIGN.md`, the spines win. Onboarding and the Settings window are spine-only by choice: no mockup. The Story 1.7 design pass (settings gear, stale and process-only looks, drop display, script widgets, Time, Twin Metal Tactical tabs and notes) is in [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html); its banner names the option chosen for each part (decided 2026-11-07).

## Foundation

| | |
|---|---|
| Platform | macOS 15+ (SPEC §2). Swift, SwiftUI, AppKit where needed. |
| Window | Non-activating `NSPanel` above the menu bar (SPEC §3). Vigie never becomes the key app unless the user opened a surface deliberately (see Interaction Primitives). |
| Form factor | Desktop only. On a MacBook with a physical notch, Vigie draws around the notch. On plain displays (external monitors, Mac mini/Studio, iMac without notch) it draws a virtual notch (SPEC §5.5). Dynamic Island Macs run in plain/fallback mode (SPEC §14.10). |
| UI system | None. Notch surfaces are custom, styled by `DESIGN.md` tokens. Settings is a regular macOS window with native controls. |
| Visual reference | `DESIGN.md` (theme family: Chrome Hologram default, Twin Metal Tactical; each light and dark). |
| Stakes | Hobby / dogfooding first, public release once stable; GNU GPLv3 since 2026-11-25 (was closed source from 2026-11-06), business model undecided (SPEC §2.1). |
| Language | English first. All strings go through i18n from the first commit; other languages later. |

## Information Architecture

| Surface | Reached from | Purpose |
|---|---|---|
| Closed notch · left wing | Always visible | Shared item lane: quota rings (one per provider, nested when two windows are tracked, provider name under each), script side-slot items and the Time readout; every left-wing item (each provider quota ring, each script side-slot item, the Time readout) has a priority; items sort by state, then priority, fill the slots (3 by default), and the rest collapse into `+X` like sessions (decided 2026-11-07). The Image to Text `COPIED` readout is transient |
| Closed notch · right wing | Always visible | Agent sessions only: per-session status glyphs (3 slots by default) and `+X` overflow. No count, no alert label, no other module |
| Drop display | A file is dragged over the notch from any app | Drag-only display attached to the notch: Stash, Ask AI, AirDrop, Image to Text. Replaces the earlier two-wing closed-notch drop zones |
| Peek | A session turns blocked, failed or done; several sessions interrupted by sleep (summary); quota warning (if set to alert); setup problem; Timer end or Pomodoro phase end; break due (if set to peek); a calendar event's own reminder time | One-time alert with two actions (the break peek has three). One peek at a time (see Peek concurrency) |
| Expanded view · Home | Click on the notch, or global expand shortcut | Widget grid of one fixed card size, chosen and ordered in Settings › Home. Opens here every time. |
| Expanded · Agents | Tab | Dense, scrollable session list; only action is Focus |
| Expanded · Usage | Tab | Per-provider limits, reset times, pace bars; 7-day history and today's cost (SPEC §7.2) |
| Expanded · Shelf | Tab | Stashed items and the `SEND TO` card: Ask AI, AirDrop, Image to Text (SPEC §7.3) |
| Expanded · Calendar | Tab | Month grid and upcoming events (SPEC §7.5). Calendar has no closed-notch presence: events reach the notch only as reminder peeks |
| Expanded · Time | Tab, or the Time hotkey | Quick start on top, running Timers / Countdowns / Pomodoro below |
| Expanded · Notes | Tab | Notes list, search and preview |
| Expanded · script pages | Tab per script that enables a page | Full-page view of one script module: large widget, its documentation, last / next run and source |
| Floating notes panel | Global notes shortcut | Write or read a note without opening the notch |
| Script Confirmation | A `vigie://install` link, a synced script awaiting confirmation, an update available (widget, side slot, script page or Settings › Scripts) | Regular macOS window: the whole script file, its source and author, signature state, the update diff; Confirm or Decline (PRD FR-39, FR-42, FR-43) |
| Setup-problem alert | Adapter/CLI version unsupported, invalid config, missing permission | Distinct from agent alerts |
| Settings window | Setup-problem `Open settings`, empty-state buttons, `⌘,`, the settings gear at the far right of the expanded view's tab row, and the right-click menu on the closed notch (`Settings…`, `Quit Vigie`) | Regular macOS window that edits the config files |
| Onboarding | First launch | Guided sequence (see Settings & Onboarding) |

Tab order: Home first, then module tabs in user order (SPEC §10). Mocked tab bar: `Home · Agents · Usage · Shelf · Calendar · Time · GitHub PRs · Notes`, then the settings gear (not a tab: no active state, no `⌘1–9` slot).

→ Composition references: [`mockups/theme-family-4-looks.html`](mockups/theme-family-4-looks.html) (closed notch, blocked peek, expanded Home, status system in four looks); [`mockups/compare-a-vs-c-v3.html`](mockups/compare-a-vs-c-v3.html) (calm presence, shared base); [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (Story 1.7 surfaces); key screens linked per section below.

Not mocked: Home in states other than the baseline, Agents tab empty state, onboarding and settings (spine-only by choice), the C look of the drop display, script widgets and Time surfaces (C Agents, Usage, Shelf, Calendar card and notes panel are mocked in 1.7f), the quota-warning, sleep-summary and calendar-reminder peeks, Home at its fixed card size, the Script Confirmation window, the `Send to` menu, Privacy mode and multiple Accounts.

## Voice and Tone

Microcopy. Brand posture lives in `DESIGN.md` Brand & Style. Wording is identical in every theme variant.

- **Compact UI** (notch, tabs, labels, status): short uppercase technical labels.
- **Longer messages** (alerts, onboarding, errors, empty states): terse, factual, complete sentences. No exclamation marks, no personification.

| Do (from mocks) | Don't |
|---|---|
| `BLOCKED · NEEDS INPUT` · `T+00:02` | "Hey! Claude needs you 👋" |
| `Claude Code wants to run Bash · npm run db:migrate` | "An action requires your attention" |
| `FAILED · HOST SLEPT` · `Run interrupted during Bash · ./scripts/backup.sh` | "Oops, something went wrong" |
| `Turn ended · 3 files` | "Task completed successfully ✓" |
| `Codex adapter: CLI version 0.9.2 unsupported` | "Uh-oh, we hit a snag" |
| `FOCUS TERMINAL ⌥⌘↵` · `DISMISS ⌥⌘⌫` · `OPEN SETTINGS` | "Take me there" |
| `RESET 16:40 · IN 1H52` · `WARN · ≥ 80%` · `SORTED BY URGENCY` | Sentences in labels |
| `WITHIN PACE · +3` · `AHEAD OF PACE · +9` | "You're burning through tokens!" |
| `6D LEFT` · `EXPIRES IN 5H` · `PINNED` | "Hurry, this file is about to vanish" |
| `NO AGENT CONNECTED` · `NO ACTIVE SESSIONS` · `NO USAGE PROVIDER` | Lowercase or mixed-case labels in compact UI |
| `STALE · 18M` · `RUNNING` · `LAST EVENT 14:30` | "Session may have crashed?" |
| `DROP · 1 ITEM` · `ESC · CANCEL` · `RELEASE TO STASH` · `RELEASE TO SHARE` · `COPIED · 3 LINES` | "Drop it like it's hot" |
| `OK` · `WARN` · `DOWN` · `CHECKED 2 MIN AGO` · `DOWN SINCE 14:44` | "Your site is having a bad day" |
| `TIMER · ENDED` · `AWAY · PAUSED` · `BREAK DUE` · `START BREAK` · `SNOOZE 5M` · `SKIP` · `ENDED 14:48` | "Time to stretch those legs!" |
| `QUOTA · WARN` · `FAILED · EXIT 2` · `UPDATE AVAILABLE` · `Verified: Vigie Script repository` | "Heads up, you're almost out!" |

Status labels: `IDLE`, `WORKING · 14M`, `DONE · 1M`, `BLOCKED · 12M`, `FAILED · 41M`. For blocked and failed, the time is `T+` since entering the state and keeps running after the alert. Neutral session labels: `STALE · 18M` (time since the last event) and `RUNNING` (process-only, no time). A `vigie run` session that exits non-zero reads `FAILED · EXIT 2` (the exit code). Module levels (status vocabulary): `OK`, `WARN`, `DOWN`, optionally with a qualifier (`OK · UP`).

Proposed strings for states without decided copy are marked [ASSUMPTION] where they appear.

## Component Patterns

Behavioral. Visual specs live in `DESIGN.md` Components (same names).

| Component | Use | Behavioral rules |
|---|---|---|
| Closed island | Always | Usage left, sessions right. Non-session items (script side slot, Time readout, `COPIED` readout) share the left wing with the quota rings: each item has a priority, items sort by state then priority, fill the slots (3 by default), and the rest collapse into `+X` like sessions; the right wing keeps session glyphs only, so an alert is never hidden. Hover: small reaction only; click opens Home. While a file is dragged over it, the drop display grows out of it. Empty side: black on a physical notch; virtual notch shrinks or hides per `virtual_notch.idle` (SPEC §5.1). → [`mockups/key-closed-notch-states.html`](mockups/key-closed-notch-states.html) |
| Quota dial | Left wing, one per provider | Shows the Account of the most recent Session (PRD FR-29); the label under the ring is the provider name (`CLAUDE`), or provider and Account (`CLAUDE · WORK`) when that provider has several Accounts [ASSUMPTION: Account name truncated to 6 characters on the wing]. 3 slots by default, configurable. Setting: 5h only, or 5h + weekly (nested, 5h inside). Value inside = 5h, or the only window the plan has. Single provider: dial + readout (`38 %` / `CLAUDE · WEEK`). Two or more: provider name in small text under each ring. Window absent (e.g. Ultra plan, no 5h): weekly ring alone at single-ring size; pace moves to weekly. |
| Pace marker | Closed ring, Usage bars | Optional per setting. Marks elapsed time in the paced window (5h, or weekly when there is no 5h). Ahead only when used > elapsed + tolerance (default 5 points, configurable). Colors per look: `{colors.a-dark-pace-on}` / `{colors.a-dark-pace-ahead}` (A), `{colors.c-dark-pace-on}` / `{colors.c-dark-pace-ahead}` (C); all user-configurable. Never raises an alert or sound. |
| Quota warning | Closed ring, Usage | Triggered only by the % threshold, never by pace. `{colors.a-dark-quota-warning}` (same default in C), always with hatched fill, triangle and `WARN`. Wins over pace-ahead on the same window. |
| Status glyph | Right wing, Agents tab, Home, peek | One per session. Encodes idle / working / done / blocked / failed by shape, motion, color. Two neutral looks: stale (dashed ring with `?`) and process-only (plain grey dot), static, no hue. → [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7b) |
| Status vocabulary | Any module that reports a level: script status widgets, side slot, script page; first- and third-party modules | Shared primitive: OK (ring, idle hue), WARN (triangle, quota-warning yellow), DOWN (×, failed hue), always with the label. Modules pass a level, never a color. Follows the user's status-color settings. Never raises an alert by itself (script alerts are deferred). → [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7d) |
| Overflow count | Both wings | Right: `+X` for sessions that don't fit; never hides a blocked or failed session while a lower-urgency session is visible. When blocked and failed sessions outnumber the slots, the most recent fill every slot and `+X` counts the rest, with no new visual (SPEC §14.17, epics A19). Nothing else on the wing counts sessions. Left: `+X` for left-wing items that don't fit (lower priority); never covers an item in alert (e.g. a quota warning) while a lower one is visible. |
| Peek alert panel | Blocked, failed, done; sleep summary; quota warning if set to alert; Timer end; break due; calendar reminder | Plays once per event; dwell `{motion.peek-dwell}` (5 s default, configurable). Hover pauses the dwell. Optional secondary reminder after a configurable delay. Two actions, except the break peek (three: see Time). Never takes focus. Shortcuts registered globally only while visible; each button's accessibility label includes its shortcut. Every peek posts a VoiceOver announcement (kicker, title, primary shortcut). After dwell, the panel retracts; the glyph (or the `BREAK DUE` readout) keeps the state in the closed notch. Variants: **quota warning** [ASSUMPTION: copy] kicker `QUOTA · WARN`, title `<PROVIDER> · <WINDOW> 82 %` (Account appended when the provider has several), triangle beacon in the quota-warning hue, `OPEN USAGE ⌥⌘↵` / `DISMISS ⌥⌘⌫`; **sleep summary** (several sessions interrupted) failed hue and × beacon, kicker `FAILED · HOST SLEPT`, title `<n> sessions interrupted by sleep`, `OPEN AGENTS ⌥⌘↵` / `DISMISS ⌥⌘⌫`; **calendar reminder** (see Calendar) kicker `CALENDAR · IN 10 MIN` (`CALENDAR · NOW` at start time), title the event title, detail time range and calendar, `JOIN CALL ⌥⌘↵` when the event has a video link [ASSUMPTION] else `OPEN CALENDAR ⌥⌘↵`, then `DISMISS ⌥⌘⌫` [ASSUMPTION: copy]. → [`mockups/key-alert-variants.html`](mockups/key-alert-variants.html) |
| Setup-problem alert | Adapter/CLI version unsupported, invalid config, missing permission | Same peek frame and dwell, neutral styling. Actions: `Open settings ⌥⌘↵` (opens the relevant pane, named in the alert) and `Dismiss ⌥⌘⌫`. |
| Action button | Peek, Agents (Focus), Calendar (Join call), empty states | Focus brings the session's exact terminal tab forward (SPEC §7.1.1); falls back to activating the terminal app. Dismiss retracts the peek and cancels the reminder for that event; it does not change the session state. |
| Dwell timer | Peek | Drains over the dwell; pauses on hover. |
| Settings gear | Expanded view, far right of the tab row, every tab | Click, or `↵` when it has keyboard focus, opens the Settings window (same as `⌘,`). Reached by Tab / `←→` in the tab row; `←→` moves focus without activating a tab, `↵` / Space activates. Not a tab: never active, no `⌘1–9` slot. Hover shows the macOS tooltip `Settings (⌘,)`. Accessibility label `Settings`. → [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7a) |
| Expanded panel | Click / expand shortcut | Opens on Home. Takes keyboard focus only when opened deliberately. Closes on click outside, Esc (when focused), or the shortcut again. Hover-to-open / leave-to-close are opt-in. Dense, HUD-like information. |
| Tab bar | Expanded | `⌘1…9` switches tabs when focused (SPEC §10). Tab with an alert carries a marker (Agents for a blocked or failed session, Time while a break is due or an ended timer is unacknowledged); its accessibility label adds "needs attention" ("Agents, needs attention"). |
| Widget card | Home | One fixed card size in v1, no spans (decided 2026-11-07). The user ticks widgets (modules and scripts) and drags them into order in Settings › Home; Home has no in-place edit mode. Romain's set: sessions, quota, shelf, script results. Click on a card opens its tab (PRD FR-7). |
| Session row | Agents tab, Home sessions widget | Agent, project, last action, terminal (only when sessions span more than one terminal app), status `· T+`. A `vigie run` session shows agent `RUN` and the command as its last action (Flow 6). Sorted by urgency. Hover shows `FOCUS`; click anywhere on the row or ↵ on the selection = Focus. No other action: Vigie never acts on the user's behalf. → [`mockups/key-agents-tab.html`](mockups/key-agents-tab.html) |
| Usage provider card | Usage tab | One card per Account (PRD FR-29). Header: provider, plus the Account name when the provider has several (`CLAUDE · WORK`). Ring + one bar per window with reset time, elapsed %, pace label, threshold tick. Remote limits that failed show the last value with `STALE · 14:02` [ASSUMPTION: copy], never a wrong number (FR-30). Order is user-set: drag the grip, or reorder in Settings. → [`mockups/key-usage-tab.html`](mockups/key-usage-tab.html) |
| Drop display | A file dragged over the notch from any app | Appears only while the drag is over the notch; grows out of it without taking focus and without opening the expanded view. Layout B: Stash (primary, 2 × 2), Ask AI (1 × 2), AirDrop and Image to Text (1 × 1 each). Disabled zones are hidden and the grid reflows. Hovering a zone lights it and shows its release line (`RELEASE TO STASH`, `RELEASE TO ASK`, `RELEASE TO SHARE`, `RELEASE TO COPY TEXT` [ASSUMPTION: wording, as in DESIGN]), set at label size in place of the meta line. Release on a zone = drop; Esc, or releasing outside any zone, cancels; dragging away from the notch and display closes it with no action. Zones that can't take the item stay unlit. Shelf disabled: Stash, AirDrop and Image to Text are gone and Ask AI stays while `agents.sessions` is on; with no enabled zone, no drop display appears. Each zone has a VoiceOver label, e.g. "Stash, keep 7 days, 5 items", "Ask AI, Claude Code in ~/dev, Option for alternate folder". → [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7c) |
| Drop zone | Drop display; Shelf tab (`SEND TO` card); Home shelf widget | Stash stores (SPEC §7.3). Ask AI launches the default agent in a new terminal tab with no dialog (Flow 4). ⌥ while dropping on Ask AI uses the alternate folder. AirDrop opens the macOS AirDrop picker for the dropped items (on by default). Image to Text recognizes the text of an image or PDF on the Mac and copies it (off by default). Inside the expanded view, stash items (the only drags that reach it) can be dragged onto Ask AI, AirDrop or Image to Text in the `SEND TO` card. Non-drag paths reach the same zones: the `Send to` menu on a Shelf item, `⌘V` on the Shelf tab (Stash), and the macOS Services entry `Stash in Vigie` (see Shelf). → [`mockups/key-shelf-tab.html`](mockups/key-shelf-tab.html), [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) |
| Copied readout | Left wing, after a drop on Image to Text | `READING…` while recognition runs (e.g. a multi-page PDF), then `COPIED · N LINES` for 2 s with a draining line, then normal. `NO TEXT FOUND` when nothing was recognized (clipboard unchanged). Holds while the pointer is over the notch. Posts a VoiceOver announcement ("Copied 3 lines" / "No text found") and leaves `LAST · 3 LINES · 14:48` as the Image to Text meta in the `SEND TO` card. No peek, no sound; the right wing is never touched. |
| Shelf row | Shelf tab, Home shelf widget | Drag out = move; ⌥-drag = copy. Space = Quick Look. Hover shows Quick Look / Reveal / Pin. Right-click, or `↵` on the selected row, opens the `Send to` menu; the same entries are VoiceOver custom actions. Pinned items never expire. |
| `Send to` menu | Shelf row (tab and Home widget) | Native menu: Ask AI, Ask AI in alternate folder, AirDrop, Image to Text (enabled zones only), then Quick Look, Reveal, Pin / Unpin. Same result as dragging the item onto that zone of the `SEND TO` card. |
| `SEND TO` card | Shelf tab, right column | Ask AI (shorter, still naming default agent, default folder and ⌥ folder), AirDrop and Image to Text below; disabled zones hidden. Takes dragged stash items; the `Send to` menu is its keyboard equivalent. |
| Month grid | Calendar tab | Click a day: the upcoming list starts at that day. `‹ ›` change the month shown (grid only; the list keeps its day). Header dot returns to today and the current month. → [`mockups/key-calendar-tab.html`](mockups/key-calendar-tab.html) |
| Upcoming list | Calendar tab | From now (or the selected day) onward, grouped by day, at most 5 events, then `+N LATER`. Next event as hero with countdown. `JOIN CALL ↵` only when the event has a video link; it is a user-triggered action. |
| Event track | Calendar hero row, Home calendar card | Now → event track with countdown (SPEC §7.5). |
| Script widget | Home, closed-notch side slot, script page | Renders one of three v1 types: status, number, short text. No lists. Status uses the status vocabulary (OK / WARN / DOWN + detail + when checked). Script-raised alerts deferred. Side slot: an item on the left-wing lane by the script's priority (overflow in `+X`), level over target. → [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7d) |
| Time readout | Left-wing item lane, by its priority (`closed_notch = "time" \| "ring" \| "both"`) | Nearest-to-end running item. Setting: remaining time, ring, or both. Pomodoro shows its phase label (`WORK · 2/4`). Redraws at most once per second. Ring-only adds a center mark when not running: a pause glyph for Away, a small triangle for Break due. `BREAK DUE` shows even when `closed_notch = "off"` (see Time). |
| Phase indicator | Time tab, Pomodoro readout | Pips for the 4 cycles: done filled, current ringed (hatched during a break), upcoming a hollow ring. VoiceOver reads "Work, cycle 2 of 4". |
| Time tab | Expanded · Time | Quick start on top: Pomodoro, 5 / 10 / 25 min presets, `+ COUNTDOWN` (to a clock time) [ASSUMPTION: chip label], custom minutes + `START ↵`. Running items below, sorted by end time, each with Pause (Resume) / Reset / Remove; a Countdown has only Remove. A break-due row shows `START BREAK` (primary), `SNOOZE 5M`, `SKIP`; an ended timer stays as `ENDED 14:48` with `DISMISS` until acknowledged. Keyboard: see Time. → [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7e) |
| Notes panel | Global notes shortcut | Floating panel; takes keyboard focus (deliberate open). See Notes. → [`mockups/key-notes.html`](mockups/key-notes.html) |
| Notes tab | Expanded · Notes | Notes list with search and preview of the selected note; `↑↓` move the selection when focused. List summaries show only how many secrets a note holds. |
| Side-slot item | Left-wing lane | A script's level (or value) over its target, by the script's `priority`; overflow in `+X`. Accessibility label leads with the module ("vigie.app, OK"). Clicking the closed notch still opens Home. |
| Script page | Expanded · tab named after the script | Large widget, `ABOUT · FROM <file>` documentation, runs card, `REVEAL` / `OPEN SOURCE` chips. Tab order: hero → About → runs → chips. Hero label e.g. "vigie.app, OK, up, 200, 142 ms, checked 2 minutes ago". |
| Script Confirmation | Window, on install link, sync arrival or update | Shows signature state (`Verified: Vigie Script repository`, or a stronger warning for unsigned, invalid-signature or other-site scripts, with the author "claimed by the file"), source URL, the whole file (or, for an update, the diff from the confirmed version), the plain "runs with your user rights, unsandboxed" line, secret fields, `Confirm` and `Decline`. Takes focus (deliberate). Decline leaves no file behind. |
| Secret mask | Notes | Masked at a fixed width. Click toggles reveal. `COPY` copies without revealing; the clipboard is cleared after a configurable delay. |
| Setup card | A tab whose module lacks a permission (e.g. Calendar access) | In-tab, neutral; buttons to System Settings and the module's settings pane. |
| Empty state | Tabs, closed right wing | Label, one factual sentence, and a button to the relevant Settings pane where one helps. Uses DESIGN's Empty state block. |
| Privacy redaction | Every surface while Privacy mode is on | User-supplied names and text render as fixed-width dots in the secret-mask style; glyphs, rings, T+ and numbers stay (see Privacy Mode). |

## State Patterns

### Session states

| State | Entered on (normalized events, SPEC §7.1) | Closed notch | Alert |
|---|---|---|---|
| idle | `session.start`; done after a configurable delay (default 15 min) | Static glyph | None |
| working | `prompt.submit` (also from done), `tool.*`, `subagent.end` | Animated glyph | None |
| done | `turn.end` | Static glyph | Once ("finished" alert setting) + optional reminder |
| blocked | `needs.input` | Top-priority glyph | Once + optional reminder |
| failed | Connection lost, login required, host went to sleep (local sessions) | Top-priority glyph | Once + optional reminder |
| gone | `session.end`, liveness check fails | Removed | None |

- **Done → idle** happens only after the delay. No hook can tell that the user has read the reply; a new prompt moves the session to working, not idle. Focusing or dismissing does not change the state.
- Blocked and finished alerts have separate settings that behave identically for now. Failed has its own setting, same behavior. Failed actions: Focus / Dismiss.
- **Urgency order** (closed notch and Agents tab): blocked and failed (shared top priority, most recent first) > done > working > idle. Working needs the least attention among active states. The closed notch shows the latest active sessions in this order; the rest go to `+X`.
- **More blocked/failed sessions than slots:** the most recent fill every slot and `+X` counts the rest; no new visual (SPEC §14.17, epics A19).
- **`vigie run` sessions** (PRD FR-23): a command run as `vigie run -- <command>` is a Session like any other: working while it runs, done on exit code 0, failed on any other (`FAILED · EXIT 2`), same alerts and Focus. Ctrl-C passes to the command and ends the Session with no alert (gone).
- **T+** counts from entering blocked or failed (from wake for host-slept) and keeps running after the alert. Done has no T+.
- **Stale** (no hook event for `stale_after`, SPEC §7.1) and **process-only** (agent process seen, no hook event ever, SPEC §8.3) keep SPEC behavior and have their own neutral looks (decided 2026-11-07, Story 1.7b, Option 3): stale = dashed ring with `?` inside, label `STALE · 18M` (time since the last event), last-action line `LAST EVENT 14:30 · <action>`; process-only = plain grey dot, label `RUNNING`, line `Process seen · no hook events`. Both are static, never use a status hue, never alert, and sort after idle. Focus still works on them. The next hook event returns a stale session to its real state. Accessibility labels: "<project>, stale, no event for 18 minutes" and "<project>, running, no status available" [ASSUMPTION: label wording]. → [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7b)

→ [`mockups/key-closed-notch-states.html`](mockups/key-closed-notch-states.html) (state h, priority), [`mockups/key-alert-variants.html`](mockups/key-alert-variants.html).

### Surface states

| State | Surface | Treatment |
|---|---|---|
| No agent connected | Closed right wing; Agents tab, Home sessions widget | Right wing shows only `NO AGENT CONNECTED`; left wing black (no provider). Click opens the expanded empty state (Empty state block): "Connect Claude Code, Codex or Gemini in Settings." with `Open settings`, leading to Settings › Agents. |
| Nothing running | Same surfaces | Different label: `NO ACTIVE SESSIONS`; quota rings stay. Expanded copy: "Agent sessions appear here when they start." |
| Home empty | Home | No widget chosen: `NO WIDGETS` + "Pick Home widgets in Settings." with `Open settings`, leading to Settings › Home [ASSUMPTION: copy]. |
| Setup problem | Setup-problem alert; setup card in a tab | Adapter or CLI version unsupported (SPEC §14.5), invalid config (SPEC §11 keeps last valid config), denied permission (SPEC §4.3). Own neutral UI, never an agent state. |
| Quota warning | Closed ring, Usage | Threshold configurable per provider (default 80%). User chooses: alert (quota-warning peek + optional sound) or visual change only. % only, never pace. |
| Several Accounts | Closed ring, Usage | The ring shows the Account of the most recent Session; the Usage tab shows one card per Account; each Account has its own settings (Settings › Usage) (PRD FR-29). |
| Remote limits stale | Closed ring, Usage card | Fetch failed: the last known value stays with `STALE · 14:02` on the card [ASSUMPTION: copy] and the ring keeps its value; never a wrong number (FR-30). |
| Usage loading / day one | Usage tab | Before the first read: `READING LOGS…` [ASSUMPTION]. `HISTORY · 7D` with no data: `NO HISTORY YET`; `COST · TODAY` unavailable: `—` with `NO COST DATA` [ASSUMPTION: copy]. |
| Pace ahead | Closed ring, Usage bar | Used > elapsed + tolerance. Visual only. Hidden under quota warning on the same window. |
| Window absent | Closed ring, Usage | Show only the windows the plan has (5h, weekly, daily); no empty ring. Pace runs on the weekly window when there is no 5h. |
| No usage provider | Usage tab | `NO USAGE PROVIDER`, one sentence, `Open settings ⌘,` [ASSUMPTION: copy and shortcut]. |
| Interrupted by sleep | Right wing, Agents, peek | On wake, local sessions that were working when the Mac slept become failed (`FAILED · HOST SLEPT`, `Run interrupted during …`) and raise one failed alert for the wake: the usual alert with `FOCUS TERMINAL` for a single session, or a summary `<n> sessions interrupted by sleep` with `OPEN AGENTS` for several (decided 2026-11-06). |
| Overflow | Both wings | `+X`, never hides a blocked or failed session (right) or an item in alert (left) while a lower-urgency one is visible. |
| Peek concurrency [ASSUMPTION] | Peek | One peek at a time. A newer blocked or failed alert replaces a visible peek of lower urgency; other alerts queue by urgency (blocked / failed > break due / Timer end / calendar reminder > quota warning > done > setup problem) and show after the current dwell; a queued alert whose state has resolved is dropped. While the expanded view is open no peek shows: the tab marker shows instead (sound follows the alert rules). While the drop display is open, peeks wait until it closes. |
| Shelf item expiring | Shelf row, Shelf card meta, Home shelf widget | 24 h before expiry: visual warning (quota-warning yellow + triangle, `EXPIRES IN 5H`). Optional macOS notification (setting, off by default). No sound. |
| Shelf item expired | Shelf | References (bookmarks/aliases) leave the shelf, file untouched. Copies and saved text/URL/image items go to the Trash. Nothing is deleted permanently. |
| Stash empty | Shelf tab | `STASH EMPTY` + "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for N days." [ASSUMPTION: copy]. Ask AI stays usable. |
| Drop failed | Left wing | Stash or AirDrop could not take the item (unreadable file, disk full): `NOT STASHED` / `AIRDROP UNAVAILABLE` for 2 s like the `COPIED` readout, plus an activity-log entry [ASSUMPTION: copy]. Image to Text that can't read the file: `NO TEXT FOUND`. |
| Shelf disabled | Drop display, Shelf paths | Stash, AirDrop and Image to Text disappear (they are Shelf zones); Ask AI stays while `agents.sessions` is on. With no enabled zone no drop display appears. `⌘V` and `Stash in Vigie` need the Shelf on. |
| Calendar access missing | Calendar tab | Setup card: `Vigie can't read your calendars`, buttons `Open System Settings` and `Calendar settings` [ASSUMPTION: copy]. |
| No events today | Calendar tab | Grid stays, no dot on today. List shows `NO EVENTS TODAY`, then the following days. |
| Calendar reminder | Peek, Calendar tab | At each alarm time set on the event in Calendar (EventKit), a reminder peek (Calendar section); events without a reminder raise nothing. Nothing persists in the closed notch after the peek retracts. DND / macOS Focus mode suppresses it; with replay after Focus, the latest reminder for an event not yet over shows as a normal peek [ASSUMPTION: unresolved until the event ends]. |
| Script status level | Status widget, side slot, script page | OK / WARN / DOWN from the script's output, shown with the shared status vocabulary (shape + hue + label) and when it was checked; `DOWN SINCE 14:44` while down. No alert (script alerts deferred). |
| Script errored or timed out | Script widget, side slot, script page | Keep last good output with a warning badge (SPEC §9.2); the page's runs card shows the exit code or `TIMED OUT · 30S` [ASSUMPTION: copy]. |
| Script awaiting confirmation | Script widget, side slot, script page, Settings › Scripts | Not running until confirmed on this Mac: `NOT CONFIRMED` in `ink-3`, no level glyph; click opens the Script Confirmation [ASSUMPTION: copy]. |
| Script never run | Script widget, side slot, script page | Confirmed, first run pending: `WAITING · FIRST RUN` [ASSUMPTION: copy], no level glyph. |
| Script update available | Script widget, script page, Settings › Scripts | `UPDATE AVAILABLE` badge (epics A88); the confirmed version keeps running until the new one is confirmed (PRD FR-43). |
| Image to Text result | Left wing | `READING…` while recognition runs; `COPIED · N LINES` for 2 s after the text is on the clipboard; `NO TEXT FOUND` when nothing was recognized (clipboard unchanged). Never a peek or a sound; a VoiceOver announcement is posted. |
| Drop display open | Drop display | Only while a file is dragged over the notch. Esc or a release outside every zone cancels; leaving the notch area closes it. Opening it never takes focus. |
| Time · nothing running | Time tab | Quick start stays; the running list shows `NOTHING RUNNING` [ASSUMPTION: copy]. The closed readout is hidden. |
| Time · away | Time tab row, closed readout | Away during a Pomodoro work phase pauses it: ring and value freeze, `AWAY · PAUSED`, `PAUSED 14:31`, and Pause becomes Resume. It resumes on its own when the user is Present again; Resume resumes it at once. Time Away does not count as work for break reminders (PRD FR-49). |
| Time · break due | Left wing, Time tab | A break reminder or a Pomodoro work-phase end: after the break peek retracts (or at once with strength "quiet"), the left wing shows the `BREAK DUE` readout (full dashed ring, `15:00` over `BREAK DUE`, static) as a left-lane item in alert state, **even when `closed_notch = "off"`**, until the break is started or skipped. Snooze keeps it showing and re-raises the peek after 5 min. The Time tab row shows `START BREAK` (primary), `SNOOZE 5M`, `SKIP`, and the Time tab carries the attention marker. For a break reminder, Away for the break length also counts as the break. A Pomodoro break never starts on its own. Break due counts as an unresolved alert for `[notify] after_focus = "replay"`. With strength "quiet": no peek, no sound. |
| Time · ended | Time tab, peek | A Timer or Countdown end raises the Timer-end peek; the Time tab keeps the row as `ENDED 14:48` with `DISMISS` until acknowledged. An end that passed while the Mac slept raises its alert once on wake (PRD FR-45). A Pomodoro break end raises a Timer-end-style alert [ASSUMPTION: kicker `BREAK · ENDED`] and work resumes on its own (FR-48). |
| Time · Pomodoro running | Break reminders | Break reminders are paused while a Pomodoro runs; its own breaks replace them (PRD FR-49). |
| Focus fails | Peek, Agents | Terminal app activates without selecting the tab (SPEC §7.1.1). No error toast [ASSUMPTION]. |
| Do Not Disturb / macOS Focus mode | Peek, sounds | Follows the OS: alerts and sounds suppressed, closed notch still updates (SPEC §5.2). No bypass option. When the macOS Focus mode ends, missed alerts are dropped by default; a setting shows instead the latest unresolved alert per module, as normal peeks (a due break counts as unresolved). |
| Privacy mode | Every surface | See Privacy Mode: user-supplied names and text become fixed-width dots; glyphs, rings, T+ and numbers stay; macOS notifications carry only the kind label. |
| Notes empty / no match | Notes tab, floating panel | No notes: `NO NOTES` + "Press ⌥⌘N to write one." No search result: `NO MATCH`. [ASSUMPTION: copy] |
| Notes not set up | Floating panel, Notes tab | First use: `Set up notes` creates the notes key (architecture D3). On a new Mac where a key may exist in iCloud Keychain: `NOTES LOCKED` + "Waiting for iCloud Keychain, or enter your recovery key." Never a second key. [ASSUMPTION: copy] |
| Notes sync conflict | Notes tab | Both versions kept; the second is saved as `<title> (conflict)`; no text is lost (user ruling 2026-11-07, AD-10). |
| Full-screen app | Closed notch | Inherited: hidden on that display (SPEC §5.4). |

## Interaction Primitives

**Never steal focus.** The user must never end up typing into nowhere. Vigie panels are non-activating by default.

| Interaction | Rule |
|---|---|
| Hover on closed notch | Small reaction inside the island over `{motion.enter}`. Opens on hover only if the user enabled hover-to-open. Hover zone follows SPEC §5.5 on plain displays. |
| Click on closed notch | Opens the expanded view on Home and takes keyboard focus. |
| Click outside expanded | Collapses. Leave-to-close is opt-in. |
| Global expand shortcut | Opens and takes focus (deliberate). Default per SPEC §11 `expand_hotkey`. |
| Keyboard in expanded (only when focused) | `⌘1…9` tabs, `↑↓` move the selection in lists, `↵` acts on it (Focus, Join call, Start on the Time quick start, Start break on a break-due row, the `Send to` menu on a Shelf row), Space = Quick Look on the Shelf, `⌘V` on the Shelf stashes the clipboard, Tab / `←→` reach the settings gear in the tab row (`←→` moves focus, `↵` / Space activates), Esc closes. Time tab keys: see Time. |
| Opened any other way (alert, drag) | No keyboard focus; no non-global shortcuts. |
| Peek shortcuts | `⌥⌘↵` primary (Focus terminal, Open settings on a setup alert, Open Usage on a quota warning, Open Agents on the sleep summary, Open Time on a Timer end, Start break on a break peek, Join call or Open Calendar on a calendar reminder), `⌥⌘⌫` Dismiss (Skip on a break peek), `⌥⌘Z` Snooze 5m (break peek only). Global, registered only while the peek is visible, unregistered on retract; each is shown on its button. Never bare Esc or other common keys. |
| Drag a file from any app | Nothing happens until the drag reaches the notch. Over the notch, the drop display grows out of it (layout B: Stash, Ask AI, AirDrop, Image to Text) without taking focus. Hovering a zone lights it with its release line; releasing on a zone drops; Esc or releasing outside every zone cancels; leaving the notch and display closes it. The expanded view collapses on focus loss, so it is never the drop target for outside drags. |
| ⌥ while dropping on Ask AI | Uses the alternate-folder setting; the zone shows the hint. |
| Drag a stash item onto Ask AI (Shelf tab) | Same launch as a notch drop; ⌥ = alternate folder. AirDrop and Image to Text in the `SEND TO` card take stash items the same way. |
| `Send to` menu | Right-click a Shelf item, or `↵` on the selected row: Ask AI, Ask AI in alternate folder, AirDrop, Image to Text (enabled zones only), Quick Look, Reveal, Pin. Same entries as VoiceOver custom actions. |
| `⌘V` on the Shelf tab | Stashes the clipboard (files, image, text, URL) like a Stash drop. |
| Services › `Stash in Vigie` | macOS Services entry in Finder and any app (files and text): stashes the selection without dragging or opening Vigie. With the Shelf off, it raises a setup-problem alert `Shelf is off` with `Open settings` [ASSUMPTION]. A Share extension is not in v1 [ASSUMPTION]. |
| Drag a stash item out | Move; ⌥ = copy (Finder convention). The two ⌥ meanings are accepted: ⌥ on drag-out = copy, ⌥ on Ask AI drop = alternate folder. |
| Drag a provider card | Reorders the Usage list; same order as in Settings. |
| Calendar day click | Upcoming list starts at that day. `‹ ›` change month; the lit header dot returns to today. |
| Secret click | Toggles reveal. `COPY` copies without revealing. |
| Notes shortcut | Global; opens the floating notes panel with focus. Esc closes. |
| Theme / Presence mode change | Applies live, no restart. |

Banned: acting on a session on the user's behalf (approve, deny, send), mascots, auto-opening the expanded view, taking focus on alerts, bypassing Do Not Disturb.

## Accessibility Floor

Behavioral; contrast lives in `DESIGN.md` Colors. v1 is a proof of concept: minimum floor, full VoiceOver experience deferred to v2.

- Every control and glyph has a correct accessibility label with state, e.g. "vigie / api-refactor, blocked, 2 minutes" [ASSUMPTION: label format]. The settings gear reads "Settings"; a side-slot item reads its module, level and target (e.g. "vigie.app, OK"); the Time readout reads the item and the remaining time; drop zones read their role and target ("Stash, keep 7 days, 5 items"); peek buttons include their shortcut.
- **Announcements:** panels never take focus, so every peek posts a VoiceOver announcement (kicker, title, primary shortcut), and the Image to Text readout announces "Copied 3 lines" / "No text found".
- **No drag required:** every drop zone is reachable without dragging: the `Send to` menu and VoiceOver custom actions on Shelf items, `⌘V` on the Shelf tab, and Services › `Stash in Vigie`.
- System settings win. **Reduce motion** removes animations from v0.1 (state changes are instant or a short cross-fade); once Presence mode exists it also forces Calm mode and stops loops; the settings window shows a warning that explains the override. Functional drains (peek dwell line, `COPIED` drain, notes clipboard drain) become a static full line that disappears at the end. The Time peek rim, the Ask AI breathing `+`, the card iris filament and the drop display rim are static. [ASSUMPTION] The remaining attention pulse becomes an opacity change with no scale; T+ counters show static values.
- **Reduce transparency** and **Increase contrast** are honored: glass gradients become flat `surface-panel` / `surface-card` fills [ASSUMPTION]; Increase contrast follows the table in `DESIGN.md` (zone, chip and card borders solid `ink-3`, focus ring 2px).
- Color is never the only cue: each session state has a distinct shape and a text label (stale and process-only have their own shapes and labels and no hue); module levels use the status vocabulary (shape + label); quota warning adds hatch, triangle and `WARN`; pace-ahead adds `AHEAD OF PACE`; shelf expiry adds a triangle and text; Time work vs break is solid vs dashed arc plus label.
- Status, pace and quota-warning colors are user-configurable per look.
- Light-mode text reaches at least 4.5:1 and non-text UI 3:1 (`DESIGN.md` Contrast). Warning text in A light and C light uses `quota-warning-text`; the `quota-warning` yellow is for fills and triangles.
- Time ring-only readout: Away and Break due add a center mark (pause glyph, triangle), so they never rely on color alone.
- Keyboard: every expanded-view action is reachable when it has focus; peek actions are reachable through the global shortcuts (including `⌥⌘Z` Snooze on the break peek). A missed break peek leaves `BREAK DUE` on the left wing and Start break / Snooze / Skip in the Time tab.
- Secrets are never shown in list summaries; the mask has a fixed width.

## Responsive & Platform

| Context | Behavior |
|---|---|
| Physical notch | Island is the hardware notch: always black, dark tokens, in both appearances. |
| Plain display, `style = black` | Virtual notch looks like the hardware notch. |
| Plain display, `style = menu_bar` | Takes the menu-bar material; in light mode, light material and light tokens. In dark mode it falls back to the black island look until dark virtual-notch tokens exist [ASSUMPTION] (Open Question 15). |
| Island display | Plain/fallback mode until the island spike (SPEC §14.10). |
| Multiple displays | SPEC §5.4: every notch shows the same state; expanded view and peeks appear only on the display under the cursor. |
| Light / dark | Follows macOS unless forced. Peek and expanded keep a 34px black band; body switches material. |
| Hot-plug, lid, resolution | Placement re-runs live (SPEC §5.4). |
| Touch | Open question (SPEC §14.12). |

## Inspiration & Anti-patterns

- **Lifted from Notchi:** the circular quota ring in the closed notch.
- **Lifted from Claude-Usage-Tracker:** the pace bar with an elapsed-time marker that changes color when consumption outpaces time (`imports/ref-claude-usage-tracker-pace-bar.png`).
- **Lifted from Itsycal:** the compact month grid (`imports/ref-itsycal-month.png`).
- **Lifted from sci-fi HUDs:** thin tick rings, tick scales, uppercase readouts (`imports/ref-gods-eye-hud.png`), as aesthetic only.
- **Rejected — mascots/avatars** (GrokBot, Notchi, Coucou): no personification.
- **Rejected — single-session tracking** (Notchi): every session is visible.
- **Rejected — military targeting:** reticles, crosshairs, radar rings (`imports/feedback-c-peek-crosshair-overkill.png`).
- **Rejected — HUD spilling over the menu bar** (`imports/feedback-v2-still-outside-notch.png`): strict containment.
- **Rejected directions:** Gold Command Bridge, Liquid Alloy.

## Key Flows

### Flow 1 — Multi-session day (Romain, solo developer, 3–10 sessions open, 2–4 active)

Core pain: keeping track of several concurrent agent sessions and the Claude 5h/weekly quota.

1. Romain starts Claude Code in four terminal tabs and Codex in one, all in Warp. The right wing fills with glyphs: three slots in urgency order, most urgent nearest the notch, then `+2`.
2. The left wing shows one ring per provider, names underneath: Claude with nested 5h + weekly rings, Codex with its own. The pace tick sits ahead of the arc: he is within pace.
3. He works in his editor. Working arcs turn; nothing else asks for him.
4. `vigie / api-refactor` asks to run `npm run db:migrate`. The session turns blocked; its diamond takes the slot nearest the notch, pushing a working session into `+X`.
5. **Climax:** the peek grows out of the notch once: `BLOCKED · NEEDS INPUT`, `T+` counting, the command, `FOCUS TERMINAL ⌥⌘↵`. His editor keeps focus; the keystroke he was typing lands in the editor. He presses `⌥⌘↵`; the exact terminal tab comes forward. He approves in the terminal himself. Vigie only helped him find it.
6. The peek retracts after 5 s; the session returns to working. Later another session ends its turn: a done alert plays once, and the glyph turns to ring + check. Fifteen minutes later, with no new prompt, it settles to idle.
7. In the afternoon he opens the expanded view by click. Home shows sessions, quota, shelf and his GitHub PR count. On Agents (`⌘2`) the list has no terminal column, since everything runs in Warp. He closes it with Esc.

Failure paths: he misses the peek → the blocked glyph stays in the notch, the Agents tab marker stays, `BLOCKED · 12M` keeps counting, and the optional reminder replays after the configured delay. Terminal tab can't be located (e.g. Warp, SPEC §14.1) → the terminal app activates without selecting the tab. Do Not Disturb is on → no peek, no sound; the glyph still changes.

→ [`mockups/key-closed-notch-states.html`](mockups/key-closed-notch-states.html), [`mockups/key-alert-variants.html`](mockups/key-alert-variants.html), [`mockups/key-agents-tab.html`](mockups/key-agents-tab.html)

### Flow 2 — Wake after sleep (Romain, lid closed with an agent working)

1. `infra / backup` is working when Romain closes the MacBook lid to leave. Keep-awake (opt-in) does not cover lid close or manual sleep.
2. Sleep kills the local agent mid-run.
3. He opens the lid an hour later.
4. **Climax:** Vigie detects that the session was working when the Mac slept and marks it failed: orchid × (A) stuttering in the top-priority slot, a failed peek `FAILED · HOST SLEPT` with `T+` counting from wake, the interrupted command, and `FOCUS TERMINAL`. Without Vigie, nothing would have reminded him.
5. He focuses the tab and restarts the run.

Failure path: several sessions were interrupted → each becomes failed, and one summary alert plays for the wake: `<n> sessions interrupted by sleep` with `OPEN AGENTS ⌥⌘↵`; the most recent take the slots. Research item: whether macOS allows a warning before a user-initiated sleep while agents work.

### Flow 3 — First week (Léa, backend developer, MacBook Pro 14 + 27-inch external)

Léa uses Codex CLI for work and Claude Code for a side project, both in iTerm2. Romain invited her to try Vigie before its public release.

1. She installs it from the `homebrew-vigie` tap (`brew tap <org>/vigie`, then `brew install --cask vigie`) [ASSUMPTION: org name].
2. First launch opens onboarding. **Theme:** she sees Chrome Hologram and Twin Metal Tactical live and keeps A (the default if skipped).
3. **Agents:** Vigie detects Codex and Claude Code and shows the hook config diff for each (SPEC §8.3); she approves both.
4. **Accessibility permission:** she grants it so Vigie can focus terminal tabs.
5. **Displays:** Vigie asks about non-notch displays even though her MacBook has a notch. She enables a virtual notch on the 27-inch.
6. **Sounds:** she enables them.
7. Two days later, she is typing a message in Slack on the external display. A Codex session needs approval.
8. **Climax:** the peek appears on the display under her cursor; Slack keeps focus and her sentence is intact. She presses `⌥⌘↵` and the exact iTerm2 tab comes forward.

Failure paths: she skips the Accessibility step → Focus activates iTerm2 without selecting the tab, and a setup-problem alert explains the missing permission [ASSUMPTION]. Installed Codex version unsupported → setup-problem alert `Codex adapter: CLI version 0.9.2 unsupported` with `Open settings` and `Dismiss`; no wrong statuses (SPEC §14.5).

### Flow 4 — Ask AI drop (Romain, reading a log file in the browser)

1. Romain drags a downloaded log from the browser's download bar.
2. As the drag reaches the notch, the drop display grows out of it: Stash on the left half, Ask AI, then AirDrop (and Image to Text when enabled). Nothing took focus.
3. He hovers Ask AI (it lights and reads `RELEASE TO ASK`) and drops. No dialog.
4. **Climax:** a new terminal tab opens in the default folder (home, the dropped file's folder, or a custom folder) running his default agent, with the file attached or its path pasted into the prompt. He types his question there.
5. Variant: holding ⌥ while dropping uses the alternate folder setting.
6. Variant: he had stashed the log earlier. On the Shelf tab he drags it onto Ask AI; the zone reads `RELEASE TO ASK` and names the agent and folder. Without dragging, he selects the row, presses `↵` (or right-clicks) and picks `Send to › Ask AI`.

Failure path: the CLI can't start with an attachment or an unsent prefilled prompt → the path is pasted for him to complete (research item). Agent not installed → setup-problem alert [ASSUMPTION]. He changes his mind mid-drag → Esc, or releasing away from the zones, cancels.

→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7c, layout B), [`mockups/key-shelf-tab.html`](mockups/key-shelf-tab.html). The two-wing drop zones in `key-closed-notch-states.html` (state e) are superseded.

### Flow 5 — Script arrives via sync (Romain, second Mac)

1. On his MacBook, Romain writes a BugSink open-issues script as a Markdown file (front matter + one code block) and enables it as a Home widget. Its API token is a secret setting, stored in the Keychain.
2. iCloud sync carries the script file to his Mac Studio. The token does not travel.
3. On the Mac Studio, the widget appears in an "awaiting confirmation" state and does not run.
4. He opens it and sees the script's documentation, front matter and code [ASSUMPTION: confirmation shows the whole file, per SPEC §14.7].
5. **Climax:** he confirms and enters the token on that Mac; the script runs for the first time there and the widget shows `12` open issues.

Failure path: he declines → the script stays disabled on that Mac only. The script exits non-zero → last good output with a warning badge (SPEC §9.2).

### Flow 6 — Watch a deploy like an agent (Romain, `vigie run`)

PRD UJ-6: "Romain watches a deploy like an agent. He runs `vigie run -- make deploy`. The notch shows it working; ten minutes later it fails and peeks, and Focus takes him to the tab."

1. In a Warp tab, Romain runs `vigie run -- make deploy` and goes back to his editor. The command's output and exit code pass through unchanged.
2. A working glyph joins his agent sessions on the right wing, ranked by urgency like them. On the Agents tab the row reads agent `RUN`, the project folder, and `make deploy` as its last action.
3. Ten minutes later the deploy exits with code 2. The session turns failed and takes the slot nearest the notch.
4. **Climax:** the failed peek grows out of the notch once: `FAILED · EXIT 2`, `T+` counting, `make deploy`, `FOCUS TERMINAL ⌥⌘↵`. His editor keeps focus. He presses `⌥⌘↵`; the Warp tab with the error comes forward.
5. He fixes it and runs the command again. It exits 0: the session turns done and the done alert plays once, per his "finished" alert setting.

Failure paths: he interrupts with Ctrl-C → the signal goes to the command and the session ends with no alert (a user interrupt is not a failure). Vigie isn't running → the events are delivered on next launch (PRD FR-16). The tab can't be located → the terminal app activates without selecting the tab.

### Flow 7 — Install a community script (Léa, CI status script)

PRD UJ-7: "Léa installs a community script. On the Script repository she finds a CI status script and clicks its install link. Vigie shows the full file, its source and author; she confirms; the Widget appears. A week later an update arrives, Vigie shows what changed, and she confirms again."

1. On the Script repository, Léa finds a CI status script and clicks its `vigie://install` link in her browser.
2. Vigie downloads the file and opens the Script Confirmation window (deliberate, so it takes focus). The header reads `Verified: Vigie Script repository`, with the source URL and the author; below it, the whole file: documentation, front matter and code, and the plain line that scripts run with her user rights, unsandboxed.
3. She enters the script's CI token in its secret field; it goes to the Keychain on this Mac only.
4. **Climax:** she confirms. The script runs for the first time and its status widget appears on Home with its level and `CHECKED JUST NOW` [ASSUMPTION: copy].
5. A week later, the daily update check finds a new version. The widget and Settings › Scripts show `UPDATE AVAILABLE`; the confirmed version keeps running.
6. She opens it. The Confirmation shows the diff from her confirmed version and the signature state again. She confirms, and the new version runs.

Failure paths: the script is unsigned, its signature is invalid, or the link comes from another site → the Confirmation shows a stronger warning instead of `Verified`, and the author reads "claimed by the file"; the full file is still shown. She declines → nothing is written and no file is left behind. She ignores the update → the old version keeps running and the badge stays. The download fails → the Confirmation says so and offers nothing to confirm [ASSUMPTION].

### Flow 8 — Romain takes his break (break reminder)

PRD UJ-8: "Romain takes his break. With no Pomodoro running, after 55 minutes at the keyboard a break reminder peeks; he walks away; when he has been Away 5 minutes the break counts as taken and the cycle restarts without a click."

1. Romain has been working since 9:00 with no Pomodoro running. Break reminders are on with strength Peek (55 min of work, 5 min break). Time Away does not count as work.
2. At 9:55 the break peek grows out of the notch: `BREAK DUE`, `START BREAK ⌥⌘↵`, `SNOOZE 5M ⌥⌘Z`, `SKIP ⌥⌘⌫`. His editor keeps focus.
3. He presses nothing; he stands up and leaves. The peek retracts, and the left wing shows the `BREAK DUE` readout.
4. After 90 s without input he is Away.
5. **Climax:** once he has been Away 5 minutes, the break counts as taken: `BREAK DUE` leaves the left wing and the cycle restarts without a click.
6. He comes back; the next reminder comes after 55 more minutes at the Mac.

Variant (Pomodoro): Romain starts a Pomodoro instead, and break reminders pause. When the 25-minute work phase ends, the same break peek appears; the break waits until he presses `START BREAK` (peek or Time tab), counts down 5 minutes, and work resumes on its own with a break-end alert. Away during a work phase pauses it (`AWAY · PAUSED`).

Failure paths: he misses the peek (macOS Focus mode on, or he is away from the screen) → `BREAK DUE` stays on the left wing even with the closed-notch Time readout off, and the Time tab, with its attention marker, offers `START BREAK` / `SNOOZE 5M` / `SKIP`. He snoozes → the peek returns after 5 minutes and `BREAK DUE` stays. He stays at the keyboard → `BREAK DUE` stays and nothing escalates; `SKIP` counts no break and starts a new work cycle. He is Away less than 5 minutes → it counts as neither work nor break [ASSUMPTION].

→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7e).

## Presence Mode

Presence mode (PRD glossary) is the user setting for motion and glow, for people who find motion distracting; "Calm mode" means Presence mode set to calm. Visual specs in `DESIGN.md` Layout & Spacing → Presence mode (visual).

| Level | Behavior |
|---|---|
| Full (default) | Permanent presence: ambient loops, live glyph animation, reactions to background agent events. |
| Calm (lowest) | Static lines. Values update without transitions. One simple pulse when something is blocked or failed; otherwise nothing moves. |

Intermediate levels are not decided. Reduce motion forces Calm mode (Accessibility Floor). [ASSUMPTION] Presence applies to the closed notch, peek and expanded view alike; only the closed notch is mocked in calm ([`mockups/key-closed-notch-states.html`](mockups/key-closed-notch-states.html) state i).

## Sounds

- Fully optional; onboarding asks whether to enable them.
- Seven events: blocked, failed, done, quota warning, Timer end, break reminder, calendar reminder. Each configurable on/off and per sound file. Timer end, break reminder and calendar reminder are off by default (SPEC §11 `[sounds]`) [ASSUMPTION: calendar reminder off]. Pace never plays a sound; shelf expiry has no sound.
- Built-in sounds: sci-fi register, simple, under 1 s. Custom files per event, any length.
- Sounds play once with the alert and follow Do Not Disturb and macOS Focus modes; a reminder replays the sound [ASSUMPTION].

## Theming & Customization

- Theme family: Chrome Hologram (default) and Twin Metal Tactical built in; each has light and dark looks.
- Appearance: follows macOS by default; a setting forces light or dark.
- Choose the variant at onboarding; switch later in settings, live, with no restart.
- Custom themes extend the shared base (geometry, layout, motion grammar stay fixed) [ASSUMPTION: custom themes override token values only].
- User-configurable colors: every status color, pace on / ahead, quota warning.
- Closed-notch slots: 3 per side by default, configurable (max about 4). Left-wing item priority per item: each usage provider, each script, Time; lower ones collapse into `+X`. Quota rings: 5h only or 5h + weekly. Pace indicator on/off; pace tolerance (default 5 points).
- Usage provider order: drag on the Usage tab or reorder in Settings.
- Open/close behavior: click (default) or hover-to-open / leave-to-close.
- Peek dwell (default 5 s), secondary reminder delay, done → idle delay (default 15 min).

## Sync & Encryption

| Data | Where | Sync |
|---|---|---|
| Config and personalization (theme, Presence mode, colors, alert and sound settings) | Config folder | iCloud, optional |
| Machine-specific settings (displays, virtual notch, terminal, …) | Local | Never synced |
| AI auth tokens, script settings marked secret | Keychain (SPEC §4.4) | Never synced |
| Script modules | Config folder, readable Markdown | Via sync; confirmation required on each Mac before first run |
| Notes | Notes folder, end-to-end encrypted | iCloud (when sync is on), encrypted by default |

- The config folder location is user-choosable so it can be committed to git. Script files stay readable so they can be committed and shared; their secrets live in the Keychain.
- Notes are end-to-end encrypted: only the app can decode them. They are therefore not plain Obsidian-compatible files (SPEC impact).

## Notes

→ [`mockups/key-notes.html`](mockups/key-notes.html)

- Mostly temporary memos; also quick copy/paste of secrets and passwords.
- Markdown. Inline secret: `||…||`. Multi-line secret (SSH keys, `.env`): a fenced ` ```secret ` block.
- Secrets render masked at a fixed width with a click-to-reveal toggle. `COPY` copies without revealing. A copied secret is cleared from the clipboard after a configurable delay [ASSUMPTION: 30 s default, as mocked]; the footer shows the countdown. Touch ID unlock deferred post-v1.
- Surfaces: the global shortcut opens the floating panel (takes focus, Esc closes); the Notes tab lists notes with search and previews the selected one (`↑↓` when focused). List summaries show only how many secrets a note holds. No closed-notch presence.

## Script Modules

- Format: a Markdown file with YAML front matter (`id`, `name`, `interval`, `runtime`, `widget`, …), exactly one fenced code block (the script), and free Markdown documentation around it. The file is not executable, so it can't be run directly. It stays readable (not encrypted); settings marked secret live in the Keychain.
- v1 widget types: **status** (e.g. website health check), **number** (stats), **short text**. No lists.
- Surfaces, per script: Home widget, closed-notch side slot, full page in the expanded view (any combination). → [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7d, Direction 2)
- **Status levels** use the shared status vocabulary (decided 2026-11-07): OK = ring, WARN = triangle, DOWN = ×, each with its label and the session hues idle / quota-warning / failed. Scripts never get their own colors; the same primitive is open to every first- or third-party module.
- **Home widget:** header (script name and target, cadence); status = glyph + level + value line + `CHECKED 2 MIN AGO` (or `DOWN SINCE …`); short text = value + `UPDATED 4 MIN AGO`; number = big numeral + segmented bar with the warn segment.
- **Side slot:** an item on the left-wing lane with the script's `priority` (lower ones collapse into `+X`); level (or value) over the target. Clicking the closed notch still opens Home.
- **Script page** (a tab named after the script): the widget at large size on top; the script's Markdown documentation (`ABOUT · FROM <file>`); a runs card with runtime, last run (time, exit code, duration), next run (time, countdown, interval), timeout and source file; `REVEAL` (shows the file in Finder) and `OPEN SOURCE` (opens it in the default editor) [ASSUMPTION: chip targets].
- Script-raised alerts: wanted, deferred to a later version.
- Romain's first scripts: GitHub PR/issue counts, BugSink open issues (per project or total), Stripe balance, Umami stats.
- Execution, timeout and settings follow SPEC §9.2.

## Usage Tab

→ [`mockups/key-usage-tab.html`](mockups/key-usage-tab.html)

- Layout 50/50: provider cards on the left, `HISTORY · 7D` (tokens, all agents) and `COST · TODAY` (estimate by project, from local logs) on the right.
- More than two providers: the left half scrolls, in user order (drag or Settings).
- **Accounts** (PRD FR-29): one card per Account, headed `CLAUDE · WORK` when a provider has several; the closed ring shows the Account of the most recent Session. Each Account is bound to its own agent config or log location and has its own settings, including plan-limit sign-in (Settings › Usage).
- Windows per provider: 5h, weekly, or daily (Gemini CLI), whichever the plan has.
- Pace label per window: `WITHIN PACE`, `WITHIN PACE · +3` (inside tolerance), `AHEAD OF PACE · +9`. Warning: `WARN · ≥ 80%`.

## Shelf

→ [`mockups/key-shelf-tab.html`](mockups/key-shelf-tab.html), [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7c `SEND TO` card)

- TTL is a configurable number of days (not everyone uses their computer daily), default 7 days. Pinned items don't expire.
- Item modes shown on each row: `REF` (bookmark), `COPY`, `SAVED` (text, URL or image saved as a file). The mode tells the user what expiry will do.
- Expiry: references leave the shelf, file untouched; copies and saved items go to the Trash.
- Expiry warning 24 h before: visual on the row, the card meta and the Home shelf widget. Optional macOS notification (setting).
- **Without dragging** (accessibility, PRD FR-8): the `Send to` menu on a Shelf item (right-click, `↵` on the selected row, or VoiceOver actions) sends it to Ask AI (or Ask AI in the alternate folder), AirDrop or Image to Text; `⌘V` on the Shelf tab stashes the clipboard; the macOS Services entry `Stash in Vigie` stashes a selection from Finder or any app (declared by the app, no extension).
- **Shelf disabled:** Stash, AirDrop and Image to Text disappear everywhere (they are Shelf zones); Ask AI stays in the drop display while `agents.sessions` is on.
- Drag out = move, ⌥-drag = copy. Stash items can be dragged onto the `SEND TO` card in the expanded view: Ask AI (shorter, still showing the default agent, default folder and ⌥ folder), then AirDrop and Image to Text below it. Disabled zones are not shown.
- Drops from other apps go through the drop display on the notch (Stash, Ask AI, AirDrop, Image to Text), never through the expanded view.

## Calendar

→ [`mockups/key-calendar-tab.html`](mockups/key-calendar-tab.html), `imports/ref-itsycal-month.png`

- Month grid left (Itsycal-like: weekday initials, ISO week numbers, one dot per calendar per day in macOS calendar colors, today outlined, adjacent-month days dimmed), upcoming list right.
- Clicking a day shows that day's events and the following ones, at most 5, then `+N LATER`.
- Month navigation `‹ ›`, plus the header dot to return to today.
- `JOIN CALL` on events with a video link (user-triggered).
- Reads every account through EventKit (SPEC §7.5). Week view: maybe later.
- **No closed-notch glance** (decided 2026-11-07, closes Open Question 27): Calendar takes no left-wing item. An event raises an alert peek, like a blocked session, at each reminder (alarm) time set on it in Calendar; events without a reminder raise nothing. Settings › Calendar has `Reminders` on/off (on by default).
- **Reminder peek:** routed like any alert (Do Not Disturb, macOS Focus modes and the after-Focus drop / replay setting apply). Two actions: `JOIN CALL ⌥⌘↵` when the event has a video link [ASSUMPTION], otherwise `OPEN CALENDAR ⌥⌘↵` (opens the Calendar tab with the upcoming list at that event); `DISMISS ⌥⌘⌫`. Join call stays a user-triggered action. VoiceOver announcement: kicker, title, primary shortcut. Privacy mode hides the event title.

## Time

→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7e). Module `time` (SPEC §7.7). Visuals use the Time accent (A cyan, C gold), never a status hue.

- **Time tab:** quick start on top (Pomodoro with its lengths, 5 / 10 / 25 min presets, `+ COUNTDOWN` for a Countdown to a clock time [ASSUMPTION: chip label], a custom minutes field with `START ↵`); running items below, sorted by end time, each with `PAUSE` / `RESUME`, `RESET`, `REMOVE`. A Countdown has only `REMOVE`. The Time hotkey opens this tab with the quick start focused.
- **Time tab keyboard:** Tab cycles the quick start (`←→` inside the button group), the minutes field, `START`, the running list (`↑↓`), then the row chips. On a selected row: Space = Pause / Resume, `⌘⌫` = Remove (with undo), `⌘R` = Reset; on a break-due row `↵` = Start break. VoiceOver row label, e.g. "Tea, 5 minute timer, 3 minutes 12 seconds left, ends 14:52, paused"; the ring is hidden as decoration.
- **Closed-notch readout** (`closed_notch = "time" | "ring" | "both"`, `"off"` by default): the nearest-to-end item, on the left-wing lane with the Time module's `priority`. Exception: `BREAK DUE` always shows (see State Patterns, Time · break due). Setting in Settings › Time: **remaining time**, **ring**, or **ring + time**. Work and plain timers draw a solid arc, breaks a dashed arc; Pomodoro adds the phase label (`WORK · 2/4`, `BREAK · 2/4`, `LONG BREAK`).
- **Phase indicator:** see Component Patterns.
- **Pomodoro phases** (decided 2026-11-07): when a work phase ends, the break **waits** for the user. It is announced by the break peek (or `BREAK DUE` with strength "quiet") and starts only on Start break (peek or Time tab). When a break ends, the next work phase starts on its own.
- **Away:** see State Patterns (Time · away).
- **Timer end:** an alert peek routed like any alert: kicker `TIMER · ENDED` + clock time, title `<label> / <duration>`, detail start and end times, actions `OPEN TIME ⌥⌘↵` and `DISMISS ⌥⌘⌫`, 5 s dwell. The row stays as `ENDED 14:48` with `DISMISS` (State Patterns, Time · ended).
- **Break reminder strength** (Settings › Time, `breaks.style = "peek" | "quiet"`, decided 2026-11-07): **Peek** — an alert-style break peek with three actions: `START BREAK ⌥⌘↵` (primary; starts the break countdown), `SNOOZE 5M ⌥⌘Z` (re-raises the reminder in 5 min), `SKIP ⌥⌘⌫` (counts no break and starts a new work cycle) [ASSUMPTION: Snooze and Skip effects beyond their labels]; after it retracts, `BREAK DUE` stays on the left wing; or **Quiet** (closed notch only) — no peek, no sound; the readout shows a full dashed ring, `15:00` and `BREAK DUE` until the break starts or is skipped. The same break peek and readout announce Pomodoro breaks, which wait for Start break. For break reminders, being Away for the break length still counts as the break (PRD FR-49).
- Three actions on the break peek are a scoped exception to the two-action peek rule; Snooze and Skip share the secondary styling. `⌥⌘Z` is registered only while the break peek is visible.
- Flow 8 walks through a break reminder and the Pomodoro variant.

## Privacy Mode

PRD FR-55, SPEC §10.3, v0.2. Visual notes in `DESIGN.md` Components → Privacy mode (visual).

- **When:** while Vigie detects screen sharing or recording, or while the user forces it on. It turns on and off by itself, with no peek and no sound [ASSUMPTION].
- **What changes:** every surface (closed notch, peeks, expanded tabs, floating notes panel, Script Confirmation) shows only glyphs, rings, `T+` and numbers. User-supplied names and text render as fixed-width dots in the secret-mask style (epics A88): session titles, last-action lines and peek details, project names (also in cost by project), Shelf item names and thumbnails, Timer labels, Account names, widget text, calendar titles, note titles and bodies. Status labels and kickers (`BLOCKED · NEEDS INPUT`), provider and module names stay.
- **macOS notifications** Vigie sends carry only the kind label (A88).
- **Indicator** [ASSUMPTION]: a small eye-slash glyph in `ink-3` in the expanded tab row (left of the settings gear) and in the peek band while Privacy mode is on; nothing is added to the closed notch. Accessibility label "Privacy mode on".
- **Actions still work:** Focus, Dismiss, Join call and drop zones behave as usual; revealing a secret is unavailable while Privacy mode is on [ASSUMPTION].
- **Settings › General** (epics A89): `Automatic (when sharing or recording)` toggle and `Force on`. Where detection is impossible on the macOS version, Settings says "Screen sharing can't be detected on this macOS version." and offers only `Force on`. If detection needs the Screen Recording permission, it is requested only when Automatic is turned on, and Automatic is off by default in that case (A88).

## Settings & Onboarding

Spine-only by user choice: no mockup for either.

**Onboarding** (first launch, guided, each step skippable [ASSUMPTION]):

1. Theme picker (skip → Chrome Hologram).
2. Agent connections and hooks (diff confirmation, SPEC §8.3).
3. Accessibility permission.
4. Display choice: always asks about non-notch displays, whatever the setup.
5. Sounds on/off. Skipping it leaves sounds off. [ASSUMPTION: position at the end; the memlog adds this step without placing it.]
6. Launch at login (preselected on).

Before onboarding exists (v0.1–v0.3), a first launch on a Mac with a display without a notch shows a one-time prompt in the expanded view asking where Vigie should appear, and Settings › General has a `Launch at login` toggle.

**Settings:** a regular macOS window that edits the config file (SPEC §4.4, §11). Shows the Reduce motion override warning next to the Presence mode setting. [ASSUMPTION] Panes: General (launch at login, Privacy mode: `Automatic (when sharing or recording)` and `Force on`, epics A89), Appearance (variant, forced light/dark, Presence mode, status / pace / warning colors), Displays, Home (a list of modules and scripts: tick to show a card, drag to order; decided 2026-11-07), Agents, Usage (providers, Accounts, order, thresholds, pace tolerance), Shelf (TTL, expiry notification, AirDrop and Image to Text zones), Calendar (calendars, reminders on/off, hide all-day events), Time (closed-notch readout: time / ring / both; Pomodoro lengths; break reminders on/off and strength: Peek / Closed notch only), Notes (clipboard delay), Scripts (confirmations, update checks), Sounds, Sync, Updates. (Support pane superseded: closed source.) Default notes shortcut: `⌥⌘N`.

Keep-awake while an agent is working: opt-in, off by default.

## Open Questions

**Research items**
1. Can macOS intercept or delay user-initiated sleep to warn while agents work?
2. Can Claude Code, Codex and Gemini CLI start interactively with an attachment or a prefilled, unsent prompt?
3. How is "host went to sleep" detected reliably for a session (wake notification + session was working)?
4. Are 7.5–8px closed-notch labels and provider names legible on real displays?

**Design gaps (no visual yet)**
9. Quota-warning treatment on the closed-notch ring (only the Usage ring is mocked; the Story 1.7 pass did not cover it).
14. Agents tab and Home empty-state visuals (copy committed in State Patterns; the visual reuses the Empty state block).
15. Dark-mode `menu_bar` virtual-notch material (falls back to the black island look for now).
16. Presence mode levels between full and calm.
17. Collapse motion duration (provisional `motion.exit` in `DESIGN.md`).

**Decisions to confirm**
23. Calendar colors may clash with status hues; a later option could map calendars to metal tones.
24. All `[ASSUMPTION]` tags in this file and `DESIGN.md`.

**Decided** (history in `.memlog.md`; the body states each rule)
- 5 More blocked/failed sessions than slots: the most recent fill the slots, `+X` counts the rest.
- 6 Wake with several interrupted sessions: one summary alert.
- 7 Alerts suppressed by a macOS Focus mode: dropped by default; a setting replays the latest unresolved one per module.
- 8 Stale and process-only looks: dashed ring with `?` / plain grey dot.
- 10 C tabs and notes panel; Calendar today in C is gold.
- 11 `c-light-pace-on` `#4F6A00`.
- 12 Light quota-warning text: `quota-warning-text` `#7E6300` in A light and C light, on any surface (replaces "C light: cards only").
- 13 Script widgets and page: shared status vocabulary.
- 18 Sounds off when onboarding's sound step is skipped.
- 19 Left-wing item lane by state then priority, `+X`; right wing sessions only.
- 20 Notes shortcut `⌥⌘N`; Settings entry points.
- 21 Defaults: quota warning 80%, shelf TTL 7 days, clipboard clear 30 s.
- 22 Shelf expiry and script warn color: quota-warning yellow.
- 25 Pomodoro work → break waits for Start break; break → work advances on its own.
- 26 Away pauses a Pomodoro work phase; it resumes when the user is back.
- 27 Calendar in the closed notch: no glance; an event raises a reminder peek at its own Calendar alarm times, none without a reminder (PRD FR-50, 2026-11-07).
- Home widget catalog and sizing (validation finding): one fixed card size, no spans; cards ticked and ordered in Settings › Home; no in-place edit mode (2026-11-07).
- Design before build: Story 1.7 parts a–f done (→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html)).

## SPEC.md impacts

Memlog decisions that change or extend `SPEC.md`. This file wins for UX. Every row below is applied in SPEC up to v0.9 (2026-11-07) and kept as a record; there are no pending SPEC changes.

| SPEC § | SPEC says | UX decision |
|---|---|---|
| §1 Goals, §5 | Closed notch shows at most one item per side | Each side shows multiple items: up to 3 provider rings (left), 3 session glyphs + `+X` (right), configurable; empty-state labels on the right wing |
| §5.2 Peek | Compact `wide` view, default 3 s; rate-limited | Two actions with global shortcuts (`⌥⌘↵`, `⌥⌘⌫`) registered only while visible; dwell 5 s default, configurable, paused on hover; plays once + optional reminder; separate blocked / finished / failed settings; setup-problem alert uses the same frame with Open settings / Dismiss |
| §7.1 Status model | idle / working / blocked / gone; green / orange / red | Adds **done** (`turn.end`, → idle after a configurable delay, default 15 min) and **failed** (connection lost, login, host slept); colors per theme look, all user-configurable; T+ since blocked/failed |
| §7.1 Closed notch | Row of colored dots; optional count or project name | Per-session animated, shape-coded glyphs; order blocked/failed (most recent) > done > working > idle; `+X` only, no count or project name |
| §7.1, §10 Expanded tab | Click-to-focus session list | Agents tab: dense rows, urgency order, only action is Focus; terminal column only when sessions span several terminal apps |
| §7.1 Ask AI | Pick an agent, type a prompt in an inline field | No dialog; default agent and folder from settings; ⌥ alternate folder; prompt typed in the new terminal tab; stash items can be dragged onto Ask AI |
| §7.1 Settings | Terminal list | Same four terminals (Terminal, Warp, Ghostty, iTerm2); others via community issues/PRs |
| §7.2 Closed notch | Most constrained limit with glyph, or one pinned agent | One ring per provider (up to 3) with name under it, nested rings for 5h + weekly, optional pace marker; handles absent windows |
| §7.2 Thresholds | warn 70 / critical 90 states | One configurable quota warning threshold per provider; alert vs visual-only configurable; own color (signal yellow); % only; sound event |
| §7.2 (new) | — | Pace indicator: elapsed-time marker, 5-point tolerance, pace-on / pace-ahead colors; weekly when no 5h; never alerts |
| §7.2 Expanded tab | One section per agent, history chart, cost by project | 50/50 layout; provider list scrolls beyond two, user-ordered (drag or Settings); 7-day history; cost today by project |
| §7.3 Shelf, §11 `ttl = "24h"` | Items expire after `ttl` (default 24 h) unless pinned | TTL in days; expiry warning 24 h before (visual, optional macOS notification); references leave, copies and saved items go to the Trash; drag out = move, ⌥ = copy |
| §7.5 Calendar expanded tab | Today's agenda, tomorrow smaller | Month grid + upcoming list (max ~5, `+N later`), day click, month navigation, macOS calendar colors, Join call; week view later |
| §7.5 Calendar state | Lead-time state in the closed notch | No closed-notch glance; `calendar.reminder` peek at each event's own alarm times (PRD FR-50, 2026-11-07) |
| §10 Home | User picks cards and order | Settings › Home list (tick, drag to order); one fixed card size; no edit mode (2026-11-07) |
| §7.6 Notes | Plain Markdown files, Obsidian-compatible; recent notes + search | Adds `||secret||` and ` ```secret ` syntax, masked reveal, copy without reveal, clipboard clear; end-to-end encrypted, synced via iCloud (no longer plain Obsidian files); floating panel + Notes tab, no closed-notch presence |
| §9.1 Discovery | Executable files with comment headers | Non-executable Markdown with YAML front matter and one fenced code block; readable, git-committable; secret settings in the Keychain |
| §9.3 Output | `card.rows` lists; `notify` | v1 widget types status / number / short text, no lists; script alerts deferred |
| §14.7 | Consider a first-run prompt for scripts | Required confirmation on each Mac before a synced script first runs |
| §2, §11 Config | Single file at `~/.config/vigie/config.toml` | Config folder location user-choosable; optional iCloud sync of config/personalization; machine-specific settings local; secrets never synced |
| §10, §11 `open_on_hover = true` | Opens on hover; closes on mouse leave; Escape closes | Click to open by default, hover only reacts; click outside closes; hover-to-open opt-in; keyboard focus only on deliberate open |
| §5.2 DND | Peeks suppressed during Do Not Disturb / Focus | Unchanged, made explicit: no bypass option, sounds suppressed too |
| — (new) | — | Keep-awake while agents work (opt-in) and interrupted-session alert on wake |
| — (new) | — | Theme family, forced light/dark setting, Presence mode, custom themes, live switching |
| — (new) | — | Onboarding sequence; settings as a regular macOS window |
| — (new) | — | Sounds: six events, built-in < 1 s, custom files |
| — (new) | — | i18n from the start |
| §4.6, §7.3 Drop zones | Closed notch turns into Stash (left) / Ask AI (right), plus AirDrop and Copy text | A drag-only drop display grows out of the notch while a file is dragged over it (700 × 196, layout B: Stash 2 × 2, Ask AI 1 × 2, AirDrop and Image to Text 1 × 1), Esc cancels; Shelf tab `SEND TO` card holds Ask AI, AirDrop, Image to Text (decided 2026-11-07) |
| §4.6, §7.3, §11 `copy_text` | "Copy text" zone, key `copy_text` | Renamed **Image to Text**, key `image_to_text`; confirmation `COPIED · N LINES` (or `NO TEXT FOUND`) on the left wing for 2 s |
| §7.1, §8.3 Stale / process-only | `?` badge; grey dot | Stale = dashed ring with `?` inside, `STALE · <time since last event>`; process-only = plain grey dot, `RUNNING`; both neutral, sorted after idle |
| §9.3 Output (status) | — | Shared status vocabulary OK / WARN / DOWN (ring / triangle / ×, idle / quota-warning / failed hues) for every module |
