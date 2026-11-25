---
stepsCompleted: [1, 2, 3, 4]
workflowMode: unattended
inputDocuments:
  - prds/prd-vigie-2026-11-06/prd.md
  - prds/prd-vigie-2026-11-06/addendum.md
  - prds/prd-vigie-2026-11-06/.memlog.md
  - SPEC.md
  - architecture/architecture-vigie-2026-11-05/ARCHITECTURE-SPINE.md
  - architecture/architecture-vigie-2026-11-05/.memlog.md
  - ux-designs/ux-vigie-2026-11-04/DESIGN.md
  - ux-designs/ux-vigie-2026-11-04/EXPERIENCE.md
referencedMockups:
  - ux-designs/ux-vigie-2026-11-04/mockups/key-closed-notch-states.html
  - ux-designs/ux-vigie-2026-11-04/mockups/key-alert-variants.html
  - ux-designs/ux-vigie-2026-11-04/mockups/key-agents-tab.html
  - ux-designs/ux-vigie-2026-11-04/mockups/key-usage-tab.html
  - ux-designs/ux-vigie-2026-11-04/mockups/key-shelf-tab.html
  - ux-designs/ux-vigie-2026-11-04/mockups/key-calendar-tab.html
  - ux-designs/ux-vigie-2026-11-04/mockups/key-notes.html
  - ux-designs/ux-vigie-2026-11-04/mockups/theme-family-4-looks.html
  - ux-designs/ux-vigie-2026-11-04/mockups/compare-a-vs-c-v3.html
  - ux-designs/ux-vigie-2026-11-04/mockups/key-design-pass-1-7.html
status: final
created: '2026-11-06'
updated: '2026-11-07'
prdReconciled: '2026-11-06'
assumptionsRuled: '2026-11-06'
updateRun:
  mode: validate-and-update
  date: '2026-11-07'
  stepsCompleted: [1, 2, 3, 4]
---

# Vigie - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for Vigie, decomposing the requirements from the PRD ~~(here: `SPEC.md` draft v0.4)~~, the UX design contract (`DESIGN.md` + `EXPERIENCE.md`, final) and the Architecture spine ~~(AD-1..AD-23, final)~~ into implementable stories. **Amended 2026-11-07 (epics update run):** sources are the PRD (`prd.md`, FR-1..FR-64, final), `SPEC.md` v0.9 (supporting), the UX spines (final, updated 2026-11-07) and the Architecture spine (AD-1..AD-26, final, updated 2026-11-07).

**Reconciled with the PRD (2026-11-06).** The real PRD now exists: `prds/prd-vigie-2026-11-06/prd.md` (final, FR-1..FR-64), with `addendum.md` and `.memlog.md` (the memlog is authoritative on decisions). This file keeps its own numbering (FR1–FR111, NFR1–NFR29, UX-DR1–107; NFR29 and UX-DR80–107 added 2026-11-07) and adds a **PRD traceability** table that maps every PRD FR to these FRs and stories. PRD FRs are always written with a hyphen and a "PRD" prefix (`PRD FR-23`) to avoid confusion with this file's `FR23`. Changes made in the reconciliation are marked *Added 2026-11-06*, **[Changed by PRD]** or **[SUPERSEDED]**; nothing was renumbered. The architecture spine was amended the same day (AD-6 carve-out for `vigie run`, AD-16/AD-18 script install and signing, AD-23 multi-Account, AD-13 new alert kinds, AD-20 Screen Recording and public release hosting) and gained AD-24 Privacy mode, AD-25 Away service and AD-26 activity log.

**Totals:** 21 epics, 130 stories (129 active, 1 superseded: 17.3; recounted 2026-11-07, the earlier 127 was one short; 1.7 and 19.3 added by the rulings, 2026-11-06; 9.10 added by the 2026-11-07 UX review; 3.9 and 12.11 split out in the 2026-11-07 AC update). Coverage: PRD FR-1..FR-64 64/64; FR1–FR111 110 active / 111 (FR109 superseded); NFR1–NFR29 28 active / 29 (NFR21 superseded; NFR29 added 2026-11-07, AC in Story 19.2); UX-DR1–UX-DR107 (UX-DR80–107 added 2026-11-07; UX-DR20 superseded by UX-DR83; UX-DR74 Support pane superseded); every active UX-DR maps to at least one story AC (AC update step done 2026-11-07).

It was produced **unattended**: every point where the workflow would normally stop for a decision was decided by the facilitator and logged in **Assumptions to rule on** at the end of this file (A1, A2, …). Stories cite the assumptions they depend on. Items the PRD or its memlog have since decided are marked **[RESOLVED]** or **[SUPERSEDED]** there; A79 and later were added by the PRD reconciliation.

Conventions used in stories:

- **Requirements:** line lists the FR / NFR / UX-DR / AD ids the story covers (AD = Architecture Spine decision).
- Paths such as `Packages/VigieCore` follow the Architecture Spine Structural Seed.
- "Settings › X" names a pane of the Settings window.
- Mockup links are relative to `ux-designs/ux-vigie-2026-11-04/`.

## Requirements Inventory

### Functional Requirements

SPEC.md has no numbered FRs. Each FR below is derived from one SPEC section (cited) and, where the UX spines or the architecture spine refine it, worded per the winning source (see A3).

FR1 (§1, §4.3): Every module (built-in or script) can be enabled or disabled in config; a disabled module is never started, requests no permission and does no background work.
FR2 (§4.3): When a module is enabled, its required permissions are checked and requested only then; if one is denied, the module shows as "needs permission" in Settings and stays stopped.
FR3 (§4.3, §4.5): Module lifecycle: `start(context:)` registers hotkeys, scheduled jobs and event subscriptions through the context; on disable or quit `stop()` is called and everything the module registered is removed automatically.
FR4 (§4.2): Built-in modules implement `NotchModule`: manifest (id, name, icon, permissions, settings), observable state (`hidden < ambient < active < alert`), `compactView(size: icon|short|wide)`, optional `homeCard()`, optional `expandedView()`, `dropZones`. **Amended 2026-11-07:** no default side; the wings are fixed (right = `agents.sessions` only; left = the item lane of FR9).
FR5 (§4.4): Modules declare settings with typed descriptors (`bool`, `int`/`double` with min/max/step, `string`, `secret`, `enum`, `duration`, `hotkey`, `path`, `list<T>`); the core generates the settings UI; a module may add a custom settings view only in addition to the generated one.
FR6 (§3, §4.5): Modules reach the system only through `ModuleContext` services and never reference each other directly.
FR7 (§4.6): ~~Modules can contribute drop zones (id, label, icon, accent, accepted types, async handler); built-in zones are Stash (Shelf) and Ask AI (Agents).~~ **Amended 2026-11-07 (epics update run, step 1):** Modules contribute drop zones (id, label, glyph, accent, `role`, `cell`, `order`, accepted types, async handler); built-in zones are Stash, AirDrop and Image to Text (Shelf) and Ask AI (`agents.sessions`); the host lays them out in the drop display (AD-19).
FR8 (§3, §8.1): A `vigie` CLI is bundled in the app, made available on `PATH`, and provides `vigie event <topic> [json]`, `vigie hook <agent>`, `vigie agent …` and `vigie reload`.
FR9 (§5): The closed notch has a leading and a trailing side, each rendering up to `closed.slots` items (default 3, max about 4) plus `+X`. **Amended 2026-11-07 (SPEC v0.7 §5):** trailing = sessions only; leading = an item lane shared by provider rings, script side-slot items and the Time readout, ordered by state then per-item `priority`, overflow in `+X` (replaces one winning module per side and `stacked` mode).
FR10 (§5.1): ~~Arbitration per side: candidates are enabled modules assigned to that side or `any` …~~ **Amended 2026-11-07 (SPEC v0.7 §5):** the right wing renders only `agents.sessions`; the left wing pools the items of enabled modules with state ≠ hidden (each provider ring, script side-slot item, Time readout), sorts them by state (desc), then item `priority` (asc), then provider `order`, shows the first `closed.slots` and counts the rest in `+X`; each shown item is asked for its compact view from the largest size the width allows, falling back to smaller sizes.
FR11 (§5.1): An empty side is black on a physical notch; on a plain display the virtual notch shrinks to its minimum width, hides, or keeps its size per `virtual_notch.idle`.
FR12 (§5.2): When a module enters `alert`, the host may peek: a short partial expansion that plays once per event, with an optional secondary reminder; dwell default 5 s, configurable (`closed.peek_duration`), paused while hovered; after the dwell it retracts and the closed notch keeps the state; peeks are rate-limited per module and can be turned off globally (`closed.peek`) or per module.
FR13 (§5.2): A peek offers two actions with global shortcuts registered only while it is visible: primary `⌥⌘↵` and Dismiss `⌥⌘⌫`; Dismiss retracts the peek and cancels its reminder and never changes module state; never bare Esc or other common keys.
FR14 (§1, §5.2): Peeks and alerts never take keyboard focus; the app the user is typing in keeps it.
FR15 (§5.2): Alert settings per kind: blocked, finished (done) and failed sessions each have their own on/off and reminder settings; quota warning chooses alert or visual-only.
FR16 (§5.2): Setup-problem alerts (unsupported adapter/CLI version, invalid config, missing permission) use the peek frame and dwell with neutral styling and are never an agent state; actions Open settings (on the relevant pane) and Dismiss.
FR17 (§5.2, §10.2): Do Not Disturb / Focus mode suppresses peeks and sounds with no bypass option; the closed notch still updates.
FR18 (§5.3): On a physical notch, each side's width is the safe-area region beside the notch (`NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`) capped by `closed.max_side_width`; on a virtual notch the width is user-set (default: MacBook notch size).
FR19 (§5.4): `display = "main" | "notched" | "all" | "<display name>"` (machine-specific); default is the notched display if any, otherwise the main display; in clamshell mode it falls back to the main external display.
FR20 (§5.4): Vigie hides on a display that has a full-screen app open (configurable, `hide_in_fullscreen`).
FR21 (§5.4, §14.10): The host classifies displays as `physical`, `plain` or `island`; `island` displays run in plain mode until the island spike. **[Changed by PRD FR-2, §6.2: Macs with a system Dynamic Island use plain mode for all of v1; the island display mode is after v1.]**
FR22 (§5.4): Connecting/disconnecting a display, changing resolution or arrangement, and opening/closing the lid re-run placement live, without restart.
FR23 (§5.4): With `display = "all"`, every notch shows the same state; the expanded view and peeks appear only on the display under the cursor.
FR24 (§5.5): Virtual notch layout options: idle minimum width or hide (`virtual_notch.idle`), `position = center | right`, `placement = menu_bar | below`.
FR25 (§5.5): Virtual notch `style = black | menu_bar` (`menu_bar` matches the menu bar material).
FR26 (§5.5): With "Automatically hide menu bar" on, the virtual notch hides and returns with the menu bar; alerts still peek.
FR27 (§5.5): On plain displays the hover zone is the whole top-center strip, a few points tall and wider than the pill.
FR28 (§6): All user-facing alerts go through the core `Notifier`, never directly through macOS notifications; events carry `module`, `kind`, `severity` (`info|warn|critical`), `title`, `body`, `action`, `dedupe_key`.
FR29 (§6): Notifier rules from config: mute a kind, minimum severity, quiet hours, cooldown per `dedupe_key`, combinable outputs (`peek`, `system`, `sound`), and a `reminder` delay that replays peek and sound once if the state is unchanged.
FR30 (§6): The `system` output posts a macOS notification.
FR31 (§7.1): Adapters translate native agent events into the normalized events `session.start`, `prompt.submit`, `tool.start`, `tool.end`, `subagent.end`, `needs.input`, `turn.end`, `session.error`, `session.end`.
FR32 (§7.1): Session status model `idle / working / done / blocked / failed / gone` with the SPEC §7.1 transition table, including done → idle only after `done_to_idle` (default 15 min) and a new prompt moving done → working; focusing or dismissing never changes state.
FR33 (§7.1): Blocked and failed sessions show `T+` since entering the state (since wake for host-slept), which keeps running after the alert.
FR34 (§7.1): Urgency order (closed notch, Agents tab): blocked and failed (shared top priority, most recent first) > done > working > idle.
FR35 (§7.1, §8.3): If an adapter can't detect `needs.input` or `session.error`, its sessions can never turn blocked or failed, and that adapter's settings say so.
FR36 (§7.1): Liveness: each session stores its agent PID; a check every 10 s removes sessions whose process died; a session `working` with no events for longer than `stale_after` (default 10 min) is shown with the stale look (Story 1.7b: the glyph is replaced by a dashed ring with `?` inside, label `STALE · <time since last event>`, static, no hue, sorted after idle); liveness never removes a failed session, which stays until dismissed or 24 h.
FR37 (§7.1): Closed notch right wing: one animated, shape-coded glyph per session in urgency order, most urgent nearest the notch, up to `closed.slots`; the rest collapse into `+X`, which never hides a blocked or failed session; no session count, no project name; empty states `NO AGENT CONNECTED` and `NO ACTIVE SESSIONS`.
FR38 (§7.1): `agents.sessions` module state is `alert` if any session is blocked or failed, `active` if any is done or working, `ambient` otherwise (so the empty-state label shows).
FR39 (§7.1): Agents tab: dense list sorted by urgency with agent, project (from `cwd`), last action, status with time in status, and the terminal app only when sessions span more than one terminal app; the only action is Focus (click the row or ↵ on the selection).
FR40 (§7.1): Ask AI drop zone: dropping files (drop display, Shelf tab `SEND TO` card, a stash item, or the Shelf item `Send to` menu, Story 9.10) opens a new terminal tab running `ask_default_agent`, with no dialog, in `ask_cwd` (`home`, the file's folder, or a path); holding ⌥ uses `ask_alt_cwd`; files are attached or their paths prefilled in an unsent prompt; if the CLI can't, paths are pasted; agent not installed → setup-problem alert.
FR41 (§7.1): `agents.sessions` settings: enabled adapters, terminal app, Ask AI default agent and folders, alert settings for blocked / finished / failed, `done_to_idle`, idle-sleep prevention, ignored paths, stale timeout, and each adapter's own settings.
FR42 (§7.1): Sessions whose project path is under an ignored path are not tracked.
FR43 (§7.1.1): Terminal focus: a `TerminalAdapter` captures a locator at `session.start` and `focus(locator)` brings the session's exact terminal tab to the front; v1 supports exactly Terminal.app, iTerm2, Warp and Ghostty.
FR44 (§7.1.1): If focusing the tab fails, the terminal app is activated without selecting a tab; a missing Accessibility permission raises a setup-problem alert.
FR45 (§7.1.2): Opt-in idle-sleep prevention (off by default) while any session is working. **[PRD FR-19 adds: the setting says lid close and manual sleep are not covered.]**
FR46 (§7.1.2): On wake, local sessions that were working when the Mac slept become failed (`FAILED · HOST SLEPT`, with the interrupted action) and raise one failed alert for the wake (a summary when several were interrupted; A20 ruled 2026-11-06).
FR47 (§7.2): Each agent adapter can provide usage, enabled separately: token counts and estimated cost over time, optionally plan limits (% used and reset time per window: 5h, weekly, daily).
FR48 (§7.2): Claude Code local-log usage reads `~/.claude/projects/**/*.jsonl`, works offline and needs no sign-in.
FR49 (§7.2, §14.2): Plan-limit sources that use unofficial endpoints must be enabled explicitly, may break without notice, store credentials in the Keychain, and are isolated per adapter.
FR50 (§7.2): Closed notch left wing: one quota ring per provider up to `closed.slots`, in user order, provider name under each ring; a single provider shows ring + value/label readout; `rings = "5h" | "5h+weekly"` (nested, 5h inside); only the windows the plan has; no provider → empty left wing.
FR51 (§7.2): Quota warning: one `warn_threshold` per provider (% used only, default 80), `warn_action = alert` (peek + optional sound, state alert) or `visual` (state active); own color plus non-color cues; wins over pace-ahead on the same window.
FR52 (§7.2): Optional pace indicator (`pace = true`): marks elapsed time in the paced window (5h, or weekly when no 5h); ahead when used > elapsed + `pace_tolerance` (default 5 points); configurable colors; visual only, never alerts or sounds.
FR53 (§7.2): `agents.usage` state is ambient normally, active or alert above `warn_threshold` per `warn_action`.
FR54 (§7.2): Usage tab: provider cards (ring, one bar per window with reset time, elapsed %, pace label, threshold tick) on one half, scrolling beyond two, user-ordered (drag on the tab or Settings); 7-day token history (all agents) and today's estimated cost by project (local logs) on the other half; empty state `NO USAGE PROVIDER`.
FR55 (§7.2, §8.3): Codex CLI usage from `~/.codex/sessions/` logs (token counts, and rate-limit windows if the logs carry them).
FR56 (§7.2, §8.3): Gemini CLI usage from local telemetry/session files, if a usable source exists.
FR57 (§4.6, §7.3): ~~Dragging a file from any app turns the closed notch into Stash (left) and Ask AI (right) zones without expanding~~ **Amended 2026-11-07 (Story 1.7c):** dragging a file from any app over the notch shows the drag-only drop display (layout B: Stash, Ask AI, AirDrop, Image to Text) without expanding or taking focus; the zones also appear on the Shelf tab (`SEND TO` card) and in the Home shelf widget.
FR58 (§7.3): Stash stores a reference (bookmark) by default; `copy` mode stores a copy; text, URLs and images dragged in are saved as files; each row shows its mode `REF` / `COPY` / `SAVED`.
FR59 (§7.3): Shelf item actions: drag out = move, ⌥-drag = copy, Quick Look (Space), Reveal in Finder, Pin; stash items can be dragged onto Ask AI.
FR60 (§7.3): Items expire after `ttl` days (default 7) unless pinned; 24 h before expiry a visual warning shows on the row, the shelf card and the Home shelf widget, plus an optional macOS notification (off by default), no sound; on expiry references leave the shelf (file untouched), copies and saved items go to the Trash; nothing is deleted permanently.
FR61 (§7.3): Shelf module state is ambient with an item count when not empty, otherwise hidden.
FR62 (§7.4, §9.1): Every `*.md` file in `<config folder>/modules/` is a script module: YAML front matter, exactly one fenced code block, free Markdown documentation; not executable; Vigie runs the code block with the declared `runtime`; each script appears as its own module in arbitration, settings and tabs.
FR63 (§9.2): A script runs only after the user confirms it on this Mac after seeing the whole file; a script that arrives through sync or git, or whose content changes, is "awaiting confirmation"; declining disables it on that Mac only; secrets must be entered on each Mac.
FR64 (§9.2): Scripts run every `interval`, once at startup and when the user clicks Refresh; settings are passed as `VIGIE_SETTING_*` environment variables; secrets are read from the Keychain at run time.
FR65 (§9.2): Script timeout `min(interval, 30 s)`; stderr goes to the module log; a non-zero exit marks the module errored and keeps the last good output with a warning badge.
FR66 (§9.3): Script stdout JSON: `state` (default ambient), `widget` (`type` status|number|text, `value`, `label`, `detail`, `level` ok|warn|error), `action` (`open` url, `run` argv, `copy` text); `notify` is ignored in v1.
FR67 (§9.1, §9.3): Script surfaces (front matter `surfaces`): Home widget, closed-notch side slot, full page tab; widgets are rendered by core templates.
FR68 (§9.3, §12.5): A versioned JSON Schema is published at `schemas/script-module.schema.json`.
FR69 (§13): 2–3 example scripts ship with v0.3. **[Changed by PRD FR-41: five examples (GitHub PRs, site up/down, CI or deploy status, revenue Stripe-style, text widget) live in the Script repository; the app bundles a subset. See Stories 12.7, 12.8.]**
FR70 (§7.5): Calendar reads every account through EventKit; ~~state hidden when nothing is soon, active from `lead_time` (default 15 min) before an event, alert at start~~ **Amended 2026-11-07 (PRD FR-50 ruling):** no closed-notch glance; each event's own Calendar alarm raises a `calendar.reminder` alert (peek), events without alarms raise nothing; clicking an event with a video link (Meet, Zoom, Teams) joins the call.
FR71 (§7.5): Calendar tab: month grid (one dot per calendar per day in macOS calendar colors, ISO week numbers, month navigation, return to today) and an upcoming list from now or the clicked day (at most about 5 events, then `+N LATER`, next event highlighted with a countdown); `JOIN CALL` on video events; setup card when calendar access is missing.
FR72 (§7.5): Calendar settings: calendars to include, ~~lead time~~ reminders on/off (amended 2026-11-07), hide all-day events.
FR73 (§7.6): A global hotkey opens a floating notes panel that takes focus; Esc closes it.
FR74 (§7.6): Markdown notes with inline `||…||` and multi-line ```` ```secret ```` blocks; secrets render masked at a fixed width, click to reveal; `COPY` copies without revealing; the clipboard is cleared after a configurable delay (default 30 s).
FR75 (§7.6): Note list summaries never show secrets, only how many a note holds.
FR76 (§7.6, §11.1): Notes are saved in a user-chosen folder, end-to-end encrypted (only Vigie can decode them), and synced via iCloud when sync is on.
FR77 (§7.6): Notes tab: notes list with search and a preview of the selected note; notes have no closed-notch presence.
FR78 (§8.1): Event Server listens on a user-only (0600) Unix socket in Application Support; one JSON object per line; modules subscribe to topics through `context.events`.
FR79 (§8.2): `vigie hook <agent>` reads the agent's native event (stdin or args), adds process ancestry, TTY and relevant environment (`TERM_PROGRAM`, `ITERM_SESSION_ID`, `WARP_*`, …), sends it tagged with the agent id, and exits immediately with code 0 and no output, even when the app isn't running.
FR80 (§8.3): Agent adapters are compiled into the app and are the only agent-specific code: capabilities, settings, integration and removal plans returned as diffs the user confirms, `normalize`, optional transcript watcher, usage providers, Ask AI launch command; adding one requires no change to the sessions or usage modules.
FR81 (§8.3): Integration tiers, best available first: hooks, transcript watching, process-only (presence only, one grey dot, no status).
FR82 (§8.3): Claude Code adapter via hooks in `~/.claude/settings.json` (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SubagentStop`, `SessionEnd`) with full status coverage; the installer shows the diff before writing.
FR83 (§8.3): Codex CLI adapter: `notify` program in `~/.codex/config.toml` plus transcript watching of `~/.codex/sessions/` for working/blocked; native hooks if the installed version has them.
FR84 (§8.3): Gemini CLI adapter: hooks if the installed version supports them, otherwise transcript watching.
FR85 (§14.5): Each adapter detects the installed CLI version and reports "unsupported version" instead of showing wrong statuses; recorded fixtures per supported version.
FR86 (§8.4): `vigie agent --agent <id> --session <id> --status <s> [--cwd] [--message] | --end` lets any tool report a session without an adapter; PID and TTY are captured automatically so liveness and focus work.
FR87 (§10): The expanded view opens on click (or tap) on the notch or with the global expand hotkey, always on Home, and takes keyboard focus; hovering only gives a small reaction; hover-to-open (`open_on_hover`, `hover_delay`) is opt-in.
FR88 (§10): The expanded view closes on click outside, Esc (when focused) or the hotkey again; close-on-mouse-leave (`close_on_leave`) is opt-in; it never opens by itself; opened any other way it takes no focus.
FR89 (§10): Tab bar: Home first, then one tab per enabled module with an `expandedView` plus one per script page; user-set order; a tab with an active alert carries a marker.
FR90 (§10): Home is a grid of `homeCard()` widgets; the user picks which appear and in what order. **Amended 2026-11-07:** chosen in Settings › Home (tick modules and scripts, drag to order); one fixed card size in v1; no in-place edit mode.
FR91 (§10): Keyboard when focused: `⌘1…9` switches tabs, `↑↓` moves the selection in lists, `↵` acts on it (Focus, Join call), Space = Quick Look on the Shelf, Esc closes.
FR92 (§10): Every tab has an empty state (label, one sentence, button to the relevant Settings pane where useful) and a setup card when its module lacks a permission.
FR93 (§10.1, §4.4): Settings is a regular macOS window with native controls that edits the config files; reached from setup-problem alerts, empty states and `⌘,`.
FR94 (§10.1): First-launch onboarding, each step skippable: theme, agent connections and hooks (diff confirmation), Accessibility permission, display choice (always asks about non-notch displays), sounds on/off, launch at login (preselected on); Vigie never shows a Dock icon.
FR95 (§10.2): Theme family: Chrome Hologram (default) and Twin Metal Tactical, each with light and dark looks; appearance follows macOS unless forced; custom themes extend the shared base; theme and appearance changes apply live.
FR96 (§10.2): Every status color, pace on/ahead and quota-warning color is user-configurable.
FR97 (§10.2): Presence levels `full` (default) and `calm`; macOS Reduce motion forces calm; Reduce transparency and Increase contrast are honored.
FR98 (§10.2): Sounds are optional: seven events (blocked, failed, done, quota warning, timer end, break reminder, calendar reminder; amended 2026-11-07), each on/off with its own sound file; built-in sounds < 1 s, custom files any length; play once with the alert, replay with a reminder, follow Do Not Disturb; pace and shelf expiry never play a sound. **[Extended by PRD FR-35: timer end (Story 20.2, off by default) and break reminder (Story 20.4, off by default) are sound-capable kinds too; so is calendar reminder (Story 13.4, off by default, 2026-11-07).]**
FR99 (§11): `config.toml` in the config folder holds shared settings; the settings window writes it; edits made outside the app are picked up live; invalid config raises a setup-problem alert and the last valid config stays active.
FR100 (§11, §11.1): Machine-specific settings (displays, virtual notch, terminal, config folder location, script confirmations) live in a local file that is never synced.
FR101 (§2, §11.1): The config folder location is user-choosable (default `~/.config/vigie/`) so it can live in a git repo.
FR102 (§11.1): Turning `[sync] icloud` on moves the config and notes folders into `iCloud Drive/Vigie/`; turning it off moves them back.
FR103 (§11.1): The notes key is created only when the user sets up notes; on another Mac, Vigie waits for it through iCloud Keychain or asks for the recovery key, never creating a second key.
FR104 (§12.1): `ci.yml` on pull requests and pushes to `master`: build, unit tests, adapter fixture tests, lint; no secrets, no signing.
FR105 (§12.2, §12.3): `release.yml` on a `vX.Y.Z` tag on `master`: verify ancestry and version, sign (Developer ID, hardened runtime, CLI included), notarize and staple, package DMG + zip, Sparkle EdDSA signature + appcast, GitHub Release with checksums, Homebrew tap PR; suffixed tags publish pre-releases; secrets only in the `release` environment. **[Changed by PRD §9 Q1: the code repository is private; DMG, zip, checksums and appcasts publish to a public release host (Story 6.2, A86).]**
FR106 (§12.4): Sparkle 2 auto-update from the GitHub Releases appcast; `[updates]` settings `auto_check`, `check_interval`, `auto_install`, `channel = stable | beta` (beta uses `appcast-beta.xml`); public EdDSA key in `Info.plist`. **[Changed by PRD FR-61 and §9 Q1: the appcast is served from the public release host; Vigie installs only after the user agrees, automatic install is opt-in.]** **[A63 ruled 2026-11-06: the beta channel arrives with the public release, Story 19.3.]**
FR107 (§12.5): Semantic versioning; `CFBundleVersion` is an always-increasing CI build number; the script schema and adapter event format carry their own versions.
FR108 (§12.3, §12.4, §13): Homebrew cask (tap at first) declaring `auto_updates true`.
FR109 (§2.1): **[SUPERSEDED 2026-11-06 by PRD §9 Q1 and memlog (business model undecided; SPEC §2.1 donationware and the Settings Support pane are superseded); not reinstated by the 2026-11-25 license change to GNU GPLv3. Story 17.3 superseded; no replacement story.]** Settings has a Support item (GitHub Sponsors, Ko-fi/Buy Me a Coffee); at most one dismissible donation message after a few weeks of use, never shown again once dismissed.
FR110 (§14.8): Vigie detects other notch apps and warns that two apps can't share the notch.
FR111 (§4.5, §11): Global hotkeys: expand hotkey (`expand_hotkey`, default `cmd+shift+space`) and module hotkeys, with conflict detection.

### NonFunctional Requirements

NFR1 (§2): macOS 15.0+ deployment target; Swift, SwiftUI, AppKit `NSPanel` where needed.
NFR2 (§1, §5.2, §10): Never steal focus: panels are non-activating; Vigie takes keyboard focus only on a deliberate user action (click, hotkey, menu).
NFR3 (§8.2, AD-6): The hook CLI never slows or blocks an agent: synchronous, 150 ms total budget, exit 0 with no output in every case, never forks or detaches.
NFR4 (§1, §4.3): Disabled modules cost nothing: no permission prompts, no timers, no background work (e.g. shelf-only setup = file shelf and nothing else).
NFR5 (§8.1): The event socket is accessible only to the current user (0600).
NFR6 (§2, §4.4, §11.1, AD-9): Secrets live only in the Keychain; never in config files, app data, logs, diagnostics or synced folders; never synced (except the notes key, AD-9).
NFR7 (AD-16): No telemetry and no automatic crash reporting; network calls only for Sparkle, opt-in plan-limit providers and user scripts. **[Changed by PRD §5: also script install and update fetches, user-initiated or user-enabled (AD-16 amended 2026-11-06); the update check can be turned off (PRD FR-4).]**
NFR8 (§2, AD-15): English first; every user-facing string goes through String Catalogs from the first commit.
NFR9 (§10.2): Accessibility floor (v1): every control and glyph has an accessibility label with its state; color is never the only cue.
NFR10 (§10.2): macOS Reduce motion, Reduce transparency and Increase contrast are honored.
NFR11 (§2, §1, AD-20): Developer ID signed, hardened runtime, notarized, unsandboxed; not distributed through the Mac App Store.
NFR12 (§12.1, §12.3): Release builds happen only on GitHub Actions from tagged `master` commits; pull-request CI never reads secrets or signs.
NFR13 (§12.4): Updates are verified twice: Sparkle EdDSA signature and Developer ID + notarization.
NFR14 (§5.4, §10.2, §11): Config, theme, appearance and display changes apply live without restart.
NFR15 (§11, Conventions): A module failure never crashes the host; invalid config keeps the last valid one; unreadable state files are set aside (`.corrupt`) and the module starts empty.
NFR16 (§7.3, Conventions): No silent data loss: the shelf never deletes permanently; every app-written file is written atomically.
NFR17 (§1, AD-8): Config as code: human-editable TOML; app writes preserve comments, ordering and unknown keys byte-for-byte.
NFR18 (§14.5, AD-23): Robust to agent CLI changes: version detection, recorded fixtures per supported version, never wrong statuses on unsupported versions.
NFR19 (§9.2): Script trust: scripts run unsandboxed as the user, only after per-Mac confirmation of the exact content; the README says so clearly.
NFR20 (§7.6, AD-10): Note plaintext exists only in memory; each note file is authenticated-encrypted at rest.
NFR21 (§2): GPL-3.0 license; reused GPL-compatible code (e.g. Boring Notch) is attributed. **[REINSTATED 2026-11-25: the user decided GNU GPLv3 only (GPL-3.0-only). It was struck through on 2026-11-06 (closed source, all rights reserved, PRD §9 Q1) and is reinstated for the license only. The rule kept from that decision stays: GPL code such as Boring Notch is not copied into the app; only permissively licensed code may be reused, with attribution.]**
NFR22 (§2): Bundle IDs fixed from v0.1: `fr.baguettelabs.vigie` (release), `fr.baguettelabs.vigie.dev` (dev).
NFR23 (§8.3, AD-4): Adding an agent adapter = one new package + one line in App assembly; no change to `agents.sessions` or `agents.usage`.
NFR24 (AD-3): Responsiveness and safety: all I/O off the main actor; Swift 6 language mode with complete concurrency checking in every target.
NFR25 (Conventions): CI test floor: SessionStore transitions, arbitration, ConfigStore patcher round-trip corpus, spool/replay/launch order, usage ingest, adapter fixtures, theme regeneration diff, locale check.
NFR26 (§1 Non-goals, EXPERIENCE Interaction Primitives): Vigie never acts on an agent session on the user's behalf (only Focus), never shows mascots, never auto-opens the expanded view. **[PRD §5 and memlog: no animated characters, companions or pets, ever.]**
NFR27 (§14.2): Unofficial plan-limit integrations are optional, isolated per adapter and quick to patch; their failure degrades to local-only data, never breaks the module.
NFR28 (AD-17): Dev builds are fully isolated from release builds (bundle id, Application Support, socket, spool, CLI name, hooks).
NFR29 (PRD SM-4, SM-C2; added 2026-11-07): Footprint: with `agents.sessions`, `agents.usage` and two Script modules enabled and the app idle (closed notch, no drag, no peek), average CPU < 1 % and resident memory < 150 MB over a 10-minute sample; every module must stay within it (SM-C2).

### Additional Requirements

Extracted from the Architecture Spine (final; summary regenerated 2026-11-07 from AD-1..AD-26). These bind stories as acceptance-criteria constraints.

**Starter / scaffold (Epic 1 Story 1).** No starter template. The "starter" is the SwiftPM-first Structural Seed (AD-2): `App/` thin Xcode target + `Packages/{Wire, ModuleKit, AgentKit, VigieUI, VigieCore, VigieCLI, Modules/*, Adapters/*, Terminals/*}`, `Themes/` (generated), `schemas/`, `.github/workflows/`. Module/adapter packages are created by the first story that needs them.

- AD-1: Each built-in module, adapter and terminal adapter is its own SwiftPM target; modules depend only on ModuleKit, VigieUI (+ AgentKit, Wire for agent modules); never on another module or VigieCore; cross-module interaction only through `ModuleContext` (AD-19); graph enforced by `Package.swift`.
- AD-2: All code in local Swift packages under `Packages/`; the Xcode project contains only the app target (assembly, entitlements, Info.plist, assets, CLI bundling).
- AD-3: Swift 6 language mode, complete concurrency checking; module state is `@MainActor @Observable`; I/O and persistence in actors/tasks off main; boundary types `Sendable`; no singletons, no central store, no TCA.
- AD-4: App assembly is the only composition point: builds modules, agent adapters, terminal adapters, their `AdapterContext`s; both agent modules get the same adapter instances; onboarding steps composed in App.
- AD-5: Single session status authority: one `SessionStore` in `agents.sessions` applies the transition table; identity `<adapter id>:<native session id>`; timing from envelope `sent_at`; out-of-order events don't change status; replayed transitions older than 5 min post no alert; CLI sends ancestor chain (≤ 8 levels), adapter picks agent PID; liveness compares PID + start time; on wake, working sessions → `failed (host_slept)` before liveness resumes; failed sessions kept until dismissed or 24 h; idle-sleep prevention (Keep-awake) only via `context.power`; generic agent mapping lives in `agents.sessions`; persist on status/membership change only.
- AD-6: Durable event path: CLI non-blocking socket write within 150 ms, else append to `spool.jsonl` (`O_APPEND`, `flock`, single write); payloads > 1 MiB truncated; fixed launch order (instance lock → bind + queue → start modules → replay spool → drain queue → `host.ready` + liveness reconcile). **`vigie run` carve-out:** the child runs with inherited stdio and forwarded signals, its output and exit code pass through; only its event sends follow socket-else-spool; reports as `agent.generic` agent `run`; SIGINT sends `--end`, no alert.
- AD-7: Wire envelope `{ v, topic, sent_at, payload }`; app accepts `v` and `v-1`, ignores unknown fields, drops others with a log; wire types only in `Wire`; Event Server publishes opaque `EventMessage { topic, payload, sentAt, receivedAt, replayed }`.
- AD-8: `ConfigStore` is the only reader/writer of `config.toml` and `local.toml`; swift-toml decode only; in-house line-level TOML patcher with round-trip corpus; re-read → patch → re-parse → verify → atomic write to symlink-resolved path; `SettingDescriptor.scope = .synced | .local`; `local.toml` in Application Support, local wins; wrong-type keys fall back to default with an alert; watcher ignores own writes.
- AD-9: All Keychain access through `SecretStore` (`context.secrets`, `AdapterContext.secrets`), data protection keychain, access group `<TeamID>.<bundle id>`; notes key in `<TeamID>.<release id>.notes`, synchronizable, with recovery key; only the app process touches the Keychain. `readExternal(_:)` reads another app's credential (Claude Code login) only with per-Mac, per-Account consent in `local.toml`, in memory only; never copies, caches, writes or renews it (A57).
- AD-10: Notes: one encrypted file per note (CryptoKit), plaintext header `{format, key_id}`; ~~last writer wins per file~~ **amended 2026-11-07 (user ruling):** on a sync conflict both versions are kept, the other version saved as a new encrypted note `<title> (conflict)`, no text lost; never create a key while note files exist; key created only on explicit "Set up notes"; unknown `key_id` → waiting / recovery state, no writes; Vigie Dev uses its own folder if it can't read the release key.
- AD-11: Module data only via `context.storage` (`Application Support/<app>/modules/<id>/`); small state JSON; usage history is the only SQLite DB (GRDB) owned by `agents.usage`, ingested through `AgentAdapter.logReader`; no SwiftData/Core Data; nothing in Application Support synced; exceptions: notes folder (`context.storage.userFolder`), shelf Trash moves.
- AD-12: Sync is folder placement (iCloud Drive or git), no CloudKit; reads of synced folders off main via `NSFileCoordinator` with download-status checks; directory watchers; only ConfigStore relocates folders; `[sync] icloud` on/off moves the config and notes folders into/out of `iCloud Drive/Vigie/`.
- AD-13: All alerts via Notifier; only the Notch Host shows peeks; Notifier is the only reader of `notify` tables and `[sounds]`; canonical kinds `session.blocked`, `session.done`, `session.failed`, `usage.quota_warning`, `shelf.expiring`, `time.timer_end` (Timer or Countdown end, Pomodoro break end), `time.break_reminder` (break reminder or Pomodoro work-phase end; amended 2026-11-07, user ruling), `calendar.reminder` (amended 2026-11-07), `setup.problem`; sound-capable: the three `session.*`, `usage.quota_warning`, `time.timer_end` → `[sounds] timer_end`, `time.break_reminder` → `[sounds] break_reminder`, `calendar.reminder` → `[sounds] calendar_reminder` (off by default); every output passes the Privacy filter (AD-24); `AlertHandle.resolve()`; typed actions `.module(id:actionID:payload:)`, `.openSettings(pane:)`, `.openURL`; focus requires a `UserIntent` token; at most one key surface; hotkeys namespaced `<module id>.<name>`, earlier registration wins, later raises setup-problem; peek shortcuts take precedence while visible.
- AD-14: Themes are TOML token files with `schema`; built-ins generated from DESIGN.md frontmatter by a `themegen` executable in VigieUI, CI fails on diff; custom themes can't reuse built-in ids; resolution order base → skin → look → custom → `[appearance.colors]` → `[appearance.colors.<look>]` → accessibility; physical notch always dark look; presence and accessibility resolved once in VigieUI.
- AD-15: Strings only from per-package String Catalogs (`bundle: .module`); status labels defined once in VigieUI as public API; InfoPlist catalog; CI builds via `xcodebuild` and checks shipped locales.
- AD-16: Dependency allowlist = Stack table (Sparkle, GRDB, KeyboardShortcuts, swift-toml, Yams, swift-markdown); no telemetry; network only Sparkle, opt-in plan providers via `AdapterContext.http`, scripts, and script install and update fetches (user-initiated `vigie://install` or user-enabled update checks, HTTPS only, through integrations); user-triggered "Copy diagnostics" without secrets.
- AD-17: Dev build isolation via one `AppEnvironment` (declared in Wire, compile-time flag): bundle id `fr.baguettelabs.vigie(.dev)`, CLI name `vigie-dev`, Application Support, socket, spool, lock, `local.toml`, URL scheme `vigie-dev`; socket path ≤ 100 bytes else `DARWIN_USER_TEMP_DIR` fallback; dev builds signed with a stable Apple Development identity.
- AD-18: Only the integrations runner executes scripts: runtime via `context.executables`, `VIGIE_SETTING_*`, timeout kills process group, output validated; confirmation keyed by relative path + SHA-256 in `local.toml`; one dynamic `NotchModule` per confirmed script; reserved ids, duplicate ids errored; host-owned keys forbidden in script settings; widgets rendered only by VigieUI templates. **Install from link:** `vigie://install` routed to integrations only, HTTPS fetch, full file + source + author shown, nothing written until confirmed. **Updates:** at most daily, diff then new confirmation; old version runs until confirmed. **Signatures:** detached Ed25519 verified with CryptoKit against compiled-in keys; valid → "Verified: Vigie Script repository", else stronger warning; never replaces confirmation.
- AD-19: `ModuleContext` exposes exactly settings, storage, secrets, scheduler, hotkeys, notifier, events, host, permissions, power, clipboard, executables, privacy, away, activity, log; `AdapterContext` exposes settings (read-only), secrets, executables, http, log. `DropZone` (Sendable) `{ id, label, glyph, accentToken, role: .primary | .secondary, cell: DropCell, order, accepts, handler(DropPayload) }`; `DropPayload { urls, modifiers, source: .dropDisplay | .shelfTab | .homeWidget | .stashItem | .paste | .service }`; the host owns and lays out the drag-only drop display (4 × 2, layout B), hides disabled zones and reflows; Shelf renders the zones on its tab (`SEND TO`) and Home widget; Shelf disabled ⇒ Stash, AirDrop and Image to Text disappear, Ask AI stays while `agents.sessions` is on; file promises materialized into `<Application Support>/drops/`; security-scoped access handled by Shelf.
- AD-20: Unsandboxed, Hardened Runtime, Developer ID with embedded provisioning profile; entitlements only apple-events + keychain-access-groups; CLI signed with no entitlements; Info.plist `LSUIElement = YES`, `NSAppleEventsUsageDescription`, `NSCalendarsFullAccessUsageDescription`, `CFBundleURLTypes` (`vigie`, `vigie-dev` in dev), `NSServices` (`Stash in Vigie`, file URLs and text; no new target); `Permission` cases `.accessibility`, `.automation(bundleID)`, `.calendar`, `.notifications`, `.screenRecording` (only if the Privacy detection method needs it and automatic detection is on). **Release hosting:** code repository private; DMGs, update zips and appcast on a public releases-only repository or static host; `SUFeedURL` and Homebrew cask point there.
- AD-21: One accessory GUI process + short-lived CLI and script children; no XPC/LaunchAgents/helpers; launch at login only via `SMAppService.mainApp`; never a Dock icon; single instance via `flock` on `instance.lock`, second launch sends `app.expand` and quits; socket unlinked only while holding the lock and only if inode unchanged.
- AD-22: `CLIInstaller` keeps `~/.local/bin/<cliName>` symlink at every launch; hooks use the absolute symlink path; adapters only produce `ConfigDiff`s; `IntegrationInstaller` shows diff, checks base hash, writes timestamped backup, applies atomically, records in `local.toml`; managed entries identified only by exact command `<symlink> hook <adapter id>`. Exception: a single-program agent hook (Codex `notify`) may be chained through a Vigie wrapper only on the user's explicit choice; the original argv is recorded in `local.toml` and restored on Disconnect (A71).
- AD-23: Adapters `Sendable`; version detection with `unsupported(version)` → setup-problem; one `logReader` per adapter shared by both agent modules; adapter settings at SPEC paths, edited only on Settings › Agents, read-only view for `agents.usage`; usage identity = adapter id + Account (one provider per adapter serving all its Accounts; Account bound to its config/log location; closed-notch ring shows the Account of the most recent session, Usage tab every Account; per-Account settings and Keychain items); `TerminalAdapter` = `matches(env:)`, pure `capture(env:pid:tty:)`, `focus(_:)`, `openTab(argv:cwd:)`; Apple Events/AX only from user actions.
- AD-24: Privacy mode is a host-level display filter: core `PrivacyService` (`context.privacy`) from automatic detection or force-on; modules mark user-supplied fields `Sensitive`; VigieUI and Notifier redact them (peeks and macOS notifications included); glyphs, rings and numbers stay; script widget text sensitive by default; no opt-out.
- AD-25: Away is a shared host service (`context.away`): input idle time (Quartz, unaffected by Keep-awake) plus lock, screensaver and display sleep; 90 s threshold; no camera, no permission; Time consumes it; modules never read idle time directly.
- AD-26: Local activity log: core `ActivityLog` of alerts, peeks, reminders and Focus outcomes; JSON Lines in Application Support, one file per day, 30 days, never synced or sent; no secrets, note content or raw script output; modules write only through `context.activity`.
- Conventions: lowercase dotted module ids; adapter ids single word; durations as strings; ISO 8601 UTC; JSON state files with `schema`, atomic, coalesced ≤ 1 write / 250 ms, `.corrupt` fallback; `os.Logger` (subsystem = bundle id, category = module id), never log secrets or note content; permissions only via `context.permissions`; hotkeys only via `context.hotkeys` (KeyboardShortcuts), Recorder only in Settings, no Option-only defaults; executables only via resolver; adapter fixtures under `Packages/Adapters/<Name>/Tests/Fixtures/<cli-version>/`.
- Stack pins: macOS 15.0 target; Swift 6 mode, toolchain Swift 6.4 / Xcode 27.1 in CI (`.xcode-version`), local floor Swift 6.3 / Xcode 26.4; Sparkle 2.10.x (≥ 2.10.1); GRDB 7.12.x; KeyboardShortcuts 3.1.x; swift-toml 2.1.0 (decode only); Yams 6.2.x; swift-markdown 0.8.x; CI runners `macos-26` arm64.
- Deferred by architecture (handled as research stories or "Later"): Warp/Ghostty focus technique (spikes), host-slept detection and pre-sleep warning, Ask AI launch syntax, DND detection and replay, notch-app coexistence, touch input, island mode, ActivityKit, menu bar fallback, script sandboxing and script alerts, Touch ID, full VoiceOver, UI snapshot tests, Privacy detection method (spike), releases host choice. (blocked/failed > slots decided by A19; side-slot arbitration decided by SPEC v0.7 §5.)

### UX Design Requirements

Extracted from `DESIGN.md` (visual, tokens) and `EXPERIENCE.md` (behavior) as one contract. `[ASSUMPTION]` items in the spines are adopted as requirements (A6).

**Design tokens**

UX-DR1: Chrome Hologram (A) color tokens for dark and light looks: `base-island/band/shadow` (#000000), `surface-panel`, `surface-card`, `ink-1/2/3`, `line`, `status-{idle,working,done,blocked,failed}`, `pace-on`, `pace-ahead`, `quota-warning`, A accents `iris-1/2/3`, `line-silver`, light `filament-1/2/3`, light `surface-vn-top/bottom`; values exactly as DESIGN.md frontmatter. **Amended 2026-11-07 (epics update run):** adds the role `quota-warning-text` (light looks: `#7E6300`; resolves to `quota-warning` in dark) and the darkened A light `status-idle #0B7651` / `status-done #1A68B5`.
UX-DR2: Twin Metal Tactical (C) color tokens for dark and light looks: same roles plus `struct`, `gold`, `gold-text`; `c-light-pace-on = #4F6A00` ~~(spine assumption)~~ **Amended 2026-11-07 (epics update run):** adopted in the 1.7f pass; adds `c-light-quota-warning-text #7E6300`.
UX-DR3: A typography tokens (readout-value, readout-label, kicker, peek-title, body, action, tab, card-title, row-primary, row-status, numeral-big, code) on SF Pro / SF Mono, with the DESIGN role table mapping; tabular numerals for live values; no bundled fonts. **Amended 2026-11-07 (epics update run):** adds `a-time-value` (Time remaining values).
UX-DR4: C typography tokens (Avenir Next Condensed with DIN Condensed fallback for labels, SF Mono values, SF Pro prose incl. `c-prose`), same role mapping. **Amended 2026-11-07 (epics update run):** adds `c-time-value`.
UX-DR5: Radius tokens: island-closed 14 (bottom corners only), peek 22, expanded 24, notes-panel 16, a-card 16, a-setup-card 14, a-zone 13, a-row 10, a-day-cell 8, a-code 5, c-card / c-action 0, full 9999. **Amended 2026-11-07 (epics update run):** adds `a-mini-zone` 11; drop display uses the peek radius.
UX-DR6: Spacing tokens: band-height 34, wing-padding-x 16, wing-gap 9, glyph-gap 7, peek-inset-x 26, peek-column-gap 18, peek-timer-bottom 12, expanded-bar-padding-x 20, tabs-margin-x 16, tab-padding-x 12, grid-gap 10, grid-padding-x 16, card-padding 12×13, action-gap 8, row-gap 10. **Amended 2026-11-07 (epics update run):** adds `drop-grid-*` insets, `drop-band-padding-x`, `mini-zone-gap` 6 and `tab-row-gap`, values exactly as DESIGN frontmatter.
UX-DR7: Motion tokens: enter 280 ms, ambient-loop 6 s, working-cycle 1.5 s, blocked-cycle 1.8 s, failed-cycle 1.8 s, calm-pulse 2.6 s, peek-dwell 5 s (configurable), panel-scan 7 s, dial-bezel 14 s, c-usage-bezel 30 s, a-card-iris 12 s. **Amended 2026-11-07 (epics update run):** adds `exit` 200 ms (provisional), `peek-grow` 280 ms, `drop-display-grow` 180 ms, `confirm-readout` 2 s (see UX-DR96).
UX-DR8: Component geometry tokens: closed island 540×34 reference, peek 700×150, expanded 720×420, notes panel 460×372, status glyph 16/26, quota dial 24/23/58, action button 30, session-row columns, tab bar 30, setup card max 380 with 18×20 padding, month grid 300 / `22px repeat(7,36px)` / 37, ~~Ask AI card 212~~, panel shadows (dark/light). **Amended 2026-11-07 (epics update run):** `SEND TO` card 212 replaces the Ask AI card; adds the component geometry of the drop display (700 × 196, 4 × 2), `send-to-card`, `home-grid` (222 × 138 cells), `script-card`, `script-page`, `time-tab`, `time-ring` (23/30/26), `phase-pips`, `settings-gear`, `status-vocabulary` (26/16/10), `selection-ring`, `copied-readout` and `peek-panel.columns-three-actions` (196), values exactly as DESIGN frontmatter.

**Visual rules**

UX-DR9: The hardware island is always `#000000` and renders with the active variant's dark role set in both appearances; peek and expanded panels keep a 34 px black band at the top (wordmark and clock on expanded) and only the body below switches to light material; the floating notes panel has no band.
UX-DR10: Strict containment and elevation: nothing drawn outside the island or panel outline (no hairlines, readouts, glows on the menu bar/desktop; hover reactions, drop zones, scroll fades and drag ghosts inside); panels cast only a neutral drop shadow; no colored glow escapes an outline; light looks drop all glows.
UX-DR11: Status color defaults per look (DESIGN status table), each user-configurable per look; ~~working hue doubles as generic warning hue (script warn threshold, shelf expiry) always paired with a triangle.~~ **[A43 ruled 2026-11-06: script warn and shelf expiry use the quota-warning yellow instead, still paired with a triangle.]** **Amended 2026-11-07 (epics update run):** non-quota warnings (script warn, shelf expiry) use `quota-warning` with a triangle; the working hue means only working.
UX-DR12: Pace and quota-warning roles: A metal = within pace / Ember = ahead; C inverted (Volt within pace, gold ahead); signal-yellow quota warning shared by A and C, never color-only (hatched fill 135° 3px/2px@40%, triangle, `WARN`); quota warning wins over pace-ahead; closed island always uses dark values.
UX-DR13: Contrast: every text color reaches ≥ 4.5:1 on its surface; `c-light-gold` only for frames/arcs/markers/fills, gold text uses `gold-text`; ~~`c-light-quota-warning` text only on `surface-card`~~ **Amended 2026-11-07 (epics update run):** warning text uses `quota-warning-text #7E6300` on any surface in A light and C light, `#8A6D00` only for fills (see UX-DR94); the settings window shows the contrast of a custom color but does not block it.

**Components** (visual spec in DESIGN.md Components, behavior in EXPERIENCE.md Component Patterns)

UX-DR14: Closed island: two wings either side of the cut-out, `wing-gap` inside; ornaments inside the outline only — A: 1px iris rim along bottom and sides + interior shimmer; C: 1px struct hairline, lower corner marks, 3px tick scale, 28px gold tracer; plain display `menu_bar` style in light looks fills `surface-vn-top → surface-vn-bottom` with the light role set. Mockup: `mockups/key-closed-notch-states.html`.
UX-DR15: Hover reaction inside the outline over `motion.enter`: A rim to full strength, interior lift, one shimmer; C hairline and corner marks brighten, tracer runs once.
UX-DR16: Quota dial: 24px (23 stacked, 58 on Usage tab), track in `line`; nesting inner 5h (thicker, primary fill) / outer weekly (thinner, A silver / C struct); value inside = 5h or the only window; single window = one ring at single size, no empty ring; fills pace-on / pace-ahead / quota-warning (triangle replaces value on the ring centre); pace marker = radial tick with 1px black keyline, arc ends before it on pace, runs past it when ahead; C dashed tick bezel turning every `dial-bezel`; calm = flat silver. Mockups: `key-closed-notch-states.html` (c, f, g), `key-usage-tab.html`.
UX-DR17: Readout: value over label; single-provider left wing (`38 %` / `CLAUDE · WEEK`) and the right-wing empty-state labels in `ink-3`. **Amended 2026-11-07 (epics update run):** the same readout serves the script side-slot item, the Time readout (UX-DR88) and the `COPIED` readout (UX-DR85).
UX-DR18: Status glyph: 16px (26 large); fixed shapes per variant — A: idle hollow ring, working spinning ¼ arc (1.5 s), done ring + check, blocked solid diamond with ripple (1.8 s), failed × double stutter (1.8 s); C: dot in circle, triangle in turning tick ring, check in circle, square in breathing brackets, X in square frame with stutter; A dark glyphs carry a soft halo, light looks none.
UX-DR19: Overflow count `+X` after the visible glyphs, readout-label style, `ink-3`; nothing else counts sessions. **Amended 2026-11-07 (epics update run):** `+X` on either wing; on the left it counts lower-priority items and never covers an item in alert.
UX-DR20: ~~Closed-notch drop zones during an external file drag: Stash (left wing), Ask AI (right wing).~~ **Superseded 2026-11-07 (Story 1.7c):** a drag-only drop display (700 × 196, peek radius, black band `DROP · 1 ITEM` / `ESC · CANCEL`) grows out of the notch only while a file is dragged over it; layout B 4 × 2: Stash 2 × 2, Ask AI 1 × 2 (round `+` target, hint `⌥ ALT FOLDER`, lit with ⌥ held), AirDrop and Image to Text 1 × 1 stacked; hidden zones reflow; drag-hover = solid accent border + tint + `RELEASE TO …`; Esc cancels; macOS cursor and drag ghost. Mockup: `ux-designs/ux-vigie-2026-11-04/mockups/key-design-pass-1-7.html` (1.7c, Option B). **Amended 2026-11-07 (epics update run):** **superseded by UX-DR83** (full drop display spec); kept for history.
UX-DR21: Peek alert panel 700×150, grid `44px | 1fr | 176px`: beacon (A round radial tint + inner ring; C square with corner brackets) holding the 26px glyph; kicker `STATE · REASON` in alert hue + live `T+` in `ink-3` for blocked/failed only; title `project / branch-or-path`; detail with code chip (A rose on 7% tint; C gold text); edge takes the alert hue (A rim at blocked-cycle); 1px dwell timer draining left along the bottom (inset 26, 12 up); variants blocked / done / failed; A peek faint radial tint from below in dark. Mockup: `key-alert-variants.html`.
UX-DR22: Setup-problem alert: same frame and dwell, no beacon, no glyph, no status hue, static neutral rim; kicker `SETUP` + category (`ADAPTER · VERSION CHECK`); problem as title; one factual sentence; actions `OPEN SETTINGS ⌥⌘↵` / `DISMISS ⌥⌘⌫`; target pane named beside actions in `ink-3` (`SETTINGS › AGENTS › CODEX`). Mockup: `key-alert-variants.html` (variant 4).
UX-DR23: In-tab setup card: centred, max 380px, neutral 1px inner outline (A platinum 16% dark / graphite 14% light), 2.5% fill, `i`-in-square mark, `SETUP · <topic>` kicker, title, one sentence, two buttons (System Settings + module pane). Mockup: `key-calendar-tab.html` (03).
UX-DR24: Empty state block: centred uppercase `ink-3` label, one factual prose sentence, optional button to the relevant Settings pane.
UX-DR25: Action button 30px, two stacked `action-gap` apart, label left, shortcut right; A pill with 1px platinum 22% border and glass gradient (secondary: no fill, dimmer border; light: white → #EEF1F5 + 1px shadow); C square, struct 30% inner border, primary gold inner frame + gold-text + gold gradient 16%→3%; inline chips (`FOCUS ↵`, `JOIN CALL ↵`, `COPY`, `REVEAL`).
UX-DR26: Expanded panel 720×420: band with wordmark `VIGIE` (A iris-gradient text, 0.5em tracking; C condensed caps with gold `·`) and right-side status `● Online · 14:48 · Wed 04 Nov` in `ink-2` with the dot in `status-idle`; A slow vertical scan in the body (`panel-scan`).
UX-DR27: Tab bar 30px: A pill container (3.5% white, inner hairline), active tab raised pill; C 1px `line` underline, active tab gold text with 2px gold underline; alert marker 5px in blocked hue (A diamond, C square).
UX-DR28: Widget card: 11px header row with title (card-title) left and meta right in `ink-3`; A 1px iris filament on top edge at 45% (80% light) animating every `a-card-iris`; C four 7px inner corner marks in struct 38%; tab bodies reuse the frame.
UX-DR29: Scroll and reorder affordances: overflowing lists fade the last row under a bottom mask, thin thumb inside the card's right edge (2px Agents, 3px track Usage), optional `SCROLL ↓` footer hint; reorderable cards carry a 6-dot grip.
UX-DR30: Session row 30px, Agents grid `18 | 84 | 1fr | 62 | 104 | 76` (glyph, agent, project + last action in mono `ink-3`, terminal, `STATUS · T+`, Focus chip), terminal column dropped when single terminal; Home widget grid `18 | 92 | 1fr | 64`; blocked/failed rows tinted (A 10% fade + 1px inner outline; C fade + 2px left bar); hover brightens and shows `FOCUS`; keyboard selection adds 1px ring + `↵`; header `SESSIONS · 9 · 3 ALERTS`, hints `↑↓ SELECT · ↵ FOCUS · ⌘1–9 TABS · ESC`, meta `SORTED BY URGENCY`, column headers. Mockup: `key-agents-tab.html`.
UX-DR31: Usage provider card: grip, provider name, meta (`MAX · WARN 80%`, `ULTRA · WEEKLY ONLY`, `DAILY QUOTA ONLY`); 58px dial with big value; one bar per window with value, reset (`RESET 16:40 · IN 1H52`), pace line (`ELAPSED 63%` + label); bars A 5h platinum / weekly silver, C Volt; 2px platinum pace marker; dashed threshold tick on every bar; ahead = solid pace-ahead fill + `AHEAD OF PACE · +9`; within = metal + `WITHIN PACE` / `WITHIN PACE · +3`; warning = hatched quota-warning + triangle + `WARN · ≥ 80%` (wins); right half `HISTORY · 7D` (one series per agent, weekday initials) and `COST · TODAY` per project with `FROM LOCAL LOGS · OFFLINE`; footer `DRAG TO REORDER · ALSO IN SETTINGS` and `SCROLL ↓` beyond two providers. Mockup: `key-usage-tab.html`.
UX-DR32: Drop zones in panels: Stash (A 3% fill + hairline; C struct-ruled rows); Ask AI dashed 1px border (A lilac 35%, C gold 55%), round `+` target (A breathes on `calm-pulse` in dark, static in light), label `ASK AI`; ~~Shelf-tab Ask AI card (212px) shows `AGENT`, `FOLDER`, `⌥ FOLDER`~~ **Amended 2026-11-07 (epics update run):** the Shelf tab shows the `SEND TO` card (212px, UX-DR84) whose 84px Ask AI zone shows `AGENT`, `FOLDER`, `⌥ FOLDER`; drag-hover = solid lilac (C gold) border + inner tint, label `RELEASE TO ASK` naming agent and folder; with ⌥ the default-folder row dims, `⌥ FOLDER` lights, ghost carries ⌥ badge. Mockup: `key-shelf-tab.html`.
UX-DR33: Shelf row: columns item (name, `size · mode`), source app, added, expires; expires text `6D LEFT` (≥ 2 days), `1D 18H LEFT` (< 2 days), `EXPIRES IN 5H` (< 24 h) over a thin metal TTL bar; expiry warning (last 24 h) = quota-warning yellow (A43) + small triangle and `1 EXPIRING` in card meta; pinned = dashed lilac line + `PINNED`; hover chips `QUICK LOOK · REVEAL · PIN` replace source/added, grip shows `DRAG · MOVE  ⌥ DRAG · COPY`; footer `DRAG OUT MOVE · ⌥ DRAG COPY · ␣ QUICK LOOK` + expiry rule; Home shelf widget puts the expiring item on top with a `5H` tag and a warning line `1 EXPIRES IN 5H`. Mockup: `key-shelf-tab.html`.
UX-DR34: Month grid (Itsycal structure, 300px card): header `NOVEMBER 2026` with `‹ ● ›`, Monday-first weekday initials, ISO week column, 36×37 cells, one dot per calendar (EventKit color), no counts, adjacent-month days dimmed, 1px platinum 28% line tracing the month; today = 1px rounded outline in the now color (A `iris-1`, C gold); selected day = platinum tint + hairline; header dot dim when today in view and selected, lit when the user can jump back; legend under the grid. Mockup: `key-calendar-tab.html`.
UX-DR35: Upcoming list and event track: day headers (`TODAY · WED 04 NOV`, `THU 05 NOV · TOMORROW`), all-day events as header chips; hero row for the next event (big numeral time, title, `IN 42 MIN` in now color, 1px track now → event with now marker A cyan dot / C gold diamond, `JOIN CALL ↵` only with a video link); other rows time · calendar dot · title (+ video tag) · calendar · relative time; ≤ 5 events then `+N LATER THIS WEEK`; the same track serves the Home calendar card.
UX-DR36: Script widget templates in the card frame for `status`, `number` and `text`; number = big numeral + segmented 6px bar (A platinum → silver, C silver → white) with the warn segment outlined in quota-warning yellow (A43; mocked `GitHub PRs · 3 open · Warn ≥ 5`); status uses the shared status vocabulary (OK ring / WARN triangle / DOWN ×, idle / quota-warning / failed hues, with label) and text = label + value + updated time, per Story 1.7d (2026-11-07; supersedes A39).
UX-DR37: Floating notes panel 460×372, `surface-panel`, no band, iris filament on top; header `NOTES · <title>` with `SYNCED · ENCRYPTED · ESC`; footer `EDITED 14:31` and, after a copy, `COPIED · CLEARS IN 30S` with a 1px line draining over the clipboard delay. Mockup: `key-notes.html`.
UX-DR38: Secret mask: inline = fixed-width dots in an `a-code` chip, hover brightens + `COPY`, revealed = plain text in rose code tint, copied = cyan outline + `COPIED`; block = card `SECRET · 4 LINES` with `REVEAL` / `COPY` chips and rows of fixed-width dots; Notes tab list (232px) with title, last edit and one-line summary showing only the secret count (`2 SECRETS`), preview right with every secret masked, search field and note count on top. Mockup: `key-notes.html`.
UX-DR39: Settings and onboarding are native macOS windows using system text styles; previews inside them use Vigie tokens.
UX-DR40: Interaction depth: depth from tone (`surface-card` over `surface-panel`, 1px inner hairline — A translucent platinum, C corner marks); hover brightens a row; keyboard selection adds a 1px ring (A platinum dark / graphite light) that stacks on any alert tint.
UX-DR41: Information placement: left wing = priority item lane (quota rings, script items, Time readout; amended 2026-11-07), right wing sessions, identical in both variants; peek grid; expanded = band, tab bar, body; Home ~~3 columns (`1.2fr 1.2fr 1.1fr`) × 2 rows (162, 138), cards may span two columns~~ 3 equal columns, one fixed card size 222 × 138, no spans (amended 2026-11-07); Agents one full-width card; Usage 50/50; Shelf Stash `1fr` + `SEND TO` card 212 (Ask AI, AirDrop, Image to Text; amended 2026-11-07); Calendar month 300 + list; Notes list 232 + preview.
UX-DR42: Presence levels visuals — Full: A rim slide + shimmer (`ambient-loop`), panel scan, working arc spins, blocked ripple, failed stutter; C tracer, dial bezel turning, working ring turns, brackets breathe, failed stutter. Calm: A no shimmer/slide/scan, rim = flat platinum line, working arc frozen, quota arcs flat silver, ~~only blocked diamond moves~~ only a blocked diamond or failed × moves (one halo per `calm-pulse`); C no tracer/turning/breathing, bezel and marks static dimmer, gold → struct silver, ~~only blocked square pulses~~ only a blocked square or failed X frame pulses. **Amended 2026-11-07 (epics update run):** blocked **and** failed keep the calm pulse (PRD FR-37, user ruling 2026-11-07; DESIGN fixed the same day). In calm values update without transitions; with nothing blocked/failed the notch is perfectly still. Mockups: `key-closed-notch-states.html` (i), `compare-a-vs-c-v3.html`.
UX-DR43: Voice and tone: compact UI = short uppercase technical labels; longer messages terse factual complete sentences, no exclamation marks, no personification, no emoji; wording identical in every variant; status labels `IDLE`, `WORKING · 14M`, `DONE · 1M`, `BLOCKED · 12M`, `FAILED · 41M`; examples from the EXPERIENCE Do/Don't table (`BLOCKED · NEEDS INPUT`, `FAILED · HOST SLEPT`, `Turn ended · 3 files`, `Codex adapter: CLI version 0.9.2 unsupported`, `RESET 16:40 · IN 1H52`, `6D LEFT`).
UX-DR44: Specified copy for empty and setup states: `NO AGENT CONNECTED` + "Connect Claude Code, Codex or Gemini in Settings."; `NO ACTIVE SESSIONS` + "Agent sessions appear here when they start."; `NO USAGE PROVIDER` + one sentence + `Open settings ⌘,`; `STASH EMPTY` + ~~"Drag a file, text or image onto the notch to keep it here for N days."~~ "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for N days."; Calendar setup `Vigie can't read your calendars` with `Open System Settings` and `Calendar settings`; `NO EVENTS TODAY`. **Amended 2026-11-07 (epics update run):** plus the copy in UX-DR100 (`NO WIDGETS`, `READING LOGS…`, `NO HISTORY YET`, `NO COST DATA`, `NOTHING RUNNING`, `NO NOTES`, `NO MATCH`, `NOTES LOCKED`).

**Interaction primitives** (EXPERIENCE.md)

UX-DR45: Never steal focus: panels non-activating; surfaces opened by an alert or a drag take no keyboard focus and expose no non-global shortcuts.
UX-DR46: Hover on the closed notch = small reaction only (opens only if hover-to-open enabled); click opens the expanded view on Home with focus; global expand shortcut opens with focus.
UX-DR47: Click outside the expanded view collapses it; leave-to-close is opt-in.
UX-DR48: Keyboard in expanded (only when focused): `⌘1…9` tabs, `↑↓` selection, `↵` acts, Space Quick Look on Shelf, Esc closes. **Amended 2026-11-07 (epics update run):** `↵` also = Start on the Time quick start, Start break on a break-due row, the `Send to` menu on a Shelf row; `⌘V` on the Shelf stashes the clipboard; Tab / `←→` reach the settings gear (`↵` / Space opens Settings); Time tab keys per EXPERIENCE Time.
UX-DR49: Peek shortcuts ~~`⌥⌘↵` (Focus terminal / Open settings) and `⌥⌘⌫` (Dismiss)~~ **Amended 2026-11-07 (epics update run):** `⌥⌘↵` primary (Focus terminal, Open settings, Open Usage, Open Agents, Open Time, Start break, Join call / Open Calendar), `⌥⌘⌫` Dismiss (Skip on the break peek), `⌥⌘Z` Snooze 5m (break peek only); all are global, registered only while the peek is visible and unregistered on retract, each shown on its button; never bare Esc or common keys.
UX-DR50: Drag interactions (amended 2026-11-07): external file drag → drag-only drop display on the notch (Stash, Ask AI, AirDrop, Image to Text); the drop happens on the drop display (expanded view is not a target for outside drags); non-drag paths per Story 9.10; ⌥ on Ask AI = alternate folder; stash item dragged onto Ask AI (Shelf tab) = same launch; stash item dragged out = move, ⌥ = copy (both ⌥ meanings accepted).
UX-DR51: Dragging a provider card reorders the Usage list and the same order shows in Settings.
UX-DR52: Calendar: day click starts the upcoming list at that day; `‹ ›` change the grid month only (list keeps its day); the lit header dot returns to today and the current month.
UX-DR53: Secret click toggles reveal; `COPY` copies without revealing.
UX-DR54: Theme, appearance and presence changes apply live with no restart.
UX-DR55: Banned: acting on a session on the user's behalf (approve, deny, send), mascots/avatars, auto-opening the expanded view, taking focus on alerts, bypassing Do Not Disturb; no crosshairs, reticles, radar rings or targeting frames.

**States** (EXPERIENCE.md State Patterns)

UX-DR56: Session state visuals: idle static, working animated, done static (no T+), blocked/failed top-priority glyph with T+ (from wake for host-slept); urgency order; done → idle after delay; stale and process-only keep SPEC behavior with the Story 1.7b looks (2026-11-07): stale = dashed ring with `?` inside, `STALE · <time>`; process-only = plain grey dot, `RUNNING`; both `ink-3`, no hue, sorted after idle.
UX-DR57: Agents surface states: no agent connected (right wing label only, left wing black, expanded empty state → Settings › Agents), nothing running (`NO ACTIVE SESSIONS`, rings stay), interrupted by sleep (`FAILED · HOST SLEPT`, `Run interrupted during …`), overflow `+X` never hides blocked/failed.
UX-DR58: Usage surface states: quota warning (threshold per provider, alert or visual, % only), pace ahead (visual only, hidden under quota warning), window absent (only plan windows, pace on weekly without 5h), no usage provider.
UX-DR59: Shelf surface states: item expiring (quota-warning yellow + triangle, `EXPIRES IN 5H`, optional notification, no sound), item expired (refs leave, copies/saved → Trash), stash empty (Ask AI stays usable).
UX-DR60: Calendar surface states: access missing (setup card), no events today (grid stays, no dot on today, list shows `NO EVENTS TODAY` then following days).
UX-DR61: Script surface states: errored (last good output + warning badge), awaiting confirmation (not running until confirmed on this Mac).
UX-DR62: Global surface states: setup problem (own neutral UI, never an agent state), focus fails (terminal app activates, no error toast), Do Not Disturb (alerts and sounds suppressed, notch updates), full-screen app (hidden on that display).

**Accessibility floor**

UX-DR63: Every control and glyph has an accessibility label with state, format "vigie / api-refactor, blocked, 2 minutes".
UX-DR64: Reduce motion forces calm and stops loops; Settings shows a warning explaining the override next to the presence setting; the remaining attention pulse becomes an opacity change with no scale; T+ counters show static values.
UX-DR65: Reduce transparency and Increase contrast: glass gradients become flat `surface-panel` / `surface-card` fills; hairlines move to `ink-3`.
UX-DR66: Keyboard: every expanded-view action is reachable when it has focus; peek actions are reachable through the global shortcuts.

**Key flows** (acceptance journeys)

UX-DR67: Flow 1 — Multi-session day: multiple Claude/Codex sessions in Warp; right wing urgency order + `+2`; nested rings within pace; blocked peek once with editor keeping focus; `⌥⌘↵` brings the exact tab; peek retracts after 5 s; done → idle after 15 min; Agents tab via click + `⌘2`, no terminal column, Esc closes; failure paths (missed peek → glyph, tab marker, T+, reminder; tab not locatable → app activates; DND → no peek, glyph changes).
UX-DR68: Flow 2 — Wake after sleep: working session interrupted by lid close becomes failed on wake with `FAILED · HOST SLEPT`, T+ from wake, interrupted command, `FOCUS TERMINAL`; ~~several sessions → one alert each~~ **Amended 2026-11-07 (epics update run):** several sessions → one summary alert `<n> sessions interrupted by sleep` with `OPEN AGENTS ⌥⌘↵` (A20, Story 4.12); each session is still failed in the Agents tab.
UX-DR69: Flow 3 — First week: Homebrew install, onboarding (theme live preview, agent detection + hook diffs, Accessibility, displays incl. virtual notch on external, sounds), peek on the display under the cursor without stealing focus from Slack, exact iTerm2 tab focus; failure paths (Accessibility skipped → app-level focus + setup-problem alert; unsupported Codex → setup-problem).
UX-DR70: Flow 4 — Ask AI drop: drag from browser → drop display (amended 2026-11-07; replaces closed-notch zones) → drop on Ask AI → new terminal tab in default folder with default agent and file attached/pasted, no dialog; ⌥ alternate folder; stash item onto Ask AI shows `RELEASE TO ASK`; failures (no attachment support → paste; agent missing → setup-problem).
UX-DR71: Flow 5 — Script via sync: script written on Mac A with a secret token; arrives on Mac B via iCloud without the token; shows awaiting confirmation; whole-file review; confirm + enter token → first run shows value; decline → disabled on that Mac only; non-zero exit → last good output + badge.

**Sounds, customization, settings, platform**

UX-DR72: Sounds: fully optional (asked at onboarding); seven events (amended 2026-11-07: plus timer end, break reminder and calendar reminder, all off by default); built-in sounds sci-fi register, simple, < 1 s; custom files any length; play once with alert, replay with reminder, follow DND; pace and shelf expiry silent.
UX-DR73: Customization surface: closed-notch slots per side (3 default, max ~4), quota rings 5h / 5h+weekly, pace on/off and tolerance, usage provider order, open/close behavior (click vs hover/leave), peek dwell, reminder delay, done → idle delay.
UX-DR74: Settings panes: ~~General, Appearance (variant, forced light/dark, presence, status/pace/warning colors), Displays, Agents, Usage, Shelf, Calendar, Notes, Scripts, Sounds, Sync, Updates, Support~~; Reduce motion override warning next to presence. **[Changed by PRD §9 Q1: the Support pane is superseded; PRD adds a Time module pane and Privacy mode controls (A89).]** **Amended 2026-11-07 (epics update run):** panes per EXPERIENCE: General (incl. Privacy mode and Launch at login), Appearance (variant, forced light/dark, presence, status/pace/warning colors), Displays, Home, Agents, Usage, Shelf, Calendar, Time, Notes, Scripts, Sounds, Sync, Updates.
UX-DR75: Onboarding sequence: 1 theme picker (skip → Chrome Hologram, live preview), 2 agent connections + hook diffs, 3 Accessibility, 4 display choice (always asks about non-notch displays), 5 sounds on/off (+ launch at login per SPEC); each step skippable.
UX-DR76: Platform contexts: physical notch (always black, dark tokens), plain `black` (looks like hardware), plain `menu_bar` (menu-bar material, light tokens in light mode; ~~dark per A42~~ **Amended 2026-11-07 (epics update run):** in dark appearance it falls back to the black island look, `base-island` with the dark role set, until dark virtual-notch tokens exist (OQ15)), island display (plain/fallback), multiple displays (same state everywhere, expanded/peek under cursor), light/dark (black band kept), hot-plug/lid/resolution re-placement live.
UX-DR77: Do's and Don'ts: keep wording/layout/slots identical across variants; C gold reserved for active, now and ahead-of-pace (never decoration or session status); only glyphs and `+X` on the right wing (no total count, no `N ALERTS`); subtle sci-fi cues only; no mascot.
UX-DR78: Usage tab content rules: windows per provider are whichever the plan has (5h, weekly, daily for Gemini CLI); pace labels `WITHIN PACE`, `WITHIN PACE · +3`, `AHEAD OF PACE · +9`; warning `WARN · ≥ 80%`.
UX-DR79: Calendar day and event dots use macOS (EventKit) calendar colors as user data, not Vigie tokens.

**Added 2026-11-07** (design pass 1.7 and the 2026-11-07 review fixes; source lines in DESIGN.md / EXPERIENCE.md as cited)

UX-DR80: Settings gear (DESIGN Settings gear; EXPERIENCE Expanded view): a detached button at the far right of the tab row on every tab, `tabs-margin-x` from the edge and `tab-row-gap` from the tabs; 14 px outline gear, 1.2 px stroke; A 24 px round, C 26 px square; default `ink-3`; hover A raised pill / C struct border 30 %; focus A dark 1 px platinum 55 % ring + 3 px cyan halo 14 %, A light graphite ring, C selection ring; not a tab (no active state, not in `⌘1–9`); tooltip `Settings (⌘,)`; accessibility label `Settings`; Tab / `←→` reach it and `↵` / Space opens the Settings window.
UX-DR81: Stale and process-only glyphs (Story 1.7b): stale = dashed ring in `ink-3` (A r 6.6 in the 16 px slot, 1.1 px stroke, dash 2.1 / 1.8; C r 7, 1 px, dash 1.6 / 1.6) with a 9 px `?` in `ink-2`; process-only = plain 5.6 px dot in `ink-3`; static in every Presence mode, no hue, halo or row tint; row labels `STALE · 18M` / `RUNNING`, last-action line `LAST EVENT 14:30 · <last action>` / `Process seen · no hook events`; Focus still works; accessibility labels "<project>, stale, no event for 18 minutes" / "<project>, running, no status available".
UX-DR82: Status vocabulary primitive (VigieUI): OK = ring in `status-idle`, WARN = triangle in `quota-warning` (label in `quota-warning-text` on light), DOWN = × in `status-failed`; the label always accompanies the shape; optional `·` qualifier (`DOWN SINCE 14:44`, `CHECKED 2 MIN AGO`); sizes 26 / 16 / 10 px; follows the user's status colors; static in every Presence mode; never raises an alert.
UX-DR83: Drag-only drop display, layout B (replaces UX-DR20): 700 × 196, peek radius, grows out of the notch over `drop-display-grow` only while a file is dragged over it, never takes focus; black band `DROP · 1 ITEM` / `ESC · CANCEL`; 4 × 2 grid with `drop-grid-*` insets: Stash 2 × 2 (meta `KEEP 7 DAYS · 5 ITEMS`), Ask AI 1 × 2 (round `+` target, `⌥ ALT FOLDER` lit while ⌥ is held), AirDrop and Image to Text 1 × 1 stacked; reflow: one of AirDrop / Image to Text off → the other spans column 4; both off → 3 columns; Shelf off → only Ask AI; no enabled zone → no display; drag-hover = solid accent border + tint + `RELEASE TO …` line at label size; a zone that can't accept the item stays unlit; Esc or a release outside every zone cancels; rim static under Calm and Reduce motion. Mockup: `key-design-pass-1-7.html` (1.7c).
UX-DR84: `SEND TO` card on the Shelf tab (212 px wide): header `SEND TO`, meta `DEFAULTS` (after Image to Text: `LAST · 3 LINES · 14:48`); Ask AI zone 84 px tall with `ASK AI`, `Drop a file to start a session` and `AGENT` / `FOLDER` / `⌥ FOLDER` rows (no hint sentence); two 38 px mini zones `AIRDROP` / `SHARE` and `IMAGE TO TEXT` / `COPY`, `mini-zone-gap` 6, A radius 11; disabled zones are not drawn; stash items dragged onto any zone act like a notch drop.
UX-DR85: `COPIED` readout (Image to Text, left wing): `READING…` while recognition runs; `COPIED · N LINES` for `confirm-readout` (2 s) with a draining line; `NO TEXT FOUND` when nothing was recognized (clipboard unchanged); the readout holds while the pointer is over the notch; never a peek or sound; VoiceOver announces "Copied 3 lines" / "No text found"; under Reduce motion the drain is a static full line that disappears.
UX-DR86: Script surfaces: widget card 222 × 138 (`script-card`) with name + target left and cadence right in the header; templates status (UX-DR82 vocabulary, checked time), number, text; errored = last good output + WARN triangle badge on the meta line; side-slot item on the left lane with accessibility label "<name>, OK"; script page grid `1fr 212px` × `118px 1fr` with hero, `ABOUT · FROM <file>`, runs list (time, duration, exit code), chips `REVEAL` (Finder) and `OPEN SOURCE` (default editor); tab order hero → About → runs → chips; hero label e.g. "vigie.app, OK, up, 200, 142 ms, checked 2 minutes ago".
UX-DR87: Script state copy: `NOT CONFIRMED` in `ink-3` with no level glyph (click opens the Script Confirmation); `WAITING · FIRST RUN` (confirmed, no run yet, no glyph); `TIMED OUT · 30S` or the exit code on the runs card; `UPDATE AVAILABLE` badge on widget, page and Settings › Scripts while the confirmed version keeps running.
UX-DR88: Time surfaces (Story 1.7e): Time accent = A `iris-1` (light `#126F8C` for arcs and text, `filament-1` for the rim only), C gold / `gold-text`; time ring 23 px (closed) / 30 px (tab rows) / 26 px (peek beacon), solid for work and timers, dashed 2.2 / 2 for breaks; phase pips (done 4 px filled `ink-1`, current 7 px accent ring, hatched in a break, upcoming 4 px hollow `ink-3`; VoiceOver "Work, cycle 2 of 4"); closed Time readout variants time only / ring only / ring + time, `AWAY · PAUSED` with a center pause mark in ring-only mode; Time tab grid rows `84px | 1fr` (Quick start: `POMODORO 25 · 5 · 15`, `5 MIN`, `10 MIN`, `25 MIN`, `+ COUNTDOWN`, custom field + `START ↵`; Running list rows 62 px on `30 | 1fr | 92 | 196`, chips ≥ 24 px tall with 8 px gaps, `ENDED 14:48` + `DISMISS`); values in `a-time-value` / `c-time-value`; Timer-end peek: full ring beacon, kicker `TIMER · ENDED` + end time, title `<label> / <length>`, detail `Started 14:43 · ended 14:48`, `OPEN TIME ⌥⌘↵` / `DISMISS ⌥⌘⌫`.
UX-DR89: `BREAK DUE` persistence: after the break peek retracts (or at once with strength quiet) the left wing shows `BREAK DUE` (full dashed ring, `15:00` over `BREAK DUE`, static, center triangle in ring-only mode) as a left-lane item in alert state, even with `[modules.time] closed_notch = "off"`, until the break is started or skipped; Snooze keeps it; it counts as an unresolved alert for `[notify] after_focus = "replay"`.
UX-DR90: Break peek: full dashed ring beacon; kicker `BREAK · DUE` (reminder) or `POMODORO · LONG BREAK`; title `4 cycles done / 15 min break`; detail `Focused 1 h 40 min since 13:05`; three actions (the only exception to two): `START BREAK ⌥⌘↵` full width, then `SNOOZE 5M ⌥⌘Z` and `SKIP ⌥⌘⌫` side by side; action column 196 px (`peek-panel.columns-three-actions`); `⌥⌘Z` registered only while this peek is visible.
UX-DR91: Peek variants: sleep summary (failed hue, × beacon, `FAILED · HOST SLEPT`, title `<n> sessions interrupted by sleep`, `OPEN AGENTS ⌥⌘↵` / `DISMISS ⌥⌘⌫`, no `T+`); quota warning (triangle beacon in `quota-warning`, kicker `QUOTA · WARN` in `quota-warning-text` on light bodies, title `<PROVIDER> · <WINDOW> 82 %` with the Account appended when the Provider has several, detail `RESET 16:40 · IN 1H52`, `OPEN USAGE ⌥⌘↵` / `DISMISS ⌥⌘⌫`, rim and dwell line in `quota-warning`); calendar reminder (now accent, never a status hue or calendar color, 26 px event-track beacon, kicker `CALENDAR · IN 10 MIN` / `CALENDAR · NOW`, title = event title, detail `14:00–14:30 · <calendar>` + video tag, `JOIN CALL ⌥⌘↵` with a video link else `OPEN CALENDAR ⌥⌘↵`, `DISMISS ⌥⌘⌫`, nothing left on the closed notch after retract).
UX-DR92: Peek concurrency: one peek at a time; a newer blocked or failed alert replaces a visible lower-urgency peek; other alerts queue blocked / failed > break due / Timer end / calendar reminder > quota warning > done > setup problem and show after the current dwell; a queued alert whose state resolved is dropped; while the expanded view is open no peek shows (tab marker instead, sound per the alert rules); while the drop display is open peeks wait until it closes.
UX-DR93: Every peek posts a VoiceOver announcement (kicker + title + primary shortcut); each action button's accessibility label includes its shortcut.
UX-DR94: Contrast table: text ≥ 4.5:1 on its surface incl. status labels; non-text meaning ≥ 3:1 (WCAG 1.4.11: glyphs, rings, Time arcs, focus rings, zone and chip borders); in dark looks the secondary line of an alert-tinted row uses `ink-2`; warning text in A light and C light uses `quota-warning-text #7E6300` on any surface, `#8A6D00` only for hatch, triangles, arcs and fills; A light `status-idle #0B7651`, `status-done #1A68B5`; the pairs in the DESIGN contrast and further-surfaces tables are checked in CI.
UX-DR95: Increase contrast (all looks): zone, chip and card borders → solid 1 px `ink-3`; Ask AI dashed border at 100 % lilac (A) / gold (C); tracks (time ring, countdown, quota, pace) ≥ 40 % `ink-3`; focus ring 2 px, halo dropped; glass gradients flat `surface-panel` / `surface-card`; upcoming phase pips unchanged; decorative-only elements reach 3:1.
UX-DR96: Motion additions and Reduce motion: `exit` 200 ms ease-in (provisional) for collapse and retract, `peek-grow` 280 ms, `drop-display-grow` 180 ms, `confirm-readout` 2 s; under Reduce motion grows are instant or a short cross-fade, functional drains (peek dwell, `COPIED`, notes clipboard) are a static full line that disappears at the end, and the Time peek rim, Ask AI `+`, card iris filament and drop display rim are static (also in Calm).
UX-DR97: Home: one fixed card size 222 × 138 in three equal columns (`home-grid`), no spans; cards chosen and ordered in Settings › Home (tick modules and scripts, drag to order), no in-place edit mode; content that doesn't fit fades under the bottom mask; empty Home: `NO WIDGETS` + "Pick Home widgets in Settings." with `Open settings` → Settings › Home.
UX-DR98: Privacy mode visuals: every user-supplied name or text (session titles, project names, Shelf items and thumbnails, Timer labels, Account names, Widget text, calendar titles, notes, Script Confirmation body and secret fields) renders as fixed-width dots in the secret-mask style in `ink-3`; status labels, kickers, glyphs, rings, `T+`, numbers, provider and module names stay; eye-slash glyph in `ink-3` left of the settings gear and in the peek band, accessibility label "Privacy mode on"; nothing added to the closed notch; revealing a secret is unavailable; macOS notifications carry only the kind label; turning it on or off posts no peek or sound; Settings copy `Automatic (when sharing or recording)`, `Force on`, "Screen sharing can't be detected on this macOS version." where detection is impossible.
UX-DR99: Accounts UI: wing label `CLAUDE · WORK` (Account truncated to 6 characters) only when the Provider has several Accounts; the closed ring shows the Account of the most recent Session; Usage card header `<PROVIDER> · <ACCOUNT>`, one card per Account; quota peek title appends the Account; per-Account settings in Settings › Usage; failed remote fetch: last value with `STALE · HH:MM` on the card, ring keeps its value, never a wrong number.
UX-DR100: Additional empty / loading / error copy: Usage `READING LOGS…` before the first read, `NO HISTORY YET` (7-day history), `—` with `NO COST DATA` (cost); Time `NOTHING RUNNING` (Quick start stays, closed readout hidden); Notes `NO NOTES` + "Press ⌥⌘N to write one.", `NO MATCH`, `NOTES LOCKED` + "Waiting for iCloud Keychain, or enter your recovery key."; Notes sync conflict = both versions kept, the second as `<title> (conflict)`, no text lost (AD-10 amended 2026-11-07); `STASH EMPTY` sentence with "or press ⌘V"; `NO WIDGETS`; script install download failure: the Confirmation says so and offers nothing to confirm.
UX-DR101: Drop failed readout: Stash or AirDrop that can't take an item (unreadable file, disk full, AirDrop off) shows `NOT STASHED` / `AIRDROP UNAVAILABLE` on the left wing for 2 s like `COPIED`, plus an activity-log entry; not an Alert, no peek or sound.
UX-DR102: Non-drag paths to the drop zones: `Send to` menu (right-click a Shelf item or `↵` on the selected row: Ask AI, Ask AI in alternate folder, AirDrop, Image to Text for enabled zones, Quick Look, Reveal, Pin; same entries as VoiceOver custom actions); `⌘V` on the Shelf tab stashes the clipboard; Services › `Stash in Vigie` (files and text) stashes without opening Vigie; with the Shelf off the Services entry raises a setup-problem alert `Shelf is off` with `Open settings`.
UX-DR103: Vocabulary additions (extends UX-DR43; status-label API per AD-15): `STALE · 18M`, `RUNNING`, `LAST EVENT 14:30`, `DROP · 1 ITEM`, `ESC · CANCEL`, `RELEASE TO …`, `COPIED · 3 LINES`, `OK` / `WARN` / `DOWN`, `CHECKED 2 MIN AGO`, `DOWN SINCE 14:44`, `TIMER · ENDED`, `AWAY · PAUSED`, `BREAK DUE`, `START BREAK`, `SNOOZE 5M`, `SKIP`, `ENDED 14:48`, `QUOTA · WARN`, `FAILED · EXIT 2`, `UPDATE AVAILABLE`, `Verified: Vigie Script repository`.
UX-DR104: Tab attention marker: the 5 px marker shows on Agents while a session is blocked or failed and on Time while a break is due or an ended timer is unacknowledged; VoiceOver reads a marked tab as "<tab>, needs attention".
UX-DR105: Flow 6 — `vigie run`: the wrapped command appears as a session with agent `RUN`, the project folder and the command as last action; output and exit code pass through; exit 0 → done, non-zero → failed with `FAILED · EXIT 2` on the row and peek kicker; Ctrl-C ends the session with no alert.
UX-DR106: Flow 7 — community script install and update: `vigie://install` link → Script Confirmation with the full file, source, author and `Verified: Vigie Script repository` or the stronger warning; confirm → first run shows the widget with `CHECKED JUST NOW`; decline → no file written; a later update shows `UPDATE AVAILABLE`, the diff and a new Confirmation while the old version keeps running.
UX-DR107: Flow 8 — break reminder and Pomodoro variant: after the work interval (default 55 min, Away time excluded) the break peek (or quiet `BREAK DUE`) appears; Start break starts it, Snooze 5m re-raises it, Skip clears it; for a break reminder, Away for the break length counts as the break and Away shorter than the break counts as neither work nor break; during a Pomodoro, break reminders pause and the Pomodoro work-phase end raises the same break peek, which waits for Start break.

### PRD traceability (PRD FR-1..FR-64)

Added 2026-11-06. Maps each requirement of the final PRD to this file's FRs/NFRs and the stories that realize it. "New" = no earlier FR; stories were added for it.

| PRD FR | Release (PRD) | Epics FRs / NFRs | Stories | Note |
|---|---|---|---|---|
| FR-1 Display placement | v0.1 | FR19, FR22, FR23 | 2.7 | Within 2 s of a display change (2.7 AC amended 2026-11-07) |
| FR-2 Virtual notch | v0.1 | FR11, FR21, FR24–FR27 | 2.6, 2.7 | Dynamic Island Macs = plain mode in v1 (A26 resolved) |
| FR-3 Wing arbitration | v0.1 | FR9, FR10, FR37, UX-DR10 | 2.5, 2.8, 4.9 | |
| FR-4 Disabled modules cost nothing | v0.1 | FR1, FR2, NFR4 | 2.2, 2.12, 6.3 | Update check can be turned off (6.3) |
| FR-5 Never steal focus | v0.1 | FR14, FR87, FR88, NFR2, UX-DR45 | 2.1, 2.9, 2.10, 3.2 | |
| FR-6 Tabs per module | v0.1 | FR89 | 2.10, 11.1, 20.2 | |
| FR-7 Home | v0.3 | FR90, UX-DR97 | 11.1, 11.2, 11.3, 17.2 | Card click opens tab (A34 resolved); Settings › Home list, one card size, no edit mode (2026-11-07); Home pane in 17.2 |
| FR-8 Keyboard operation | v0.1 | FR91, UX-DR48, UX-DR66, UX-DR80, UX-DR102 | 2.10, 9.3, 9.10, 13.3, 15.5, 19.2, 20.2 | Amended 2026-11-07: keyboard paths in 9.10 (Send to, ⌘V) and 20.2 (Time tab) |
| FR-9 Peek | v0.1 | FR12, FR13, FR23, UX-DR91–93 | 3.2, 3.3, **3.9**, 4.12, 7.6, 13.4, 20.2, 20.4 | Amended 2026-11-07: peek variants (sleep summary 4.12, quota 7.6, calendar 13.4, Timer end 20.2, break 20.4); fallback to the main Vigie display in 3.2; concurrency in 3.9 (added 2026-11-07) |
| FR-10 Alert rules | v0.1 | FR15, FR29 | 3.1, 3.7 | |
| FR-11 Do Not Disturb respected | v0.1 | FR17 | 3.5, 10.1 | |
| FR-12 Setup problems | v0.1 | FR16, FR99 | 2.3, 3.4 | |
| FR-13 Local activity log | v0.1 | New | **3.8** | New story |
| FR-14 Session tracking | v0.1 | FR31–FR34, FR36, FR38 | 4.5, 4.8 | |
| FR-15 Hook installation with consent (and removal) | v0.1 | FR80, FR82 | 4.7, 8.1, 14.1 | Removal = Disconnect in 4.7; already covered |
| FR-16 Hooks never slow agents | v0.1 | FR79, NFR3 | 1.4, 4.2, 4.3 | |
| FR-17 Honest status | v0.1 | FR35, FR85, NFR18 | 4.6, 8.1, 8.2, 14.1, 14.2 | |
| FR-18 Host-slept detection | v0.1 | FR46 | 4.12 | |
| FR-19 Keep-awake | v0.1 | FR45 | 4.12 (changed) | AC added: setting says lid close / manual sleep not covered |
| FR-20 Agents tab | v0.1 | FR39 | 4.10 | |
| FR-21 Generic agent CLI | v0.1 | FR86 | 4.13 | |
| FR-22 Ignored folders | v0.1 | FR42 | 4.8 | |
| FR-23 `vigie run` | v0.2 | New | **8.4** | New story, Codex epic |
| FR-24 Exact-tab focus | v0.1 | FR43 | 1.5, 1.6, 5.2–5.5 (5.4 changed) | Warp fallback rule in 5.4 |
| FR-25 Graceful fallback | v0.1 | FR44 | 5.1, 5.4, 5.5 | |
| FR-26 Quota rings and Pace | v0.2 | FR50, FR52 | 7.4, 7.5 | |
| FR-27 Quota warning | v0.2 | FR51, FR53 | 7.6 | |
| FR-28 Usage tab | v0.2 | FR54 | 7.7, 7.8, 7.9 | |
| FR-29 Multiple Accounts | v0.2 | New (extends FR47, FR50, FR54) | **7.10**, 8.3, 14.3 (changed) | New story |
| FR-30 Opt-in remote limits | v0.2 | FR49, NFR27, UX-DR99 | 7.3, 7.10 | Per Account in 7.10; `STALE · HH:MM` indicator in 7.3 (2026-11-07) |
| FR-31 Stash | v0.2 | FR57–FR61 | 9.1–9.4, 9.10 | Non-drag paths in 9.10 (2026-11-07) |
| FR-32 Ask AI | v0.2 | FR40 | 9.5–9.7, 9.10 | |
| FR-33 AirDrop drop zone | v0.2 | New (extends FR7) | **9.8**, 9.10 | New story |
| FR-34 Image to Text drop zone (formerly Copy text) | v0.2 | New (extends FR7) | **9.9**, 9.10 | New story |
| FR-35 Sounds | v0.2 | FR98 | 10.1, 10.2, 13.4, 20.2, 20.4 | Timer end in 20.2, break reminder in 20.4, calendar reminder in 13.4 (all off by default; 13.4 added 2026-11-07) |
| FR-36 Themes | v0.1 / v0.4 | FR95, FR96 | 2.4, 18.1, 18.2 | |
| FR-37 Calm Presence mode | v0.4 | FR97, UX-DR42 | 18.3 | Blocked and failed keep the calm pulse (18.3 amended 2026-11-07) |
| FR-38 Script format and widgets | v0.3 | FR62, FR64–FR67 | 12.1, 12.2, 12.4, 12.5 | |
| FR-39 Confirmation per Mac | v0.3 | FR63, NFR19 | 12.3, 12.9, 12.10 | |
| FR-40 Script secrets | v0.3 | FR63, FR64, NFR6 | 12.4, 12.6 | |
| FR-41 Example scripts | v0.3 | FR69 (changed) | 12.7 (changed), 12.8 | A68 resolved |
| FR-42 Install from link | v0.3 | New | **12.9**, 12.8 (signing) | New stories |
| FR-43 Script updates | v0.3 | New | **12.10** | New story |
| FR-44 Script repository | v0.3 | New | **12.8** | New story |
| FR-45 Timers and Countdowns | v0.3 | New | **20.2** | New epic 20 |
| FR-46 Pomodoro | v0.3 | New | 20.4, **20.5** | Work-phase end raises the break reminder kind (user ruling 2026-11-07, AD-13) |
| FR-47 Closed-notch time display | v0.3 | New | **20.6** | |
| FR-48 End alerts | v0.3 | New | **20.2, 20.5** | |
| FR-49 Break reminders | v0.3 | New | **20.1, 20.3, 20.4** | Includes the input-idle spike (20.1) |
| FR-50 Calendar reminders and tab | v0.3 | FR70–FR72 | 13.1–13.4 | No closed-notch glance; reminder peeks at the event's own alarms (ruled 2026-11-07, Story 13.4 added) |
| FR-51 Join call | v0.3 | FR70, FR71 | 13.3, 13.4 | Join call is the reminder peek's primary for video events [ASSUMPTION] |
| FR-52 Quick notes panel | v0.4 | FR73 | 15.3 | |
| FR-53 Secrets in notes | v0.4 | FR74, FR75 | 15.4, 15.5 | |
| FR-54 Encrypted notes | v0.4 | FR76, FR103, NFR20 | 15.1, 15.2 | |
| FR-55 Privacy mode | v0.2 | New, UX-DR98 | **21.1, 21.2, 21.3**, 7.10, 12.5, 12.9, 12.11, 13.3, 13.4, 15.3, 15.4, 15.5, 20.2 | New epic 21; Privacy ACs in 7.10, 13.4, 20.2 (2026-11-07); 12.5, 12.9, 12.11, 13.3, 15.3–15.5 added in the AC update (2026-11-07) |
| FR-56 Config as code | v0.1 | FR99, NFR17 | 2.3, 2.13 | |
| FR-57 iCloud sync | v0.4 | FR100, FR102, NFR6 | 16.2, 16.3, 7.10 | Account credentials never sync (7.10) |
| FR-58 Settings and onboarding | v0.1 basic / v0.4 full | FR93, FR94 | 2.14, 17.1, 17.2 | A13 resolved |
| FR-59 Single instance and login | v0.1 / v0.4 | FR94, AD-21 | 2.1, 17.1 | |
| FR-60 Other notch apps | v0.4 | FR110 | 17.5 | Already covered; A29 resolved |
| FR-61 Signed builds and updates | v0.1 | FR105, FR106, NFR11, NFR13 | 6.1, 6.2, 6.3 (changed) | Public release host; ask before install |
| FR-62 Homebrew | v0.4 | FR108 | 19.1 (changed) | |
| FR-63 Accessibility floor | v0.1 | NFR9, NFR10, UX-DR13, UX-DR63–66, UX-DR93–95 | **2.15**, 2.11, 3.2, 4.9, 9.10, 18.3, 18.4, 19.2, 20.4, 20.6 | New story for the v0.1 floor (A79); 9.10, 20.4, 20.6 added 2026-11-07 |
| FR-64 Localizable from the start | v0.1 | NFR8 | 1.1, 1.3, 19.2 | |

PRD success metric with no FR: SM-4 footprint (and counter-metric SM-C2) → NFR29 → 19.2 (AC added 2026-11-07).

PRD decisions with no FR that change stories: closed source with no license from 2026-11-06, replaced 2026-11-25 by GNU GPLv3 only (1.1, 17.2, 17.3 superseded, 19.2), public release hosting with a private code repository (6.2, 6.3, 19.1), no animated companions or pets (NFR26, 19.2), Warp fallback rule (5.4), Dynamic Island Macs in plain mode (2.7).

### FR Coverage Map

FR → epic (stories) — requirement summary. All 110 active FRs covered; FR109 superseded (see PRD traceability above for the PRD view).

FR1: Epic 2, 12 (2.2, 12.2) — Every module (built-in or script) can be enabled or disabled in config; a…
FR2: Epic 2, 3, 5, 13 (2.12, 2.14, 3.6, 5.1, 13.1) — When a module is enabled, its required permissions are checked and requested…
FR3: Epic 2 (2.2) — Module lifecycle: start(context:) registers hotkeys, scheduled jobs and event…
FR4: Epic 2 (2.2) — Built-in modules implement NotchModule: manifest (id, name, icon, permissions,…
FR5: Epic 2, 7, 12 (2.14, 7.2, 12.6) — Modules declare settings with typed descriptors (bool, int/double with…
FR6: Epic 2 (2.2) — Modules reach the system only through ModuleContext services and never…
FR7: Epic 9 (9.1, 9.2, 9.6, 9.8, 9.9) — Amended 2026-11-07: modules contribute drop zones (role, cell, order…); built-in Stash, AirDrop, Image to Text, Ask AI; host lays them out (AD-19)…
FR8: Epic 4 (4.3) — A vigie CLI is bundled in the app, made available on PATH, and provides vigie…
FR9: Epic 2 (2.5, 2.8) — Amended 2026-11-07: trailing side = sessions only; leading side = item lane (rings, script items, Time readout) by state then priority, `+X`…
FR10: Epic 2 (2.8) — Amended 2026-11-07: right wing renders only agents.sessions; left wing pools items, sorts by state, priority, provider order; first closed.slots shown, rest in +X…
FR11: Epic 2 (2.6, 2.8) — An empty side is black on a physical notch; on a plain display the virtual…
FR12: Epic 3, 4 (3.2, 3.9, 4.11) — When a module enters alert, the host may peek: a short partial expansion that…
FR13: Epic 3, 4 (3.3, 4.11) — A peek offers two actions with global shortcuts registered only while it is…
FR14: Epic 3 (3.2, 3.9) — Peeks and alerts never take keyboard focus; the app the user is typing in keeps…
FR15: Epic 3, 4, 7 (3.7, 4.11, 7.6) — Alert settings per kind: blocked, finished (done) and failed sessions each have…
FR16: Epic 3 (3.4) — Setup-problem alerts (unsupported adapter/CLI version, invalid config, missing…
FR17: Epic 3, 10 (3.5, 10.1) — Do Not Disturb / Focus mode suppresses peeks and sounds with no bypass option;…
FR18: Epic 2 (2.5, 2.6) — On a physical notch, each side's width is the safe-area region beside the notch…
FR19: Epic 2 (2.7) — display = "main" | "notched" | "all" | "<display name>" (machine-specific);…
FR20: Epic 2 (2.7) — Vigie hides on a display that has a full-screen app open (configurable,…
FR21: Epic 2 (2.7) — The host classifies displays as physical, plain or island; island displays run…
FR22: Epic 2 (2.7) — Connecting/disconnecting a display, changing resolution or arrangement, and…
FR23: Epic 2, 3 (2.7, 2.10, 3.2) — With display = "all", every notch shows the same state; the expanded view and…
FR24: Epic 2 (2.6) — Virtual notch layout options: idle minimum width or hide (virtual_notch.idle),…
FR25: Epic 2 (2.6) — Virtual notch style = black | menu_bar (menu_bar matches the menu bar material).
FR26: Epic 2 (2.6) — With "Automatically hide menu bar" on, the virtual notch hides and returns with…
FR27: Epic 2 (2.6) — On plain displays the hover zone is the whole top-center strip, a few points…
FR28: Epic 3 (3.1) — All user-facing alerts go through the core Notifier, never directly through…
FR29: Epic 3 (3.1) — Notifier rules from config: mute a kind, minimum severity, quiet hours,…
FR30: Epic 3 (3.6) — The system output posts a macOS notification.
FR31: Epic 4, 8 (4.5, 4.6, 8.2) — Adapters translate native agent events into the normalized events…
FR32: Epic 4 (4.5) — Session status model idle / working / done / blocked / failed / gone with the…
FR33: Epic 4 (4.5, 4.11, 4.12) — Blocked and failed sessions show T+ since entering the state (since wake for…
FR34: Epic 4 (4.5) — Urgency order (closed notch, Agents tab): blocked and failed (shared top…
FR35: Epic 4, 8, 14 (4.6, 8.2, 14.1) — If an adapter can't detect needs.input or session.error, its sessions can never…
FR36: Epic 4 (4.8) — Liveness: each session stores its agent PID; a check every 10 s removes…
FR37: Epic 4 (4.9) — Closed notch right wing: one animated, shape-coded glyph per session in urgency…
FR38: Epic 4 (4.5, 4.9) — agents.sessions module state is alert if any session is blocked or failed,…
FR39: Epic 4 (4.10) — Agents tab: dense list sorted by urgency with agent, project (from cwd), last…
FR40: Epic 9 (9.5, 9.6, 9.7) — Ask AI drop zone: dropping files (drop display, Shelf tab `SEND TO` card, a stash item, or the Shelf item `Send to` menu, Story 9.10)…
FR41: Epic 2, 3, 4, 17 (2.14, 3.7, 4.7, 17.2) — agents.sessions settings: enabled adapters, terminal app, Ask AI default agent…
FR42: Epic 4 (4.8) — Sessions whose project path is under an ignored path are not tracked.
FR43: Epic 1, 5 (1.5, 1.6, 5.1, 5.2, 5.3, 5.4, 5.5) — Terminal focus: a TerminalAdapter captures a locator at session.start and…
FR44: Epic 4, 5 (4.10, 5.1, 5.4, 5.5) — If focusing the tab fails, the terminal app is activated without selecting a…
FR45: Epic 4 (4.12, changed) — Opt-in idle-sleep prevention (off by default) while any session is working.
FR46: Epic 4 (4.12) — On wake, local sessions that were working when the Mac slept become failed…
FR47: Epic 7, 8, 14 (7.1, 7.3, 8.3, 14.3) — Each agent adapter can provide usage, enabled separately: token counts and…
FR48: Epic 7 (7.1) — Claude Code local-log usage reads `~/.claude/projects/**/*.jsonl`, works offline…
FR49: Epic 7 (7.3) — Plan-limit sources that use unofficial endpoints must be enabled explicitly,…
FR50: Epic 7 (7.4, 7.9) — Closed notch left wing: one quota ring per provider up to closed.slots, in user…
FR51: Epic 7 (7.6) — Quota warning: one warn_threshold per provider (% used only, default 80),…
FR52: Epic 7 (7.5) — Optional pace indicator (pace = true): marks elapsed time in the paced window…
FR53: Epic 7 (7.4, 7.6) — agents.usage state is ambient normally, active or alert above warn_threshold…
FR54: Epic 7 (7.7, 7.8, 7.9) — Usage tab: provider cards (ring, one bar per window with reset time, elapsed %,…
FR55: Epic 8 (8.3) — Codex CLI usage from ~/.codex/sessions/ logs (token counts, and rate-limit…
FR56: Epic 14 (14.3) — Gemini CLI usage from local telemetry/session files, if a usable source exists.
FR57: Epic 9, 11 (9.1, 9.7, 9.10, 11.3) — Amended 2026-11-07: dragging a file over the notch shows the drag-only drop display…
FR58: Epic 9 (9.2) — Stash stores a reference (bookmark) by default; copy mode stores a copy; text,…
FR59: Epic 9 (9.3, 9.7) — Shelf item actions: drag out = move, ⌥-drag = copy, Quick Look (Space), Reveal…
FR60: Epic 9, 11 (9.4, 11.3) — Items expire after ttl days (default 7) unless pinned; 24 h before expiry a…
FR61: Epic 9 (9.2) — Shelf module state is ambient with an item count when not empty, otherwise…
FR62: Epic 12 (12.2, 12.5) — Every *.md file in <config folder>/modules/ is a script module: YAML front…
FR63: Epic 12, 16 (12.3, 12.6, 16.3) — A script runs only after the user confirms it on this Mac after seeing the…
FR64: Epic 12 (12.4, 12.6) — Scripts run every interval, once at startup and when the user clicks Refresh;…
FR65: Epic 12 (12.4) — Script timeout min(interval, 30 s); stderr goes to the module log; a non-zero…
FR66: Epic 12 (12.1, 12.5) — Script stdout JSON: state (default ambient), widget (type status|number|text,…
FR67: Epic 12 (12.5, 12.11) — Script surfaces (front matter surfaces): Home widget, closed-notch side slot,…
FR68: Epic 12 (12.1) — A versioned JSON Schema is published at schemas/script-module.schema.json.
FR69: Epic 12 (12.7, 12.8) — **[Changed by PRD FR-41]** 2–3 example scripts ship with v0.3.
FR70: Epic 13 (13.1, 13.3, 13.4) — Calendar reads every account through EventKit; no closed-notch glance; reminder alerts at each event's own alarms…
FR71: Epic 13 (13.2, 13.3) — Calendar tab: month grid (one dot per calendar per day in macOS calendar…
FR72: Epic 13 (13.1, 13.4) — Calendar settings: calendars to include, reminders on/off, hide all-day events.
FR73: Epic 15 (15.3) — A global hotkey opens a floating notes panel that takes focus; Esc closes it.
FR74: Epic 15 (15.4) — Markdown notes with inline ||…|| and multi-line  secret  blocks; secrets render…
FR75: Epic 15 (15.4, 15.5) — Note list summaries never show secrets, only how many a note holds.
FR76: Epic 15, 16 (15.2, 16.2) — Notes are saved in a user-chosen folder, end-to-end encrypted (only Vigie can…
FR77: Epic 15 (15.5) — Notes tab: notes list with search and a preview of the selected note; notes…
FR78: Epic 1, 4 (1.4, 4.1) — Event Server listens on a user-only (0600) Unix socket in Application Support;…
FR79: Epic 1 (1.4) — vigie hook <agent> reads the agent's native event (stdin or args), adds process…
FR80: Epic 4, 8, 14 (4.4, 4.7, 8.1, 14.1) — Agent adapters are compiled into the app and are the only agent-specific code:…
FR81: Epic 8, 14 (8.2, 14.2) — Integration tiers, best available first: hooks, transcript watching,…
FR82: Epic 4 (4.6, 4.7) — Claude Code adapter via hooks in ~/.claude/settings.json (SessionStart,…
FR83: Epic 8 (8.1) — Codex CLI adapter: notify program in ~/.codex/config.toml plus transcript…
FR84: Epic 14 (14.1) — Gemini CLI adapter: hooks if the installed version supports them, otherwise…
FR85: Epic 4, 8, 14 (4.6, 8.1, 14.1) — Each adapter detects the installed CLI version and reports "unsupported…
FR86: Epic 4 (4.13) — vigie agent --agent <id> --session <id> --status <s> [--cwd] [--message] |…
FR87: Epic 2, 11 (2.10, 11.1) — The expanded view opens on click (or tap) on the notch or with the global…
FR88: Epic 2 (2.10) — The expanded view closes on click outside, Esc (when focused) or the hotkey…
FR89: Epic 2, 11, 12 (2.10, 11.1, 12.5, 12.11) — Tab bar: Home first, then one tab per enabled module with an expandedView plus…
FR90: Epic 11 (11.1, 11.2) — Home is a grid of homeCard() widgets, one fixed card size; the user picks which appear and in what order in Settings › Home…
FR91: Epic 2, 9, 13, 15 (2.10, 9.3, 13.3, 15.5) — Keyboard when focused: ⌘1…9 switches tabs, ↑↓ moves the selection in lists, ↵…
FR92: Epic 2, 4, 13 (2.11, 4.10, 13.1) — Every tab has an empty state (label, one sentence, button to the relevant…
FR93: Epic 2, 17 (2.14, 17.2) — Settings is a regular macOS window with native controls that edits the config…
FR94: Epic 2, 17 (2.1, 17.1) — First-launch onboarding, each step skippable: theme, agent connections and…
FR95: Epic 2, 18 (2.4, 18.1, 18.2) — Theme family: Chrome Hologram (default) and Twin Metal Tactical, each with…
FR96: Epic 18 (18.2) — Every status color, pace on/ahead and quota-warning color is user-configurable.
FR97: Epic 18 (18.3, 18.4) — Presence levels full (default) and calm; macOS Reduce motion forces calm;…
FR98: Epic 10, 13, 20 (10.1, 10.2, 13.4, 20.2, 20.4) — Sounds are optional: seven events (blocked, failed, done, quota warning, timer end, break reminder, calendar reminder)…
FR99: Epic 2, 3, 4 (2.3, 3.4, 4.3) — config.toml in the config folder holds shared settings; the settings window…
FR100: Epic 2, 12, 16 (2.3, 12.3, 16.1, 16.3) — Machine-specific settings (displays, virtual notch, terminal, config folder…
FR101: Epic 16 (16.1) — The config folder location is user-choosable (default ~/.config/vigie/) so it…
FR102: Epic 16 (16.2) — Turning [sync] icloud on moves the config and notes folders into iCloud…
FR103: Epic 15 (15.1) — The notes key is created only when the user sets up notes; on another Mac,…
FR104: Epic 1 (1.3) — ci.yml on pull requests and pushes to master: build, unit tests, adapter…
FR105: Epic 6, 19 (6.2, 19.1; both changed) — release.yml on a vX.Y.Z tag on master: verify ancestry and version, sign…
FR106: Epic 6 (6.3, changed), Epic 19 (19.3, beta channel) — Sparkle 2 auto-update from the GitHub Releases appcast; [updates] settings…
FR107: Epic 6, 12 (6.4, 12.1) — Semantic versioning; CFBundleVersion is an always-increasing CI build number;…
FR108: Epic 19 (19.1) — Homebrew cask (tap at first) declaring auto_updates true.
FR109: **[SUPERSEDED]** Epic 17 (17.3, superseded) — Settings has a Support item (GitHub Sponsors, Ko-fi/Buy Me a Coffee); at most…
FR110: Epic 17 (17.5) — Vigie detects other notch apps and warns that two apps can't share the notch.
FR111: Epic 2 (2.9) — Global hotkeys: expand hotkey (expand_hotkey, default cmd+shift+space) and…

#### NFR Coverage

All 28 active NFRs mapped to a story AC; NFR21 superseded; NFR29 (added 2026-11-07) → 19.2.

NFR1: Epic 1 (1.1) — macOS 15.0+ deployment target; Swift, SwiftUI, AppKit NSPanel where needed.
NFR2: Epic 2, 3 (2.1, 2.5, 2.9, 3.2) — Never steal focus: panels are non-activating; Vigie takes keyboard focus only…
NFR3: Epic 1, 4 (1.4, 4.2) — The hook CLI never slows or blocks an agent: synchronous, 150 ms total budget,…
NFR4: Epic 2 (2.2, 2.12) — Disabled modules cost nothing: no permission prompts, no timers, no background…
NFR5: Epic 4 (4.1) — The event socket is accessible only to the current user (0600).
NFR6: Epic 7, 12, 15, 16, 17 (7.2, 12.4, 15.1, 16.2, 16.3, 17.4) — Secrets live only in the Keychain; never in config files, app data, logs,…
NFR7: Epic 6, 7, 9, 12, 17, 19 (6.3, 7.3, 9.9, 12.9, 12.10, 17.4, 19.2) — No telemetry and no automatic crash reporting; network calls only for Sparkle,…
NFR8: Epic 1, 19 (1.1, 19.2) — English first; every user-facing string goes through String Catalogs from the…
NFR9: Epic 2, 4, 19 (2.11, 2.15, 4.9, 19.2) — Accessibility floor (v1): every control and glyph has an accessibility label…
NFR10: Epic 2, 18 (2.15, 18.3, 18.4) — macOS Reduce motion, Reduce transparency and Increase contrast are honored.
NFR11: Epic 6 (6.1, 6.2) — Developer ID signed, hardened runtime, notarized, unsandboxed; not distributed…
NFR12: Epic 1, 6 (1.3, 6.2) — Release builds happen only on GitHub Actions from tagged master commits;…
NFR13: Epic 6 (6.3) — Updates are verified twice: Sparkle EdDSA signature and Developer ID +…
NFR14: Epic 2 (2.3, 2.4) — Config, theme, appearance and display changes apply live without restart.
NFR15: Epic 2 (2.2, 2.3) — A module failure never crashes the host; invalid config keeps the last valid…
NFR16: Epic 2, 4, 9 (2.13, 4.2, 4.7, 9.2, 9.4) — No silent data loss: the shelf never deletes permanently; every app-written…
NFR17: Epic 2 (2.3, 2.13) — Config as code: human-editable TOML; app writes preserve comments, ordering and…
NFR18: Epic 4, 8, 14 (4.6, 8.1, 14.1) — Robust to agent CLI changes: version detection, recorded fixtures per supported…
NFR19: Epic 12, 16, 19 (12.3, 12.7, 16.3, 19.2) — Script trust: scripts run unsandboxed as the user, only after per-Mac…
NFR20: Epic 15 (15.1, 15.2) — Note plaintext exists only in memory; each note file is authenticated-encrypted…
NFR21: **[REINSTATED 2026-11-25; superseded 2026-11-06]** Epic 1, 19 (1.1, 19.2: now state GNU GPLv3 only) — GPL-3.0 license; reused GPL-compatible code (e.g. Boring Notch) is attributed.
NFR22: Epic 1 (1.1, 1.2) — Bundle IDs fixed from v0.1: fr.baguettelabs.vigie (release),…
NFR23: Epic 4, 8 (4.4, 8.1) — Adding an agent adapter = one new package + one line in App assembly; no change…
NFR24: Epic 1, 7 (1.1, 7.1) — Responsiveness and safety: all I/O off the main actor; Swift 6 language mode…
NFR25: Epic 1, 2, 3, 4, 7 (1.3, 2.8, 2.13, 3.1, 4.2, 4.5, 7.1) — CI test floor: SessionStore transitions, arbitration, ConfigStore patcher…
NFR26: Epic 4, 19 (4.10, 19.2) — Vigie never acts on an agent session on the user's behalf (only Focus), never…
NFR27: Epic 7 (7.3) — Unofficial plan-limit integrations are optional, isolated per adapter and quick…
NFR28: Epic 1, 4 (1.2, 4.7) — Dev builds are fully isolated from release builds (bundle id, Application…
NFR29: Epic 19 (19.2: measured AC, re-run at the end of each roadmap release) — Footprint: idle CPU < 1 %, memory < 150 MB with Sessions, Usage and two Script modules (PRD SM-4)…

#### UX-DR Coverage

All UX-DRs mapped to an epic and to at least one story AC (UX-DR74's Support pane superseded; UX-DR20 superseded by UX-DR83). The step-3 markers were resolved by the AC update step (2026-11-07).

UX-DR1: Epic 2 (2.4) — Chrome Hologram (A) color tokens for dark and light looks:…
UX-DR2: Epic 18 (18.1) — Twin Metal Tactical (C) color tokens for dark and light looks: same roles plus…
UX-DR3: Epic 2 (2.4) — A typography tokens (readout-value, readout-label, kicker, peek-title, body,…
UX-DR4: Epic 18 (18.1) — C typography tokens (Avenir Next Condensed with DIN Condensed fallback for…
UX-DR5: Epic 2, 18 (2.4, 18.1) — Radius tokens: island-closed 14 (bottom corners only), peek 22, expanded 24,…
UX-DR6: Epic 2 (2.4) — Spacing tokens: band-height 34, wing-padding-x 16, wing-gap 9, glyph-gap 7,…
UX-DR7: Epic 2 (2.4) — Motion tokens: enter 280 ms, ambient-loop 6 s, working-cycle 1.5 s,…
UX-DR8: Epic 2 (2.4) — Component geometry tokens: closed island 540×34 reference, peek 700×150,…
UX-DR9: Epic 2 (2.5) — The hardware island is always #000000 and renders with the active variant's…
UX-DR10: Epic 2 (2.5) — Strict containment and elevation: nothing drawn outside the island or panel…
UX-DR11: Epic 9, 12, 18 (9.4, 12.5, 18.2) — Status color defaults per look (DESIGN status table), each user-configurable…
UX-DR12: Epic 7, 18 (7.4, 7.5, 7.6, 18.2) — Pace and quota-warning roles: A metal = within pace / Ember = ahead; C inverted…
UX-DR13: Epic 2, 17, 18 (2.15, 17.2, 18.1, 18.2, 18.4) — Contrast: text ≥ 4.5:1; gold text uses gold-text; warning text quota-warning-text on any surface (amended 2026-11-07)…
UX-DR14: Epic 2, 18 (2.5, 2.6, 18.1) — Closed island: two wings either side of the cut-out, wing-gap inside; ornaments…
UX-DR15: Epic 2 (2.5) — Hover reaction inside the outline over motion.enter: A rim to full strength,…
UX-DR16: Epic 7, 11, 18 (7.4, 7.5, 7.6, 11.2, 18.1) — Quota dial: 24px (23 stacked, 58 on Usage tab), track in line; nesting inner 5h…
UX-DR17: Epic 4, 7 (4.9, 7.4) — Readout: value over label; single-provider left wing (38 % / CLAUDE · WEEK) and…
UX-DR18: Epic 4, 18 (4.9, 18.1) — Status glyph: 16px (26 large); fixed shapes per variant — A: idle hollow ring,…
UX-DR19: Epic 4 (4.9) — Overflow count +X after the visible glyphs, readout-label style, ink-3; nothing…
UX-DR20: **[SUPERSEDED 2026-11-07 by UX-DR83]** Epic 9 (9.1) — Closed-notch drop zones → drag-only drop display…
UX-DR21: Epic 3, 4 (3.2, 4.11) — Peek alert panel 700×150, grid 44px | 1fr | 176px: beacon (A round radial tint…
UX-DR22: Epic 3 (3.4) — Setup-problem alert: same frame and dwell, no beacon, no glyph, no status hue,…
UX-DR23: Epic 2, 13 (2.11, 13.1) — In-tab setup card: centred, max 380px, neutral 1px inner outline (A platinum…
UX-DR24: Epic 2 (2.11) — Empty state block: centred uppercase ink-3 label, one factual prose sentence,…
UX-DR25: Epic 2, 3, 13, 18 (2.11, 3.3, 13.3, 18.1) — Action button 30px, two stacked action-gap apart, label left, shortcut right; A…
UX-DR26: Epic 2 (2.10) — Expanded panel 720×420: band with wordmark VIGIE (A iris-gradient text, 0.5em…
UX-DR27: Epic 2, 18 (2.10, 18.1) — Tab bar 30px: A pill container (3.5% white, inner hairline), active tab raised…
UX-DR28: Epic 2, 11, 18 (2.11, 11.1, 18.1) — Widget card: 11px header row with title (card-title) left and meta right in…
UX-DR29: Epic 2, 7 (2.11, 7.7, 7.9) — Scroll and reorder affordances: overflowing lists fade the last row under a…
UX-DR30: Epic 4, 11 (4.10, 11.2) — Session row 30px, Agents grid 18 | 84 | 1fr | 62 | 104 | 76 (glyph, agent,…
UX-DR31: Epic 7 (7.7, 7.8) — Usage provider card: grip, provider name, meta (MAX · WARN 80%, ULTRA · WEEKLY…
UX-DR32: Epic 9, 11 (9.3, 9.7, 11.3) — Drop zones in panels: Stash; Ask AI dashed border; SEND TO card (amended 2026-11-07)…
UX-DR33: Epic 9, 11 (9.3, 9.4, 11.3) — Shelf row: columns item (name, size · mode), source app, added, expires;…
UX-DR34: Epic 13 (13.2) — Month grid (Itsycal structure, 300px card): header NOVEMBER 2026 with ‹ ● ›,…
UX-DR35: Epic 13 (13.3) — Upcoming list and event track: day headers (TODAY · WED 04 NOV, THU 05 NOV ·…
UX-DR36: Epic 12 (12.5) — Script widget templates in the card frame for status, number and text; number =…
UX-DR37: Epic 15 (15.3) — Floating notes panel 460×372, surface-panel, no band, iris filament on top;…
UX-DR38: Epic 15 (15.4, 15.5) — Secret mask: inline = fixed-width dots in an a-code chip, hover brightens +…
UX-DR39: Epic 2, 17 (2.14, 17.1) — Settings and onboarding are native macOS windows using system text styles;…
UX-DR40: Epic 2, 4 (2.11, 4.10) — Interaction depth: depth from tone (surface-card over surface-panel, 1px inner…
UX-DR41: Epic 2, 7, 9, 11, 15 (2.5, 2.10, 7.7, 9.3, 11.1, 15.5) — Information placement: left wing item lane, right wing sessions, identical in both…
UX-DR42: Epic 2, 18 (2.5, 18.3) — Presence levels visuals; calm keeps one pulse on blocked or failed (amended 2026-11-07)…
UX-DR43: Epic 2, 3, 4, 19 (2.11, 3.4, 4.11, 19.2) — Voice and tone: compact UI = short uppercase technical labels; longer messages…
UX-DR44: Epic 2, 4, 7, 9, 13 (2.11, 4.10, 7.7, 9.3, 13.1) — Specified copy for empty and setup states: NO AGENT CONNECTED + "Connect Claude…
UX-DR45: Epic 2, 3, 9, 15 (2.9, 3.2, 9.1, 15.3) — Never steal focus: panels non-activating; surfaces opened by an alert or a drag…
UX-DR46: Epic 2 (2.10) — Hover on the closed notch = small reaction only (opens only if hover-to-open…
UX-DR47: Epic 2 (2.10) — Click outside the expanded view collapses it; leave-to-close is opt-in.
UX-DR48: Epic 2, 9, 20 (2.10, 9.10, 20.2, 20.4) — Keyboard in expanded (only when focused): ⌘1…9 tabs, ↑↓, ↵ acts (incl. Send to, Start, Start break), ⌘V, gear…
UX-DR49: Epic 3, 4, 7, 13, 20 (3.3, 4.12, 7.6, 13.4, 20.2, 20.4) — Peek shortcuts ⌥⌘↵ primary, ⌥⌘⌫ Dismiss/Skip, ⌥⌘Z Snooze (break peek only), global only while visible…
UX-DR50: Epic 9 (9.1, 9.3, 9.6, 9.7, 9.10) — Drag interactions (amended 2026-11-07): external file drag → drag-only drop display…
UX-DR51: Epic 7 (7.9) — Dragging a provider card reorders the Usage list and the same order shows in…
UX-DR52: Epic 13 (13.2) — Calendar: day click starts the upcoming list at that day; ‹ › change the grid…
UX-DR53: Epic 15 (15.4) — Secret click toggles reveal; COPY copies without revealing.
UX-DR54: Epic 2, 18 (2.4, 18.3) — Theme, appearance and presence changes apply live with no restart.
UX-DR55: Epic 3, 4, 19 (3.5, 4.10, 19.2) — Banned: acting on a session on the user's behalf (approve, deny, send),…
UX-DR56: Epic 4, 14 (4.5, 4.8, 4.9, 14.2) — Session state visuals: idle static, working animated, done static (no T+),…
UX-DR57: Epic 4, 11 (4.9, 4.10, 4.12, 11.2) — Agents surface states: no agent connected (right wing label only, left wing…
UX-DR58: Epic 7 (7.4, 7.5, 7.6, 7.7) — Usage surface states: quota warning (threshold per provider, alert or visual, %…
UX-DR59: Epic 9 (9.3, 9.4) — Shelf surface states: item expiring (quota-warning yellow + triangle, EXPIRES IN 5H,…
UX-DR60: Epic 13 (13.1, 13.2) — Calendar surface states: access missing (setup card), no events today (grid…
UX-DR61: Epic 12 (12.3, 12.5) — Script surface states: errored (last good output + warning badge), awaiting…
UX-DR62: Epic 2, 3, 5 (2.7, 3.4, 3.5, 5.1) — Global surface states: setup problem (own neutral UI, never an agent state),…
UX-DR63: Epic 2, 4, 19 (2.11, 2.15, 4.9, 19.2) — Every control and glyph has an accessibility label with state, format "vigie /…
UX-DR64: Epic 17, 18 (17.2, 18.3) — Reduce motion forces calm and stops loops; Settings shows a warning explaining…
UX-DR65: Epic 2, 18 (2.15, 18.4) — Reduce transparency and Increase contrast: glass gradients become flat…
UX-DR66: Epic 2, 3, 4, 19 (2.10, 2.15, 3.3, 4.10, 19.2) — Keyboard: every expanded-view action is reachable when it has focus; peek…
UX-DR67: Epic 4, 5 (4.11, 5.4) — Flow 1 — Multi-session day: multiple Claude/Codex sessions in Warp; right wing…
UX-DR68: Epic 4 (4.12) — Flow 2 — Wake after sleep: interrupted sessions become failed (FAILED · HOST SLEPT); several sessions → one summary alert (amended 2026-11-07)…
UX-DR69: Epic 5, 17 (5.1, 5.3, 17.1) — Flow 3 — First week: Homebrew install, onboarding (theme live preview, agent…
UX-DR70: Epic 9 (9.6, 9.7) — Flow 4 — Ask AI drop: drag from browser → drop display → drop on Ask AI →…
UX-DR71: Epic 12, 16 (12.3, 16.3) — Flow 5 — Script via sync: script written on Mac A with a secret token; arrives…
UX-DR72: Epic 10, 13, 20 (10.2, 13.4, 20.2, 20.4) — Sounds: fully optional (asked at onboarding); seven events; built-in sounds…
UX-DR73: Epic 2, 3, 4, 7, 17 (2.8, 3.2, 3.7, 4.5, 7.4, 7.5, 17.2) — Customization surface: closed-notch slots per side (3 default, max ~4), quota…
UX-DR74: Epic 2, 10, 11, 12, 17, 20, 21 (2.14, 10.2, 11.1, 12.6, 17.2, 20.2, 21.3) — Settings panes per EXPERIENCE incl. Home, Time, Privacy in General (amended 2026-11-07)…
UX-DR75: Epic 17 (17.1) — Onboarding sequence: 1 theme picker (skip → Chrome Hologram, live preview), 2…
UX-DR76: Epic 2 (2.6, 2.7) — Platform contexts: physical notch, plain black, plain menu_bar, island, multiple displays…
UX-DR77: Epic 2, 4, 18, 19 (2.5, 4.9, 18.1, 19.2) — Do's and Don'ts: keep wording/layout/slots identical across variants; C gold…
UX-DR78: Epic 7, 14 (7.7, 14.3) — Usage tab content rules: windows per provider are whichever the plan has (5h,…
UX-DR79: Epic 13 (13.2) — Calendar day and event dots use macOS (EventKit) calendar colors as user data,…
UX-DR80: Epic 2, 18 (2.10, 18.1) — Settings gear: detached button at the far right of the tab row, not a tab, tooltip Settings (⌘,)…
UX-DR81: Epic 4, 14 (4.8, 14.2) — Stale and process-only glyphs, labels, last-action lines…
UX-DR82: Epic 2, 12 (2.11, 12.5) — Status vocabulary OK / WARN / DOWN: shape + hue + label, static, never alerts…
UX-DR83: Epic 9 (9.1) — Drag-only drop display, layout B, 700 × 196, reflow rules…
UX-DR84: Epic 9 (9.7, 9.8, 9.9) — SEND TO card 212 px: Ask AI 84 px + two 38 px mini zones…
UX-DR85: Epic 9 (9.9) — COPIED readout…
UX-DR86: Epic 12 (12.5, 12.11) — Script widgets, side-slot item, script page…
UX-DR87: Epic 12 (12.3, 12.4, 12.10, 12.11) — Script state copy: NOT CONFIRMED, WAITING · FIRST RUN, TIMED OUT · 30S, UPDATE AVAILABLE…
UX-DR88: Epic 20 (20.2, 20.5, 20.6) — Time accent, time ring, phase pips, Time tab grid, closed readout, Timer-end peek…
UX-DR89: Epic 20 (20.4, 20.6) — BREAK DUE persistence even with closed_notch = "off"; Snooze keeps it; counts for replay…
UX-DR90: Epic 20 (20.4, 20.5) — Break peek: three actions, ⌥⌘Z only while visible, 196 px column…
UX-DR91: Epic 4, 7, 13 (4.12, 7.6, 7.10, 13.4) — Peek variants: sleep summary, quota warning, calendar reminder…
UX-DR92: Epic 3, 9 (3.9, 9.1) — Peek concurrency: preemption, queue order, resolved dropped, none while expanded, wait while drop display open…
UX-DR93: Epic 3, 13, 20 (3.2, 3.3, 7.6, 13.4, 20.2, 20.4) — Every peek posts a VoiceOver announcement; button labels include the shortcut…
UX-DR94: Epic 2, 4, 18 (2.15, 4.10, 18.1, 18.4) — Contrast table, non-text 3:1, ink-2 secondary on tinted dark rows, quota-warning-text on any surface…
UX-DR95: Epic 2, 18 (2.15, 18.4) — Increase contrast table: solid ink-3 borders, 100 % Ask AI dash, ≥ 40 % tracks, 2 px focus…
UX-DR96: Epic 2, 3, 9 (2.10, 2.15, 3.2, 9.1, 9.9) — Motion exit / peek-grow / drop-display-grow / confirm-readout; Reduce motion static drains and loops…
UX-DR97: Epic 11, 17 (11.1, 11.2, 11.3, 17.2) — Home: fixed 222 × 138 card, no spans, Settings › Home list, NO WIDGETS…
UX-DR98: Epic 12, 13, 15, 21 (12.5, 12.9, 13.3, 15.3, 15.4, 15.5, 21.2, 21.3) — Privacy mode visuals: dots in ink-3, eye-slash indicator, reveal unavailable, Settings copy…
UX-DR99: Epic 7 (7.3, 7.10) — Accounts UI: CLAUDE · WORK wing label, card header, quota peek title, STALE · HH:MM…
UX-DR100: Epic 7, 9, 11, 12, 15, 20 (7.7, 7.8, 9.3, 11.1, 12.9, 15.1, 15.2, 15.5, 20.2) — Additional empty / loading / error copy…
UX-DR101: Epic 9 (9.2, 9.8) — Drop failed readout NOT STASHED / AIRDROP UNAVAILABLE, 2 s, activity-log entry…
UX-DR102: Epic 9 (9.10) — Non-drag paths: Send to menu, ⌘V, Services Stash in Vigie, Shelf-off setup alert…
UX-DR103: Epic 2, 19 (2.11, 19.2) — Vocabulary additions…
UX-DR104: Epic 2, 20 (2.10, 3.9, 20.2, 20.4) — Tab attention marker on Agents and Time; VoiceOver "needs attention"…
UX-DR105: Epic 8 (8.4) — Flow 6 — vigie run…
UX-DR106: Epic 12 (12.9, 12.10) — Flow 7 — community script install and update…
UX-DR107: Epic 20 (20.4, 20.5, 20.6) — Flow 8 — break reminder and Pomodoro variant…

## Epic List

Epics follow the SPEC §13 roadmap (Spike → v0.1 → v0.2 → v0.3 → v0.4), as confirmed with new release slots by PRD §6.1. v0.1 is split into six epics because it is too large for one (A8). Each epic builds only on epics in the same or earlier roadmap rows. Epics 20 and 21 were added by the PRD reconciliation and numbered last so nothing is renumbered; the roadmap row, not the number, sets their order (A90).

| Roadmap | Epics |
|---|---|
| Spike | 1 |
| v0.1 | 2, 3, 4, 5, 6 |
| v0.2 | 7, 8, 9, 10, 21 |
| v0.3 | 11, 12, 13, 14, 20 |
| v0.4 | 15, 16, 17, 18, 19 |

### Epic 1: Foundation and risk spikes
Romain has a buildable, CI-checked SwiftPM workspace and hard answers to the two riskiest questions: a Claude Code hook event reaches a running Vigie, and a specific Warp (and Ghostty) tab can or cannot be focused. Story 1.7 holds the UX design work for surfaces that had no design; its parts are scheduled ahead of the stories that need them.
**FRs covered:** FR43, FR78, FR79, FR104

### Epic 2: Vigie lives in the notch
Users see a themed Vigie island in the hardware notch or a virtual notch on plain displays, on the right display(s), with sessions in the right wing and every other module in a shared left-wing lane ordered by priority (overflow → `+X`); they can open an expanded view, and configure everything in `config.toml` or a native Settings window.
**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR9, FR10, FR11, FR18, FR19, FR20, FR21, FR22, FR23, FR24, FR25, FR26, FR27, FR41, FR87, FR88, FR89, FR91, FR92, FR93, FR94, FR95, FR99, FR100, FR111 · PRD FR-63 (v0.1 floor, Story 2.15)

### Epic 3: Alerts that never steal focus
Users get one-time peek alerts with two keyboard actions that never take focus, governed by per-kind rules, Do Not Disturb, reminders and optional macOS notifications; setup problems (e.g. a bad config key) are reported in a neutral alert that opens the right Settings pane.
**FRs covered:** FR2, FR12, FR13, FR14, FR15, FR16, FR17, FR23, FR28, FR29, FR30, FR41, FR99 · PRD FR-13 (activity log, Story 3.8) · peek concurrency (Story 3.9, added 2026-11-07)

### Epic 4: Track Claude Code sessions
Users who run Claude Code (or any tool via `vigie agent`) see every session's status in the closed notch and the Agents tab, get blocked / done / failed alerts, never lose events across app restarts, and learn about sessions interrupted by sleep.
**FRs covered:** FR8, FR12, FR13, FR15, FR31, FR32, FR33, FR34, FR35, FR36, FR37, FR38, FR39, FR41, FR42, FR44, FR45, FR46, FR78, FR80, FR82, FR85, FR86, FR92, FR99

### Epic 5: Jump to the exact terminal tab
Users press `⌥⌘↵` on a peek or `↵` on a session row and the session's exact terminal tab comes to the front in Terminal.app, iTerm2, Warp or Ghostty (or the app activates when the tab can't be located).
**FRs covered:** FR2, FR43, FR44

### Epic 6: Signed releases that update themselves
Users install a signed, notarized Vigie from the public release host, and Sparkle offers every later version and installs it once they agree, from a reproducible tag-driven pipeline in the private code repository.
**FRs covered:** FR105, FR106, FR107 · PRD FR-61

#### Story 6.5: Remote price table for every provider

*Added 2026-11-08 (Romain's ruling): the bundled `prices.json` (A56) goes stale between releases and cannot price a new model family. Placed in Epic 6 because it rides the release pipeline and the Sparkle signing key.*

As a user,
I want cost estimates to use current list prices for every provider without waiting for an app update,
So that the Usage tab stays right when a provider releases or reprices a model.

**Requirements:** PRD FR-48 (cost), A56 (superseded by this story), AD-16 (amended 2026-11-08: price-table fetch allowed), AD-23 (prices keyed by adapter id), AD-8 (`[updates] prices`), NFR24

**Acceptance Criteria:**

**Given** the price table schema
**When** it is defined
**Then** one JSON document holds a `providers` map keyed by adapter id (`claude`, `codex`, `gemini` today; any future adapter adds a key, nothing else changes), each with its `currency`, `unit`, `updated` date and a `models` map of ids to `input`, `output`, `cache_write`, `cache_read` and optional tiers (e.g. long-context thresholds); `AgentAdapter` exposes `priceProviderID` so an adapter maps its models to one provider section; the schema is versioned and the bundled file in `AgentsUsage` follows it

**Given** the release workflow (Story 6.2)
**When** a release is tagged, or the `prices/` folder of the private repository changes on `master`
**Then** CI publishes `prices.json` and a detached EdDSA signature made with the Sparkle private key to a fixed public HTTPS location (the public releases repository or its Pages site), and the app knows only that location

**Given** `[updates] prices = true` (default) and `check_interval`
**When** the interval elapses, or the user presses `Check now` in Settings › Usage
**Then** the app fetches the table and its signature, verifies the signature with the embedded Sparkle public key, rejects a lower `version` or a bad signature (logged as a setup problem once), and otherwise stores it in `context.storage` of `agents.usage`; no other data is sent, no cookies or identifiers beyond the HTTPS request

**Given** a stored table
**When** `CostEstimator` is built
**Then** it uses the stored table when its `version` is newer than the bundled one, else the bundled one; the Usage tab footer reads `PRICES <date>` with `BUNDLED` or `UPDATED`; a provider section missing from the stored table falls back to the bundled section

**Given** `[updates] prices = false`, or the Mac offline
**When** Vigie runs
**Then** no request is made and the newest table already on disk is used

**Given** a model id with no price in any table
**When** cost is summed
**Then** it stays unpriced as today (no invented number)

**Given** unit tests
**When** run with a fake HTTP client and a test key pair
**Then** they cover: valid update applied, bad signature rejected, downgrade rejected, offline fallback, per-provider fallback, `prices = false` makes no request, adapters mapped to provider sections, schema round-trip of the bundled file

## Epic 7: AI usage at a glance
Users see one quota ring per provider in the left wing, a pace marker, a quota warning at their threshold, and a Usage tab with per-window bars, 7-day history and today's cost — starting with Claude Code.
**FRs covered:** FR5, FR15, FR47, FR48, FR49, FR50, FR51, FR52, FR53, FR54 · PRD FR-29, FR-30 (multiple Accounts, Story 7.10)

#### Story 7.11: Hook installation per Account location

*Added 2026-11-08 (Romain's ruling): Story 4.7 installs hooks only into the default `~/.claude/settings.json`; an extra Account (Story 7.10) with its own `CLAUDE_CONFIG_DIR` reports usage from its logs but no Sessions.*

As a user with several Accounts on one Provider,
I want Vigie's hooks installed in each Account's config location,
So that Sessions from every Account reach the notch.

**Requirements:** PRD FR-23, AD-22 (IntegrationInstaller, diff confirmation), AD-23 (Accounts bound to a location), A82

**Acceptance Criteria:**

**Given** an Account with a `location` (Story 7.10)
**When** the user connects the Provider's integration, or adds the Account while it is connected
**Then** the installer shows the same unified diff for `<location>/settings.json` and writes it only after confirmation; the hook command carries the Account's location so the hook CLI attributes events to it (A82)

**Given** a connected Provider with several Accounts
**When** Settings › Agents › Integrations renders
**Then** the status line lists each Account's location as installed, missing or modified, and `Install` repairs every missing one

**Given** Disconnect, or an Account removed
**When** confirmed
**Then** the hooks are removed from that location only, with a diff

**Given** a location that does not exist or has no `settings.json`
**When** the installer runs
**Then** it creates the file with only Vigie's hooks after confirmation, or reports the missing folder as a setup problem naming the path (sensitive in Privacy mode)

**Given** unit tests with two fake Account locations
**When** install, repair and remove run
**Then** each location is touched independently and the default location is unchanged by the others

## Epic 8: Codex CLI support
Users who run Codex CLI get its sessions and usage in Vigie through the same modules, with honest reporting of what the integration can detect; any long command can report like an agent with `vigie run`.
**FRs covered:** FR31, FR35, FR47, FR55, FR80, FR81, FR83, FR85 · PRD FR-23 (`vigie run`, Story 8.4)

### Epic 9: Shelf and Ask AI
Users drag anything onto the notch to stash it for days (with expiry they can trust) or drop files on Ask AI to start their default agent in a new terminal tab with the files attached.
**FRs covered:** FR7, FR40, FR57, FR58, FR59, FR60, FR61, FR91 · PRD FR-33, FR-34 (AirDrop and Image to Text, Stories 9.8, 9.9) · non-drag paths to the zones (Story 9.10, added 2026-11-07)

### Epic 10: Sounds
Users can hear the seven alert sound events (blocked, failed, done, quota warning, plus timer end, break and calendar reminder from Epics 20 and 13) with built-in or custom sounds, fully optional and silent under Do Not Disturb.
**FRs covered:** FR17, FR98

### Epic 11: Home dashboard
Users open Vigie onto a configurable Home grid summarizing sessions, quota and shelf.
**FRs covered:** FR57, FR60, FR87, FR89, FR90

#### Story 11.4: Keep the current tab on quick re-open

*Added 2026-11-08 (Romain's ruling after the first live session): Story 11.1 lands on Home on every expand; closing and immediately re-opening must come back to the tab the user was on.*

As a user,
I want the expanded view to come back to the tab I was on when I re-open it shortly after closing,
So that a quick close does not throw away where I was.

**Requirements:** PRD FR-6, AD-8 (`[general] home_after`), UX-DR83

**Acceptance Criteria:**

**Given** `[general] home_after` (duration, default `"2m"`; `"never"` = always keep the last tab; `"0s"` = always return to Home)
**When** the expanded view opens
**Then** it shows the last selected tab if it was closed less than `home_after` ago, and Home otherwise

**Given** an explicit request (`vigie expand --tab <id>`, an alert's Open action, a module hotkey)
**When** the view opens
**Then** the requested tab wins regardless of `home_after`

**Given** Settings › General
**When** the control shows
**Then** it reads `Return to Home after` with choices `Immediately`, `30 s`, `2 min`, `10 min`, `Never`

**Given** unit tests with a fake clock
**When** the view closes and re-opens inside and outside the window, and with `never` and `0s`
**Then** the landing tab follows the rule

## Epic 12: Script modules
Users extend Vigie without Swift by dropping a Markdown script file into the config folder; scripts run only after per-Mac confirmation and render as Home widgets, side-slot items or full pages.
**FRs covered:** FR1, FR5, FR62, FR63, FR64, FR65, FR66, FR67, FR68, FR69, FR89, FR100, FR107 · PRD FR-41 to FR-44 (Script repository, install from link, updates, Stories 12.8–12.10) · script page split into Story 12.11 (added 2026-11-07)

### Epic 13: Calendar
Users see upcoming meetings, a month grid and a countdown, get a peek at each event's own reminder times, and join video calls from the notch.
**FRs covered:** FR2, FR70, FR71, FR72, FR91, FR92 · FR98 (extended: calendar-reminder sound, Story 13.4) · PRD FR-50 (amended 2026-11-07)

### Epic 14: Gemini CLI support
Users who run Gemini CLI get its sessions (and usage if available); any agent that offers no hooks or logs still shows presence.
**FRs covered:** FR35, FR47, FR56, FR80, FR81, FR84, FR85

### Epic 15: Encrypted quick notes
Users write quick Markdown notes with masked secrets in a floating panel, stored end-to-end encrypted and readable on their other Macs.
**FRs covered:** FR73, FR74, FR75, FR76, FR77, FR91, FR103

### Epic 16: Portable config and iCloud sync
Users choose where their config lives (git, iCloud) and optionally sync config and notes across Macs, with machine-specific settings and secrets staying local.
**FRs covered:** FR63, FR76, FR100, FR101, FR102

### Epic 17: Onboarding and settings polish
New users are guided through setup on first launch; everyone gets a complete Settings window, diagnostics and a warning when another notch app is running. (The donation option is superseded 2026-11-06, PRD §9 Q1, and not reinstated by the 2026-11-25 GNU GPLv3 license change.)
**FRs covered:** FR41, FR93, FR94, FR110 (FR109 superseded)

### Epic 18: Theme family and presence
Users choose Twin Metal Tactical or a custom theme, override any status color, and calm the motion down (automatically under Reduce motion).
**FRs covered:** FR95, FR96, FR97

### Epic 19: Public release
Anyone can install Vigie with Homebrew and find a README that sets the right expectations (including script trust), with the accessibility floor verified; early adopters can opt into a beta update channel (Story 19.3, A63).
**FRs covered:** FR105, FR106 (beta channel, Story 19.3), FR108 · PRD FR-62

### Epic 20: Time (v0.3, added 2026-11-06)
Users run named Timers, Countdowns and Pomodoro cycles, optionally see the nearest one in the closed notch, get their end as a normal Alert, and get break reminders driven by whether they are actually at the Mac (Away service, after a spike on input idle time and permission).
**FRs covered:** PRD FR-45, PRD FR-46, PRD FR-47, PRD FR-48, PRD FR-49, PRD FR-35 (timer-end sound); FR98 (extended)

### Epic 21: Privacy mode (v0.2, added 2026-11-06)
While the screen is shared or recorded, every Vigie surface shows only glyphs, rings and numbers; detection is automatic where macOS allows, with a manual toggle otherwise.
**FRs covered:** PRD FR-55

### Out of scope / Later (not broken into stories)

Listed for traceability; no stories are created for them (A26–A28, A66; now confirmed by PRD §6.2 where noted).

| Item | Source | Why not now |
|---|---|---|
| Island spike (window layering vs system Dynamic Island, auxiliary areas on island Macs, ActivityKit on macOS) and the `island` display mode | SPEC §13, §14.10, §14.11; PRD FR-2, §6.2 | After v1, hardware-gated; island Macs use plain mode for all of v1 (FR21) |
| Menu bar fallback mode | SPEC §13 Later, §14.13; PRD §6.2 | Later |
| Touch input (tap equivalents, finger-sized targets) | SPEC §14.12; PRD §6.2 | Later, tied to island Macs |
| Window management, clipboard history, dictation, translation, media controls | SPEC §13 Later, §1 non-goals | Later |
| Script-raised alerts (`notify` field), script sandboxing | SPEC §9.3, Architecture Deferred | After v1 |
| Touch ID unlock for notes, full VoiceOver experience, UI snapshot tests | SPEC §7.6, §10.2, Architecture Deferred | After v1 / v2 |
| Calendar week view, presence levels between full and calm, calendar-to-metal color mapping | SPEC §7.5, EXPERIENCE Open Questions | Maybe later |
| release-please automation, official homebrew-cask submission, GitHub Pages appcast mirror | SPEC §12.2, §12.3, §12.4 | Optional later |
| ~~Paid supporter edition~~ | SPEC §2.1 | **[SUPERSEDED]** business model undecided (PRD §9 Q1) |
| Community adapters (OpenCode, Aider, Cursor CLI, …) and other terminals | SPEC §8.3, §7.1; PRD §6.2 | Not before outside contributions are accepted (no outside contributions for now, 2026-11-06; license is GNU GPLv3) |
| Escalation to phone (ntfy, Pushover) after a Session stays blocked | PRD §6.2, memlog | Accepted, after v1 |
| Public script website with install buttons | PRD FR-44, §6.2 | After v1 (repository and links ship in v0.3) |
| Natural-language timer entry ("25m tea") | PRD §4.10, §6.2 | Later |
| Community script library beyond the curated repository | memlog | Later |
| Animated companions, mascots, pets | PRD §5, memlog | Never (non-goal) |
| Trademark search (INPI/EUIPO) and domain purchase | SPEC §14.3 | Non-code task for Romain |

## Epic 1: Foundation and risk spikes

Romain has a buildable, CI-checked SwiftPM workspace and hard answers to the two riskiest questions (SPEC §13 Spike, §14.1): a Claude Code hook event reaches a running Vigie, and a specific Warp (and Ghostty) tab can or cannot be focused. The spike outputs are decision records that Epic 5 consumes.

### Story 1.1: Scaffold the SwiftPM-first workspace

As Romain (solo developer working with AI coding agents),
I want the repository laid out exactly as the Architecture Spine's Structural Seed with compiler-enforced package boundaries,
So that every later story lands in the right package and agents cannot create hidden coupling.

**Requirements:** NFR1, NFR8, NFR21 (GPL-3.0-only, reinstated 2026-11-25), NFR22, NFR24, AD-1, AD-2, AD-3, AD-15, AD-16, AD-20 (Info.plist part), Additional: Starter/scaffold, PRD §9 Q1, PRD FR-64

**Acceptance Criteria:**

**Given** an empty `vigie/` repository
**When** the scaffold is created
**Then** it contains `App/` (thin Xcode app target), `Packages/Wire`, `Packages/ModuleKit`, `Packages/AgentKit`, `Packages/VigieUI`, `Packages/VigieCore`, `Packages/VigieCLI`, `Themes/`, `schemas/`, `.github/workflows/`, a `LICENSE` file holding the GNU GPLv3 text, license GPL-3.0-only (changed 2026-11-25; was "All rights reserved" from 2026-11-06, PRD §9 Q1, and GPL-3.0 before that) and a `.xcode-version` pinning Xcode 27.1
**And** `Modules/*`, `Adapters/*` and `Terminals/*` packages are NOT created yet (each is created by the first story that needs it, A7)

**Given** the package manifests
**When** I inspect dependencies
**Then** they match the layer table exactly (Core → ModuleKit, VigieUI, Wire; AgentKit → ModuleKit, Wire; VigieUI → ModuleKit; VigieCLI → Wire only; contracts depend on Foundation/SwiftUI only)
**And** every target uses Swift 6 language mode with complete concurrency checking
**And** no third-party dependency outside the AD-16 allowlist is declared
**And** no GPL-licensed code (e.g. from Boring Notch) is copied into the repository (NFR21: rule kept after the 2026-11-25 GNU GPLv3 decision)

**Given** the app target
**When** it is built in Debug and Release
**Then** the deployment target is macOS 15.0, `LSUIElement = YES`, bundle id is `fr.baguettelabs.vigie.dev` (Debug) / `fr.baguettelabs.vigie` (Release)
**And** the target contains only assembly code, Info.plist, an InfoPlist String Catalog, entitlements and assets

**Given** any package with user-facing text
**When** it is scaffolded
**Then** it has a String Catalog and a sample string looked up with `bundle: .module`
**And** `swift test` passes in every package with at least one placeholder test

### Story 1.2: AppEnvironment and dev build isolation

As Romain,
I want the dev build and the installed release build to use completely separate paths, socket and CLI name,
So that I can develop Vigie while dogfooding the released app without either corrupting the other.

**Requirements:** AD-17, NFR28, NFR22

**Acceptance Criteria:**

**Given** the `Wire` package
**When** `AppEnvironment` is compiled with the dev flag
**Then** it yields bundle id `fr.baguettelabs.vigie.dev`, display name "Vigie Dev", CLI name `vigie-dev`, its own Application Support folder, socket, spool, `instance.lock` and `local.toml` paths
**And** compiled without the flag it yields the release values (`fr.baguettelabs.vigie`, `vigie`)

**Given** both the app target and the CLI target
**When** they resolve any path
**Then** the path comes from `AppEnvironment` (no path literals elsewhere; a unit test greps for `Application Support` literals outside Wire and fails if found)

**Given** an Application Support path that makes the socket path longer than 100 bytes
**When** `AppEnvironment.socketPath` is computed
**Then** both sides use `<DARWIN_USER_TEMP_DIR>/<bundle id>/vigie.sock` obtained with `confstr` (not `$TMPDIR`)
**And** a unit test covers both branches

**Given** the dev configuration
**When** the config folder default is read
**Then** it defaults to the release config folder but can be overridden for dev builds

### Story 1.3: Continuous integration for pull requests

As Romain,
I want every push and pull request built and tested on GitHub Actions without secrets,
So that agent-written code is gated from day one and fork PRs are safe.

**Requirements:** FR104, NFR12, NFR25, AD-15, Conventions (Tests)

**Acceptance Criteria:**

**Given** a pull request or a push to `master`
**When** `ci.yml` runs on a `macos-26` arm64 runner with the Xcode version from `.xcode-version` selected explicitly
**Then** it runs `swift test` for every package and `xcodebuild build test` for the app scheme (so String Catalogs compile)
**And** it runs a lint step using `swift-format` from the toolchain (A75)

**Given** the workflow definition
**When** it is reviewed
**Then** it references no secrets, performs no signing, and uses no `release` environment

**Given** the built app bundle
**When** the locale check step runs
**Then** it fails if any shipped locale is missing from the bundle (English only for now)

**Given** later stories add the theme generator, adapter fixtures and the ConfigStore corpus
**When** they land
**Then** they hook into named CI steps already present as no-ops (`theme-regen-diff`, `adapter-fixtures`, `config-corpus`) so the CI floor (NFR25) grows without restructuring

### Story 1.4: Spike — Claude Code hook reaches a socket listener

As Romain,
I want `vigie-dev hook claude` to deliver Claude Code's native hook events to a socket listener that logs them,
So that the event path is proven end to end before building the session model.

**Requirements:** FR79 (spike scope), FR78 (spike scope), NFR3, AD-7, SPEC §13 Spike

**Acceptance Criteria:**

**Given** the `Wire` package
**When** the envelope type is defined
**Then** it is `{ "v": 1, "topic": "...", "sent_at": "<ISO 8601 UTC fractional>", "payload": {...} }` with Codable round-trip tests
**And** decoding ignores unknown fields

**Given** a minimal listener in VigieCore bound to `AppEnvironment.socketPath` with permissions 0600
**When** Claude Code (configured by hand with `vigie-dev hook claude` on all 8 hook events) runs a session that uses a tool and ends its turn
**Then** each hook invocation produces one logged envelope with topic `agent.hook`, agent id `claude`, the raw native payload, TTY, `TERM_PROGRAM`/`ITERM_SESSION_ID`/`WARP_*` env, and the process ancestor chain (≤ 8 levels of `{pid, ppid, name, start_time}`)

**Given** the app is not running
**When** the hook fires
**Then** the CLI exits 0 with no stdout/stderr output in under 150 ms (measured over 100 runs in a test)
**And** it never forks, detaches or retries

**Given** the spike is complete
**When** Romain reads `docs/decisions/spike-hook-path.md`
**Then** it records the observed Claude Code payloads (saved as raw fixtures for Story 4.6) and any surprises in hook behavior

### Story 1.5: Spike — focus a specific Warp tab

As Romain (a Warp user),
I want to know whether Vigie can bring one specific Warp tab to the front from a session's captured data,
So that the Warp terminal adapter is built on a proven technique or explicitly documented as app-level focus only.

**Requirements:** FR43 (research), SPEC §14.1, §13 Spike, AD-23 (Terminals), Architecture Deferred (Warp technique)

**Acceptance Criteria:**

**Given** a throwaway prototype (outside the shipped packages or in a spike folder)
**When** three Warp windows/tabs run Claude Code sessions
**Then** the prototype attempts focus using the Accessibility API, locating the tab by a unique title (set by the agent or by a hook-set title) and pressing it
**And** it records which `WARP_*` environment variables are available at hook time and whether they identify a tab

**Given** the experiment results
**When** the spike ends
**Then** `docs/decisions/spike-warp-focus.md` states one of: (a) exact-tab focus works, with the technique, required permissions (Accessibility and/or Automation) and failure modes; or (b) only app-level focus is reliable, and Warp is documented as "app-level focus only" (SPEC §14.1)
**And** the record lists what `capture(env:pid:tty:)` must store as the `TerminalLocator` for Warp

**Given** the decision record
**When** Story 5.4 is picked up
**Then** it can be implemented without further research

### Story 1.6: Spike — Ghostty tab focus investigation

As Romain,
I want the Ghostty focus approach investigated with the same rigor as Warp,
So that the v0.1 promise "focus on the four terminals" is either achievable or downgraded knowingly for Ghostty.

**Requirements:** FR43 (research), SPEC §7.1.1 (Ghostty "to be investigated"), A9

**Acceptance Criteria:**

**Given** the installed current Ghostty release
**When** the investigation runs
**Then** it checks AppleScript/Apple Events support, any CLI or IPC for tab selection, the environment exposed to child processes, and Accessibility-based tab selection

**Given** the findings
**When** the spike ends
**Then** `docs/decisions/spike-ghostty-focus.md` states exact-tab, window-level or app-level focus, the locator fields to capture, and the required permissions
**And** it notes how `openTab(argv:cwd:)` (Ask AI, Epic 9) could open a new tab in Ghostty

### Story 1.7: UX design pass for undesigned surfaces

*Added 2026-11-06 (ruling "design first" on A32, A35, A38, A39, A83, A87).*

As Romain,
I want every surface that has no design yet designed before the story that builds it starts,
So that no story invents visuals on the fly and the UX spines stay the single source of look and behavior.

**Requirements:** DESIGN.md, EXPERIENCE.md (spines win on conflict), A32, A35, A38, A39, A83, A87

**Status: done 2026-11-07 (parts a–f).** Design delivered in DESIGN.md and EXPERIENCE.md (both `status: final`, updated 2026-11-07); key-screen mock `ux-designs/ux-vigie-2026-11-04/mockups/key-design-pass-1-7.html` (its banner names the chosen option per part). Chosen: 1.7a detached gear far right of the tab row; 1.7b Option 3 (stale = dashed ring with `?`, process-only = plain grey dot); 1.7c layout B drag-only drop display + Shelf-tab `SEND TO` card + `COPIED · N LINES` readout on the left wing; 1.7d Direction 2 (shared status vocabulary); 1.7e all Time surfaces as drawn; 1.7f C tabs and notes as drawn, Calendar today gold. The consuming stories below are unblocked.

This story is done in parts (run with `bmad-ux` in Update mode). Each part must be finished before its first consuming story, so sprint planning schedules each part ahead of that story rather than all of them in Epic 1.

| Part | Surface | Needed before | Status |
|---|---|---|---|
| 1.7a | Settings (gear) icon in the expanded view: placement, size, states, accessibility label | Story 2.10 | Done 2026-11-07 |
| 1.7b | Stale session and process-only presence looks | Stories 4.8, 14.2 | Done 2026-11-07 |
| 1.7c | AirDrop and Image to Text drop zones during a drag (drag-only drop display), and the Image to Text confirmation readout | Stories 9.1, 9.8, 9.9 | Done 2026-11-07 |
| 1.7d | Script widgets (status, number, text), the side-slot item and the script page | Story 12.5 | Done 2026-11-07 |
| 1.7e | Time tab, closed-notch time readout, Timer-end and break-reminder peeks | Stories 20.2, 20.4, 20.5, 20.6 | Done 2026-11-07 |
| 1.7f | Twin Metal Tactical expanded tabs and notes panel | Story 18.1 | Done 2026-11-07 |

**Acceptance Criteria:**

**Given** a part of this story
**When** it is done
**Then** DESIGN.md (tokens, components) and EXPERIENCE.md (states, interactions, accessibility label, microcopy) describe the surface in both Chrome Hologram looks, with a key-screen mock in `ux-designs/ux-vigie-2026-11-04/mockups/`
**And** the matching `[ASSUMPTION]` or open question in the spines is closed, and the assumption it replaces in this file (A32, A35, A38, A39, A83, A87) is marked superseded by the design

**Given** a consuming story listed above
**When** sprint planning schedules it
**Then** it is not ready for development until its part of Story 1.7 is done

## Epic 2: Vigie lives in the notch

Users see a themed Vigie island in the hardware notch or a virtual notch on plain displays, on the right display(s), with sessions in the right wing and every other module in a shared left-wing lane ordered by priority (overflow → `+X`); they can open an expanded view and configure everything in `config.toml` or a native Settings window. A test module (`dev.sample`, debug builds only) exercises the host until real modules arrive in Epic 4 (A10).

### Story 2.1: Single-instance accessory app shell

As a user,
I want Vigie to run as one background accessory process with no Dock icon,
So that it never clutters my Dock and two copies never fight over the notch.

**Requirements:** AD-21, NFR2, FR94 (no Dock icon), A32

**Acceptance Criteria:**

**Given** Vigie is launched
**When** it starts
**Then** it uses the accessory activation policy, shows no Dock icon and no menu bar item, and takes an exclusive `flock` on `<Application Support>/instance.lock` before touching anything else

**Given** Vigie is already running
**When** a second instance launches
**Then** it detects the held lock, sends `app.expand` to the running instance (once the Event Server exists in Epic 4; until then it just quits), and quits

**Given** the user right-clicks the closed notch (A32)
**When** the context menu appears
**Then** it offers `Settings…` (enabled once Story 2.14 lands) and `Quit Vigie`, and choosing Quit terminates the app cleanly

**Given** the app quits
**When** it releases resources
**Then** the instance lock is released and no helper process, LaunchAgent or XPC service remains

### Story 2.2: Module contracts and registry lifecycle

As a user,
I want every feature to be a module I can switch off, with nothing running when it is off,
So that Vigie only does what I asked for.

**Requirements:** FR1, FR3, FR4, FR6, NFR4, NFR15, AD-1, AD-3, AD-4, AD-11, AD-19 (settings, storage, scheduler, events, host, log), Conventions (JSON state files, Errors, Logging)

**Acceptance Criteria:**

**Given** `ModuleKit`
**When** the contracts are declared
**Then** `NotchModule` (instance `manifest`, `state`, `compactView(size:)`, `homeCard()`, `expandedView()`, `dropZones`, `start(context:)`, `stop()`), `ModuleManifest`, `ModuleState` (`hidden < ambient < active < alert`), `CompactSize`, `SettingDescriptor` (with `scope: .synced | .local`) and the `ModuleContext` protocol with the AD-19 service list exist, all boundary types `Sendable`
**And** services not yet implemented are declared in the protocol and implemented by the story that first needs them

**Given** the App assembly lists modules and the config has `[modules."dev.sample"] enabled = false`
**When** Vigie launches
**Then** the Registry never instantiates the module's work, never calls `start`, and no timer or subscription for it exists (verified by a test spy)

**Given** a module is enabled at runtime
**When** its config flips to `enabled = true`
**Then** `start(context:)` is called once; hotkeys, scheduler jobs and event subscriptions it registers are tracked by the context
**And** when it flips back or the app quits, `stop()` is called and every tracked registration is removed automatically

**Given** a module throws or its state file is unreadable
**When** the Registry starts it
**Then** the host does not crash, the module is marked errored, and an unreadable JSON state file is renamed `.corrupt` and the module starts empty with a log entry

**Given** `context.storage`
**When** a module writes JSON state
**Then** it lands in `Application Support/<app folder>/modules/<module id>/` with a top-level `"schema"` field, atomically (temp + rename), coalesced to ≤ 1 write per 250 ms

### Story 2.3: ConfigStore read path with live reload

As a user,
I want Vigie to read `config.toml` and pick up my edits immediately,
So that my configuration lives as code and changes apply without restart.

**Requirements:** FR99, FR100, NFR14, NFR15, NFR17, AD-8 (reading, scope routing, watching), AD-12 (directory watching), A11

**Acceptance Criteria:**

**Given** no config folder exists
**When** Vigie starts
**Then** it creates `~/.config/vigie/config.toml` with the SPEC §11 defaults (commented) and an empty `local.toml` in Application Support

**Given** settings declared with `scope: .local` (`[display]`, `[virtual_notch]`, `[modules."agents.sessions".local]`, folder locations, `[sync]`, script state)
**When** values exist in both files
**Then** `local.toml` wins, and `.local` keys are never read from the synced file into shared state

**Given** a config with a TOML parse error
**When** it is loaded
**Then** the last valid config stays active and a config problem `{kind: invalidFile, path, line}` is published on ConfigStore's observable problems list and logged (the setup-problem alert is wired in Story 3.4)

**Given** a known key with a wrong type or out-of-range value
**When** it is loaded
**Then** that key falls back to its default, a problem naming the key is published, and the rest of the file applies
**And** unknown keys and tables are ignored and logged once

**Given** the user edits `config.toml` in an editor that saves by atomic replace
**When** the change is saved
**Then** the directory watcher detects it, observers are notified only for keys whose resolved value changed, and the change applies live

### Story 2.4: Chrome Hologram theme engine

As a user,
I want Vigie drawn in the Chrome Hologram look that follows my macOS appearance,
So that it looks like a native instrument and stays consistent everywhere.

**Requirements:** FR95 (Chrome Hologram, light/dark, forced mode, live), UX-DR1, UX-DR3, UX-DR5, UX-DR6, UX-DR7, UX-DR8, UX-DR54, NFR14, AD-14, A14

**Acceptance Criteria:**

**Given** DESIGN.md frontmatter
**When** the `themegen` executable target in VigieUI runs
**Then** it generates `Themes/base.toml` and `Themes/chrome-hologram.toml` (dark and light looks) with `schema = 1`, using the same Codable token types as the runtime loader
**And** the CI `theme-regen-diff` step regenerates them and fails on any diff

**Given** VigieUI
**When** a view needs a color, metric, radius, motion duration or font role
**Then** it reads it from the active theme (no literals in views; a lint/test rule flags hex colors and numeric durations in module view code)

**Given** `[appearance] mode = "system"`
**When** macOS switches between light and dark
**Then** panels switch looks live without restart; with `mode = "light" | "dark"` the look is forced

**Given** any appearance
**When** the island is drawn on a physical notch
**Then** it resolves the dark look of the active variant (AD-14)

**Given** typography tokens
**When** live numerals render (T+, percentages, countdowns)
**Then** they use tabular figures and only system fonts (SF Pro, SF Mono)

### Story 2.5: Notch Host on a physical notch

As a MacBook user,
I want Vigie's closed island to sit exactly around my hardware notch with two wings,
So that status lives in space I never use, without covering anything else.

**Requirements:** FR9 (frame), FR18 (physical), NFR2, UX-DR9, UX-DR10, UX-DR14, UX-DR15, UX-DR41, UX-DR77, UX-DR42 (full presence, A ornaments)

**Acceptance Criteria:**

**Given** a Mac with a hardware notch
**When** Vigie starts
**Then** a non-activating `NSPanel` above the menu bar draws a black island of `band-height` (34 px) with `island-closed` bottom radius, leading and trailing wings sized from `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` and each capped by `closed.max_side_width` (default 120)
**And** the frontmost app keeps key status (verified by a UI test that types into TextEdit while Vigie is visible)

**Given** the Chrome Hologram look at full presence
**When** the island is idle
**Then** the 1px iris rim and the interior shimmer run inside the outline on `ambient-loop`, and nothing (hairline, glow, readout) is drawn outside the island outline (mockup `key-closed-notch-states.html`)

**Given** the pointer hovers the island
**When** it enters
**Then** the A hover reaction plays over `motion.enter` (rim full strength, interior lift, one shimmer) inside the outline and the island does not expand

**Given** the `dev.sample` module returns a compact view
**When** it wins a side
**Then** its view is clipped to the wing frame

### Story 2.6: Virtual notch on plain displays

As a user with an external monitor or a Mac without a notch,
I want a virtual notch that behaves like the real one without hiding menu items,
So that I get Vigie on any display.

**Requirements:** FR11 (virtual), FR18 (virtual), FR24, FR25, FR26, FR27, UX-DR14 (menu_bar style), UX-DR76 (amended 2026-11-07), A42 (superseded 2026-11-07)

**Acceptance Criteria:**

**Given** a plain display selected for Vigie
**When** the virtual notch is drawn
**Then** its width is `virtual_notch.width` (default 200, MacBook notch size) at `position = center` or just left of the status items at `right`, and at `placement = menu_bar` or just below the menu bar at `below`

**Given** no module wants either side
**When** `virtual_notch.idle` is `shrink`, `hide` or `keep`
**Then** the pill shrinks to its minimum width, hides, or keeps its width respectively

**Given** `virtual_notch.style = "menu_bar"` in light appearance
**When** the pill is drawn
**Then** it fills `surface-vn-top → surface-vn-bottom` and uses the light role set; ~~in dark appearance it uses the dark menu-bar material with the dark role set (A42)~~ **Amended 2026-11-07 (epics update run):** in dark appearance it falls back to the black island look (`base-island` with the dark role set) until dark virtual-notch tokens exist (DESIGN token scheme, EXPERIENCE OQ15; A42 superseded); `style = "black"` looks like a hardware notch

**Given** macOS "Automatically hide menu bar" is on
**When** the menu bar hides and reappears
**Then** the virtual notch hides and returns with it, and a peek can still appear while it is hidden

**Given** the pointer is pushed to the top edge anywhere over the top-center strip (wider than the pill, a few points tall)
**When** it arrives
**Then** the hover reaction triggers

### Story 2.7: Display selection, multi-display and hot-plug

As a user with several displays,
I want to choose where Vigie appears and have it follow lid and monitor changes live,
So that it is always on the screen I'm using and never over a full-screen app.

**Requirements:** PRD FR-1 (within 2 s), FR19, FR20, FR21, FR22, FR23 (same state on all), UX-DR62 (full-screen), UX-DR76, A60

**Acceptance Criteria:**

**Given** `[display] display` in `local.toml` is unset
**When** Vigie places itself
**Then** it uses the notched display if any, otherwise the main display; in clamshell mode it uses the main external display

**Given** the first launch on a Mac whose connected displays include one without a notch (A60, ruled 2026-11-06: in v0.1)
**When** Vigie places itself for the first time
**Then** it shows its island using the default rule above and a one-time prompt in the expanded view asking where Vigie should appear (this display, the notched display, all displays), which writes `[display] display` to `local.toml`
**And** the prompt never takes focus by itself (it waits in the expanded view, marked on the island) and is not shown again once answered or dismissed

**Given** `display = "main" | "notched" | "all" | "<display name>"`
**When** placement runs
**Then** Vigie appears on the matching display(s); with `all` every notch shows the same state

**Given** each connected display
**When** the host classifies it
**Then** it is `physical`, `plain` or `island`, and `island` displays are handled exactly like `plain` for all of v1 (PRD FR-2; A26 resolved)

**Given** a display is connected/disconnected, resolution or arrangement changes, or the lid opens/closes
**When** the screen-parameters notification fires
**Then** placement re-runs ~~live~~ **Amended 2026-11-07 (epics update run):** within 2 s of the display change (PRD FR-1), without restart and without duplicating panels

**Given** `hide_in_fullscreen = true` and a full-screen app on a display
**When** that space is active
**Then** Vigie's island is hidden on that display only

### Story 2.8: Closed-notch arbitration with multi-slot sides

As a user,
I want the right wing to show my sessions and the left wing to show the most relevant items from any module,
So that the most important information wins the little space available.

**Requirements:** FR9, FR10 (amended 2026-11-07), FR11, NFR25, UX-DR73 (slots), A22, SPEC v0.7 §5 (left-wing item lane, ruled 2026-11-07)

**Acceptance Criteria:**

**Given** the trailing (right) side
**When** arbitration runs
**Then** only `agents.sessions` may take it (no other module, so an alert glyph is never hidden)

**Given** enabled modules offering left-wing items (each provider ring of `agents.usage`, each script with `side` in its surfaces, the Time readout), each item with a `priority` and its module's observable `state`
**When** arbitration runs for the leading (left) side
**Then** the host pools the items of modules with state ≠ hidden, sorts them by state descending, then priority ascending (ties: provider `order`), shows the first `closed.slots`, and counts the rest in a left `+X` (readout-label style, `ink-3`) that never hides an item in alert while a lower one is visible

**Given** a shown item and the wing's available width
**When** the host asks for its compact view
**Then** it requests `wide`, then `short`, then `icon` until a non-nil view is returned; an item returning nil at all sizes yields its slot to the next item in the lane

**Given** `closed.slots` (default 3, clamped to 1…4)
**When** a side renders
**Then** it holds at most that many items plus `+X`; the transient Image to Text `COPIED` readout sits after the first left item for 2 s and pushes the last visible item into `+X` meanwhile

**Given** state changes in any module
**When** they happen
**Then** arbitration re-runs on the main actor; unit tests cover ordering, ties, mixed-module left items, `+X` counts, size fallback and empty sides (NFR25)

### Story 2.9: Hotkeys and user-intent focus control

As a user,
I want global shortcuts that never collide silently and a guarantee that Vigie only takes focus when I ask,
So that my typing is never hijacked.

**Requirements:** FR111, NFR2, UX-DR45, AD-13 (focus, hotkeys), AD-19 (hotkeys, host), Conventions (Hotkeys)

**Acceptance Criteria:**

**Given** `context.hotkeys` backed by KeyboardShortcuts 3.1.x
**When** a module registers a hotkey
**Then** its name is namespaced `<module id>.<name>`; on a conflict the earlier registration wins and the later one is reported as a hotkey conflict problem (alert wired in Story 3.4)

**Given** VigieCore
**When** a click, hotkey callback or menu action happens
**Then** it issues a `UserIntent` token; focus-taking host calls (`expand(focus:)`, `showPanel(focus:)`) require that token, and without it surfaces open without focus

**Given** two Vigie surfaces
**When** both are open
**Then** at most one is key, and Esc closes only the key surface

**Given** default shortcuts
**When** they are defined
**Then** none uses Option-only modifiers; `expand_hotkey` defaults to `cmd+shift+space` and is editable in config

### Story 2.10: Expanded view shell

As a user,
I want to click the notch (or press my shortcut) to open a panel with tabs, and close it as I expect,
So that details are one click away without ever popping up by themselves.

**Requirements:** FR87, FR88, FR89, FR91, FR23 (expanded under cursor), UX-DR26, UX-DR27, UX-DR41, UX-DR46, UX-DR47, UX-DR48, UX-DR66, UX-DR80, UX-DR96 (`exit`), UX-DR104, A12, A32, A41 (superseded 2026-11-07), A73 · **Depends on:** Story 1.7a (settings icon design, done 2026-11-07)

**Acceptance Criteria:**

**Given** the closed notch
**When** the user clicks it or presses `expand_hotkey`
**Then** the expanded panel (720×420, `expanded` radius, 34 px black band with `VIGIE` wordmark and `● Online · HH:MM · Ddd DD Mon` status) grows out of the notch on the display under the cursor and takes keyboard focus
**And** it opens on Home once Home exists (Epic 11); until then it opens on the first tab (A12)

**Given** `open_on_hover = false` (default)
**When** the pointer hovers the notch
**Then** only the hover reaction plays; with `open_on_hover = true` it opens after `hover_delay` without taking focus

**Given** the expanded view is open and focused
**When** the user clicks outside, presses Esc, or presses the hotkey again
**Then** it collapses (~~over `motion.enter`, A41~~ **Amended 2026-11-07 (epics update run):** over `motion.exit`, 200 ms ease-in, provisional per DESIGN; A41 superseded); with `close_on_leave = true` it also collapses when the pointer leaves

**Given** enabled modules with an `expandedView()`
**When** the tab bar renders
**Then** it shows their tabs in the user order from `[general] tab_order` (A12), a module in `alert` carries the 5 px marker, and `⌘1…9` switch tabs while focused

**Given** a tab carrying the 5 px attention marker (Agents while a session is blocked or failed; later Time while a break is due or an ended timer is unacknowledged, Epic 20) (added 2026-11-07)
**When** VoiceOver focuses that tab
**Then** it reads "<tab>, needs attention"; the marker is a shape, so color is never the only cue (UX-DR104)

**Given** the expanded view (A32, ruled 2026-11-06)
**When** it renders
**Then** it shows the settings gear designed in Story 1.7a (DESIGN.md Settings gear): a detached 24px round button (C: 26px square) with a 14px outline gear, at the far right of the tab row, apart from the tab pill, on every tab; default `ink-3`, hover raised like an active tab with the macOS tooltip `Settings (⌘,)`, keyboard focus ring; clicking it or `↵` on focus opens Settings (enabled once Story 2.14 lands, as in Story 2.1); it never becomes the active tab and has no `⌘1–9` slot; accessibility label `Settings`
**And** (added 2026-11-07) Tab / `←→` reach the gear after the last tab, and `↵` or Space opens Settings; its focus ring is, per look, A dark 1 px platinum 55 % ring + 3 px cyan halo 14 %, A light the 1 px graphite selection ring (no halo), C the C selection ring; hover is the raised pill in A and a 30 % struct border in C; it sits `tabs-margin-x` from the edge and `tab-row-gap` from the tabs (UX-DR80)

**Given** the expanded view
**When** nothing triggers it
**Then** it never opens by itself (no code path opens it without a click, hotkey or opt-in hover)

### Story 2.11: Shared VigieUI components

As a user,
I want every tab to use the same cards, empty states, setup cards and buttons,
So that Vigie feels like one instrument and every empty or broken state tells me what to do.

**Requirements:** FR92 (components), NFR9, UX-DR23, UX-DR24, UX-DR25, UX-DR28, UX-DR29, UX-DR40, UX-DR43, UX-DR44, UX-DR63, UX-DR82, UX-DR103, AD-15 (status labels in VigieUI)

**Acceptance Criteria:**

**Given** VigieUI
**When** the components are implemented
**Then** it provides `WidgetCard` (header title + meta, A iris filament), `EmptyStateBlock` (label, sentence, optional Settings button), `SetupCard` (i-in-square, `SETUP · <topic>` kicker, title, sentence, two buttons), `ActionButton` (primary/secondary, label + shortcut) and inline chips, list scroll fade + thumb + `SCROLL ↓`, 6-dot grip, row hover brighten and keyboard selection ring

**Given** status labels
**When** any module needs `IDLE`, `WORKING · 14M`, `DONE · 1M`, `BLOCKED · 12M`, `FAILED · 41M` **Amended 2026-11-07 (epics update run):** and `STALE · 18M`, `RUNNING`, `FAILED · EXIT <n>`, `OK` / `WARN` / `DOWN` with their `·` qualifiers (`CHECKED 2 MIN AGO`, `DOWN SINCE 14:44`) (UX-DR103)
**Then** they come from one public VigieUI API backed by its String Catalog

**Given** an accessibility-label helper
**When** a glyph or control is labeled
**Then** it produces the format "vigie / api-refactor, blocked, 2 minutes" (UX-DR63)

**Given** the status vocabulary primitive (added 2026-11-07)
**When** a module renders a level `ok`, `warn` or `down`
**Then** VigieUI draws OK = ring in `status-idle`, WARN = triangle in `quota-warning` (label in `quota-warning-text` on light looks), DOWN = × in `status-failed`, always with its label beside the shape, at 26 / 16 / 10 px, following the user's status colors, static in every Presence mode; drawing it never raises an alert (UX-DR82)

**Given** the EXPERIENCE copy table
**When** empty and setup strings are added
**Then** they follow Voice and Tone (uppercase labels, factual sentences, no exclamation marks) and live in String Catalogs

### Story 2.12: Permissions service and needs-permission state

As a user,
I want Vigie to ask for a permission only when I enable the feature that needs it,
So that a shelf-only setup never asks for Accessibility or Calendar.

**Requirements:** FR2, NFR4, AD-19 (permissions), AD-20 (Permission cases), Conventions (Permissions)

**Acceptance Criteria:**

**Given** `context.permissions` with cases `.accessibility`, `.automation(bundleID)`, `.calendar`, `.notifications`
**When** a module declaring a permission is enabled
**Then** the permission is checked and, if not determined, requested only at that moment

**Given** a permission is denied
**When** the module would start
**Then** it stays stopped and its state is `needsPermission(permission)`, observable by Settings and by the module's tab (setup card)

**Given** a module is disabled
**When** Vigie runs
**Then** none of its permissions is ever requested

**Given** the user grants the permission later in System Settings
**When** Vigie re-checks (on app activation and every 30 s while a module waits)
**Then** the module starts without restart

### Story 2.13: ConfigStore writer (comment-preserving TOML patcher)

As a user who keeps `config.toml` in git,
I want changes made from the app to touch only the lines that changed,
So that my comments, ordering and unknown keys survive.

**Requirements:** NFR17, NFR16, AD-8 (writing), Conventions (File writes), NFR25

**Acceptance Criteria:**

**Given** a round-trip corpus under `Packages/VigieCore/Tests/ConfigCorpus/` (comments, blank lines, inline tables, arrays, arrays of tables, quoted keys like `[modules."agents.sessions"]`, CRLF, unknown tables)
**When** a single key is set
**Then** only that `key = value` line is replaced or inserted in the target table and every other byte is identical (golden-file tests in CI step `config-corpus`)

**Given** a write
**When** ConfigStore performs it
**Then** it re-reads the file, patches the fresh text, re-parses it with swift-toml, aborts if parsing fails or the decoded value differs, then writes atomically to the symlink-resolved path

**Given** a setting with `scope: .local`
**When** it is written
**Then** it goes to `local.toml`, never to `config.toml`

**Given** ConfigStore's own write
**When** the watcher sees it
**Then** it is ignored (content hash equals last write) and no reload storm occurs

### Story 2.14: Generated Settings window

As a user,
I want a native Settings window generated from what each module declares,
So that I can change anything without editing TOML, and every setting stays editable in the file.

**Requirements:** FR5, FR93, FR2 (needs-permission display), FR41 (pane structure), UX-DR39, UX-DR74 (pane skeleton), AD-8, AD-21 (no Dock icon), A13, A32, A61

**Acceptance Criteria:**

**Given** modules' `SettingDescriptor`s
**When** Settings opens
**Then** each module has a pane with native controls generated for `bool`, `int`/`double` (min/max/step), `string`, `secret` (masked field; storage wired in Story 7.2, disabled until then), `enum`, `duration`, `hotkey` (KeyboardShortcuts Recorder, only here), `path`, `list<T>`
**And** a module may add a custom view below the generated controls, never replacing them

**Given** a change in Settings
**When** the user edits a control
**Then** it is written through ConfigStore and appears in `config.toml`/`local.toml` immediately; an outside edit updates the open window live

**Given** the expanded view is focused, the context menu `Settings…` is chosen, or the expanded-view settings icon is clicked (A32)
**When** the user presses `⌘,` or picks the item
**Then** the Settings window opens and becomes key, and no Dock icon appears

**Given** Settings › General (A61, ruled 2026-11-06: in v0.1)
**When** the user turns on `Launch at login` (`[general] launch_at_login`, local, default off)
**Then** Vigie registers itself as a login item through `SMAppService.mainApp`, turning it off unregisters it, and the toggle reflects the real registration state (including a change made in System Settings › Login Items)

**Given** a host API `openSettings(pane:)`
**When** called with a pane id (e.g. `agents.codex`)
**Then** Settings opens on that pane

**Given** a module in `needsPermission`
**When** its pane shows
**Then** it states the missing permission with a button to System Settings

### Story 2.15: Accessibility floor in v0.1

*Added 2026-11-06 for PRD FR-63 (floor from v0.1).*

As a user who relies on macOS accessibility settings,
I want the v0.1 surfaces to meet the accessibility floor from the first build,
So that Vigie is usable for me long before the v0.4 theme work.

**Requirements:** PRD FR-63, NFR9, NFR10 (Reduce transparency, Increase contrast), UX-DR13, UX-DR63, UX-DR65, UX-DR66, UX-DR94, UX-DR95, UX-DR96, AD-14 (accessibility adjustments resolved last, once, in VigieUI), AD-15, A15, A79

**Acceptance Criteria:**

**Given** macOS Reduce transparency is on
**When** any Chrome Hologram surface renders (closed notch, peek, expanded view, previews in Settings)
**Then** glass gradients become flat `surface-panel` / `surface-card` fills, and the change applies live when the setting flips

**Given** macOS Increase contrast is on
**When** rendered
**Then** ~~hairlines move to `ink-3`~~ **Amended 2026-11-07 (epics update run):** the DESIGN Increase contrast table applies: hairlines and zone, chip and card borders become solid 1 px `ink-3`; the Ask AI dashed border is drawn at 100 % lilac; tracks (time ring, countdown, quota, pace) reach at least 40 % `ink-3`; focus rings become 2 px with the halo dropped; glass gradients become flat `surface-panel` / `surface-card`; upcoming phase pips are unchanged; decorative-only elements reach 3:1 (UX-DR95); and user color overrides keep their hue (contrast may be raised, never discarded)

**Given** macOS Reduce motion is on (A15, A79, ruled 2026-11-06: from v0.1)
**When** any surface would animate (expand and collapse, peek arrival, hover reaction, working pulse, ring fill)
**Then** it changes state without motion (instant or a short cross-fade), information stays the same, and the change applies live when the setting flips
**And** (added 2026-11-07) functional drains (peek dwell line, `COPIED` drain, notes clipboard drain) become a static full line that disappears at the end; the Time peek rim, Ask AI `+`, card iris filament and drop display rim are static as those surfaces arrive; `peek-grow`, `drop-display-grow` and the `exit` collapse become instant or a short cross-fade (UX-DR96)

**Given** the Chrome Hologram dark and light token sets
**When** CI runs
**Then** a contrast check fails the build if any text token is below 4.5:1 on a surface it is used on (UX-DR13 pairs) **Amended 2026-11-07 (epics update run):** or if any non-text meaning (status glyphs, rings, Time arcs, focus rings, zone and chip borders) is below 3:1 (WCAG 1.4.11); the checked pairs are the DESIGN contrast table and further-surfaces table, including warning text in `quota-warning-text #7E6300` on every A light surface (`#8A6D00` only for hatch, triangles, arcs and fills) and A light `status-idle #0B7651` / `status-done #1A68B5` (UX-DR94)

**Given** the six session Statuses and the quota and pace states
**When** a unit test inspects their VigieUI definitions
**Then** each has a distinct glyph shape or text label, so color is never the only cue

**Given** `docs/accessibility-floor.md`
**When** this story is done
**Then** it lists the floor checks (label with state via the 2.11 helper, non-color cue, 4.5:1 text, keyboard reachability, peek actions by global shortcut), and every later story that adds a surface is done only when that surface passes them
**And** Story 18.3 only adds "Reduce motion forces calm presence" once presence levels exist (A15, A79)

### Story 2.16: Virtual notch height follows the menu bar

As a user with an external monitor,
I want the virtual notch to be exactly as tall as that display's menu bar,
So that Vigie does not overhang the menu bar on plain displays.

**Requirements:** FR11 (virtual), FR24, FR25, UX-DR14, SPEC §5.5 · **Depends on:** Story 2.6, Story 2.7 · **Ruled by Romain 2026-11-12:** match the menu bar exactly, no legibility floor

**Context:** on a MacBook with a notch the menu bar is as tall as the notch, so the island (height = max(band, notch)) hugs it. On a plain display the virtual notch uses the theme's fixed `spacing.band-height` (34px) and overhangs the 24 pt menu bar by about 10 px (seen live on 2026-11-12, MacBook Air on an external monitor). The host already measures the menu bar height per screen (`MenuBarProbing.menuBar(on:)`), but `NotchGeometry.virtual` uses it only for `placement = below`.

**Acceptance Criteria:**

**Given** a plain display selected for Vigie
**When** the virtual notch is placed
**Then** its height is that display's measured menu bar height (24 pt on a default external display, more on scaled ones), exactly: `[closed] notch_overlap` stays a hardware cut-out setting (ruled 2026-11-12, match the menu bar exactly); the theme band height is no longer used for virtual height

**Given** the measured height changes (display scaling, display hot-plug, menu bar probe fallback)
**When** the host re-places its islands
**Then** the virtual notch follows the new height without a relaunch

**Given** a band shorter than the designed 34px
**When** closed-notch content is drawn (wing lane items: session chips, quota rings, Time readout, `BREAK DUE`, drop display, idle pill)
**Then** it fits the band: the theme exposes the band height to views (`Theme.withBandHeight` already raises it; it must also lower it) and the closed-notch components scale their rings, glyphs and labels from the band height instead of fixed values, with no clipping at 24 pt; the expanded view, peeks and the physical-notch band are unchanged

**Given** a plain display whose menu bar is hidden (auto-hide) or unmeasurable
**When** the probe falls back
**Then** the fallback height is the standard menu bar height of that screen (`SystemMenuBarProbe.fallbackHeight`), never the theme band

**Given** the `notch geometry` debug log
**When** a virtual island is placed
**Then** the line records the measured menu bar height next to the island frame

## Epic 3: Alerts that never steal focus

Users get one-time peek alerts with two keyboard actions that never take focus, governed by per-kind rules, Do Not Disturb, reminders and optional macOS notifications. The epic is usable on its own through setup-problem alerts (invalid config, hotkey conflicts); session alerts plug in during Epic 4 (A10).

### Story 3.1: Notifier rules engine

As a user,
I want every alert to pass through one set of rules I control in config,
So that noisy events (e.g. subagent stops) are silenced once and for all.

**Requirements:** FR28, FR29, AD-13 (alert config, lifecycle), NFR25, A53, A54

**Acceptance Criteria:**

**Given** `context.notifier`
**When** a module calls `post(event)` with `module`, `kind`, `severity`, `title`, `body`, `action`, `dedupe_key` (and optional numeric `metrics`)
**Then** it returns an `AlertHandle`, and only kinds declared in the module manifest are accepted (others are logged and dropped)

**Given** `[modules."<id>".notify."<kind>"]` rules and a global `[notify]` table
**When** an event is posted
**Then** Notifier applies mute, `min_severity`, `quiet_hours` (format `"22:00-08:00"`, A53), `cooldown` per `dedupe_key`, rule conditions such as `min_working_time` compared against event metrics (A54), and routes to the configured `outputs` (`peek`, `system`, `sound`)
**And** Notifier is the only component that reads `notify` tables and `[sounds]`

**Given** a rule with `reminder = "10m"`
**When** the handle is not resolved after 10 minutes
**Then** the outputs replay once; `resolve()` before then cancels the reminder and retracts a visible peek

**Given** actions
**When** an alert is acted on
**Then** `.module(id:actionID:payload:)` is routed back to the posting module, `.openSettings(pane:)` opens Settings on that pane, `.openURL` opens the URL

**Given** the rules engine
**When** unit tests run
**Then** they cover mute, severity, quiet hours across midnight, cooldown, reminder, resolve, and undeclared kinds

### Story 3.2: Peek presentation

As a user,
I want an alert to grow briefly out of the notch, once, and get out of my way,
So that I notice it without losing what I was typing.

**Requirements:** PRD FR-9 (fallback display), FR12, FR14, FR23 (peek under cursor), UX-DR21 (frame, dwell timer), UX-DR45, UX-DR73 (dwell), UX-DR93, UX-DR96 (`peek-grow`), NFR2, AD-13 (only host shows peeks), A52

**Acceptance Criteria:**

**Given** an event routed to `peek`
**When** the Notch Host shows it
**Then** a 700×150 panel with `peek` radius and the 34 px black band grows out of the notch on the display under the cursor, using the three-column grid (44 | 1fr | 176) and content supplied by the event
**And** the frontmost app keeps keyboard focus (UI test types continuously during the peek; no keystroke is lost)
**And** (added 2026-11-07) the panel grows over `motion.peek-grow` (280 ms) and retracts over `motion.exit` (200 ms); under Reduce motion both are instant or a short cross-fade

**Given** the display under the pointer does not show Vigie (added 2026-11-07)
**When** a peek is due
**Then** it shows on the main Vigie display instead (PRD FR-9)

**Given** any peek (blocked, failed, done, sleep summary, setup problem, quota warning, and the kinds later epics add) (added 2026-11-07)
**When** it appears
**Then** it posts a VoiceOver announcement with its kicker, title and primary shortcut (e.g. "Blocked, api-refactor, Option Command Return, focus terminal") without moving VoiceOver focus or keyboard focus (UX-DR93)

**Given** a visible peek
**When** `closed.peek_duration` (default 5 s) elapses
**Then** it retracts; the dwell timer line drains left over the dwell; hovering pauses both, leaving resumes them

**Given** several peeks arrive
**When** one is visible
**Then** others queue in urgency order; one peek is visible at a time; a module cannot show a new peek within 3 s of its previous one retracting (rate limit, A52)

**Given** `closed.peek = false` or a per-module peek off setting
**When** events arrive
**Then** no peek is shown but other outputs still apply

**Given** each event
**When** it has been shown once
**Then** it never re-peeks except through its reminder

### Story 3.3: Peek actions with temporary global shortcuts

As a user,
I want to act on an alert with `⌥⌘↵` or dismiss it with `⌥⌘⌫` without touching the mouse,
So that I can react in a keystroke while my editor keeps focus.

**Requirements:** FR13, UX-DR49, UX-DR25, UX-DR66, UX-DR93, AD-13 (peek shortcuts precedence)

**Acceptance Criteria:**

**Given** a visible peek with a primary action and Dismiss
**When** it appears
**Then** `⌥⌘↵` and `⌥⌘⌫` are registered globally and unregistered when the peek retracts; they take precedence over other Vigie shortcuts meanwhile

**Given** a visible peek
**When** the user presses `⌥⌘↵` or clicks the primary button
**Then** the event's primary action is dispatched (with a `UserIntent` token) and the peek retracts

**Given** a visible peek
**When** the user presses `⌥⌘⌫` or clicks Dismiss
**Then** the peek retracts and its reminder is cancelled, and the module's state is unchanged

**Given** a visible peek
**When** the user presses bare Esc or any other key
**Then** nothing happens in Vigie and the keystroke reaches the frontmost app

**Given** a visible peek's action buttons (added 2026-11-07)
**When** VoiceOver reads them
**Then** each button's accessibility label includes its shortcut (e.g. "Focus terminal, Option Command Return"; "Dismiss, Option Command Delete") (UX-DR93)

### Story 3.4: Setup-problem alerts

As a user,
I want a neutral alert when something in my setup is wrong, with a button to the exact Settings pane,
So that I fix problems instead of seeing wrong information.

**Requirements:** FR16, FR99 (alert part), UX-DR22, UX-DR62 (setup problem), UX-DR43, AD-8 (problems), AD-13 (setup.problem, hotkey conflicts)

**Acceptance Criteria:**

**Given** a `setup.problem` event
**When** it peeks
**Then** it uses the peek frame and dwell with no beacon, no glyph, no status hue and a static neutral rim; kicker `SETUP · <CATEGORY>`, the problem as title, one factual sentence, actions `OPEN SETTINGS ⌥⌘↵` / `DISMISS ⌥⌘⌫`, and the target pane named in `ink-3` (mockup `key-alert-variants.html` variant 4)

**Given** ConfigStore publishes an invalid-file or bad-key problem
**When** it appears
**Then** a setup-problem alert is posted once per distinct problem (dedupe on path + key) with `Open settings` targeting General (or the key's pane) and resolved when the problem disappears

**Given** a hotkey conflict reported by `context.hotkeys`
**When** it is detected
**Then** a setup-problem alert names both shortcuts' owners

**Given** a setup problem
**When** it is shown
**Then** it is never rendered as an agent state and never changes any module state

### Story 3.5: Do Not Disturb and Focus modes

*Status 2026-11-12: the shipped `Assertions.json` detection did not work (Full Disk Access, misses scheduled Focus); detection is replaced by Story 3.10 (Focus filter), the suppression rules below are unchanged.*

As a user in a meeting or Focus mode,
I want Vigie to stay silent while still updating the notch,
So that it respects macOS focus without hiding state from me.

**Requirements:** FR17, UX-DR62 (DND), UX-DR55 (no bypass), A21

**Acceptance Criteria:**

**Given** macOS Do Not Disturb or any Focus mode is active
**When** an event would peek or play a sound
**Then** neither happens, and the module's closed-notch state still updates

**Given** an alert suppressed by DND and `[notify] after_focus = "drop"` (default; A21, ruled 2026-11-06)
**When** DND ends
**Then** it is not replayed; it stays visible in its module's tab and in the activity log, and pending reminders that fall inside DND are also suppressed

**Given** `[notify] after_focus = "replay"`
**When** DND ends
**Then** Notifier posts only the latest still-unresolved suppressed alert per module, as normal peeks through the usual queue (Story 3.2), with no sound burst (sounds follow the normal rules, one per peek); an alert resolved during DND is never replayed
**And** the setting appears in Settings › Alerts as "When Focus ends: Drop missed alerts / Show the latest per module"

**Given** Settings
**When** the user looks for a DND bypass
**Then** none exists

**Given** DND detection
**When** it is implemented
**Then** it lives inside Notifier (Architecture Deferred) with a unit-testable abstraction

### Story 3.6: macOS notification output

As a user who prefers Notification Center for some alerts,
I want to route chosen alert kinds to macOS notifications,
So that I keep a history of them.

**Requirements:** FR30, FR2 (notifications permission), AD-19, AD-20 (.notifications), A70

**Acceptance Criteria:**

**Given** a rule whose `outputs` include `system`
**When** an event matches
**Then** Notifier posts a macOS notification with title and body, and clicking it dispatches the event action

**Given** no rule uses `system` (and shelf expiry notification is off)
**When** Vigie runs
**Then** the notifications permission is never requested (A70)

**Given** the notifications permission is denied
**When** a `system` output is needed
**Then** a setup-problem alert names the missing permission and other outputs still work

### Story 3.7: Alert settings generated from declared kinds

As a user,
I want to turn each alert kind on or off and set its reminder in Settings,
So that blocked, done and failed alerts behave the way I want.

**Requirements:** FR15, FR41 (alert settings), UX-DR73 (reminder), AD-13 (alert settings UI generated from kinds)

**Acceptance Criteria:**

**Given** kinds declared in module manifests
**When** a module's Settings pane renders
**Then** each kind has controls generated by Notifier: enabled, outputs (peek / system / sound), reminder delay; modules never declare alert settings themselves

**Given** the user changes a kind's settings
**When** saved
**Then** ConfigStore writes `[modules."<id>".notify."<kind>"]` in the SPEC §6 shape

**Given** `agents.sessions` (Epic 4) declares `session.blocked`, `session.done`, `session.failed`
**When** its pane renders
**Then** the three kinds have separate settings (blocked, finished, failed)

### Story 3.8: Local activity log

*Added 2026-11-06 for PRD FR-13 (v0.1, data source for the PRD §8 success metrics).*

As Romain,
I want a local record of every Alert, peek, reminder and Focus outcome for the last 30 days,
So that I can check the success metrics (SM-2, SM-6, SM-C1) from real use without any telemetry.

**Requirements:** PRD FR-13, PRD §8 (SM-2, SM-5, SM-6, SM-C1), NFR6, NFR7, NFR16, AD-13 (Notifier is the single alert path), AD-26 (activity log), A80

**Acceptance Criteria:**

**Given** the Notifier
**When** an Alert is posted, suppressed (mute, quiet hours, cooldown, Do Not Disturb), shown as a peek, repeated by a reminder, dismissed or resolved
**Then** one entry is appended with time (ISO 8601 UTC), module id, alert kind, severity, dedupe key and outcome
**And** the entry holds no secret values, note content or script secret settings

**Given** a Focus action (peek `⌥⌘↵` or an Agents row)
**When** it completes
**Then** the outcome is logged: exact tab, app-level fallback or failed, with the terminal adapter id (Stories 4.10, 4.11 and Epic 5 call the log API; soft forward reference like A16)

**Given** the log store in Application Support (never in the config folder, never synced)
**When** entries are written
**Then** writes happen off the main actor, are append-only and atomic per entry, and a crash loses at most the last entry
**And** (added 2026-11-07) entries are JSON Lines, one file per day under `Application Support/<app>/activity/`; modules add outcome entries only through `context.activity`, never by writing files themselves (AD-26)

**Given** entries older than 30 days
**When** Vigie launches, and once a day while running
**Then** they are deleted

**Given** Settings › General › Activity log (A80)
**When** opened
**Then** it shows a read-only list, newest first, filterable by module and kind, with a per-day summary (alerts by kind, peeks, Focus outcomes) and a Copy as text button
**And** nothing in the log is ever sent over the network

### Story 3.9: Peek concurrency and suppression

*Added 2026-11-07 (epics update run, step 3) for UX-DR92 / EXPERIENCE Peek concurrency; split from Story 3.2 to keep each story one dev-agent session.*

As a user who can get several alerts at once,
I want the most urgent alert to win the single peek, and alerts that no longer matter never to show late,
So that a peek is always about something that still needs me.

**Requirements:** PRD FR-9, FR12, FR14, UX-DR92, UX-DR104 (tab marker instead of a peek), AD-13 (only the host shows peeks; `AlertHandle.resolve()`), A52 · **Depends on:** Stories 2.10, 3.1, 3.2, 3.8

**Acceptance Criteria:**

**Given** a visible peek of lower urgency (anything but blocked or failed)
**When** a newer `session.blocked` or `session.failed` alert routed to peek arrives
**Then** it replaces the visible peek at once; the replaced alert keeps its closed-notch state and does not peek again except through its reminder (Story 3.2 rule)

**Given** several alerts waiting while a peek is visible
**When** the current dwell ends
**Then** the next one shown follows the urgency order blocked / failed > break due / Timer end / calendar reminder > quota warning > done > setup problem, in arrival order within a rank; the ranks of kinds added by later epics (Time, Calendar) come from one table in the Notifier, not from module code

**Given** a queued alert
**When** its handle is resolved before it shows (e.g. the blocked session moved on, usage dropped below the threshold)
**Then** it is dropped from the queue and never peeks; the activity log records it as resolved (Story 3.8)

**Given** the expanded view is open
**When** an alert routed to peek arrives
**Then** no peek shows; the module's tab carries the attention marker instead, and sound and macOS notification outputs follow the alert rules as usual

**Given** the rules above
**When** unit tests run against the peek queue
**Then** they cover preemption, rank order, ties, resolved-before-shown drops and suppression while expanded (the wait while the drop display is open is added by Story 9.1)

### Story 3.10: Detect Focus through a Vigie Focus Filter

*Added 2026-11-12 from `docs/decisions/spike-focus-detection.md` (Romain ruled "research another route" on 3.5; the spike found the shipped `Assertions.json` route unreadable without Full Disk Access and stale even with it).*

As a user who turns on Do Not Disturb or another Focus,
I want Vigie to go quiet for the Focus modes I choose, without granting Full Disk Access,
So that Story 3.5's suppression actually works in the shipped app.

**Requirements:** FR17, UX-DR62, UX-DR55, A21, AD-19, AD-20 (no new entitlement or permission), Story 3.5,
`docs/decisions/spike-focus-detection.md`

**Acceptance Criteria:**

**Given** the App target
**When** it is built
**Then** it declares one `SetFocusFilterIntent` ("Silence Vigie", parameter `silence: Bool`, default `false`,
suggested `true`, strings from the String Catalog) whose `perform()` only forwards `silence` to the core
`FocusFilterMonitor` and returns
**And** no entitlement, `Permission` case, usage string or extension target is added

**Given** a Focus with Vigie's filter set to silence
**When** that Focus turns on (manually, by schedule, smart activation or from another device)
**Then** `FocusFilterMonitor.isActive` becomes `true` and Story 3.5 suppression applies; when it turns off,
`isActive` becomes `false` and `[notify] after_focus` applies

**Given** Vigie launches while a filtered Focus is already on
**When** the monitor starts
**Then** it reads `SetFocusFilterIntent.current` and starts active; `notFound` or `silence == false` reads as off

**Given** the user has never added the filter
**When** they open Settings › Alerts or the Alerts tab
**Then** a "Focus" row shows a needs-setup state with "Open Focus settings" and a three-step how-to; nothing
is shown at launch and no modal appears; the state clears once `perform()` has run once (recorded in
`local.toml`)

**Given** a user who prefers Shortcuts
**When** `vigie event app.focus '{"active":true}'` (or `false`) arrives
**Then** the core feeds the same monitor; an "on" with no later message for 12 h is treated as off
**And** Settings › Alerts links to the two-automation recipe from the spike

**Given** the old route
**When** this story lands
**Then** `SystemFocusModeMonitor` no longer reads `~/Library/DoNotDisturb/DB/Assertions.json`; the App wires
`FocusFilterMonitor`; `FocusModeMonitor` and `ManualFocusModeMonitor` keep their API and tests

**Given** tests
**When** `swift test --build-system swiftbuild` runs
**Then** the monitor is covered with a fake filter source (on, off, launch-time `current` on / off / not
found, Shortcuts topic, 12 h cap) and the 3.5 Focus tests pass unchanged
**And** the spike's checklist items 1 to 3 are run by hand on the first build and their results recorded in
the spike file

## Epic 4: Track Claude Code sessions

Users who run Claude Code (or any tool via `vigie agent`) see every session's status in the closed notch and the Agents tab, get blocked / done / failed alerts, never lose events across restarts, and learn about sessions interrupted by sleep.

### Story 4.1: Event Server

As a user,
I want Vigie to receive agent events over a private local socket,
So that hooks reach the app instantly and no other user can inject events.

**Requirements:** FR78, NFR5, AD-6 (bind + queue), AD-7, AD-21 (socket unlink rules)

**Acceptance Criteria:**

**Given** launch with the instance lock held
**When** the Event Server starts
**Then** it unlinks a stale socket only while holding the lock, binds `AppEnvironment.socketPath` with permissions 0600, and queues incoming lines without dispatching until the Registry has started modules

**Given** a line `{ "v", "topic", "sent_at", "payload" }`
**When** it is received
**Then** versions `v` and `v-1` are accepted, unknown fields ignored, anything else dropped with a log entry
**And** the server publishes `EventMessage { topic, payload: Data, sentAt, receivedAt, replayed: false }` on `context.events` without interpreting the payload

**Given** a module subscribed to `agent.*`
**When** a matching message arrives
**Then** the module receives it; modules not subscribed don't

**Given** the app quits
**When** it cleans up
**Then** it unlinks the socket path only if its inode is still the one it bound

### Story 4.2: Durable spool and launch order

As a user,
I want hook events sent while Vigie is quitting, crashed or updating to be applied when it comes back,
So that statuses are never stale after a restart.

**Requirements:** AD-6, NFR3, NFR16, NFR25

**Acceptance Criteria:**

**Given** the socket is unavailable or the 150 ms budget is exceeded
**When** the CLI sends an event
**Then** it appends the same line to `spool.jsonl` opened `O_APPEND` under `flock(LOCK_EX)` in a single `write`, exits 0, and writes nothing to stdout/stderr
**And** payloads over 1 MiB are replaced by `{"truncated": true}` plus the adapter's identifying fields

**Given** launch
**When** the app starts
**Then** it follows: instance lock → bind + queue → start modules → replay leftover `spool.replaying.jsonl` → rename `spool.jsonl` to `spool.replaying.jsonl`, dispatch in file order with `replayed = true`, delete → dispatch queued socket lines → post `host.ready`

**Given** the app is running
**When** `spool.jsonl` appears (a CLI fell back)
**Then** the Event Server drains it the same way

**Given** concurrent CLI writers during a rename
**When** the test harness runs 1,000 events across restart cycles
**Then** no event is lost or duplicated (CI floor test)

### Story 4.3: CLI install on PATH, `vigie event` and `vigie reload`

As a user,
I want the `vigie` command always on my PATH and pointing at the installed app,
So that hooks never fail with "command not found" and I can script Vigie.

**Requirements:** FR8, AD-22 (CLIInstaller), AD-17 (cliName), FR99 (reload)

**Acceptance Criteria:**

**Given** every launch
**When** `CLIInstaller` runs
**Then** `~/.local/bin/<cliName>` is a symlink to the bundled CLI, repaired if the app moved; `~/.local/bin` is created if missing and Settings › General shows a hint if it is not on the login shell PATH

**Given** `vigie event <topic> [json]`
**When** run
**Then** it sends a v1 envelope with the topic and payload via the same socket/spool path and exits 0

**Given** `vigie reload`
**When** run
**Then** ConfigStore reloads config from disk and the result is logged

**Given** a second app instance launched (Story 2.1)
**When** it finds the lock held
**Then** it sends `app.expand` through the socket and the running instance opens its expanded view

### Story 4.4: Agent adapter contracts and assembly

As a user,
I want agent support to plug in through adapters without touching the sessions or usage modules,
So that new agents can be added safely by anyone.

**Requirements:** FR80, NFR23, AD-4, AD-19 (AdapterContext, executables), AD-23 (Sendable, settings paths), Conventions (External executables)

**Acceptance Criteria:**

**Given** `AgentKit`
**When** the contracts are declared
**Then** `AgentAdapter` (id, name, capabilities, settings, `detectVersion`, `integrationPlan`/`removalPlan` → `ConfigDiff`, `normalize`, `agentProcess(in:)`, optional transcript watcher, `logReader`, `usageProvider`, `launchCommand(files:cwd:)`), `TerminalAdapter`, `UsageProvider`, `AgentEvent` (the SPEC §7.1 normalized events) and `AdapterContext` (`settings` read-only, `secrets`, `executables`, `http`, `log`) exist, all `Sendable`

**Given** VigieCore
**When** `ExecutableResolver` is implemented
**Then** it captures the login-shell `PATH` once per launch with a 2 s timeout, supports per-runtime overrides in `local.toml`, and is exposed as `context.executables` / `AdapterContext.executables`; no code calls `Process` with a bare executable name

**Given** the App target
**When** it assembles
**Then** it builds the adapter list and each adapter's `AdapterContext`, and passes the same instances to `agents.sessions` (and later `agents.usage`) through initializers

**Given** `Packages/Modules/AgentsSessions` is created
**When** it is compiled
**Then** it depends only on ModuleKit, VigieUI, AgentKit and Wire

### Story 4.5: SessionStore status engine

As a user,
I want each session's status computed by one consistent set of rules,
So that what the notch shows is always right, even with late or replayed events.

**Requirements:** FR31, FR32, FR33, FR34, FR38, AD-5, NFR25, UX-DR56, UX-DR73 (done → idle delay)

**Acceptance Criteria:**

**Given** normalized events for session `<adapter id>:<native id>`
**When** SessionStore applies them
**Then** transitions follow SPEC §7.1: `session.start` → idle; `prompt.submit`, `tool.*`, `subagent.end` → working (also from done); `turn.end` → done; `needs.input` → blocked; `session.error` → failed; `session.end` → gone (removed)
**And** SessionStore is the only code that writes a session status

**Given** a session in done
**When** `done_to_idle` (default 15 min, from `sent_at`) elapses with no new prompt
**Then** it becomes idle; focusing or dismissing never changes state

**Given** an event whose `sent_at` is earlier than the last applied event for that session
**When** it arrives
**Then** it may update metadata (last action) but does not change status

**Given** blocked or failed sessions
**When** displayed
**Then** `T+` counts from `sent_at` of the entering event; sessions sort blocked/failed (most recent first) > done > working > idle
**And** module state is alert / active / ambient per FR38

**Given** a status or membership change
**When** it occurs
**Then** `sessions.json` is persisted atomically off the main actor (not on heartbeats) and reloaded at launch
**And** unit tests cover every transition, out-of-order events, replay and persistence

### Story 4.6: Claude Code adapter with version gating

As a Claude Code user,
I want Vigie to understand Claude Code's hooks precisely and refuse to guess on versions it doesn't know,
So that "blocked" means a real permission prompt, never an idle reminder.

**Requirements:** FR82 (normalize), FR85, FR35 (full coverage), FR31, NFR18, AD-23 (versions, fixtures), SPEC §14.4, §14.5, A45

**Acceptance Criteria:**

**Given** the installed Claude Code version
**When** the fixtures are recorded
**Then** `Packages/Adapters/Claude/Tests/Fixtures/<cli-version>/` contains real payloads for all 8 hook events, including each `Notification` subtype, and a note confirming which subtype means a permission prompt vs an idle prompt (SPEC §14.4)

**Given** the adapter's `normalize`
**When** fixture events are replayed
**Then** `SessionStart`→`session.start`, `UserPromptSubmit`→`prompt.submit`, `PreToolUse`/`PostToolUse`→`tool.start`/`tool.end`, `Notification` (permission subtype only)→`needs.input`, `Stop`→`turn.end`, `SubagentStop`→`subagent.end`, `SessionEnd`→`session.end`, and error notifications (if any) → `session.error`; idle reminders produce no status change

**Given** the adapter starts
**When** it detects the Claude Code version through `AdapterContext.executables`
**Then** outside the fixture-tested range it emits no normalized events and reports `unsupported(version)`, which `agents.sessions` raises as a setup-problem alert (`Claude adapter: CLI version X unsupported`) with Open settings › Agents › Claude

**Given** the ancestor chain in the hook payload
**When** `agentProcess(in:)` runs
**Then** it returns the Claude Code process (pid + start time), not the hook's short-lived shell

### Story 4.7: Hook installer with diff confirmation

As a Claude Code user,
I want Vigie to install its hooks after showing me exactly what changes,
So that my own hooks and settings are never clobbered.

**Requirements:** FR82 (installer), FR80 (plans), FR41 (enabled adapters), AD-22, NFR16, NFR28

**Acceptance Criteria:**

**Given** Settings › Agents › Claude › Connect
**When** the user clicks it
**Then** the adapter returns a `ConfigDiff` adding one entry per hook event with command `<absolute ~/.local/bin symlink> hook claude`, and `IntegrationInstaller` shows the diff for confirmation

**Given** the user confirms
**When** the installer applies it
**Then** it re-reads `~/.claude/settings.json`, checks the hash matches the diff's base (else recomputes and shows the new diff), writes a timestamped backup next to it, writes atomically, and records the result in `local.toml`

**Given** existing user hooks or the other build's (`vigie-dev`) hooks
**When** installing or removing
**Then** only entries whose command equals exactly `<symlink path> hook claude` are added or removed; nothing else is reordered, replaced or removed

**Given** Disconnect
**When** confirmed
**Then** the removal diff removes only Vigie's managed entries and the adapter is removed from `[modules."agents.sessions"] adapters`

### Story 4.8: Liveness, stale sessions and ignored paths

As a user,
I want sessions whose process died to disappear, stuck ones flagged, and ignored projects never tracked,
So that the notch only shows sessions that exist and matter.

**Requirements:** FR36, FR42, AD-5 (liveness, failed retention), UX-DR56 (stale ?), UX-DR81, A35 (superseded by Story 1.7b), A44 · **Depends on:** Story 1.7b (stale look design, done 2026-11-07)

**Acceptance Criteria:**

**Given** a session with agent pid + start time
**When** the 10 s liveness check runs
**Then** a session whose process no longer exists (or whose pid now has a different start time) is removed, except failed sessions

**Given** a failed session whose process ended
**When** 24 h pass after entering failed, or the user dismisses it in the Agents tab
**Then** it is removed

**Given** a working session with no event for longer than `stale_after` (default 10 min)
**When** displayed
**Then** it carries the stale look designed in Story 1.7b: a dashed ring with a `?` inside in `ink-3` (no hue, no motion) in place of its glyph; its row label reads `STALE · <time since last event>` (e.g. `STALE · 18M`) with `LAST EVENT 14:30 · <action>` on the last-action line; it sorts after idle and raises no alert, until an event returns it to its real state
**And** (added 2026-11-07) the stale glyph is static in every Presence mode and the row has no tint; Focus still works on a stale row; its accessibility label reads "<project>, stale, no event for 18 minutes" (UX-DR81)

**Given** `ignored_paths` contains `~/scratch`
**When** a session starts with `cwd` under `~/scratch`
**Then** SessionStore ignores all its events (no glyph, no alert) (A44)

**Given** `host.ready`
**When** the launch sequence completes
**Then** SessionStore runs one liveness reconcile over persisted sessions

### Story 4.9: Session glyphs in the closed notch

As a user,
I want one shape-coded glyph per session on the right wing, most urgent nearest the notch,
So that I can tell at a glance which session needs me.

**Requirements:** FR37, FR38, NFR9, UX-DR17, UX-DR18, UX-DR19, UX-DR56, UX-DR57, UX-DR63, UX-DR77, A19

**Acceptance Criteria:**

**Given** sessions in several states
**When** `agents.sessions` wins the trailing side
**Then** it shows up to `closed.slots` 16 px glyphs (A shapes: hollow ring, spinning ¼ arc, ring + check, rippling diamond, stuttering ×) in urgency order, first slot nearest the notch, then `+X` in `ink-3` for the rest
**And** no count, project name or alert label appears (mockup `key-closed-notch-states.html` h)

**Given** blocked/failed sessions
**When** slots are filled
**Then** a blocked or failed session is never hidden in `+X` while a less urgent session is visible; if blocked/failed outnumber slots, the most recent ones fill all slots and `+X` counts the rest (A19)

**Given** no adapter is connected
**When** the wing renders
**Then** it shows `NO AGENT CONNECTED` as a readout label; with adapters but no sessions it shows `NO ACTIVE SESSIONS`

**Given** VoiceOver
**When** focus lands on a glyph
**Then** it reads "<project>, <status>, <time>" (UX-DR63); color is never the only cue (shape + label)

### Story 4.10: Agents tab

As a user running many sessions,
I want a dense list of all sessions sorted by urgency with one action, Focus,
So that I can find and jump to any session quickly.

**Requirements:** FR39, FR44 (fallback activation), FR92 (Agents empty states), UX-DR30, UX-DR40, UX-DR44, UX-DR55, UX-DR57, UX-DR66, UX-DR94, NFR26, A16, A55

**Acceptance Criteria:**

**Given** the Agents tab (mockup `key-agents-tab.html`)
**When** it renders
**Then** one full-width card lists rows (glyph, agent, project from `cwd` + last action in mono `ink-3`, terminal, `STATUS · T+`, Focus chip) sorted by urgency, with header `SESSIONS · N · M ALERTS`, keyboard hints, `SORTED BY URGENCY` and column headers
**And** the terminal column appears only when sessions span more than one terminal app

**Given** blocked/failed rows
**When** rendered
**Then** they carry the alert tint (A 10% fade + 1px inner outline); hover brightens and shows `FOCUS`; keyboard selection adds the ring and `↵`
**And** (added 2026-11-07) in dark looks the secondary (last-action) line of a tinted row uses `ink-2`, so it keeps 4.5:1 on the tint (UX-DR94)

**Given** a row
**When** the user clicks it or presses ↵ on the selection
**Then** the Focus action is invoked through the session's terminal adapter; in this epic a generic fallback adapter activates the terminal app by `TERM_PROGRAM` without selecting a tab (A16)
**And** no other action (approve, deny, send) exists anywhere

**Given** no agent connected / no sessions
**When** the tab renders
**Then** it shows `NO AGENT CONNECTED` + "Connect Claude Code, Codex or Gemini in Settings." with a button to Settings › Agents, or `NO ACTIVE SESSIONS` + "Agent sessions appear here when they start."

**Given** a failed session whose process ended
**When** the row is selected
**Then** a `DISMISS` chip removes it (FR36 retention)

### Story 4.11: Session alerts

As a user,
I want a peek once when a session becomes blocked, finishes, or fails, with a Focus action,
So that I never miss a session waiting for me.

**Requirements:** FR12, FR13, FR15, FR33, UX-DR21, UX-DR43, UX-DR67, AD-5 (replay suppression), AD-13 (kinds, resolve), A54

**Acceptance Criteria:**

**Given** a session enters blocked, done or failed
**When** SessionStore applies the transition
**Then** `agents.sessions` posts `session.blocked` / `session.done` / `session.failed` with dedupe key = session id, and resolves the handle when the session leaves that state

**Given** a blocked peek (mockup `key-alert-variants.html`)
**When** shown
**Then** it has the rippling diamond beacon, kicker `BLOCKED · NEEDS INPUT` with live `T+`, title `project / branch-or-path`, detail `Claude Code wants to run Bash · <command>` with the command in a code chip, actions `FOCUS TERMINAL ⌥⌘↵` / `DISMISS ⌥⌘⌫`
**And** done shows `DONE` (no T+) with detail like `Turn ended · 3 files`; failed shows the stuttering × and `FAILED · <REASON>`

**Given** a replayed transition with `sent_at` older than 5 minutes
**When** applied
**Then** state updates but no Notifier event is posted

**Given** `session.done` with `min_working_time = "30s"`
**When** the working period before `turn.end` was shorter
**Then** Notifier suppresses the done alert using the event's `working_duration` metric (A54)

**Given** Focus terminal
**When** triggered
**Then** it calls the session's terminal adapter focus (fallback in this epic) and never changes session state

### Story 4.12: Sleep handling

As a user who closes the lid while agents work,
I want interrupted sessions marked failed with an alert when I come back, and optionally to keep the Mac awake while they work,
So that a run killed by sleep never goes unnoticed.

**Requirements:** FR45, FR46, FR33, UX-DR68, UX-DR57, AD-5 (sleep/wake), AD-19 (power), SPEC §14.15, PRD FR-18, PRD FR-19, A20, A24

**Acceptance Criteria:**

**Given** `context.power` in VigieCore
**When** implemented
**Then** it offers `preventIdleSleep(reason:) -> Token` (via `ProcessInfo.beginActivity(.idleSystemSleepDisabled)` or IOKit) and `sleepWake: AsyncStream<SleepWakeEvent>`, honouring `[general] prevent_idle_sleep`

**Given** `prevent_idle_sleep = true` and at least one working session
**When** sessions change
**Then** `agents.sessions` holds one token while any session is working and releases it otherwise; with the setting off (default) no token is taken

**Given** the Keep-awake setting in Settings › Agents
**When** shown
**Then** its description states that it prevents idle sleep only, and that closing the lid or putting the Mac to sleep by hand is not covered (PRD FR-19; added 2026-11-06)

**Given** sessions working when the Mac slept
**When** the wake event arrives
**Then** SessionStore first marks each `failed (host_slept)` with `T+` from wake and last action as the interrupted action, and only then resumes liveness
**And** one alert is posted for the wake (A20, ruled 2026-11-06): with one interrupted session it is the usual `session.failed` (`FAILED · HOST SLEPT`, `Run interrupted during <action>`, Focus); with several it is a single summary `session.failed` alert (`FAILED · HOST SLEPT`, `<n> sessions interrupted by sleep`) whose primary action is Open Agents (`⌥⌘↵`), and each session is still marked failed in the Agents tab

**Given** the detection method
**When** the story is done
**Then** `docs/decisions/host-slept-detection.md` records the chosen technique (wake notification + working-at-sleep state, A24) and its known false positives (e.g. a process that survived sleep is still marked failed)

### Story 4.13: Generic `vigie agent` reporting

As a user of an agent Vigie doesn't support yet,
I want to report sessions from any wrapper script,
So that every tool I use shows up in the notch.

**Requirements:** FR86, AD-5 (generic mapping, identity)

**Acceptance Criteria:**

**Given** `vigie agent --agent mytool --session ID --status working --cwd "$PWD"`
**When** run
**Then** the CLI sends topic `agent.generic` with the raw flags, ancestor chain and TTY, and exits 0 with no output

**Given** `agents.sessions` receives `agent.generic`
**When** it maps statuses
**Then** `working → prompt.submit`, `blocked → needs.input` (with `--message` as detail), `done → turn.end`, `failed → session.error`, `idle → session.start` (re-entry allowed), `--end → session.end`; identity is `generic.mytool:ID`

**Given** `--agent claude` (a registered adapter id)
**When** run
**Then** the CLI drops the event, logs a line, and exits 0

**Given** a generic session
**When** its agent PID is chosen
**Then** it is the first ancestor that is not a shell, so liveness and terminal focus work

### Story 4.14: Research — warning before manual sleep

As Romain,
I want to know whether macOS lets Vigie warn before a lid close or manual sleep while agents work,
So that a later version can prevent the interruption instead of only reporting it.

**Requirements:** SPEC §14.14, Architecture Deferred (pre-sleep warning), A25

**Acceptance Criteria:**

**Given** macOS 15 and later APIs (`NSWorkspace.willSleepNotification`, IOKit power assertions, `IORegisterForSystemPower` sleep vetoes)
**When** the research is done
**Then** `docs/decisions/pre-sleep-warning.md` states what can be intercepted or delayed (idle vs user-initiated vs lid close), for how long, and with what permissions

**Given** the findings
**When** they show a feasible approach
**Then** a follow-up story is proposed for the backlog; no user-facing feature ships in this story

## Epic 5: Jump to the exact terminal tab

Users press `⌥⌘↵` on a peek or `↵` on a session row and the session's exact terminal tab comes to the front in Terminal.app, iTerm2, Warp or Ghostty — or the terminal app activates when the tab can't be located.

### Story 5.1: Focus permissions and terminal selection

As a user,
I want Vigie to pick the right terminal for each session and tell me if a permission is missing,
So that Focus works for every session even when I use several terminals.

**Requirements:** FR43, FR44, FR2, UX-DR62 (focus fails), UX-DR69 (Accessibility skipped path), AD-23 (matches, capture purity), AD-20 (accessibility, automation)

**Acceptance Criteria:**

**Given** `session.start` with captured env, pid and tty
**When** `agents.sessions` stores the session
**Then** the terminal adapter is chosen by `matches(env:)` across registered terminal adapters (falling back to the `terminal` local setting) and `capture(env:pid:tty:)` stores a `TerminalLocator` without Apple Events, AX or I/O beyond the process table

**Given** Focus requires Accessibility or Automation for the chosen terminal
**When** the permission is missing
**Then** Focus activates the terminal app without selecting a tab and a setup-problem alert (`SETUP · PERMISSION`) explains which permission and opens the right pane / System Settings
**And** no error toast is shown

**Given** a focus attempt fails for any other reason
**When** it fails
**Then** the terminal app is activated without selecting a tab

**Given** Apple Events and AX calls
**When** reviewing the code
**Then** they occur only inside `focus`/`openTab`, which are invoked only from a user action carrying a `UserIntent`

### Story 5.2: Terminal.app focus

As a Terminal.app user,
I want Focus to select the exact tab running my session,
So that I land on the right prompt instantly.

**Requirements:** FR43, AD-1, AD-23

**Acceptance Criteria:**

**Given** `Packages/Terminals/TerminalApp`
**When** a session starts in Terminal.app (`TERM_PROGRAM = Apple_Terminal`)
**Then** `matches` returns true and the locator stores the session's tty

**Given** Focus
**When** invoked
**Then** an AppleScript selects the window and tab whose tty matches and brings Terminal.app to the front
**And** a manual test with three windows × two tabs focuses each correctly

### Story 5.3: iTerm2 focus

As an iTerm2 user,
I want Focus to select the exact iTerm2 session,
So that the peek's `⌥⌘↵` takes me straight to it.

**Requirements:** FR43, UX-DR69 (exact iTerm2 tab)

**Acceptance Criteria:**

**Given** `Packages/Terminals/ITerm`
**When** a session starts with `ITERM_SESSION_ID` in its env
**Then** `matches` returns true and the locator stores the session id

**Given** Focus
**When** invoked
**Then** iTerm2's AppleScript (or Python API if required) selects the window, tab and split pane with that id and activates iTerm2
**And** with the session gone, the app is activated (fallback)

### Story 5.4: Warp focus per spike decision

As a Warp user,
I want Focus to bring my exact Warp tab forward if technically possible, and otherwise at least Warp itself,
So that my main terminal is supported as well as it can be.

**Requirements:** FR43, FR44, UX-DR67 (Flow 1 complete), PRD FR-24 (Warp fallback rule), PRD SM-6, A17, A64

**Acceptance Criteria:**

**Given** `docs/decisions/spike-warp-focus.md` (Story 1.5)
**When** it concluded exact-tab focus works
**Then** `Packages/Terminals/Warp` implements that technique: `capture` stores the locator fields named in the record, and Focus selects the right tab in a manual test with 4 Claude sessions in 4 Warp tabs

**Given** the record concluded app-level only
**When** the adapter is built
**Then** Focus activates Warp, and Settings › Agents states "Warp: app-level focus only" (SPEC §14.1)
**And** v0.1 ships with app-level Focus for Warp rather than waiting, and SM-6 (exact-tab Focus ≥ 95 %) is measured on iTerm2 and Ghostty instead of Warp (PRD FR-24 Warp fallback rule, memlog; added 2026-11-06)

**Given** Flow 1 (UX-DR67) is replayed manually with Claude sessions in Warp
**When** a session turns blocked while the editor has focus
**Then** the peek appears once, the editor keeps every keystroke, `⌥⌘↵` focuses the session (tab or app per decision), and the Agents tab shows no terminal column

### Story 5.5: Ghostty focus per spike decision

As a Ghostty user,
I want Focus to work as well as Ghostty allows,
So that Ghostty is a first-class terminal in v1.

**Requirements:** FR43, FR44, A17, A64

**Acceptance Criteria:**

**Given** `docs/decisions/spike-ghostty-focus.md` (Story 1.6)
**When** `Packages/Terminals/Ghostty` is built
**Then** `matches` recognises Ghostty sessions and Focus uses the recorded technique (exact tab, window or app level)

**Given** the achieved level is below exact-tab
**When** Settings › Agents lists terminals
**Then** it states Ghostty's focus level

## Epic 6: Signed releases that update themselves

Users install a signed, notarized Vigie from the public release host, and Sparkle offers every later version and installs it once they agree, from a reproducible tag-driven pipeline (SPEC §12, required by the v0.1 roadmap row). **[Changed by PRD §9 Q1, FR-61, addendum §4]:** the code repository is private, so DMGs, checksums and the Sparkle appcasts publish to a separate public host (A86); updates install only after the user agrees.

### Story 6.1: Signing and runtime envelope

As a user,
I want Vigie signed with Developer ID, hardened and notarized with only the entitlements it needs,
So that Gatekeeper trusts it and every feature that works in debug works in the release build.

**Requirements:** NFR11, AD-20, AD-9 (entitlement), AD-17 (dev signing), SPEC §14.9, A49

**Acceptance Criteria:**

**Given** the App target
**When** built for release
**Then** it is unsandboxed with Hardened Runtime, embeds the Developer ID provisioning profile (explicit App ID, Keychain Sharing), and carries only `com.apple.security.automation.apple-events` and `keychain-access-groups` (+ required identifiers)
**And** the bundled CLI is signed with Hardened Runtime and no entitlements

**Given** Info.plist
**When** inspected
**Then** it has `LSUIElement = YES`, `NSAppleEventsUsageDescription` and `NSCalendarsFullAccessUsageDescription` from the InfoPlist String Catalog

**Given** dev builds
**When** signed
**Then** they use a stable Apple Development identity and the `.dev` provisioning profile, never ad-hoc

**Given** the maintainer prerequisites
**When** the story is done
**Then** `docs/release-setup.md` lists the manual steps Romain owns: organization Developer ID certificate, App Store Connect API key with the minimum notarization role, provisioning profiles for both bundle ids, Sparkle EdDSA keys, the `release` GitHub environment with required approval, GitHub org name (A49)

### Story 6.2: Tag-driven release workflow

As Romain,
I want pushing a `vX.Y.Z` tag on master to produce a signed, notarized public release automatically,
So that every release is reproducible and nothing is signed on my machine.

**Requirements:** FR105, NFR12, NFR11, PRD FR-61, PRD §9 Q1 (private code, public releases), addendum §4, AD-20 (amended 2026-11-06: public release hosting), A86

**Acceptance Criteria:**

**Given** a pushed tag matching `v*.*.*`
**When** `release.yml` starts
**Then** it checks `git merge-base --is-ancestor $TAG origin/master` and that the tag equals the project version, stopping on mismatch

**Given** checks pass and the `release` environment approval is granted
**When** the job runs
**Then** it imports the certificate into a temporary keychain, installs the provisioning profiles, archives and exports (Developer ID), notarizes with `notarytool --wait`, staples, builds `Vigie-X.Y.Z.dmg` (notarized + stapled) and `Vigie-X.Y.Z.zip`, and publishes DMG, zip and SHA-256 checksums as a release on the public release host (A86), not in the private code repository

**Given** a suffixed tag (`v1.2.0-beta.1`)
**When** released
**Then** the public release is marked pre-release and is not listed in `appcast.xml` (the beta feed arrives with Story 19.3; A63, ruled 2026-11-06)

**Given** a workflow triggered by a fork or pull request
**When** it runs
**Then** it cannot access `release` secrets

**Given** the public release host
**When** a visitor without access to the code repository opens it
**Then** releases, checksums and appcasts are downloadable, and no source code is published (added 2026-11-06)

### Story 6.3: Sparkle auto-update

As a user,
I want Vigie to check for updates and install them only when I agree,
So that I run the latest version without anything installing behind my back.

**Requirements:** FR106, NFR13, NFR7, AD-16, PRD FR-61, PRD FR-4 (update check can be turned off), A63, A86

**Acceptance Criteria:**

**Given** `release.yml`
**When** a release is built
**Then** the zip is signed with Sparkle's EdDSA key (`sign_update`), `appcast.xml` is generated with release notes from the tag message or `CHANGELOG.md` and published on the public release host (stable only; A63, ruled 2026-11-06: no beta channel before the public release)

**Given** the app with Sparkle 2.10.x and the public EdDSA key in Info.plist
**When** `[updates] auto_check = true`, `check_interval = "24h"`, `auto_install = false`
**Then** it checks the appcast on the public release host (A86) every 24 h and asks before installing
**And** automatic install happens only if the user turns `auto_install` on (PRD FR-61), and `auto_check = false` stops all update network calls (PRD FR-4)

**Given** an update package with a bad EdDSA signature or invalid notarization
**When** Sparkle downloads it
**Then** it is rejected

**Given** Sparkle relaunches the app after an update
**When** the old instance exits
**Then** the single-instance and socket rules (AD-21) let the new instance take over without losing events (spool)

### Story 6.4: Versioning and build numbers

As Romain,
I want versions and build numbers set automatically and consistently,
So that Sparkle always recognises newer builds.

**Requirements:** FR107

**Acceptance Criteria:**

**Given** a release build
**When** it is produced
**Then** `CFBundleShortVersionString` is `X.Y.Z` from the tag and `CFBundleVersion` is the CI run number (always increasing)

**Given** the script module schema and the wire/adapter event format
**When** they change incompatibly
**Then** their own version numbers (`schema`, `v`) are bumped and a note in `docs/` says breaking changes need a major app version (no CONTRIBUTING file: the app takes no outside contributions, PRD §9 Q1)

### Story 6.5: Remote price table for every provider

*Added 2026-11-08 (Romain's ruling): the bundled `prices.json` (A56) goes stale between releases and cannot price a new model family. Placed in Epic 6 because it rides the release pipeline and the Sparkle signing key.*

As a user,
I want cost estimates to use current list prices for every provider without waiting for an app update,
So that the Usage tab stays right when a provider releases or reprices a model.

**Requirements:** PRD FR-48 (cost), A56 (superseded by this story), AD-16 (amended 2026-11-08: price-table fetch allowed), AD-23 (prices keyed by adapter id), AD-8 (`[updates] prices`), NFR24

**Acceptance Criteria:**

**Given** the price table schema
**When** it is defined
**Then** one JSON document holds a `providers` map keyed by adapter id (`claude`, `codex`, `gemini` today; any future adapter adds a key, nothing else changes), each with its `currency`, `unit`, `updated` date and a `models` map of ids to `input`, `output`, `cache_write`, `cache_read` and optional tiers (e.g. long-context thresholds); `AgentAdapter` exposes `priceProviderID` so an adapter maps its models to one provider section; the schema is versioned and the bundled file in `AgentsUsage` follows it

**Given** the release workflow (Story 6.2)
**When** a release is tagged, or the `prices/` folder of the private repository changes on `master`
**Then** CI publishes `prices.json` and a detached EdDSA signature made with the Sparkle private key to a fixed public HTTPS location (the public releases repository or its Pages site), and the app knows only that location

**Given** `[updates] prices = true` (default) and `check_interval`
**When** the interval elapses, or the user presses `Check now` in Settings › Usage
**Then** the app fetches the table and its signature, verifies the signature with the embedded Sparkle public key, rejects a lower `version` or a bad signature (logged as a setup problem once), and otherwise stores it in `context.storage` of `agents.usage`; no other data is sent, no cookies or identifiers beyond the HTTPS request

**Given** a stored table
**When** `CostEstimator` is built
**Then** it uses the stored table when its `version` is newer than the bundled one, else the bundled one; the Usage tab footer reads `PRICES <date>` with `BUNDLED` or `UPDATED`; a provider section missing from the stored table falls back to the bundled section

**Given** `[updates] prices = false`, or the Mac offline
**When** Vigie runs
**Then** no request is made and the newest table already on disk is used

**Given** a model id with no price in any table
**When** cost is summed
**Then** it stays unpriced as today (no invented number)

**Given** unit tests
**When** run with a fake HTTP client and a test key pair
**Then** they cover: valid update applied, bad signature rejected, downgrade rejected, offline fallback, per-provider fallback, `prices = false` makes no request, adapters mapped to provider sections, schema round-trip of the bundled file

## Epic 7: AI usage at a glance

Users see one quota ring per provider in the left wing, a pace marker, a quota warning at their threshold, and a Usage tab with per-window bars, 7-day history and today's cost, starting with Claude Code.

### Story 7.1: Usage history from Claude Code local logs

As a Claude Code user,
I want Vigie to read my local Claude logs into a usage history,
So that I see tokens and estimated cost offline without signing in.

**Requirements:** FR47, FR48, AD-11 (GRDB, ingest), AD-23 (logReader, usage identity), NFR24, NFR25, A56

**Acceptance Criteria:**

**Given** `Packages/Modules/AgentsUsage` is created
**When** it starts
**Then** it owns the only SQLite database (GRDB 7.12.x) in its `context.storage` folder and receives the same adapter instances as `agents.sessions` from App assembly

**Given** the Claude adapter's `logReader`
**When** `~/.claude/projects/**/*.jsonl` files exist
**Then** ingest is incremental (per-file offset + size/mtime), off the main actor, and records tokens by model, project and time; re-running ingest on unchanged files adds nothing

**Given** token records
**When** cost is estimated
**Then** a bundled per-model price table is used (A56), versioned with the app; no network call is made

**Given** the usage provider
**When** queried
**Then** it returns the shared shape (token counts and estimated cost over time, optional windows) with `id = "claude"`; usage is enabled per adapter via `[modules."agents.sessions".adapters.claude] usage_providers`
**And** CI includes an ingest test over fixture logs (NFR25)

### Story 7.2: SecretStore

As a user,
I want every token I give Vigie stored only in the Keychain,
So that no secret ever lands in a config file, log or synced folder.

**Requirements:** NFR6, AD-9, AD-19 (secrets), FR5 (secret setting type), A49

**Acceptance Criteria:**

**Given** VigieCore `SecretStore`
**When** a module (`context.secrets`) or adapter (`AdapterContext.secrets`) stores a secret
**Then** it is a data-protection-keychain item (`kSecUseDataProtectionKeychain = true`) in access group `<TeamID>.<bundle id>`, non-synchronizable, scoped by owner id

**Given** a `secret` setting in the generated Settings UI
**When** the user enters a value
**Then** it is saved via SecretStore and never written to `config.toml`, `local.toml`, logs or JSON state (a test scans written files for the value)

**Given** the `vigie` CLI
**When** reviewing its code
**Then** it has no Keychain access

**Given** a signed dev build
**When** SecretStore is used
**Then** it succeeds (no `errSecMissingEntitlement`)

### Story 7.3: Claude plan-limit usage (opt-in)

As a Claude subscriber,
I want my 5-hour and weekly plan usage and reset times,
So that I can pace my work against my real limits.

**Requirements:** PRD FR-30 (stale indicator), FR47 (plan limits), FR49, NFR27, NFR7, UX-DR99 (`STALE · HH:MM`), AD-9 (amended 2026-11-06: consented read of another app's credential), AD-16 (`AdapterContext.http` only), AD-23 (one provider merging sources), SPEC §14.2, A57

**Acceptance Criteria:**

**Given** `usage_providers` does not include `plan`
**When** Vigie runs
**Then** no network request is made for Claude usage

**Given** the user enables `plan` in Settings › Agents › Claude (A57, ruled 2026-11-06)
**When** Settings asks how Vigie should sign in
**Then** it offers two choices, per Account and per Mac (`plan_auth = "token" | "claude_code"`, local):
**And** "Paste a token": the user pastes a credential, stored through SecretStore as a local, non-synchronizable Keychain item
**And** "Use Claude Code's login": Settings explains that Vigie will read the login Claude Code already stored on this Mac, only to fetch plan usage, and nothing happens until the user clicks `Allow`; macOS may then show its own Keychain access prompt, which the user answers
**And** with Claude Code's login, Vigie reads the credential once per launch and holds it in process memory (re-read only on expiry or rejection; amended 2026-11-12, Keychain prompt loop fix), never copies it into its own Keychain items, files, logs or diagnostics, never writes or refreshes it, and never syncs the consent; `Stop using Claude Code's login` revokes the consent immediately
**And** (added 2026-11-07) the consent text names the external Keychain item from the descriptor the Claude adapter declares (AD-9 amended)

**Given** either sign-in choice is set up
**When** the provider refreshes (every 5 minutes and on expanded-view open)
**Then** it fetches windows (5h, weekly, or whichever the plan has) with % used and reset time through `AdapterContext.http`, and merges them into the single `claude` provider with the local data

**Given** the unofficial endpoint fails or changes format
**When** a refresh fails
**Then** ~~the last good windows are shown with their age~~ **Amended 2026-11-07 (epics update run):** the Usage card keeps the last good values with `STALE · HH:MM` (time of the last good fetch) and the closed-notch ring keeps its value, never a wrong number (PRD FR-30), a setup-problem alert is raised once (`Claude plan usage unavailable`), and local data keeps working
**And** with Claude Code's login, an expired or missing credential raises the same setup-problem alert with "Sign in to Claude Code again, or paste a token", and Vigie never tries to renew it

**Given** the endpoint code
**When** reviewed
**Then** it lives entirely in the Claude adapter package so a breaking change is patched in one place

### Story 7.4: Quota rings in the closed notch

As a user,
I want one ring per provider on the left wing showing how much of my quota is used,
So that I know my headroom without opening anything.

**Requirements:** FR50, FR53, UX-DR16, UX-DR17, UX-DR12 (dark values on island), UX-DR73 (rings setting), UX-DR58 (window absent), A18, A69

**Acceptance Criteria:**

**Given** providers with plan windows
**When** the leading side is arbitrated
**Then** each provider offers one ring item to the left-wing lane with `[modules."agents.usage"] priority` (default 2, per-provider override in `providers.<id>`), ordered among themselves by `order` (default adapter registration order, A69); rings that don't fit beside higher-priority items collapse into the left `+X` (Story 2.8, ruled 2026-11-07); each shown ring is a 24 px dial with the provider name under each ring in readout-label style (23 px in the multi-provider layout)

**Given** exactly one provider and no other left-wing item shown
**When** rendered
**Then** it shows the dial plus a readout (`38 %` / `CLAUDE · WEEK`)

**Given** `rings = "5h+weekly"` and both windows
**When** rendered
**Then** rings are nested (inner 5h thicker in primary fill, outer weekly thinner in silver) and the value inside is the 5h value; with `rings = "5h"` only the 5h ring shows; a plan without 5h shows its only window at single-ring size, no empty ring

**Given** a provider with local data only (no windows)
**When** the left wing renders
**Then** it draws no ring for it (A18); with no provider at all the left wing is empty (black)

**Given** VoiceOver
**When** focus lands on a ring
**Then** it reads e.g. "Claude, 5 hour window 38 percent, weekly 52 percent"

### Story 7.5: Pace indicator

As a user,
I want to see whether my usage is ahead of the time elapsed in the window,
So that I can slow down before I hit the limit.

**Requirements:** FR52, UX-DR12, UX-DR16 (pace marker), UX-DR58 (pace ahead), UX-DR73 (pace, tolerance)

**Acceptance Criteria:**

**Given** `pace = true`
**When** a ring renders
**Then** a radial tick with a 1 px black keyline marks the elapsed-time position of the paced window (5h, or weekly when there is no 5h)

**Given** used ≤ elapsed + `pace_tolerance` (default 5 points)
**When** rendered
**Then** the arc uses `pace-on` (A: iris gradient on the closed ring) and ends before the tick

**Given** used > elapsed + tolerance
**When** rendered
**Then** the arc uses `pace-ahead` (A Ember) and runs past the tick; no alert, no sound, no state change

**Given** `pace = false`
**When** rendered
**Then** no tick is drawn and fills use `pace-on`

### Story 7.6: Quota warning

As a user,
I want a clear warning when a provider crosses my threshold, as an alert or just visually,
So that I'm never surprised by a limit.

**Requirements:** FR51, FR53, FR15 (quota alert vs visual), UX-DR12, UX-DR16 (warning on ring), UX-DR58, UX-DR78, UX-DR91 (quota peek), UX-DR93, AD-13 (`usage.quota_warning`), A36

**Acceptance Criteria:**

**Given** `warn_threshold = 80` (default; per-provider override `[modules."agents.usage".providers.<id>]`)
**When** any window's % used ≥ threshold
**Then** the ring arc uses `quota-warning` and a triangle replaces the value at the ring centre (A36); this wins over pace-ahead on that window

**Given** `warn_action = "alert"`
**When** the threshold is crossed
**Then** module state becomes `alert` and `usage.quota_warning` is posted once (dedupe per provider + window + reset time), ~~peek kicker `WARN · ≥ 80%`, title with provider and window~~ **Amended 2026-11-07 (epics update run):** the peek has a triangle beacon in `quota-warning`, kicker `QUOTA · WARN` (text in `quota-warning-text` on light bodies), title `<PROVIDER> · <WINDOW> <n> %` (e.g. `CLAUDE · 5H 82 %`), detail `RESET 16:40 · IN 1H52`, actions `OPEN USAGE ⌥⌘↵` (opens the Usage tab) / `DISMISS ⌥⌘⌫`, rim and dwell line in `quota-warning`, and a VoiceOver announcement (DESIGN Peek alert panel → Quota warning); the Usage card keeps its `WARN · ≥ 80%` marker (UX-DR78); the handle resolves when usage drops below or the window resets

**Given** `warn_action = "visual"`
**When** crossed
**Then** state becomes `active` and only the visual change happens

**Given** pace
**When** it is ahead without crossing the threshold
**Then** no warning is ever raised (% only, never pace)

### Story 7.7: Usage tab provider cards

As a user,
I want a Usage tab with a card per provider showing each window, reset time and pace,
So that I can plan around my limits in detail.

**Requirements:** UX-DR100 (`READING LOGS…`), FR54, UX-DR31, UX-DR29, UX-DR58, UX-DR78, UX-DR41 (Usage 50/50), UX-DR44 (no provider)

**Acceptance Criteria:**

**Given** the Usage tab (mockup `key-usage-tab.html`)
**When** it renders
**Then** the left half lists provider cards in user order, each with grip, name, meta (`MAX · WARN 80%`, `ULTRA · WEEKLY ONLY`, `DAILY QUOTA ONLY`), a 58 px dial with the big value, and one bar per window with value, `RESET 16:40 · IN 1H52`, `ELAPSED 63%` and pace label

**Given** bars
**When** rendered
**Then** each has a 2 px pace marker, a dashed threshold tick, and fills per state: within (`WITHIN PACE` / `WITHIN PACE · +3`), ahead (solid pace-ahead + `AHEAD OF PACE · +9`), warning (hatched quota-warning + triangle + `WARN · ≥ 80%`, wins)

**Given** more than two providers
**When** the left half overflows
**Then** it scrolls with the fade mask, 3 px thumb track and footer `DRAG TO REORDER · ALSO IN SETTINGS` · `SCROLL ↓`

**Given** no usage provider
**When** the tab renders
**Then** it shows `NO USAGE PROVIDER`, one sentence and `Open settings ⌘,`

**Given** the Usage tab before the first log read has finished (added 2026-11-07)
**When** it renders
**Then** each provider card shows `READING LOGS…` in place of its values, never zeros (UX-DR100)

### Story 7.8: Usage history and today's cost

As a user,
I want a 7-day token chart across agents and today's estimated cost by project,
So that I understand where my usage goes.

**Requirements:** FR54 (history, cost), UX-DR31 (right half), UX-DR100

**Acceptance Criteria:**

**Given** the usage database
**When** the right half of the Usage tab renders
**Then** `HISTORY · 7D` shows tokens per day for the last 7 days, one series per agent, weekday initials on the axis

**Given** today's records
**When** `COST · TODAY` renders
**Then** it lists estimated cost per project (from `cwd`), a total, and the source line `FROM LOCAL LOGS · OFFLINE`

**Given** no local data
**When** rendered
**Then** ~~both cards show an empty-state block~~ **Amended 2026-11-07 (epics update run):** `HISTORY · 7D` shows `NO HISTORY YET` and `COST · TODAY` shows `—` with `NO COST DATA` (UX-DR100)

### Story 7.9: Provider order by drag or Settings

As a user with several providers,
I want to reorder providers by dragging their cards or in Settings,
So that the rings appear in the order I care about.

**Requirements:** FR54 (order), FR50 (user order), UX-DR51, UX-DR29 (grip)

**Acceptance Criteria:**

**Given** the Usage tab
**When** the user drags a provider card by its grip
**Then** the list reorders, `[modules."agents.usage"] order` is written through ConfigStore, and closed-notch rings follow the new order live

**Given** Settings › Usage
**When** the user reorders providers there
**Then** the Usage tab and rings reflect the same order

### Story 7.10: Multiple Accounts per Provider

*Added 2026-11-06 for PRD FR-29 (v0.2).*

As a developer with a personal and a work login for the same agent,
I want to add several Accounts per Provider and see each one's usage separately,
So that I pace each plan on its own.

**Requirements:** PRD FR-29, PRD FR-30 (opt-in per Account), PRD FR-57 (Account credentials never sync), FR47, FR49, FR50, FR54, AD-23 (amended 2026-11-06: usage identity becomes adapter id + Account; ring per Provider), AD-9 (one Keychain item per Account), AD-8 (`.local` scope for credentials and locations), UX-DR99, A82

**Acceptance Criteria:**

**Given** Settings › Usage › <Provider>
**When** the user adds an Account
**Then** it has a label and is bound to one agent config or log location (the first Account uses the default location)
**And** this works for every Provider through the adapter's usage provider, not only Claude

**Given** a setup created before this story (one implicit Account per Provider)
**When** Vigie upgrades
**Then** it becomes that Provider's default Account with its history intact

**Given** Session events
**When** they arrive
**Then** each Session is attributed to the Account whose config location matches the environment captured by the hook CLI (A82); no match → the Provider's default Account

**Given** usage ingestion
**When** local logs are read
**Then** each Account's location is read separately and stored keyed by adapter id + Account in the usage database

**Given** remote plan limits (FR49)
**When** the user enables them
**Then** they are enabled per Account, each Account's credential is its own Keychain item, and credentials and locations stay in `local.toml` / Keychain and never sync

**Given** a Provider with several Accounts
**When** the closed notch renders
**Then** that Provider's ring shows the Account of its most recent Session, labeled with the Account label
**And** the Usage tab shows one card per Account grouped under its Provider, and history and cost can be split by Account
**And** (added 2026-11-07) the closed-notch wing label reads `<PROVIDER> · <ACCOUNT>` (e.g. `CLAUDE · WORK`, Account truncated to 6 characters) only when the Provider has several Accounts; each Usage card header reads `<PROVIDER> · <ACCOUNT>`; the quota-warning peek title appends the Account (`CLAUDE · WORK · 5H 82 %`); a failed remote fetch shows `STALE · HH:MM` on that Account's card only (UX-DR99)

**Given** Privacy mode (Epic 21)
**When** it is active
**Then** Account labels are treated as sensitive fields

### Story 7.11: Hook installation per Account location

*Added 2026-11-08 (Romain's ruling): Story 4.7 installs hooks only into the default `~/.claude/settings.json`; an extra Account (Story 7.10) with its own `CLAUDE_CONFIG_DIR` reports usage from its logs but no Sessions.*

As a user with several Accounts on one Provider,
I want Vigie's hooks installed in each Account's config location,
So that Sessions from every Account reach the notch.

**Requirements:** PRD FR-23, AD-22 (IntegrationInstaller, diff confirmation), AD-23 (Accounts bound to a location), A82

**Acceptance Criteria:**

**Given** an Account with a `location` (Story 7.10)
**When** the user connects the Provider's integration, or adds the Account while it is connected
**Then** the installer shows the same unified diff for `<location>/settings.json` and writes it only after confirmation; the hook command carries the Account's location so the hook CLI attributes events to it (A82)

**Given** a connected Provider with several Accounts
**When** Settings › Agents › Integrations renders
**Then** the status line lists each Account's location as installed, missing or modified, and `Install` repairs every missing one

**Given** Disconnect, or an Account removed
**When** confirmed
**Then** the hooks are removed from that location only, with a diff

**Given** a location that does not exist or has no `settings.json`
**When** the installer runs
**Then** it creates the file with only Vigie's hooks after confirmation, or reports the missing folder as a setup problem naming the path (sensitive in Privacy mode)

**Given** unit tests with two fake Account locations
**When** install, repair and remove run
**Then** each location is touched independently and the default location is unchanged by the others

## Epic 8: Codex CLI support

Users who run Codex CLI get its sessions and usage through the same modules, with honest reporting of what the integration can detect.

### Story 8.1: Codex adapter — fixtures, version gating and notify integration

As a Codex CLI user,
I want Vigie to connect to Codex with a reviewed config change,
So that my Codex sessions show up next to Claude's.

**Requirements:** FR83, FR85, FR80, NFR18, NFR23, AD-22, AD-23, A45, A71

**Acceptance Criteria:**

**Given** the installed Codex CLI
**When** research runs first
**Then** `Packages/Adapters/Codex/Tests/Fixtures/<cli-version>/` holds recorded `notify` payloads and session log samples, and a note records whether native hooks exist and whether approval requests and errors are observable (SPEC §14.4)

**Given** `Packages/Adapters/Codex` registered with one line in App assembly
**When** the build runs
**Then** neither `agents.sessions` nor `agents.usage` changes (NFR23)

**Given** Connect in Settings › Agents › Codex
**When** `~/.codex/config.toml` has no `notify` entry
**Then** the plan adds `notify = ["<symlink path>", "hook", "codex"]` and `IntegrationInstaller` applies it after diff confirmation
**And** if a different `notify` program already exists, nothing is changed silently (A71, ruled 2026-11-06): Settings explains the conflict and offers `Run both`, which shows the diff (the existing program moved into Vigie's wrapper, `notify` pointing at the wrapper) and applies it only after confirmation; the wrapper runs the previous program with the same arguments first, then forwards the event to Vigie, and Disconnect restores the previous `notify` entry exactly
**And** (added 2026-11-07) the wrapper entry is exactly `<symlink> hook codex --chain <original argv>`, and the original argv is recorded in `local.toml`, from which Disconnect restores it (AD-22)
**And** if the user declines, nothing is written and Settings shows manual instructions

**Given** an unsupported Codex version
**When** detected
**Then** no statuses are emitted and the setup-problem alert reads `Codex adapter: CLI version X unsupported` (UX copy)

### Story 8.2: Codex transcript watching and capability reporting

As a Codex CLI user,
I want working and blocked states inferred from Codex session logs when hooks don't provide them, and to be told what can't be detected,
So that I trust exactly what Vigie shows.

**Requirements:** FR81 (transcript tier), FR35, FR31, AD-23 (logReader shared)

**Acceptance Criteria:**

**Given** `~/.codex/sessions/` logs
**When** the transcript watcher follows them (directory watcher, incremental reads)
**Then** it emits normalized events (`session.start`, `prompt.submit`, `tool.*`, `needs.input` if observable, `turn.end`) matched to sessions using the `notify` events, through the same `logReader` parser used for usage

**Given** the adapter capabilities
**When** `needs.input` or `session.error` cannot be detected
**Then** Settings › Agents › Codex states "Codex sessions can't show blocked" / "…failed" and no such status is ever shown for Codex

**Given** fixture logs
**When** CI runs `adapter-fixtures`
**Then** replayed logs produce the expected normalized event sequence

### Story 8.3: Codex usage provider

As a Codex user,
I want Codex token usage and rate limits in the Usage tab and a ring in the notch,
So that I track both agents' quotas in one place.

**Requirements:** FR55, FR47, AD-23 (one provider per adapter; Account amended 2026-11-06), PRD FR-29

**Acceptance Criteria:**

**Given** Codex session logs with token counts
**When** ingested
**Then** the `codex` provider contributes to 7-day history and cost (if pricing is known) in the shared database

**Given** logs carrying rate-limit snapshots (to be confirmed by 8.1 research)
**When** present
**Then** the provider exposes windows with % and reset time, and a Codex ring appears in the closed notch; if absent, Codex has no ring (A18) and its card shows local data only

**Given** several Codex Accounts (Story 7.10)
**When** usage is ingested
**Then** each Account's log location is read separately and attributed to that Account (added 2026-11-06)

### Story 8.4: `vigie run` for any long command

*Added 2026-11-06 for PRD FR-23 (v0.2, with the Codex adapter epic).*

As a developer running long builds and deploys,
I want to run any command as `vigie run -- <command>` and have it report like an agent Session,
So that a failed deploy peeks and Focus brings me back to its tab (UJ-6).

**Requirements:** PRD FR-23, UJ-6, FR8, FR86 (generic mapping), NFR3 (event send budget), AD-5 (generic mapping lives in `agents.sessions`), AD-6 carve-out for `vigie run` (amended 2026-11-06: the command's own output and exit code pass through; only its event sends follow the socket-else-spool rule), AD-7, AD-17 (`vigie-dev run`), UX-DR105, A81

**Acceptance Criteria:**

**Given** `vigie run -- make deploy` in a terminal tab
**When** it starts
**Then** the CLI sends ~~a session start with status working, the command line as title~~ **Amended 2026-11-07 (epics update run):** an `agent.generic` event with agent `run` (shown as agent `RUN`), status working, the command as the last action and `cwd` as the project (AD-6), with TTY and ancestor chain (A81), then runs the command as a child with inherited stdin, stdout and stderr
**And** Vigie shows a working Session that sorts, alerts and focuses like any agent Session

**Given** the child exits
**When** its exit code is 0
**Then** the Session becomes done; any other code (or death by signal) makes it failed with the code in the message, raising the normal `session.done` / `session.failed` Alerts
**And** `vigie run` exits with the child's exit code (128 + n for death by signal n)
**And** (added 2026-11-07) a failed run's row and peek kicker read `FAILED · EXIT <code>` with the same code `vigie run` exits with (e.g. `FAILED · EXIT 2`) (UX-DR105)

**Given** the user presses Ctrl-C
**When** SIGINT reaches the foreground process group
**Then** `vigie run` ignores it itself, waits for the child, ends the Session without any Alert (a user interrupt is not a failure) and exits with the child's code
**And** SIGTERM and SIGHUP sent to `vigie run` are forwarded to the child

**Given** Vigie is not running
**When** `vigie run` is used
**Then** the command runs normally, its events go to the spool (AD-6) and replay on next launch; replayed transitions older than 5 min post no Alert (AD-5)

**Given** any run
**When** its output is compared with running the command directly
**Then** `vigie run` adds no bytes to stdout or stderr, and each event send stays within the 150 ms budget before falling back to the spool

**Given** a `vigie run` Session
**When** liveness and Focus run
**Then** its PID is the `vigie run` process and its locator is the calling tab, so Focus works as for agents

**Given** `vigie run` without `--` or without a command
**When** invoked
**Then** it prints usage to stderr and exits 64

## Epic 9: Shelf and Ask AI

Users drag anything onto the notch to stash it for days, with expiry they can trust, or drop files on Ask AI to start their default agent in a new terminal tab with the files attached.

### Story 9.1: Drop display on the notch

As a user dragging a file from any app,
I want the notch to turn into drop targets without opening or stealing focus,
So that I can stash or ask about a file in one gesture.

**Requirements:** FR7, FR57 (amended 2026-11-07), UX-DR20 (superseded by the Story 1.7c drop display), UX-DR50 (amended 2026-11-07), UX-DR45, UX-DR83, UX-DR92 (peeks wait), UX-DR96 (`drop-display-grow`), AD-19 (DropZone contract, host rendering, file promises; amended 2026-11-07), PRD FR-63 · **Depends on:** Story 1.7c (done 2026-11-07), Story 3.9.

**Acceptance Criteria:**

**Given** the `DropZone` contract `{ id, label, glyph, accentToken, role: .primary | .secondary, cell: DropCell, order, accepts, handler(DropPayload) }` with `DropPayload { urls, modifiers, source: .dropDisplay | .shelfTab | .homeWidget | .stashItem | .paste | .service }` (AD-19)
**When** modules declare `dropZones`
**Then** the host collects them (no other registration path)

**Given** a file drag starts in any app
**When** the cursor moves
**Then** nothing changes until the drag is over the notch; over it, the drop display (700 × 196, band `DROP · 1 ITEM` / `ESC · CANCEL`) grows out of the notch without opening the expanded view and without taking focus, with layout B: Stash 2 × 2 on the left, Ask AI 1 × 2 (round `+` target, hint `⌥ ALT FOLDER`), and AirDrop and Image to Text 1 × 1 stacked when enabled (Stories 9.8, 9.9); disabled zones are hidden and the grid reflows (mockup `ux-designs/ux-vigie-2026-11-04/mockups/key-design-pass-1-7.html` 1.7c, Option B)
**And** (added 2026-11-07) the display grows over `motion.drop-display-grow` (180 ms; instant under Reduce motion), the Stash zone's meta reads `KEEP <N> DAYS · <n> ITEMS` (e.g. `KEEP 7 DAYS · 5 ITEMS`), and the rim is static under Calm and Reduce motion (UX-DR83, UX-DR96)

**Given** the drop display is open
**When** the cursor hovers a zone
**Then** that zone lights (solid accent border, inner tint) and shows its release line (`RELEASE TO STASH`, `RELEASE TO ASK`, `RELEASE TO SHARE`, `RELEASE TO COPY TEXT`) at label size, replacing the meta line; a zone that can't take the item stays unlit
**And** each zone has a VoiceOver label naming it and its target (e.g. "Stash, keep 7 days, 5 items", "Ask AI, Claude Code in ~/dev, Option for alternate folder")

**Given** ⌥ is held over Ask AI
**When** hovering
**Then** the hint lights up and reads `ALT FOLDER`

**Given** a drop of file promises (e.g. from a browser)
**When** it lands
**Then** the host materializes them into `<Application Support>/drops/` before calling the handler with `source = .dropDisplay` and the modifiers

**Given** zones declared with `role` (one `.primary`), a preferred `DropCell` and `order` (AD-19, amended 2026-11-07)
**When** the drop display lays out
**Then** the host places them in the 4 × 2 grid (Stash primary 2 × 2, Ask AI 1 × 2, AirDrop and Image to Text 1 × 1), hides zones whose module or setting is off and reflows the freed cells to a neighbour; modules never position views
**And** (added 2026-11-07) with one of AirDrop / Image to Text off the other spans column 4; with both off the grid becomes 3 columns; with the Shelf off only Ask AI shows (UX-DR83)

**Given** the drag ends outside every zone, leaves the notch and display, or Esc is pressed
**When** no drop happens
**Then** the drop display retracts with no action and the closed notch shows its normal content

**Given** every zone is disabled (Shelf off and `agents.sessions` off)
**When** a file is dragged over the notch
**Then** no drop display appears

**Given** the drop display is open (added 2026-11-07)
**When** an alert routed to peek arrives
**Then** the peek waits and shows only after the display closes, under the Story 3.9 queue rules (UX-DR92)

### Story 9.2: Stash storage

As a user,
I want stashed files kept as references by default (or copies), and dragged text, links and images saved as files,
So that the shelf holds anything I drop and tells me what expiry will do.

**Requirements:** FR58, FR61, FR7 (Stash), UX-DR101, AD-11, AD-19 (security-scoped access), AD-26, NFR16

**Acceptance Criteria:**

**Given** `Packages/Modules/Shelf` declaring the Stash zone
**When** a file is dropped with `mode = "reference"` (default)
**Then** a security-scoped bookmark is stored in the shelf index (JSON in `context.storage`) with name, size, source app, added date, mode `REF`

**Given** `mode = "copy"`
**When** a file is dropped
**Then** a copy is stored in the module folder, mode `COPY`

**Given** dragged text, a URL or an image
**When** dropped
**Then** it is saved as a file (`.txt`, `.webloc`, image file) in the module folder, mode `SAVED`

**Given** the shelf has items
**When** state is computed
**Then** it is `ambient` with the item count; empty → `hidden`

**Given** handlers
**When** a bookmark is used
**Then** Shelf starts security-scoped access before calling a handler and ends it after; handlers finish reading files before returning

**Given** a Stash drop that can't be stored (unreadable file, disk full) (added 2026-11-07)
**When** the handler fails
**Then** nothing is added, the left wing shows `NOT STASHED` for 2 s as a transient readout (the slot Story 2.8 reserves for transient readouts), an activity-log entry is written, and no Alert, peek or sound follows (UX-DR101)

### Story 9.3: Shelf tab and item actions

As a user,
I want a Shelf tab where I can move, copy, preview, reveal and pin stashed items,
So that the shelf is a real temporary workspace.

**Requirements:** FR59, FR91 (Space), UX-DR33, UX-DR32 (Stash in panel), UX-DR41 (Shelf layout), UX-DR50, UX-DR59 (stash empty), UX-DR44

**Acceptance Criteria:**

**Given** the Shelf tab (mockup `key-shelf-tab.html`)
**When** it renders
**Then** the Stash table card (`1fr`) lists rows (name, `size · mode`, source app, added, expires with time left over a thin TTL bar) and the footer `DRAG OUT MOVE · ⌥ DRAG COPY · ␣ QUICK LOOK`

**Given** a row
**When** hovered
**Then** `QUICK LOOK · REVEAL · PIN` chips replace source and added, and the grip shows `DRAG · MOVE  ⌥ DRAG · COPY`

**Given** a row dragged out to Finder
**When** dropped without ⌥
**Then** the item moves (removed from the shelf); with ⌥ it is copied and stays

**Given** a selected row and focus
**When** the user presses Space
**Then** Quick Look opens; Reveal opens Finder at the file; Pin toggles `PINNED` with the dashed lilac line

**Given** an empty stash
**When** the tab renders
**Then** it shows `STASH EMPTY` and ~~"Drag a file, text or image onto the notch to keep it here for N days."~~ **Amended 2026-11-07 (epics update run):** "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for N days." (UX-DR44, UX-DR100; `⌘V` ships with Story 9.10 in the same release) while Ask AI stays usable

### Story 9.4: Shelf expiry

As a user,
I want stashed items to expire after a number of days with a warning first, and never be deleted permanently,
So that the shelf cleans itself without ever losing my files.

**Requirements:** FR60, UX-DR33, UX-DR59, UX-DR11 (quota-warning yellow, A43 ruled 2026-11-06), AD-11 (Trash), AD-13 (`shelf.expiring`), NFR16, A4, A43

**Acceptance Criteria:**

**Given** `ttl = "7d"` (default)
**When** an unpinned item reaches 24 h before expiry
**Then** its row shows the quota-warning yellow + triangle (A43) and `EXPIRES IN <N>H`, the card meta shows `1 EXPIRING`; time-left text follows `6D LEFT` / `1D 18H LEFT` / `EXPIRES IN 5H`

**Given** `expiry_notification = true`
**When** an item enters its last 24 h
**Then** `shelf.expiring` is posted with `system` output only (no peek, no sound); with the default `false`, nothing is posted

**Given** an item reaches expiry
**When** it is a reference
**Then** it leaves the shelf and the original file is untouched
**And** copies and saved items are moved to the Trash with `NSWorkspace.recycle`; nothing is deleted permanently

**Given** a pinned item
**When** time passes
**Then** it never expires

### Story 9.5: Research — Ask AI launch per agent CLI

As Romain,
I want to know how each agent CLI can start interactively with files attached or a prefilled unsent prompt,
So that Ask AI uses the best launch each CLI allows.

**Requirements:** FR40 (research), SPEC §14.16, Architecture Deferred (Ask AI syntax), A23

**Acceptance Criteria:**

**Given** Claude Code, Codex CLI (and Gemini CLI if installed)
**When** tested
**Then** `docs/decisions/ask-ai-launch.md` records for each: whether files can be attached (`claude "@<file>"`, `codex "<paths>"`, `gemini -i "@<file>"`), whether the prompt stays unsent for the user to type, quoting rules, and the fallback (paste paths)

**Given** each terminal adapter
**When** researched
**Then** the record states how `openTab(argv:cwd:)` opens a new tab running a command in a given folder (Terminal, iTerm2, Warp, Ghostty)

### Story 9.6: Ask AI from the drop display

As a user,
I want to drop files on Ask AI and land in a new terminal tab running my default agent with the files attached,
So that asking about a file takes one gesture and no dialog.

**Requirements:** FR40, FR7 (Ask AI), UX-DR70, UX-DR50, AD-19 (amended 2026-11-07), AD-23 (launchCommand, openTab), A72 (amended 2026-11-07)

**Acceptance Criteria:**

**Given** `agents.sessions` declares the Ask AI zone (secondary role, 1 × 2 cell, AD-19)
**When** files are dropped on it in the drop display
**Then** it calls `launchCommand(files:cwd:)` of the `ask_default_agent` adapter and the configured terminal adapter's `openTab(argv:cwd:)`, with no dialog

**Given** `ask_cwd = "home" | "file_folder" | "<path>"`
**When** dropped without ⌥
**Then** the tab opens in that folder; with ⌥ held it opens in `ask_alt_cwd`

**Given** the CLI cannot start with an attachment or unsent prompt (per 9.5)
**When** dropped
**Then** the agent starts and the file paths are pasted into the prompt for the user to complete

**Given** the default agent is not installed
**When** dropped
**Then** a setup-problem alert says so with Open settings › Agents

**Given** `agents.sessions` is disabled
**When** a drag starts
**Then** no Ask AI zone appears; with Shelf disabled Stash, AirDrop and Image to Text disappear and Ask AI stays (A72, amended 2026-11-07)

### Story 9.7: Ask AI on the Shelf tab

As a user with stashed files,
I want to drag a stash item onto an Ask AI card that shows where it will launch,
So that I can ask about something I stashed earlier.

**Requirements:** FR40, FR59 (stash → Ask AI), FR57 (Shelf tab zones), UX-DR32, UX-DR70, UX-DR50, UX-DR84

**Acceptance Criteria:**

**Given** the Shelf tab
**When** it renders
**Then** ~~the Ask AI card (212 px) shows a dashed lilac border, the round `+` target (breathing in dark, static in light), `ASK AI`, and rows `AGENT`, `FOLDER`, `⌥ FOLDER` with current defaults~~ **Amended 2026-11-07 (epics update run):** the `SEND TO` card (212 px wide, header `SEND TO`, meta `DEFAULTS`) shows the Ask AI zone, 84 px tall, with a dashed lilac border, the round `+` target (breathing in dark, static in light and under Reduce motion), `ASK AI`, `Drop a file to start a session` and rows `AGENT`, `FOLDER`, `⌥ FOLDER` with current defaults (no hint sentence); the 38 px AirDrop and Image to Text mini zones (`mini-zone-gap` 6, A radius 11) are added under it by Stories 9.8 and 9.9, and disabled zones are not drawn (UX-DR84)

**Given** a stash item dragged over the card
**When** hovering
**Then** the border turns solid with an inner tint and the label reads `RELEASE TO ASK` naming agent and folder; with ⌥ the folder row dims and `⌥ FOLDER` lights, and the drag ghost carries an ⌥ badge

**Given** the drop
**When** released
**Then** the same launch as Story 9.6 runs with `source = .stashItem`

### Story 9.8: AirDrop drop zone

*Added 2026-11-06 for PRD FR-33 (v0.2, on by default).*

As a user,
I want to drop files on an AirDrop zone in the notch,
So that I can send them to a nearby device without opening Finder.

**Requirements:** PRD FR-33, FR7, UX-DR20 (drop display), UX-DR45 (no focus), UX-DR101, AD-19 (DropZone contract, host rendering, file promises), new drop-zone providers (architecture amended 2026-11-06), A83 (superseded by Story 1.7c) · **Depends on:** Stories 1.7c (done 2026-11-07), 9.1

**Acceptance Criteria:**

**Given** the Shelf module enabled and `airdrop` on (default)
**When** a file is dragged over the notch
**Then** the drop display shows the AirDrop zone (column 4, row 1; label `AIRDROP`, meta `NEARBY DEVICES`; hover `RELEASE TO SHARE`), without expanding or taking focus; with Image to Text off it spans both rows of column 4
**And** the Shelf tab's `SEND TO` card shows a 38px AirDrop mini zone (meta `SHARE`) under the shortened Ask AI zone, which accepts stash items

**Given** files dropped on it
**When** the drop lands
**Then** promises are materialized (AD-19) and the macOS AirDrop picker (`NSSharingService` `.sendViaAirDrop`) opens for the dropped items; nothing is added to the Shelf

**Given** items AirDrop can't send
**When** they hover the zone
**Then** the zone shows as not accepting and the drop is refused

**Given** AirDrop is unavailable (Wi-Fi or Bluetooth off)
**When** the picker opens
**Then** the system explains it; Vigie raises no Alert of its own

**Given** dropped items for which the AirDrop share can't start (e.g. an unreadable file) (added 2026-11-07)
**When** the drop lands
**Then** the left wing shows `AIRDROP UNAVAILABLE` for 2 s as a transient readout and an activity-log entry is written; this is not an Alert (no peek, no sound) (UX-DR101)

**Given** `airdrop = false`, or the Shelf module disabled (AirDrop is a Shelf zone, A72 amended 2026-11-07)
**When** dragging
**Then** the zone does not appear in the drop display or the `SEND TO` card, and the grid reflows (Image to Text, if on, spans column 4)

### Story 9.9: Image to Text drop zone

*Added 2026-11-06 for PRD FR-34 (v0.2, off by default).*

As a user,
I want to drop an image or PDF on Image to Text and get its text on the clipboard,
So that I can copy text out of a screenshot without another app.

**Requirements:** PRD FR-34, FR7, UX-DR85, UX-DR96 (`confirm-readout`), AD-19 (DropZone, `context.clipboard`), NFR7 (no network), on-device Vision text recognition (addendum §5), A83 (superseded by Story 1.7c) · **Depends on:** Stories 1.7c (done 2026-11-07), 9.1

**Acceptance Criteria:**

**Given** `image_to_text = false` (default), or the Shelf module disabled (A72 amended 2026-11-07)
**When** dragging
**Then** no Image to Text zone appears (drop display or `SEND TO` card) and AirDrop spans column 4

**Given** `image_to_text = true` and an item being dragged over the notch
**When** the drop display opens
**Then** the Image to Text zone shows in column 4, row 2 (label `IMAGE TO TEXT`, meta `COPY TEXT`), and the Shelf tab's `SEND TO` card shows its 38px mini zone (meta `COPY`); it lights only for an image or PDF, other item types don't light it; on hover its release line reads `RELEASE TO COPY TEXT`

**Given** an image dropped on it
**When** recognition runs
**Then** on-device Vision text recognition runs off the main actor, the recognized text (reading order) is copied through `context.clipboard`, and the left wing shows `COPIED · <n> LINES` after the first left-wing item for 2 s (the last visible item steps into `+X` meanwhile) with a draining 1px line (Story 1.7c); no Alert, no peek, no sound, and the right wing is untouched
**And** (added 2026-11-07) while recognition runs the readout shows `READING…`; the result readout lasts `motion.confirm-readout` (2 s) and holds while the pointer is over the notch; VoiceOver announces "Copied 3 lines" (or "No text found"); under Reduce motion the drain is a static full line that disappears at the end; the `SEND TO` card meta changes from `DEFAULTS` to `LAST · <n> LINES · <time>` (UX-DR85)

**Given** a PDF dropped on it
**When** processed
**Then** its embedded text is used when present, otherwise its pages are rendered and recognized on the Mac

**Given** no text is found
**When** recognition ends
**Then** the clipboard is unchanged and the same left-wing readout reads `NO TEXT FOUND`

**Given** a network monitor during a test run
**When** a drop is processed
**Then** no network request is made and the materialized drop file is deleted afterwards

### Story 9.10: Keyboard, menu and Services paths to drop zones

*Added 2026-11-07 (UX accessibility review, user ruling): drop zones must be reachable without dragging.*

As a keyboard or VoiceOver user,
I want to send Shelf items to Ask AI, AirDrop or Image to Text, and stash things, without dragging,
So that every drop zone is reachable from the keyboard, a menu or a service.

**Requirements:** PRD FR-31, PRD FR-32, PRD FR-33, PRD FR-34, PRD FR-8, PRD FR-63, FR59, UX-DR50 (amended 2026-11-07), AD-19 (`DropPayload.source` `.stashItem`, `.paste`, `.service`; Shelf-off rule; amended 2026-11-07), AD-20 (`NSServices` in Info.plist; amended 2026-11-07), AD-13 (setup-problem alert), UX-DR102, A72 (amended 2026-11-07) · **Depends on:** Stories 9.1, 9.2, 9.3, 9.8, 9.9

**Acceptance Criteria:**

**Given** a Shelf row on the Shelf tab or in the Home shelf widget
**When** the user right-clicks it, or presses `↵` on the selected row while the expanded view has focus
**Then** a `Send to` menu opens listing the enabled zones only (Ask AI, Ask AI in alternate folder, AirDrop, Image to Text) plus Quick Look, Reveal and Pin / Unpin
**And** choosing a zone calls that zone's handler with the item and `source = .stashItem`, with the same result as dragging the item onto the zone (Ask AI in alternate folder sets ⌥ in `modifiers`)

**Given** VoiceOver on a Shelf row
**When** the rotor's actions are listed
**Then** the same entries are exposed as `accessibilityCustomActions`, each named after the zone or action

**Given** the Shelf tab with keyboard focus
**When** the user presses `⌘V`
**Then** the clipboard contents (files, image, text or URL) are stashed exactly like a Stash drop (reference / copy / saved per Story 9.2) with `source = .paste`; an empty or unsupported clipboard changes nothing
**And** (added 2026-11-07) the host reads the clipboard (a VigieCore capability used only for this path; `context.clipboard` stays copy-only and no module reads `NSPasteboard`) and calls the Stash handler with the contents and `source = .paste` (AD-19)

**Given** files or text selected in Finder or any app
**When** the user picks the macOS Services entry `Stash in Vigie`
**Then** the items are stashed with `source = .service`, without opening the expanded view or taking focus
**And** the entry is declared with `NSServices` in the app's Info.plist (AD-20); no new target or entitlement is added (a Share extension is not in v1) [ASSUMPTION: Services entry instead of a Share extension]

**Given** the Shelf module disabled
**When** the user invokes `Stash in Vigie`
**Then** nothing is stashed and a setup-problem alert `Shelf is off` offers Open settings [ASSUMPTION]; `⌘V` and the `Send to` menu do not exist because the Shelf tab and widget are gone

**Given** the drop zones in the drop display and the `SEND TO` card
**When** VoiceOver reads them
**Then** each zone's label names the zone and its target (e.g. "Stash, keep 7 days, 5 items"; "Ask AI, Claude Code in ~/dev, Option for alternate folder")

## Epic 10: Sounds

Users can hear the seven alert sound events (blocked, failed, done, quota warning, plus timer end, break and calendar reminder from Epics 20 and 13) with built-in or custom sounds, fully optional and silent under Do Not Disturb.

### Story 10.1: Sound output in Notifier

As a user,
I want alerts to play a sound once when I've enabled it,
So that I notice blocked or failed sessions even when I'm not looking.

**Requirements:** FR98, FR17, AD-13 (Notifier sole reader of `[sounds]`; sound table)

**Acceptance Criteria:**

**Given** `[sounds] enabled = true` and `blocked = "builtin:blocked"`
**When** `session.blocked` is routed to `sound`
**Then** the sound plays once with the alert, and once more if the reminder fires with the state unchanged

**Given** the kind-to-sound table in Notifier
**When** kinds are mapped
**Then** `session.blocked → blocked`, `session.failed → failed`, `session.done → done`, `usage.quota_warning → quota_warning`; `shelf.expiring` and pace have no sound key and never play
**And** (added 2026-11-07) the table is the AD-13 table: this story ships the four `session.*` / `usage.*` entries; `time.timer_end → timer_end`, `time.break_reminder → break_reminder` (also raised by a Pomodoro work-phase end) and `calendar.reminder → calendar_reminder` are added by Stories 20.2, 20.4 and 13.4, all off by default

**Given** Do Not Disturb or `enabled = false` or a key set to `"off"`
**When** an alert fires
**Then** no sound plays

### Story 10.2: Built-in sounds, custom files and Sounds settings

As a user,
I want a set of short sci-fi sounds and the option to use my own files,
So that alerts sound the way I like.

**Requirements:** FR98, UX-DR72, UX-DR74 (Sounds pane), A31

**Acceptance Criteria:**

**Given** the app bundle
**When** it ships
**Then** it contains built-in sounds `blocked`, `failed`, `done`, `warn`, each under 1 s, in a simple sci-fi register

**Given** a sound key set to a file path
**When** the alert fires
**Then** that file plays (any length); a missing or unreadable file raises a setup-problem alert naming the key

**Given** Settings › Sounds
**When** opened
**Then** each sound event (four here; ~~timer end and break reminder are added by Stories 20.2 and 20.4~~ **Amended 2026-11-07 (epics update run):** timer end, break reminder and calendar reminder are added by Stories 20.2, 20.4 and 13.4, seven in all) has on/off, a picker (built-ins or Choose file…) and a preview button

## Epic 11: Home dashboard

Users open Vigie onto a configurable Home grid summarizing sessions, quota and shelf.

### Story 11.1: Home tab grid

As a user,
I want the expanded view to open on a Home grid of widgets I choose and order,
So that one click shows me everything important.

**Requirements:** FR87 (always on Home), FR89 (Home first), FR90 (amended 2026-11-07), UX-DR41 (Home layout, amended 2026-11-07), UX-DR28, UX-DR97, UX-DR100, A12, A34, A51

**Acceptance Criteria:**

**Given** modules providing `homeCard()`
**When** the expanded view opens (click or hotkey)
**Then** it opens on Home, the first tab, every time

**Given** the Home tab
**When** it renders
**Then** ~~cards sit in a 3-column (`1.2fr 1.2fr 1.1fr`) × 2-row (162, 138) grid; a card may span two columns~~ **Amended 2026-11-07 (user ruling):** every card has one fixed size, 222 × 138, in a grid of three equal columns (`components.home-grid`), no spans; cards fill left to right in the set order; overflow scrolls inside the panel

**Given** Settings › Home (a list of every module that offers `homeCard()` and every script with the `home` surface, each with a checkbox, dragged to order)
**When** the user ticks, unticks or drags a row
**Then** `[home] cards = [...]` is written and Home shows exactly those cards in that order, live
**And** Home itself has no in-place edit mode (no drag, resize or remove on Home); with no card chosen it shows `NO WIDGETS` with `Open settings` leading to Settings › Home
**And** (added 2026-11-07) the empty Home reads `NO WIDGETS` + "Pick Home widgets in Settings." (UX-DR97, UX-DR100)

**Given** a Home card
**When** clicked
**Then** the module's tab opens (A34)

### Story 11.2: Home cards for sessions and quota

As a user,
I want Home cards for my sessions and my quota,
So that the dashboard reflects my main use case.

**Requirements:** FR90, UX-DR30 (Home row grid), UX-DR16, UX-DR57, UX-DR97

**Acceptance Criteria:**

**Given** `agents.sessions` `homeCard()`
**When** rendered
**Then** it lists the most urgent sessions with rows `18 | 92 | 1fr | 64` (glyph, agent, project, status · T+), with the same empty states as the Agents tab, and clicking a row focuses it

**Given** `agents.usage` `homeCard()`
**When** rendered
**Then** it shows each provider's ring and the main window value with reset time, or `NO USAGE PROVIDER`

**Given** card content taller than the fixed 222 × 138 cell (added 2026-11-07)
**When** either card renders
**Then** the overflow fades under the bottom mask and the card keeps its size (UX-DR97)

### Story 11.3: Home shelf widget

As a user,
I want a shelf widget on Home with its drop zones and expiry warning,
So that I can stash or ask from the dashboard.

**Requirements:** FR57 (Home widget zones), FR60 (Home warning), UX-DR33 (Home shelf widget), UX-DR32, UX-DR97, AD-19 (`source = .homeWidget`)

**Acceptance Criteria:**

**Given** the Shelf `homeCard()`
**When** rendered
**Then** it shows the stash list with Stash and Ask AI zones

**Given** an item in its last 24 h
**When** rendered
**Then** it moves to the top of the list with a `5H`-style tag and a warning line `1 EXPIRES IN 5H` along the zone's bottom

**Given** a file or stash item dropped on a zone in the widget (expanded view opened by click)
**When** released
**Then** the handler runs with `source = .homeWidget`

**Given** more stash items than fit the fixed 222 × 138 card (added 2026-11-07)
**When** the widget renders
**Then** the list fades under the bottom mask and the card keeps its size (UX-DR97)

### Story 11.4: Keep the current tab on quick re-open

*Added 2026-11-08 (Romain's ruling after the first live session): Story 11.1 lands on Home on every expand; closing and immediately re-opening must come back to the tab the user was on.*

As a user,
I want the expanded view to come back to the tab I was on when I re-open it shortly after closing,
So that a quick close does not throw away where I was.

**Requirements:** PRD FR-6, AD-8 (`[general] home_after`), UX-DR83

**Acceptance Criteria:**

**Given** `[general] home_after` (duration, default `"2m"`; `"never"` = always keep the last tab; `"0s"` = always return to Home)
**When** the expanded view opens
**Then** it shows the last selected tab if it was closed less than `home_after` ago, and Home otherwise

**Given** an explicit request (`vigie expand --tab <id>`, an alert's Open action, a module hotkey)
**When** the view opens
**Then** the requested tab wins regardless of `home_after`

**Given** Settings › General
**When** the control shows
**Then** it reads `Return to Home after` with choices `Immediately`, `30 s`, `2 min`, `10 min`, `Never`

**Given** unit tests with a fake clock
**When** the view closes and re-opens inside and outside the window, and with `never` and `0s`
**Then** the landing tab follows the rule

## Epic 12: Script modules

Users extend Vigie without Swift by dropping a Markdown script file into the config folder; scripts run only after per-Mac confirmation and render as Home widgets, side-slot items or full pages.

### Story 12.1: Script module schema and output types

As a script author,
I want a published JSON Schema for script front matter and output,
So that I can write scripts that Vigie will accept.

**Requirements:** FR68, FR66, FR107 (schema version), AD-16 (no JSON Schema library), AD-18 (validation)

**Acceptance Criteria:**

**Given** `schemas/script-module.schema.json`
**When** published
**Then** it defines front matter (`id`, `name`, `icon`, `interval`, `runtime`, `widget`, `surfaces`, `side`, `settings`) and stdout output (`state`, `widget{type,value,label,detail,level}`, `action{open|run|copy}`, `notify` documented as ignored in v1) with a `schema` version

**Given** Swift `Codable` types for the same shapes in `Packages/Modules/Integrations`
**When** CI runs
**Then** a check verifies the types and the schema match (sample documents validate both ways)

### Story 12.2: Script discovery and parsing

As a script author,
I want every Markdown file in `<config folder>/modules/` recognised as a script module,
So that adding an integration is just dropping a file.

**Requirements:** FR62, FR1 (scripts enable/disable), AD-18 (ids, host-owned keys), AD-12 (watching), AD-16 (Yams)

**Acceptance Criteria:**

**Given** `*.md` files in `<config folder>/modules/`
**When** the integrations module scans (at start and on directory change)
**Then** each file is parsed: YAML front matter via Yams 6.2.x, exactly one fenced code block, the rest kept as documentation

**Given** a file with zero or several code blocks, or invalid front matter
**When** parsed
**Then** it is shown as errored with a setup-problem alert naming the file

**Given** an `id` equal to a built-in id, starting with `agents.`, or duplicated across files
**When** parsed
**Then** every file declaring it is errored with a setup-problem alert

**Given** settings using host-owned keys (`enabled`, `side`, `priority`, `surfaces`, `notify`)
**When** parsed
**Then** the file is errored

### Story 12.3: Per-Mac script confirmation

As a user,
I want a script to run only after I've reviewed the whole file on this Mac,
So that nothing synced or pulled from git executes without my consent.

**Requirements:** FR63, NFR19, UX-DR61, UX-DR71, UX-DR87, AD-18 (hash confirmations in local.toml), FR100

**Acceptance Criteria:**

**Given** a new or changed script file
**When** discovered
**Then** its state is "awaiting confirmation" (not running) and its widget shows that state
**And** (added 2026-11-07) wherever the script renders (widget, side-slot item, page, Settings › Scripts) it shows `NOT CONFIRMED` in `ink-3` with no level glyph, and clicking it opens the Script Confirmation (UX-DR87)

**Given** the user opens it from the widget or Settings › Scripts
**When** the review sheet shows
**Then** it displays the full file (documentation, front matter and code) with Confirm and Decline

**Given** Confirm
**When** chosen
**Then** `local.toml` records relative path + SHA-256 of the file bytes; the script becomes eligible to run on this Mac only

**Given** any byte of the file changes
**When** detected
**Then** the confirmation no longer matches and the script returns to awaiting confirmation

**Given** Decline
**When** chosen
**Then** the script is disabled on this Mac only (local state), and other Macs are unaffected

### Story 12.4: Script runner

As a script author,
I want my script run on its interval with its settings as environment variables and safe timeouts,
So that it behaves predictably.

**Requirements:** FR64, FR65, UX-DR87, AD-18 (runner), AD-19 (executables, secrets), NFR6

**Acceptance Criteria:**

**Given** a confirmed script with `runtime: python3` and `interval: 5m`
**When** the runner starts it
**Then** it resolves `python3` via `context.executables`, runs the code block once at startup, every 5 minutes, and on Refresh

**Given** settings
**When** the process starts
**Then** each setting is passed as `VIGIE_SETTING_<KEY>`; `secret` settings are read from SecretStore at run time and injected only into the environment

**Given** the script exceeds `min(interval, 30s)`
**When** the timeout hits
**Then** its process group is killed and the module is marked errored
**And** (added 2026-11-07) the run is recorded as `TIMED OUT · <n>S` (e.g. `TIMED OUT · 30S`), and any other failed run records its exit code, for the runs card (UX-DR87)

**Given** a non-zero exit or invalid JSON
**When** the run ends
**Then** stderr goes to the module log, the last good output stays with a warning badge, and the module is errored until the next good run

**Given** a confirmed script that has not completed a run yet (added 2026-11-07)
**When** it renders
**Then** it shows `WAITING · FIRST RUN` with no level glyph (UX-DR87)

### Story 12.5: Script widgets, side slot and pages

As a user,
I want each script rendered as a Home widget, a closed-notch item or a full page, as its file declares,
So that integrations look native.

**Requirements:** FR62 (own module), FR66, FR67, FR89 (script tabs), UX-DR36, UX-DR61, UX-DR11 (warn hue), UX-DR82, UX-DR86 (widget and side slot), PRD FR-55, AD-18 (dynamic modules, VigieUI templates), AD-24 (script text sensitive by default), A22, A39 (superseded by Story 1.7d), A43 · **Depends on:** Story 1.7d (script widget design, done 2026-11-07)

**Acceptance Criteria:**

**Given** a confirmed script
**When** registered
**Then** integrations calls `context.host.registerDynamicModule(manifest:)` so it participates in arbitration, settings and tabs as its own module, and unregisters it on removal or decline

**Given** output with `widget.type` `number`, `status` or `text`
**When** rendered by VigieUI templates
**Then** number = big numeral + label + detail + segmented 6 px bar with the warn segment in quota-warning yellow (A43); status = a 26 px glyph from the shared status vocabulary (OK ring in the idle hue, WARN triangle in quota-warning yellow, DOWN × in the failed hue) with its label, the value line and `CHECKED <n> MIN AGO` (`DOWN SINCE <time>` when down); text = `TEXT` label, value, `UPDATED <n> MIN AGO` (Story 1.7d, Direction 2)
**And** the status vocabulary is a VigieUI primitive any first- or third-party module calls with a level; no script-specific colors exist
**And** (added 2026-11-07) the card is 222 × 138 (`script-card`) with the script name and target on the left of the header and the cadence on the right; an errored script keeps its last good output with a WARN triangle badge on the meta line (UX-DR86)

**Given** `surfaces` including `side`
**When** arbitration runs
**Then** the script offers one item to the left-wing lane with its own `priority` (front matter / config, e.g. `priority = 5`; never the right wing, which is reserved for sessions); left-wing items (provider rings, script items, Time readout) sort by state then priority and the ones that don't fit collapse into the left `+X` (ruled 2026-11-07). The item renders as 16 px status glyph + level over target, or value over label for number and text (A22)
**And** (added 2026-11-07) the side-slot item's accessibility label is "<name>, <level>" (e.g. "vigie.app, OK") (UX-DR86)

**Given** `surfaces` including `page`
**When** the expanded view opens
**Then** a tab named after the script ~~shows the widget at large size across the top (118 px), its Markdown documentation (`ABOUT · FROM <file>`), and a 212 px runs card (runtime, last run with exit code and duration, next run with countdown and interval, timeout, source file) with `REVEAL` and `OPEN SOURCE`~~ **Amended 2026-11-07 (epics update run):** is registered; the page content, layout, keyboard order and labels move to Story 12.11 (split for size)

**Given** `action`
**When** the widget is clicked
**Then** `open` opens the URL, `run` runs argv via the runner, `copy` copies via `context.clipboard`

**Given** Privacy mode (Epic 21) is active (added 2026-11-07)
**When** a script widget, side-slot item or Home card renders
**Then** all script-provided text (values of text widgets, labels, details, targets) renders as fixed-width dots by default, with no way for a script to opt out (AD-24); the level shapes and labels (`OK` / `WARN` / `DOWN`), numbers and the script's module name stay

### Story 12.6: Scripts settings pane

As a user,
I want to manage scripts in Settings, including entering their secrets,
So that scripts are configured without editing files.

**Requirements:** FR63 (secrets per Mac), FR64 (Refresh), FR5, UX-DR74 (Scripts pane)

**Acceptance Criteria:**

**Given** Settings › Scripts
**When** opened
**Then** it lists scripts with state (running, errored, awaiting confirmation, declined), last run time, Refresh, Review, Enable/Disable

**Given** a script's declared settings
**When** its detail shows
**Then** generated controls appear; `secret` fields save to SecretStore on this Mac only

### Story 12.7: Example scripts and trust warning

As a new user,
I want a few working example scripts and a clear warning about running scripts,
So that I can start quickly and understand the risk.

**Requirements:** FR69 (changed), PRD FR-41, NFR19, A85

*Changed 2026-11-06: the example list is now set by PRD FR-41 (A68 resolved); the full set lives in the Script repository (Story 12.8) and the app bundles a subset.*

**Acceptance Criteria:**

**Given** the app bundle
**When** v0.3 ships
**Then** it contains the bundled subset (A85): `github-prs.md` (number widget, secret token), `site-status.md` (site up/down, status widget) and a text-widget example, each validating against the schema
**And** Settings › Scripts links to the Script repository for the other examples (CI or deploy status, revenue Stripe-style)

**Given** the README and the review sheet
**When** read
**Then** they state that scripts run unsandboxed as the user and to install only scripts you trust

### Story 12.8: Script repository with CI signing

*Added 2026-11-06 for PRD FR-44 and FR-41 (v0.3).*

As Romain (maintainer),
I want a separate curated GitHub repository of community scripts whose CI validates and signs every merged script,
So that users can install reviewed scripts and Vigie can prove where they came from.

**Requirements:** PRD FR-44, PRD FR-41 (examples live there), PRD FR-42 (signing), FR68 (schema), FR107 (schema version), addendum §4, AD-18 (amended 2026-11-06), A84, A85

**Acceptance Criteria:**

**Given** the new public repository (A84)
**When** it is set up
**Then** it holds one folder per script, branch protection requires the maintainer's review on every pull request, and PR CI validates each script's front matter and sample output against `script-module.schema.json`, failing on invalid scripts
**And** PR workflows have no access to signing secrets

**Given** the script schema
**When** extended for this story
**Then** front matter gains `author`, `source` (URL) and `version`, and the schema version is bumped (FR107)

**Given** a merge to the main branch
**When** the signing job runs in a protected GitHub environment
**Then** it signs each changed script's exact bytes with an Ed25519 private key and publishes the detached signature as `<script>.md.sig` next to the file; the key never leaves that environment

**Given** the public key
**When** the story is done
**Then** it is recorded for embedding in the app (Story 12.9), and `docs/script-signing.md` describes key rotation: a new key ships in the app's trusted list in an app update before the old one is retired

**Given** the five PRD FR-41 examples (GitHub PRs, site up/down, CI or deploy status, revenue Stripe-style, text widget)
**When** published
**Then** each lives in the repository, validates against the schema and is signed

**Given** the repository README
**When** read
**Then** it explains contributing by pull request, that a signature means "reviewed by the maintainer", not "safe", and that scripts run unsandboxed as the user
**And** it states that the license and review policy are still open (PRD §9 Q1, Q3); outside pull requests are not accepted until they are settled

### Story 12.9: Install scripts from `vigie://install` links

*Added 2026-11-06 for PRD FR-42 (v0.3).*

As a user browsing the Script repository,
I want an install link that opens Vigie and shows me the full script, its source and author before anything is installed,
So that installing a community script takes one click but never happens without my review (UJ-7).

**Requirements:** PRD FR-42, UJ-7, PRD FR-39, FR63, NFR19, NFR7, AD-16 (network allowlist amended 2026-11-06: script install and update fetches, user-initiated or user-enabled), AD-18 (Confirmation covers link installs; amended 2026-11-06), AD-20 (URL scheme in Info.plist), AD-17 (dev scheme), AD-24, PRD FR-55, UX-DR98, UX-DR100, UX-DR106, addendum §4, A84, A89

**Acceptance Criteria:**

**Given** the app's Info.plist
**When** built
**Then** it registers the `vigie` URL scheme (the dev build registers its own, A89)

**Given** ~~`vigie://install?url=<https URL>[&sig=<signature>]`~~ **Amended 2026-11-07 (epics update run):** `vigie://install?url=<https URL>[&sig=<https URL of the .sig>]` (AD-18) is opened from any website
**When** Vigie handles it (launching first if needed)
**Then** it fetches the file over HTTPS only (any other scheme is refused with a clear message), parses front matter (`name`, `author`, `source`, `version`) and validates it against the schema; an invalid file shows an error and nothing is written

**Given** a signature from `<url>.sig` or the `sig` parameter
**When** verified with Ed25519 (CryptoKit) against the trusted public keys built into the app
**Then** a valid signature shows "Verified: Vigie Script repository"; an unsigned file, an invalid signature or a file from another site gets the stronger warning, and its author shows as "claimed by the file"

**Given** the Confirmation sheet
**When** it shows
**Then** it displays the full file, source URL, author, verification state and the plain warning that scripts run unsandboxed as the user, with Confirm and Decline

**Given** Confirm
**When** chosen
**Then** the file is written atomically into `<config folder>/modules/` with its source recorded, its hash is recorded as confirmed on this Mac (Story 12.3), and it starts running
**And** on other Macs that receive it by sync it stays awaiting confirmation (PRD FR-39)
**And** (added 2026-11-07) after its first run a status widget shows `CHECKED JUST NOW` (Flow 7, UX-DR106)

**Given** Decline, closing the sheet, or a network failure
**When** the flow ends
**Then** no file is left behind
**And** (added 2026-11-07) when the download fails, the Confirmation says the file could not be downloaded and offers nothing to confirm (UX-DR100)

**Given** Privacy mode (Epic 21) is active (added 2026-11-07)
**When** any Script Confirmation shows (link install, update diff, or the local review of Story 12.3)
**Then** the script body, author, source URL and any secret fields render as fixed-width dots, and Confirm is unavailable until Privacy mode is off (nothing hidden can be confirmed, PRD FR-39); Decline still works (UX-DR98)

~~**Given** a script with the same id is already installed **When** the link is opened **Then** the flow continues as an update with a diff (Story 12.10)~~ **Moved 2026-11-07 (step 4 validation):** to Story 12.10, which builds the update diff (forward dependency removed; meaning unchanged)

### Story 12.10: Script update checks

*Added 2026-11-06 for PRD FR-43 (v0.3).*

As a user with community scripts installed from links,
I want Vigie to check them for updates, show me what changed and ask again,
So that I get fixes without ever running code I haven't seen.

**Requirements:** PRD FR-43, UJ-7, PRD FR-39, PRD FR-42 (verification on every update), UX-DR87, UX-DR106, AD-16 (amended 2026-11-06), AD-18, AD-19 (scheduler), addendum §4, A88, A89

**Acceptance Criteria:**

**Given** scripts with a recorded source and update checks on (default)
**When** the scheduler runs
**Then** each source is re-fetched over HTTPS with its signature at most once a day, off the main actor

**Given** the fetched content differs from the installed file
**When** the check ends
**Then** the script shows ~~"update available"~~ **Amended 2026-11-07 (epics update run):** an `UPDATE AVAILABLE` badge on its widget, its page and in Settings › Scripts (A88) while the confirmed version keeps running (UX-DR87, UX-DR106)

**Given** the user opens the update
**When** the sheet shows
**Then** it displays a line diff of old and new content and the new version's verification state; the stronger warning shows if the new version is not validly signed

**Given** Confirm
**When** chosen
**Then** the file is replaced atomically and the new hash is confirmed on this Mac
**And** until then the old version keeps running (PRD §11, addendum §4)

**Given** Decline
**When** chosen
**Then** the old version keeps running and Vigie does not offer that exact content again

**Given** update checks are turned off in Settings › Scripts
**When** time passes
**Then** no network call is made for script updates

**Given** a script with the same id is already installed (moved from Story 12.9, 2026-11-07)
**When** its `vigie://install` link is opened
**Then** the flow continues as an update with a diff

### Story 12.11: Script page layout, keyboard order and labels

*Added 2026-11-07 (epics update run, step 3): the script page part of UX-DR86 (Story 1.7d design), split from Story 12.5 to keep each story one dev-agent session.*

As a user with a script that declares a page,
I want its tab to show the result, documentation and run history in one readable, keyboard-reachable layout,
So that I can check a script's health and source without leaving Vigie.

**Requirements:** FR67, FR89 (script tabs), FR91, UX-DR82, UX-DR86 (script page), UX-DR87 (runs card and hero states), UX-DR63, PRD FR-8, PRD FR-55, AD-18 (VigieUI templates), AD-24 · **Depends on:** Stories 1.7d, 12.3, 12.4, 12.5

**Acceptance Criteria:**

**Given** a confirmed script whose `surfaces` include `page`
**When** its tab opens
**Then** the page uses the `script-page` grid `1fr 212px` × `118px 1fr`: the widget at large size as the hero across the top (118 px), its Markdown documentation under `ABOUT · FROM <file>` on the left, and a 212 px runs card on the right (runtime, last run with exit code and duration, next run with countdown and interval, timeout, source file, and a runs list with time, duration and exit code per run)

**Given** a run that timed out or failed
**When** the runs card lists it
**Then** the row reads `TIMED OUT · 30S` or its exit code (Story 12.4), and the hero keeps the last good output with the WARN badge

**Given** a script awaiting confirmation or not yet run
**When** its page opens
**Then** the hero shows `NOT CONFIRMED` (click opens the Script Confirmation) or `WAITING · FIRST RUN`, with no level glyph (UX-DR87)

**Given** the `REVEAL` and `OPEN SOURCE` chips
**When** clicked or activated with `↵`
**Then** `REVEAL` shows the script file in Finder and `OPEN SOURCE` opens it in the default editor for its type

**Given** keyboard focus in the page
**When** the user presses Tab
**Then** focus moves hero → About → runs list → chips, and every element is reachable without a pointer (PRD FR-8)

**Given** VoiceOver on the hero
**When** it is read
**Then** the label carries the name, level and values, e.g. "vigie.app, OK, up, 200, 142 ms, checked 2 minutes ago" (UX-DR86)

**Given** Privacy mode is active
**When** the page renders
**Then** script-provided text in the hero follows Story 12.5 (dots, no opt-out); run times, durations and exit codes stay

## Epic 13: Calendar

Users see upcoming meetings, a month grid and a countdown, get a peek at each event's own reminder times, and join video calls from the notch.

### Story 13.1: Calendar module and access

As a user,
I want Vigie to read all my calendars once I allow it,
So that the Calendar tab and my reminders use every account.

**Requirements:** FR70 (EventKit; amended 2026-11-07), FR72, FR2, FR92 (setup card), UX-DR23, UX-DR44, UX-DR60, AD-20 (calendar usage string)

**Acceptance Criteria:**

**Given** `[modules.calendar] enabled = true`
**When** the module starts
**Then** it requests calendar access via `context.permissions` (`.calendar`) only now; with `enabled = false` (default) it never asks

**Given** access is missing
**When** the Calendar tab shows
**Then** a setup card reads `Vigie can't read your calendars` with `Open System Settings` and `Calendar settings` (mockup `key-calendar-tab.html` 03)

**Given** access and settings (calendars to include, reminders on/off, hide all-day)
**When** events load from EventKit (all accounts)
**Then** they feed the Calendar tab and the reminder scheduler (Story 13.4); ~~state `active` from `lead_time` before the next event, `alert` at its start~~ **Amended 2026-11-07 (user ruling):** there is no lead-time state and no `lead_time` key

**Given** the closed notch
**When** it renders
**Then** Calendar offers no left-wing item and no compact view (no persistent calendar glance, amended 2026-11-07); events reach the notch only as reminder peeks (Story 13.4)

### Story 13.2: Month grid

As a user,
I want an Itsycal-style month grid with my calendars' dots,
So that I see my month at a glance and pick a day.

**Requirements:** FR71 (grid), UX-DR34, UX-DR52, UX-DR79, UX-DR60 (no events today)

**Acceptance Criteria:**

**Given** the Calendar tab
**When** it renders
**Then** a 300 px card shows `NOVEMBER 2026` with `‹ ● ›`, Monday-first initials, ISO week numbers, 36×37 day cells, one dot per calendar with events that day in its EventKit color, adjacent-month days dimmed, today outlined in the now color

**Given** the user clicks a day
**When** selected
**Then** it gets the platinum tint and the upcoming list starts at that day

**Given** `‹` or `›`
**When** clicked
**Then** only the grid month changes; the header dot lights and returns to today and the current month when clicked

**Given** no events today
**When** rendered
**Then** today has no dot and the list shows `NO EVENTS TODAY` then the following days

### Story 13.3: Upcoming list, countdown and Join call

As a user,
I want the next events listed with a countdown and a Join call button for video meetings,
So that I can join with one key.

**Requirements:** FR70 (join), FR71 (list), FR91 (↵ Join call), UX-DR35, UX-DR25, UX-DR98, PRD FR-55, AD-24

**Acceptance Criteria:**

**Given** the upcoming list
**When** it renders
**Then** it groups by day headers (`TODAY · WED 04 NOV`), shows all-day events as header chips, at most 5 events then `+N LATER THIS WEEK`

**Given** the next event
**When** rendered
**Then** it is a hero row with big time, title, `IN 42 MIN` in the now color, and a 1 px track from now to the event with a now marker

**Given** an event with a Meet, Zoom or Teams link
**When** the user clicks `JOIN CALL ↵` or presses ↵ on it
**Then** the link opens; events without a link have no Join button

**Given** the Home calendar card
**When** shown
**Then** it reuses the event track for the next event

**Given** Privacy mode (Epic 21) is active (added 2026-11-07)
**When** the upcoming list, hero row and Home calendar card render
**Then** event titles and calendar names render as fixed-width dots; times, countdowns, day headers, the event track and `JOIN CALL` stay and work as usual

### Story 13.4: Calendar reminder alerts

As a user with meetings in my calendars,
I want an event to peek in the notch at the reminder times I set on it in Calendar, like a blocked agent does,
So that I get the meeting warning I chose without a calendar glance taking space in the closed notch.

**Requirements:** PRD FR-50 (amended 2026-11-07), PRD FR-51 (Join call), PRD FR-11, PRD FR-35 (calendar-reminder sound), FR70, FR72, AD-13 (amended 2026-11-07: `calendar.reminder` kind and `[sounds] calendar_reminder`), A21 (`after_focus`), PRD FR-55 (Privacy mode), UX-DR91, UX-DR93 · **Design:** DESIGN Peek alert panel → Calendar reminder (spine-only, no mockup)

**Acceptance Criteria:**

**Given** `[modules.calendar] reminders = true` (default) and an event in an included calendar with one or more alarms in Calendar (EventKit, relative or absolute)
**When** an alarm time arrives
**Then** the module posts `calendar.reminder` through the Notifier (declared in its manifest), which peeks once on the display under the pointer without taking focus, routed by the user's rules like any alert

**Given** an event with no alarm, a location-based alarm [ASSUMPTION], an all-day event hidden by settings [ASSUMPTION], or `reminders = false`
**When** time passes
**Then** no alert is raised, and nothing calendar-related ever shows in the closed notch

**Given** the reminder peek
**When** it shows
**Then** it uses the peek anatomy with the now accent (A `iris-1`, C `gold`), kicker `CALENDAR · IN 10 MIN` (or `CALENDAR · NOW`), title the event title, detail time range and calendar [ASSUMPTION: copy]
**And** it has two actions: `JOIN CALL ⌥⌘↵` when the event has a Meet, Zoom or Teams link [ASSUMPTION], otherwise `OPEN CALENDAR ⌥⌘↵` (Calendar tab, upcoming list at that event), and `DISMISS ⌥⌘⌫`; shortcuts are registered only while the peek is visible and each button's accessibility label includes its shortcut; the peek posts a VoiceOver announcement
**And** in the peek queue it ranks with break due and Timer end (below blocked / failed, above quota warning)
**And** (added 2026-11-07) its beacon is the 26 px event-track mark in the now accent, never a status hue or the calendar's color, and after the peek retracts nothing remains on the closed notch (UX-DR91)

**Given** Do Not Disturb or a macOS Focus mode
**When** an alarm time arrives
**Then** no peek and no sound; when the Focus mode ends, `[notify] after_focus = "drop"` drops it and `"replay"` shows the latest reminder for an event that has not ended (the alert resolves at the event's end [ASSUMPTION])

**Given** an alarm time that passed while the Mac slept
**When** the Mac wakes
**Then** the reminder is raised once if its event has not ended [ASSUMPTION]

**Given** `[sounds] calendar_reminder` set to a sound (default `"off"` [ASSUMPTION])
**When** the reminder peeks
**Then** the sound plays once, following Do Not Disturb; Settings › Sounds lists calendar reminder, off by default

**Given** Privacy mode is on
**When** the reminder peeks (or posts a macOS notification)
**Then** the event title and calendar name are hidden (fixed-width dots); macOS notifications carry only the kind label

## Epic 14: Gemini CLI support

Users who run Gemini CLI get its sessions (and usage if available); any agent that offers no hooks or logs still shows presence.

### Story 14.1: Gemini CLI adapter

As a Gemini CLI user,
I want my Gemini sessions tracked like Claude's and Codex's,
So that all my agents are in one place.

**Requirements:** FR84, FR85, FR35, FR80, NFR18, A45

**Acceptance Criteria:**

**Given** the installed Gemini CLI
**When** research runs first
**Then** fixtures and a note under `Packages/Adapters/Gemini/Tests/Fixtures/<cli-version>/` record whether hooks exist, the session/telemetry file locations, and which normalized events are observable

**Given** hooks are supported
**When** the user connects Gemini
**Then** the adapter's `integrationPlan` adds `<symlink> hook gemini` entries via `IntegrationInstaller` after diff confirmation; otherwise it uses transcript watching

**Given** unobservable events
**When** Settings › Agents › Gemini renders
**Then** it states which statuses can't be shown

**Given** an unsupported version
**When** detected
**Then** no statuses are emitted and a setup-problem alert is raised

### Story 14.2: Process-only presence tier

As a user of an agent with neither hooks nor readable logs,
I want at least to see that it is running,
So that I know a session exists even without status.

**Requirements:** FR81 (process-only), UX-DR56 (grey dot), UX-DR81, A35 (superseded by Story 1.7b) · **Depends on:** Story 1.7b (process-only look, done 2026-11-07)

**Acceptance Criteria:**

**Given** an adapter whose capabilities are process-only
**When** a matching agent process is found by a periodic process scan (every 10 s)
**Then** a presence-only session appears with the process-only look designed in Story 1.7b (a plain filled dot in `ink-3`, no ring, no hue, static), label `RUNNING` and last-action line `Process seen · no hook events`, sorted after idle, no idle/working/blocked status and no alerts
**And** (added 2026-11-07) Focus still works on the row (at its terminal's focus level); the glyph is static in every Presence mode with no row tint; its accessibility label reads "<project>, running, no status available" (UX-DR81)

**Given** the process exits
**When** liveness runs
**Then** the presence session is removed

### Story 14.3: Gemini usage provider

As a Gemini CLI user,
I want my Gemini usage (daily quota) shown if Gemini exposes it locally,
So that I track it alongside my other agents.

**Requirements:** FR56, FR47, UX-DR78 (daily window), PRD FR-29, A46

**Acceptance Criteria:**

**Given** the 14.1 research found a usable local source
**When** ingested through the Gemini `logReader`
**Then** the `gemini` provider contributes tokens/cost and, if available, a daily window shown as a single ring and `DAILY QUOTA ONLY` card meta

**Given** no usable source exists
**When** the story closes
**Then** the decision is recorded and Settings › Agents › Gemini states that usage is not available (A46)

**Given** a usable source and several Gemini Accounts (Story 7.10)
**When** usage is ingested
**Then** each Account's location is read separately (added 2026-11-06)

## Epic 15: Encrypted quick notes

Users write quick Markdown notes with masked secrets in a floating panel, stored end-to-end encrypted and readable on their other Macs.

### Story 15.1: Notes key setup and recovery

As a user,
I want my notes encrypted with one key that follows me to my other Macs, with a recovery key as backup,
So that only Vigie on my Macs can read my notes, and I never end up with two keys.

**Requirements:** FR103, AD-9 (notes key group, synchronizable), AD-10 (key rules), UX-DR100, NFR6, NFR20

**Acceptance Criteria:**

**Given** `Packages/Modules/Notes` enabled and no notes key
**When** the user clicks "Set up notes" (explicit action)
**Then** a key is created as a synchronizable iCloud Keychain item in `<TeamID>.<release bundle id>.notes`, and a recovery key is shown once for the user to save (with copy and "I saved it" confirmation)

**Given** the notes folder already contains note files or a key may exist in iCloud Keychain
**When** setup runs
**Then** no new key is created; Vigie shows a waiting state and offers "Enter recovery key"
**And** (added 2026-11-07) the floating panel and the Notes tab show `NOTES LOCKED` + "Waiting for iCloud Keychain, or enter your recovery key." (UX-DR100)

**Given** iCloud Keychain is off
**When** the key is created
**Then** it stays local and Settings states that the recovery key is the only way to read notes on another Mac

**Given** Vigie Dev cannot read the release notes key
**When** notes start in the dev build
**Then** it uses its own notes folder

### Story 15.2: Encrypted note storage

As a user,
I want each note stored as its own encrypted file in a folder I choose,
So that notes sync per file and can't be read outside Vigie.

**Requirements:** FR76, NFR20, AD-10 (amended 2026-11-07: sync conflicts keep both versions), AD-11 (userFolder), AD-12, UX-DR100, Conventions (never log note content)

**Acceptance Criteria:**

**Given** `[modules.notes] folder` (default `~/Notes/Vigie`, `.local` scope)
**When** a note is saved
**Then** it is written via `context.storage.userFolder(setting:)` as one file with a plaintext header `{format, key_id}` followed by CryptoKit authenticated ciphertext; plaintext never touches disk or logs

**Given** a note file whose `key_id` Vigie doesn't hold
**When** the folder is read
**Then** the module shows the waiting / enter-recovery-key state and writes nothing

**Given** another Mac edits a note
**When** the file changes (directory watcher, `NSFileCoordinator` off main)
**Then** the note reloads; ~~concurrent edits resolve last writer wins per file~~ **Amended 2026-11-07 (AD-10 amended, user ruling):** on a sync conflict (unresolved `NSFileVersion` conflict versions) the current version is kept, each other version is saved as a new encrypted note `<title> (conflict)`, and the conflict versions are then marked resolved; no text is lost (UX-DR100)

### Story 15.3: Floating notes panel

As a user,
I want a global shortcut that opens a floating panel to jot a note,
So that I can capture something without opening the notch.

**Requirements:** FR73, UX-DR37, UX-DR45 (deliberate focus), UX-DR98, PRD FR-55, AD-13 (only window a module may request), AD-24, A30

**Acceptance Criteria:**

**Given** the notes hotkey (default `opt+cmd+n` ⌥⌘N, A30 ruled 2026-11-06, registered as `notes.open`)
**When** pressed
**Then** a 460×372 floating panel (no band, iris filament, `notes-panel` radius) opens centred below the menu bar via `context.host` with a `UserIntent` and takes keyboard focus

**Given** the panel
**When** shown
**Then** the header reads `NOTES · <title>` with `SYNCED · ENCRYPTED · ESC`, the footer `EDITED HH:MM`

**Given** the panel is focused
**When** the user presses Esc
**Then** it closes and focus returns to the previous app; the note is saved

**Given** Privacy mode (Epic 21) is active (added 2026-11-07)
**When** the floating panel shows
**Then** the note title and body render as fixed-width dots in `ink-3` (typing still edits the note, shown as dots like a password field); `SYNCED · ENCRYPTED · ESC` and `EDITED HH:MM` stay

### Story 15.4: Secret syntax, masking and copy

As a user pasting passwords into notes,
I want secrets masked at a fixed width, revealed on click, and copied without being shown,
So that shoulder-surfers and screenshots don't leak them.

**Requirements:** FR74, FR75, UX-DR38, UX-DR53, UX-DR98, PRD FR-55, AD-19 (clipboard), AD-16 (swift-markdown), AD-24, A4

**Acceptance Criteria:**

**Given** Markdown parsed with swift-markdown 0.8.x
**When** a note contains `||…||` or a ```` ```secret ```` block
**Then** inline secrets render as fixed-width dots in a chip and blocks as a `SECRET · N LINES` card with `REVEAL` / `COPY`

**Given** a masked secret
**When** clicked
**Then** reveal toggles; `COPY` copies the plain value without revealing it via `context.clipboard.copy(_:clearAfter:)`

**Given** a copy
**When** done
**Then** the footer shows `COPIED · CLEARS IN 30S` with a draining line and the clipboard is cleared after `clipboard_clear` (default 30 s) if it still holds that value

**Given** any list or summary
**When** a note is summarized
**Then** secret text never appears, only `N SECRETS`

**Given** Privacy mode (Epic 21) is active (added 2026-11-07)
**When** the user clicks a masked secret or `REVEAL`
**Then** nothing is revealed (reveal is unavailable); `COPY` still copies the value without revealing it (UX-DR98)

### Story 15.5: Notes tab

As a user,
I want a Notes tab listing my notes with search and a masked preview,
So that I can find and reuse a note quickly.

**Requirements:** FR77, FR75, UX-DR38, UX-DR41 (Notes layout), UX-DR98, UX-DR100, PRD FR-55, AD-24, FR91 (↑↓)

**Acceptance Criteria:**

**Given** the Notes tab (mockup `key-notes.html`)
**When** it renders
**Then** a 232 px list shows title, last edit and a summary line with only the secret count, with search field and note count on top, and the selected note previews on the right with every secret masked

**Given** focus in the tab
**When** the user types in search or presses ↑↓
**Then** the list filters by title and non-secret text, and the selection moves

**Given** the notes module
**When** arbitration runs
**Then** it has no closed-notch presence (state always hidden)

**Given** no notes, or a search with no result (added 2026-11-07)
**When** the tab renders
**Then** it shows `NO NOTES` + "Press ⌥⌘N to write one.", or `NO MATCH` (UX-DR100)

**Given** Privacy mode (Epic 21) is active (added 2026-11-07)
**When** the tab renders
**Then** note titles, summary lines and the preview render as fixed-width dots in `ink-3`; the note count, edit times and `N SECRETS` counts stay (UX-DR98)

## Epic 16: Portable config and iCloud sync

Users choose where their config lives (git, iCloud) and optionally sync config and notes across Macs, with machine-specific settings and secrets staying local.

### Story 16.1: Choose the config folder location

As a user who keeps dotfiles in git,
I want to point Vigie at a config folder of my choice,
So that `config.toml`, themes and scripts live in my repo.

**Requirements:** FR101, FR100, AD-12 (only ConfigStore relocates), AD-8

**Acceptance Criteria:**

**Given** Settings › General › Config folder
**When** the user picks a folder
**Then** ConfigStore moves (or adopts, if the folder already has a `config.toml`) the config, records the location in `local.toml`, and reloads live

**Given** the config folder is a symlink or inside a git checkout
**When** ConfigStore writes
**Then** it writes atomically to the symlink-resolved path and only the changed lines differ (git diff shows one line)

### Story 16.2: iCloud sync toggle

As a user with two Macs,
I want one switch that syncs my config and notes through iCloud Drive,
So that both Macs share personalization without any server.

**Requirements:** FR102, FR76 (sync), AD-12, NFR6

**Acceptance Criteria:**

**Given** `[sync] icloud = false`
**When** the user turns it on in Settings › Sync
**Then** ConfigStore moves the config folder and the notes folder into `iCloud Drive/Vigie/`, records the new locations in `local.toml`, and Vigie keeps working without restart

**Given** it is turned off
**When** confirmed
**Then** both folders move back to their local defaults

**Given** a synced file not yet downloaded (dataless)
**When** Vigie reads it
**Then** it checks `ubiquitousItemDownloadingStatus`, calls `startDownloadingUbiquitousItem`, keeps the last good value meanwhile, and reads via `NSFileCoordinator` off the main actor

**Given** sync is on
**When** files are inspected in iCloud Drive
**Then** they contain no secrets and no `.local` settings

### Story 16.3: Two-Mac behavior check (Flow 5)

As Romain with a MacBook and a Mac Studio,
I want synced personalization to apply on both Macs while machine settings, secrets and script confirmations stay per Mac,
So that sync never runs code or leaks secrets.

**Requirements:** FR100, FR63, UX-DR71, NFR6, NFR19

**Acceptance Criteria:**

**Given** two Macs with sync on
**When** Mac A changes theme and a status color
**Then** Mac B applies them live; Mac B's display, virtual-notch and terminal settings are unchanged

**Given** Mac A adds a script with a secret token and confirms it
**When** the file syncs to Mac B
**Then** on Mac B it shows awaiting confirmation, doesn't run, and has no token until entered there (Flow 5)

**Given** Mac A declines a script
**When** Mac B has confirmed it
**Then** Mac B keeps running it

## Epic 17: Onboarding and settings polish

New users are guided through setup on first launch; everyone gets a complete Settings window, diagnostics and a warning when another notch app runs. (The donation option, Story 17.3, is superseded 2026-11-06 by PRD §9 Q1 and not reinstated by the 2026-11-25 GNU GPLv3 license change.)

### Story 17.1: First-launch onboarding

As a new user,
I want a short guided setup on first launch that I can skip at any step,
So that Vigie is configured for my agents, terminals and displays in a minute.

**Requirements:** FR94, UX-DR75, UX-DR69, UX-DR39, AD-4 (onboarding composition), AD-21 (SMAppService), AD-22, A31, A60, A61

**Acceptance Criteria:**

**Given** first launch (no onboarding-complete flag in `local.toml`)
**When** Vigie starts
**Then** a native onboarding window opens (no Dock icon) with steps in order: theme (live preview of Chrome Hologram and Twin Metal Tactical, skip → Chrome Hologram), agents (detected CLIs with their hook diffs via `IntegrationInstaller`), Accessibility, displays (always asks about non-notch displays, offering a virtual notch per display; reuses the v0.1 display prompt of Story 2.7, A60), sounds on/off, launch at login (preselected on; sets the v0.1 `[general] launch_at_login` toggle of Story 2.14, A61)
**And** every step has Skip

**Given** steps contributed by modules through ModuleKit
**When** App assembly builds onboarding
**Then** adapter-related steps are composed there, not in modules

**Given** the sounds step is skipped
**When** onboarding finishes
**Then** `[sounds] enabled = false` (A31)

**Given** onboarding completes or is skipped entirely
**When** Vigie launches next time
**Then** onboarding doesn't reappear (Settings › General has "Run setup again")

### Story 17.2: Complete Settings window

As a user,
I want every pane the UX defines, with the right extras such as the Reduce motion warning and color contrast,
So that every option is discoverable without TOML.

**Requirements:** FR93, FR41, UX-DR74 (Support pane superseded; amended 2026-11-07), UX-DR97 (Settings › Home), UX-DR13 (contrast display), UX-DR64 (warning), UX-DR73, PRD FR-7, PRD FR-58, A13, A32, A89

**Acceptance Criteria:**

**Given** Settings
**When** opened
**Then** panes are ~~General, Appearance, Displays, Agents, Usage, Shelf, Time, Calendar, Notes, Scripts, Sounds, Sync, Updates~~ **Amended 2026-11-07 (epics update run):** General (with Launch at login, the activity log and the Privacy mode controls), Appearance, Displays, Home (Story 11.1 list), Agents, Usage, Shelf, Calendar, Time, Notes, Scripts, Sounds, Sync, Updates, in that order (EXPERIENCE), each with generated controls plus pane-specific views, and the Privacy mode controls sit where A89 places them
**And** there is no Support pane (superseded by PRD §9 Q1; changed 2026-11-06)

**Given** Appearance
**When** the user picks a custom status color
**Then** its contrast ratio against the current look's surface is shown, without blocking the choice

**Given** macOS Reduce motion is on
**When** Appearance › Presence shows
**Then** a note explains that Reduce motion forces calm

**Given** entry points
**When** the user presses `⌘,` in the expanded view, clicks the expanded-view settings icon (Story 2.10), picks `Settings…` from the notch context menu, or clicks Open settings in an alert or empty state
**Then** Settings opens on the relevant pane

### Story 17.3: Support and donation prompt — SUPERSEDED

> **[SUPERSEDED 2026-11-06]** by PRD §9 Q1 and the memlog decision "start closed source with no license (all rights reserved)": SPEC §2.1 donationware and the EXPERIENCE Settings Support pane are superseded until a business model is chosen. Do not implement. FR109 and A33 are superseded with it. Kept for history.


As a user who likes Vigie,
I want an easy way to support it and at most one gentle reminder,
So that the project is sustainable without nagging me.

**Requirements:** FR109, A33

**Acceptance Criteria:**

**Given** Settings › Support
**When** opened
**Then** it links GitHub Sponsors and Ko-fi/Buy Me a Coffee; no feature is gated

**Given** 21 days of use since first launch (A33)
**When** the user next opens the expanded view
**Then** one dismissible support message appears in the expanded view (never a peek, never focus-stealing); once dismissed it never returns (stored in `local.toml`)

### Story 17.4: Copy diagnostics

As a user reporting a bug,
I want one button that copies useful diagnostics without secrets,
So that I can file an issue easily and safely.

**Requirements:** AD-16 (Copy diagnostics), NFR6, NFR7

**Acceptance Criteria:**

**Given** Settings › General › Copy diagnostics
**When** clicked
**Then** the clipboard receives app version/build, macOS version, display kinds, enabled modules, adapter versions and support status, recent setup problems, and recent log lines for Vigie's subsystem

**Given** the diagnostics text
**When** generated
**Then** it contains no secret values, tokens, note content or script secret settings (test with seeded secrets)

**Given** the action
**When** performed
**Then** nothing is sent over the network

### Story 17.5: Warn about other notch apps

As a user who also has another notch app installed,
I want Vigie to tell me when they conflict,
So that I understand why the notch looks wrong.

**Requirements:** FR110, PRD FR-60 (v0.4), A29

**Acceptance Criteria:**

**Given** a maintained list of known notch apps' bundle ids (e.g. Boring Notch, NotchNook, others found during implementation)
**When** one is running while Vigie draws on a physical notch
**Then** a setup-problem alert `Another notch app is running: <name>` explains that two apps can't share the notch, with Dismiss and Open settings › Displays

**Given** the user dismisses it
**When** the same app keeps running
**Then** the alert doesn't repeat until next launch

## Epic 18: Theme family and presence

Users choose Twin Metal Tactical or a custom theme, override any status color, and calm the motion down (automatically under Reduce motion).

### Story 18.1: Twin Metal Tactical theme

As a user,
I want the Twin Metal Tactical skin in light and dark,
So that I can pick the look I prefer with identical layout and wording.

**Requirements:** FR95, UX-DR2, UX-DR4, UX-DR5 (C radii), UX-DR14 (C ornaments), UX-DR18 (C glyph shapes), UX-DR16 (C bezel), UX-DR25 (C buttons), UX-DR27 (C tab bar), UX-DR28 (C corner marks), UX-DR77, UX-DR13, UX-DR80 (C gear), UX-DR94, A38 (superseded by Story 1.7f) · **Depends on:** Story 1.7f (C tabs and notes design, done 2026-11-07)

**Acceptance Criteria:**

**Given** DESIGN.md C tokens
**When** `themegen` runs
**Then** `Themes/twin-metal-tactical.toml` (dark and light) is generated and CI checks the diff

**Given** `[appearance] theme = "twin-metal-tactical"`
**When** applied
**Then** every surface re-skins live: square cards with inner corner marks, condensed caps labels and mono values, C glyph shapes (dot in circle, triangle in tick ring, check in circle, bracketed square, X in square frame), struct hairline + tick scale + gold tracer on the island, gold primary button frame, gold-underlined active tab, C dial bezel
**And** layout, slots and wording are identical to Chrome Hologram

**Given** C light
**When** text would be gold
**Then** it uses `c-light-gold-text`; `c-light-gold` is used only for frames, arcs, markers and fills
**And** gold is never used for decoration or session status

**Given** the C expanded tabs and notes panel designed in Story 1.7f (mockup `ux-designs/ux-vigie-2026-11-04/mockups/key-design-pass-1-7.html`, C dark and light)
**When** rendered
**Then** they follow C rules strictly, not A recolored: tab row with a 1px `line` underline, active tab in gold text with a 2px gold underline, square settings gear at the far right; square cards with inner corner marks; keyboard selection ring `ink-1` at 55% stacked on the 2px alert bar; pinned shelf items = dashed struct line + `PINNED` in `ink-1`; Calendar today outline, now marker and relative time in gold (`c-light-gold-text` for text in C light); ~~in C light, warning-yellow text only on cards~~ **Amended 2026-11-07 (epics update run):** in C light, warning-yellow text uses `c-light-quota-warning-text #7E6300` on any surface and `#8A6D00` only for hatch, triangles, arcs and fills (UX-DR13, UX-DR94)

### Story 18.2: Custom themes and color overrides

As a user,
I want to override any status, pace or warning color, or drop in my own theme file,
So that Vigie works for my eyes (e.g. color blindness) and my taste.

**Requirements:** FR95 (custom themes), FR96, UX-DR11, UX-DR12, UX-DR13, AD-14 (resolution order, ids, schema)

**Acceptance Criteria:**

**Given** `[appearance.colors] blocked = "#…"` or `[appearance.colors.dark] …`
**When** applied
**Then** resolution follows base → skin → look → custom theme → `[appearance.colors]` → `[appearance.colors.<look>]` → accessibility adjustments, live

**Given** a custom theme TOML in `<config folder>/themes/`
**When** it extends the shared base and overrides token values
**Then** it appears in Appearance and applies live

**Given** a custom theme reusing a built-in id
**When** loaded
**Then** it is ignored with a setup-problem alert

**Given** a custom theme with a newer `schema`
**When** loaded
**Then** Vigie falls back to the base theme with a setup-problem alert

### Story 18.3: Presence levels and Reduce motion

As a user who finds motion distracting,
I want a calm presence where nothing moves unless something needs me,
So that Vigie stays out of my peripheral vision.

**Requirements:** PRD FR-37, FR97, UX-DR42 (amended 2026-11-07), UX-DR64, UX-DR54, NFR10, AD-14 (presence resolved once in VigieUI), A15

**Acceptance Criteria:**

**Given** `[appearance] presence = "calm"`
**When** applied live
**Then** in A: no shimmer, rim slide or panel scan, rim = flat platinum line, working arc frozen, quota arcs flat silver, ~~only the blocked diamond pulses every `calm-pulse`~~ **Amended 2026-11-07 (epics update run):** only a blocked diamond or a failed × pulses (one halo per `calm-pulse`, PRD FR-37); in C: no tracer, bezels static and dimmer, gold → struct silver, ~~only the blocked square pulses~~ only a blocked square or a failed X frame pulses
**And** values update without transitions; with nothing blocked or failed nothing moves (mockup `key-closed-notch-states.html` i)

**Given** presence
**When** applied
**Then** it affects closed notch, peek and expanded view alike, resolved once in VigieUI

**Given** macOS Reduce motion is on
**When** Vigie renders
**Then** presence is forced to calm regardless of the setting, the remaining pulse becomes an opacity change with no scale, and T+ counters show static values
**And** this story only adds the calm-presence link; removing motion under Reduce motion already ships in v0.1 (Story 2.15, A15 ruled 2026-11-06)

### Story 18.4: Reduce transparency and Increase contrast

As a user with accessibility display settings,
I want Vigie to drop glass effects and strengthen lines when I ask macOS to,
So that it stays legible for me.

**Requirements:** FR97, UX-DR65, UX-DR13, UX-DR94, UX-DR95, NFR10, AD-14 (accessibility adjustments last), PRD FR-63, A79

*Changed 2026-11-06: Story 2.15 delivers this for Chrome Hologram in v0.1 (PRD FR-63 floor from v0.1). This story extends the same behavior to Twin Metal Tactical and custom themes and adds them to the 2.15 contrast check.*

**Acceptance Criteria:**

**Given** Reduce transparency
**When** panels render
**Then** glass gradients become flat `surface-panel` / `surface-card` fills

**Given** Increase contrast
**When** rendered
**Then** ~~hairlines move to `ink-3`~~ **Amended 2026-11-07 (epics update run):** the DESIGN Increase contrast table applies in Twin Metal Tactical and custom themes as in Story 2.15 (zone, chip and card borders including C struct inner borders become solid 1 px `ink-3`; the Ask AI dashed border is drawn at 100 % gold in C; tracks ≥ 40 % `ink-3`; focus ring 2 px with no halo; upcoming phase pips unchanged; decorative-only elements reach 3:1) (UX-DR95), and user color overrides keep their hue (contrast may be raised, never discarded)

**Given** the C dark and C light token sets (added 2026-11-07)
**When** CI runs the Story 2.15 contrast check
**Then** they are included: text pairs reach 4.5:1 and non-text meaning 3:1 (UX-DR94); for a custom theme, Appearance shows any failing pair without blocking the theme, as for custom colors (Story 17.2)

## Epic 19: Public release

Anyone can install Vigie with Homebrew and find a README that sets the right expectations, with the accessibility floor verified.

### Story 19.1: Homebrew cask

As a Mac user,
I want to install Vigie with `brew install --cask vigie`,
So that installing and updating fits my usual workflow.

**Requirements:** FR108, FR105 (tap PR step), PRD FR-62, A50 (ruled 2026-11-06: `homebrew-vigie`), A86

**Acceptance Criteria:**

**Given** a stable release
**When** `release.yml` completes
**Then** it opens a PR on the tap repository `homebrew-vigie` (`brew tap <org>/vigie`, A50) updating version and SHA-256 of the cask `vigie`

**Given** the cask
**When** reviewed
**Then** it declares `auto_updates true` and a `binary` stanza for interactive shells only (hooks keep using the `~/.local/bin` symlink)
**And** its download URL points at the public release host (A86), so the cask works while the code repository is private (added 2026-11-06)

### Story 19.2: Public release readiness

As a first-time visitor,
I want a README and an app that meet the promised floor (accessibility, privacy, trust),
So that I can adopt Vigie with confidence.

**Requirements:** NFR9, NFR21 (superseded), NFR7, NFR19, NFR26, NFR29 (footprint), UX-DR55, UX-DR63, UX-DR66, UX-DR77, UX-DR43, UX-DR103, NFR8, PRD FR-63, PRD FR-64, PRD §5, PRD §8 SM-4 / SM-C2, PRD §9 Q1

**Acceptance Criteria:**

**Given** the README
**When** published
**Then** it covers install (DMG, Homebrew), supported agents and terminals with their focus level, the script trust warning (including what a "Verified" signature does and doesn't mean), privacy (no telemetry; network calls listed, including script install and update fetches; Privacy mode), the license status "GNU GPLv3 only (GPL-3.0-only)" (changed 2026-11-25; was "all rights reserved"), and attributions for any reused permissively licensed code
**And** it contains no donation wording (changed 2026-11-06, PRD §9 Q1; the "no GPL wording" part was dropped 2026-11-25 when the license became GNU GPLv3)

**Given** an accessibility audit
**When** run against every surface
**Then** every control and glyph has a label with state, color is never the only cue, every expanded-view action is keyboard-reachable, and peek actions work via the global shortcuts; findings are fixed or filed

**Given** a copy audit
**When** all String Catalog entries are reviewed
**Then** they follow Voice and Tone, wording is identical across variants, and no banned interaction (acting on sessions, mascots, animated companions or pets, auto-open, focus on alerts, DND bypass) exists

**Given** a release build with `agents.sessions`, `agents.usage` and two Script modules enabled (added 2026-11-07)
**When** it sits idle for 10 minutes (closed notch, no drag, no peek) while Instruments or `top` samples it
**Then** average CPU is below 1 % and resident memory below 150 MB, and the run (Mac model, macOS, build, both values) is recorded in `docs/footprint.md` (NFR29, PRD SM-4)
**And** the same check is re-run and recorded at the end of each roadmap release (v0.1–v0.4), and any module that pushes either value over its limit is fixed or filed before that release (SM-C2)

**Given** the v1.0.0 tag
**When** pushed on master
**Then** the release pipeline publishes it publicly

### Story 19.3: Beta update channel

*Added 2026-11-06 (A63 ruled: no beta channel before the public release; stable only until then).*

As an early adopter,
I want to opt into beta releases,
So that I can try new versions before they reach everyone.

**Requirements:** FR106, PRD FR-61, AD-16, AD-20 (public release host), A63

**Acceptance Criteria:**

**Given** a suffixed tag (`v1.2.0-beta.1`)
**When** `release.yml` publishes it
**Then** it also generates `appcast-beta.xml` listing betas and stable releases on the public release host; `appcast.xml` keeps listing stable releases only

**Given** `[updates] channel = "beta"` (default `"stable"`), set in Settings › Updates
**When** the next check runs
**Then** the feed URL switches to `appcast-beta.xml`, and switching back to `"stable"` never downgrades an installed beta (Sparkle offers the next stable that is newer)

## Epic 20: Time

*Added 2026-11-06 for PRD §4.10 (v0.3, with Calendar). Numbered after Epic 19 to keep existing numbers; the roadmap table sets build order (A90).*

Users run named Timers, Countdowns and Pomodoro cycles from the notch, optionally see the nearest one in the closed notch, get their end as a normal Alert (sound included if configured), and get break reminders that know whether they are actually at the Mac. Uses Epics 2, 3 and 10, and the sleep events of Story 4.12.

### Story 20.1: Spike — input idle time, Away signals and permission

As Romain,
I want to know how Vigie can measure the time since the last keyboard or pointer input, and detect lock, screensaver and display sleep, on macOS 15 and later, and which permission it costs,
So that the Away service is built on a proven signal and never needs a camera.

**Requirements:** PRD FR-49 (detection), addendum §1, AD-20 (permissions), AD-25 (Away service)

**Acceptance Criteria:**

**Given** a throwaway prototype signed like the release build (Developer ID, Hardened Runtime, unsandboxed)
**When** it reads seconds since the last input event for the combined session state, on macOS 15 and the current macOS
**Then** the record states whether any permission prompt (Input Monitoring, Accessibility or other) appears, and the polling interval and CPU cost needed

**Given** a Keep-awake power assertion is held (Story 4.12)
**When** the user stops typing
**Then** the idle value still grows (assertions don't reset it)

**Given** screen lock and unlock, screensaver start and stop, display sleep and wake
**When** they happen
**Then** the notifications Vigie can observe for each are recorded with their timing

**Given** the findings
**When** the spike ends
**Then** `docs/decisions/spike-away-detection.md` records the chosen signals, permission cost, polling interval and known weak spots (passive reading or video looks Away)
**And** if a permission is needed, it proposes how Story 20.3 requests it only when break reminders are on (PRD FR-4)

### Story 20.2: Time module with Timers and Countdowns

As a user,
I want to start, pause and cancel several named Timers and Countdowns from the Time tab or a hotkey, and be alerted when one ends,
So that I keep track of short tasks without leaving what I'm doing.

**Requirements:** PRD FR-45, PRD FR-48, PRD FR-35 (timer-end sound), PRD FR-6, PRD FR-4, PRD FR-8, PRD FR-63, FR98 (extended), AD-1 (own package `Packages/Modules/Time`), AD-11 (state JSON), AD-13 (amended 2026-11-06: canonical Timer-end kind and its sound mapping), AD-19 (scheduler, hotkeys, notifier, power `sleepWake`), UX-DR88, UX-DR100, UX-DR104, A87 (Time surfaces part superseded by Story 1.7e), A89 · **Depends on:** Story 1.7e (Time surfaces design, done 2026-11-07)

**Acceptance Criteria:**

**Given** the `time` module disabled
**When** Vigie runs
**Then** it registers no hotkey, timer or job (PRD FR-4)

**Given** the Time tab
**When** opened
**Then** it shows a quick-start card on top (Pomodoro with its lengths, 5 / 10 / 25 min presets, `+ COUNTDOWN` for a Countdown to a clock time [ASSUMPTION: chip label], a custom minutes field with `START ↵`) and below it the running and paused items sorted by end time, each with a 30 px time ring in the Time accent (A cyan, C gold), label, kind and remaining time (tabular numerals) over `ENDS <time>`, and `PAUSE` / `RESUME`, `RESET`, `REMOVE`; a Countdown has only `REMOVE`; every action is keyboard-reachable (Story 1.7e)
**And** focus order is: quick start (←→ inside the button group), the minutes field, `START`, the running list (`↑↓`), then the row chips; on a selected row Space = Pause / Resume, `⌘⌫` = Remove (with undo), `⌘R` = Reset
**And** VoiceOver reads each row as, e.g., "Tea, 5 minute timer, 3 minutes 12 seconds left, ends 14:52, paused"; the ring is hidden as decoration

**Given** nothing is running (added 2026-11-07)
**When** the Time tab renders
**Then** the quick start stays, the running list shows `NOTHING RUNNING`, and the closed Time readout is hidden (UX-DR100)

**Given** the Time hotkey (A87)
**When** pressed
**Then** the expanded view opens on the Time tab with the quick start focused

**Given** several items running
**When** Vigie quits and relaunches, or the Mac sleeps
**Then** they are restored from absolute end times in the module's state file; an end that passed while asleep or not running raises its Alert once on wake or launch

**Given** an item ends
**When** the Notifier receives the Timer-end Alert
**Then** it is routed by the user's rules (peek, macOS notification, sound), Do Not Disturb wins, and the peek uses the Time accent (rim, 26 px ring beacon, kicker `TIMER · ENDED` with the end time, title `<label> / <duration>`, detail start and end) with `OPEN TIME ⌥⌘↵` and `DISMISS ⌥⌘⌫` (Story 1.7e)
**And** Settings › Sounds lists timer end with a built-in sound, off by default (`[sounds] timer_end = "off"`, SPEC v0.8)
**And** the peek posts a VoiceOver announcement (kicker, title, primary shortcut), and the Time tab keeps the ended timer as `ENDED <time>` with `DISMISS` until the user acknowledges it
**And** (added 2026-11-07) while an ended timer is unacknowledged the Time tab carries the attention marker, read by VoiceOver as "Time, needs attention" (UX-DR104)

**Given** Privacy mode (Epic 21)
**When** active
**Then** item labels are declared sensitive; remaining times still show

### Story 20.3: Away service

As a module author,
I want one shared signal telling whether the user is Present or Away,
So that break reminders, and later other modules, read one consistent source.

**Requirements:** PRD FR-49, glossary "Away", addendum §1, AD-25 (Away service; `context.away`), AD-19, AD-20 (permission per Story 20.1), PRD FR-4, A80

**Acceptance Criteria:**

**Given** the spike decision (Story 20.1)
**When** the service is built in VigieCore
**Then** it publishes Present / Away transitions with timestamps: Present when input happened within about 90 s, Away otherwise, and Away at once on screen lock, screensaver or display sleep
**And** (added 2026-11-07) modules get it only as `context.away`: a `Presence` value (`.present` / `.away(since:)`) plus a change stream (AD-25)

**Given** no module subscribes
**When** Vigie runs
**Then** the service polls nothing and requests no permission

**Given** Keep-awake holds a power assertion
**When** the user leaves the Mac
**Then** Away is still detected

**Given** the camera
**When** the service runs
**Then** it is never used

**Given** the module packages (added 2026-11-07)
**When** CI or review checks them
**Then** no module reads input idle time (Quartz) or lock, screensaver or display-sleep notifications directly; only the Away service in VigieCore does (AD-25)

**Given** the activity log (Story 3.8)
**When** a transition happens
**Then** it is logged (A80)

### Story 20.4: Break reminders

As a user who forgets to stand up,
I want a break reminder after a long stretch at the Mac that counts my break on its own when I walk away,
So that I take breaks without clicking anything (UJ-8).

**Requirements:** PRD FR-49, UJ-8, PRD FR-35 (break-reminder sound), PRD FR-63, AD-13 (amended 2026-11-06: break kind and `[sounds] break_reminder`; amended 2026-11-07: also raised by a Pomodoro work-phase end), UX-DR89, UX-DR90, UX-DR107, A21 (`after_focus`), A87 · **Depends on:** Story 1.7e (Time surfaces design, done 2026-11-07)

**Acceptance Criteria:**

**Given** break reminders enabled (off by default, A87) with defaults 55 min work and 5 min break
**When** the user has been Present for 55 min of work time
**Then** a break Alert is raised through the Notifier, routed by the user's rules and by the break reminder strength in Settings › Time
**And** (added 2026-11-07) the break Alert is the `time.break_reminder` kind, the same kind a Pomodoro work-phase end raises (Story 20.5, user ruling 2026-11-07), so both share the break peek, the `[sounds] break_reminder` sound and `BREAK DUE` persistence

**Given** `breaks.style = "peek"` (default; Settings › Time › break reminder strength)
**When** the break Alert shows
**Then** the break peek uses the Time accent with a full dashed ring beacon and three actions, the one scoped exception to the two-action peek rule: `START BREAK ⌥⌘↵` primary across the 196 px action column, then `SNOOZE 5M ⌥⌘Z` and `SKIP ⌥⌘⌫` side by side with the same secondary styling
**And** all three shortcuts are global and registered only while the break peek is visible; `⌥⌘Z` exists only there (ruled 2026-11-07); each button's accessibility label includes its shortcut, and the peek posts a VoiceOver announcement
**And** Snooze re-raises the break peek after 5 min; Skip counts no break and starts a new work cycle
**And** (added 2026-11-07) its copy follows DESIGN: kicker `BREAK · DUE` for a break reminder or the Pomodoro source (e.g. `POMODORO · LONG BREAK`) for a Pomodoro work-phase end; title e.g. `4 cycles done / 15 min break`; detail `Focused <duration> since <time>` (e.g. `Focused 1 h 40 min since 13:05`) (UX-DR90)

**Given** `breaks.style = "quiet"`
**When** the break is due
**Then** no peek and no sound; the closed-notch Time item shows a full dashed ring, `15:00` and `BREAK DUE`, static, until the break starts (Start break in the Time tab, or Away for the break length) or is skipped

**Given** a break is due (reminder or Pomodoro work-phase end) and the break peek has retracted, or `breaks.style = "quiet"`
**When** the closed notch renders, whatever `[modules.time] closed_notch` is (also `"off"`)
**Then** the left wing shows the `BREAK DUE` readout (full dashed ring + label) as a left-lane item in alert state until the break is started or skipped; Snooze keeps it showing (ruled 2026-11-07)
**And** the Time tab row in break-due state shows `START BREAK` (primary, `↵` on the selected row), `SNOOZE 5M` and `SKIP`, and the Time tab carries the attention marker
**And** a due break counts as an unresolved alert for `[notify] after_focus = "replay"`

**Given** `[sounds] break_reminder` set to a sound (default `"off"`)
**When** the break Alert is raised with `breaks.style = "peek"`
**Then** the sound plays once, following Do Not Disturb; with `"quiet"` no sound plays

**Given** the user is Away during a work period
**When** work time is counted
**Then** Away time does not count as work

**Given** the user is Away for at least the break length, at any point
**When** they come back
**Then** the break counts as taken and a new cycle starts with no action
**And** (added 2026-11-07) Away shorter than the break length counts as neither work nor break [ASSUMPTION, EXPERIENCE Flow 8] (UX-DR107)

**Given** the user stays Present after the Alert
**When** time passes
**Then** only the Notifier's reminder rule (PRD FR-10) repeats it; there is no other nagging

**Given** a Pomodoro is running (testable once Story 20.5 lands)
**When** break reminders would fire
**Then** they are paused; a fresh cycle starts when the Pomodoro stops

**Given** the Mac sleeps
**When** it wakes
**Then** the sleep counts as Away

### Story 20.5: Pomodoro

As a user,
I want to run work and break cycles with lengths I choose,
So that I pace focused work without a separate app.

**Requirements:** PRD FR-46, PRD FR-48, PRD FR-35 (break-reminder sound), UJ-8, AD-13 (~~amended 2026-11-06: Pomodoro phase kinds~~ amended 2026-11-07, user ruling: a work-phase end raises `time.break_reminder`, a break end `time.timer_end`), AD-25 (Away service), UX-DR88, UX-DR107, A87 · **Depends on:** Story 1.7e (Time surfaces design, done 2026-11-07), Story 20.3 for Away, Story 20.4 for the break peek

**Acceptance Criteria:**

**Given** the Time tab
**When** the user starts a Pomodoro
**Then** it runs work / break cycles with defaults 25 min work, 5 min break, and a 15 min long break every 4 work periods, all configurable

**Given** a phase ends
**When** the next phase is due
**Then** ~~an Alert announces the phase change through the Notifier~~ **Amended 2026-11-07 (user ruling):** the Notifier announces it: a work-phase end posts the break reminder kind `time.break_reminder`, never `time.timer_end` (break peek `START BREAK ⌥⌘↵` / `SNOOZE 5M ⌥⌘Z` / `SKIP ⌥⌘⌫` with a kicker naming the Pomodoro source, e.g. `POMODORO · LONG BREAK`; the `[sounds] break_reminder` sound; `BREAK DUE` persisting until the break is started or skipped); a break end posts `time.timer_end` with kicker `BREAK · ENDED` [ASSUMPTION, EXPERIENCE Time · ended]
**And** when a work phase ends, the break waits for the user (ruled 2026-11-07, overrides A87's auto-advance for work → break): it is announced with the break peek of Story 20.4 (`START BREAK` / `SNOOZE 5M` / `SKIP`) or, with `breaks.style = "quiet"`, the closed-notch `BREAK DUE` readout, and starts only on Start break (peek or Time tab); until the break is started or skipped, the `BREAK DUE` readout and the Time tab row behave as in Story 20.4
**And** when a break ends, the next work phase starts on its own

**Given** a running Pomodoro
**When** it is shown in the Time tab
**Then** its row shows the phase indicator (pips: done filled, current ringed in the Time accent and hatched during a break, upcoming hairline) and `WORK · CYCLE 2/4` (break phases `BREAK · 2/4`, `LONG BREAK`); work draws a solid arc, breaks a dashed arc; VoiceOver reads the pips as "Work, cycle 2 of 4"

**Given** the user is Away during a work phase (Story 20.3)
**When** Away is detected
**Then** the Pomodoro pauses: ring and value freeze in `ink-3` / `ink-2`, the row reads `AWAY · PAUSED` and `PAUSED <time>`, and `PAUSE` becomes `RESUME` (Story 1.7e, ruled 2026-11-07)
**And** when the user is Present again it resumes on its own; `RESUME` resumes it at once

**Given** a running Pomodoro
**When** the user pauses, skips the current phase or stops it
**Then** the cycle follows; only one Pomodoro runs at a time (A87)

**Given** a relaunch or sleep
**When** Vigie comes back
**Then** the Pomodoro is restored like Timers (Story 20.2)

### Story 20.6: Closed-notch time display (optional)

As a user,
I want the running item nearest to its end in the closed notch if I choose,
So that I can see time left without opening anything.

**Requirements:** PRD FR-47, PRD FR-49, FR9, FR10 (arbitration, amended 2026-11-07), UX-DR17 (readout), PRD FR-63, A87 · **Depends on:** Story 1.7e (Time surfaces design, done 2026-11-07)

**Acceptance Criteria:**

**Given** `closed_notch = "off"` (default)
**When** items run
**Then** the Time module stays hidden in the closed notch, except for a due break: `BREAK DUE` shows as a left-lane item in alert state until the break is started or skipped (Story 20.4, ruled 2026-11-07)

**Given** `closed_notch = "time" | "ring" | "both"` and at least one running item
**When** arbitration runs
**Then** the module is `active` and offers one item to the left-wing lane with `[modules.time] priority` (default 3; never the right wing); left-wing items sort by state then priority, and when this item does not fit it is counted in the left `+X`
**And** when shown, it is the nearest-to-end item in the chosen variant: `"time"` = remaining time over its label (Pomodoro: phase label, e.g. `WORK · 2/4`), `"ring"` = a 23 px ring only (accent arc = time left; solid for work and timers, dashed for breaks), `"both"` = ring + time (Story 1.7e)
**And** while Away pauses the count it shows `AWAY · PAUSED` with the ring and value frozen in `ink-3` / `ink-2`
**And** in the `"ring"` variant, Away adds a pause mark (two 1px bars) and break due a small triangle in the ring's center, so neither state relies on color alone

**Given** the readout is visible
**When** time passes
**Then** it redraws at most once per second, and only while displayed
**And** its accessibility label includes the item and the remaining time

## Epic 21: Privacy mode

*Added 2026-11-06 for PRD §4.13 (v0.2). Numbered after Epic 20 to keep existing numbers; it builds only on Epics 1–10 (A90).*

While the screen is shared or recorded, every Vigie surface shows only Status glyphs, rings and numbers, and hides every user-supplied name or text. **Done rule for later epics:** every story from Epic 11 on that renders user-supplied text (Home cards, Script widgets, Calendar titles, Notes, Time labels) declares those fields sensitive through the Story 21.2 contract, and is done only when they hide in Privacy mode.

### Story 21.1: Spike — detect screen sharing and recording

As Romain,
I want to know which method reliably detects screen sharing and recording on macOS 15 and later, and what permission it costs,
So that Privacy mode turns on by itself where possible and says so honestly where it can't.

**Requirements:** PRD FR-55, PRD §9 Q2, addendum §2, AD-20 (amended 2026-11-06: Screen Recording permission if needed)

**Acceptance Criteria:**

**Given** a prototype
**When** it is tested on macOS 15 and the current macOS while sharing in Zoom, Google Meet (browser), Microsoft Teams and a Slack huddle, and while recording with QuickTime, the screenshot toolbar and OBS
**Then** each candidate method is recorded with reliability, delay, false positives and permission cost: excluding Vigie's windows from capture (sharing type "none"), the system screen-recording indicator state, known conferencing apps sharing the screen, and a CGWindow or ScreenCaptureKit query

**Given** the findings
**When** the spike ends
**Then** `docs/decisions/spike-privacy-detection.md` chooses a method per macOS version, or "manual only", preferring one that needs no new permission

### Story 21.2: Privacy display filter

As a user sharing my screen,
I want every Vigie surface to hide names and text while keeping glyphs, rings and numbers,
So that nothing private shows to my audience.

**Requirements:** PRD FR-55, AD-24 (Privacy mode filter; `Sensitive` marking, `context.privacy`, no opt-out), AD-13 (Notifier filters macOS notifications), AD-14 / VigieUI (rendering), UX-DR98, A88

**Acceptance Criteria:**

**Given** ModuleKit and VigieUI
**When** the contract is added
**Then** ~~modules mark rendered fields as sensitive through one API, and the host exposes a single Privacy mode state that every surface reads~~ **Amended 2026-11-07 (epics update run):** VigieUI provides one `Sensitive` wrapper / `.sensitive()` modifier for view-model fields, `NotifierEvent` title and body carry the same marking, and one `PrivacyService` in VigieCore exposes `context.privacy` (read-only `isActive` plus a change stream) that every surface reads; there is no API for a module or field to opt out, and script widget text is sensitive by default (AD-24; applied when script widgets arrive in Story 12.5)

**Given** Privacy mode is active
**When** the closed notch, peeks, expanded view and Settings previews render
**Then** sensitive fields are hidden as A88 describes, while Status glyphs, rings, T+ and numbers stay
**And** (added 2026-11-07) hidden fields render as fixed-width dots in the secret-mask style in `ink-3` (length not given away); status labels, kickers, provider and module names stay; an eye-slash glyph in `ink-3` sits left of the settings gear in the expanded tab row and in the peek band, accessibility label "Privacy mode on"; nothing is added to the closed notch (UX-DR98)

**Given** the v0.1–v0.2 modules
**When** Privacy mode is active
**Then** Session titles and messages, project names (including cost by project), Shelf item names and thumbnails, Account labels and setup-problem text naming paths are hidden

**Given** an Alert posted while Privacy mode is active
**When** the Notifier sends a macOS notification
**Then** it carries only the kind label (e.g. `BLOCKED`) and no title or body

**Given** Privacy mode turns on or off
**When** the state changes
**Then** every surface updates within 1 s with no peek
**And** (added 2026-11-07) no sound plays (UX-DR98)

**Given** Privacy mode is active (added 2026-11-07)
**When** the user uses any reveal control (secret fields in Settings, and later Notes secrets, Story 15.4)
**Then** revealing is unavailable; Focus, Dismiss, Join call and drop zones work as usual (UX-DR98)

**Given** view-model unit tests for each v0.1–v0.2 surface
**When** run with Privacy mode active and seeded user text
**Then** none of the seeded strings appear

### Story 21.3: Automatic detection, manual toggle and settings

As a user who presents often,
I want Privacy mode to turn on by itself when I share or record, and to force it on when I want,
So that I never have to remember it.

**Requirements:** PRD FR-55, PRD FR-4, AD-20 (amended 2026-11-06: `.screenRecording` permission case if 21.1 needs it), AD-8, UX-DR98 (Settings copy), A88, A89

**Acceptance Criteria:**

**Given** a fresh install
**When** the `[privacy] auto` default applies
**Then** automatic detection is on by default only if the Story 21.1 method needs no new permission, and off by default if it needs Screen Recording (A88)

**Given** automatic detection on and the Story 21.1 method
**When** sharing or recording starts or stops
**Then** Privacy mode turns on or off with no user action

**Given** the chosen method needs Screen Recording
**When** the user turns automatic detection on
**Then** the permission is requested only then, through `context.permissions`; if denied, Settings shows the needs-permission state and the manual toggle still works

**Given** detection is not possible on the running macOS version
**When** Settings shows Privacy mode
**Then** ~~it says so and offers the manual toggle~~ **Amended 2026-11-07 (epics update run):** it reads "Screen sharing can't be detected on this macOS version." and offers only `Force on`

**Given** Settings › General (added 2026-11-07)
**When** the Privacy mode controls show
**Then** they read `Automatic (when sharing or recording)` and `Force on` (UX-DR98)

**Given** the manual "always on" toggle
**When** set
**Then** Privacy mode stays on until the user turns it off; the setting is machine-specific (`local.toml`)

## Validation Summary (Step 4)

- **PRD coverage (updated 2026-11-06; rechecked 2026-11-07):** 64 / 64 PRD FRs map to at least one story (see PRD traceability). 18 stories were added for PRD features that had none: 2.15, 3.8, 7.10, 8.4, 9.8, 9.9, 12.8, 12.9, 12.10, 20.1–20.6, 21.1–21.3.
- **FR coverage:** 110 / 110 active FRs map to at least one story (see FR Coverage Map); FR109 superseded. No uncovered FR.
- **NFR coverage:** ~~27 / 27 active (NFR21 superseded)~~ ~~28 / 28 active, NFR21 superseded (updated 2026-11-07: NFR29 → 19.2)~~ 29 / 29 active (updated 2026-11-25: NFR21 reinstated → 1.1, 19.2). **UX-DR coverage:** ~~79 / 79 (UX-DR74 Support pane superseded)~~ 106 / 106 active UX-DRs map to at least one story AC (UX-DR20 superseded by UX-DR83; UX-DR74 Support pane superseded; updated 2026-11-07). No uncovered requirement.
- **Update run 2026-11-07 (step 1, requirements inventory):** NFR29 and UX-DR80–UX-DR107 added, UX-DR20 superseded by UX-DR83; inventory now NFR1–NFR29 (28 active) and UX-DR1–UX-DR107. The coverage counts above were recomputed in step 3.
- **Update run 2026-11-07 (step 3, story ACs):** acceptance criteria updated so every PRD FR, NFR29, AD requirement and UX-DR1–UX-DR107 is tested by at least one story AC (changed ACs struck through and marked *Amended 2026-11-07*, new ACs marked *(added 2026-11-07)*); Stories 3.9 (peek concurrency, from 3.2) and 12.11 (script page, from 12.5) split out for size; Epic 20 build order noted (old numbers 20.1 → 20.2 → 20.5 → 20.6 → 20.3 → 20.4; renumbered in step 4 so the numbers follow it); A41 and A42 superseded; AD-13 amended (Pomodoro work-phase end = `time.break_reminder`).
- **Totals:** 21 epics; 130 stories (recounted 2026-11-07; the earlier figure of 127 was one short), of which 129 active and 1 superseded (17.3); 9.10, 3.9 and 12.11 added 2026-11-07.
- **Architecture amendments (done 2026-11-06):** stories 3.8, 7.10, 8.4, 9.8, 9.9, 12.8–12.10, 20.x, 21.x and changed 6.2/6.3 cite the amended AD-6, AD-13, AD-16, AD-18, AD-20, AD-23 and the new AD-24 (Privacy mode), AD-25 (Away service), AD-26 (activity log).
- **Starter:** no starter template; Epic 1 Story 1 is the SwiftPM-first scaffold from the Structural Seed (AD-2). Module, adapter and terminal packages are created by the first story that needs them (no big upfront package creation).
- **Data creation:** stores are created when first needed — `sessions.json` (4.5), shelf index (9.2), usage GRDB database (7.1), notes files (15.2), `local.toml` (2.3).
- **Dependencies:** every story builds only on earlier stories (Epic 21 sits in v0.2 and Epic 20 in v0.3 despite their numbers, A90); known soft forward references are guarded (2.1 sends `app.expand` only once 4.3 exists; 2.1 and 2.10 enable Settings once 2.14 lands; 20.4's Pomodoro pause is testable once 20.5 lands; 2.14 secret fields stay disabled until 7.2; 4.10/4.11 Focus uses a fallback until Epic 5). Each epic is usable without later epics.
- **File churn check:** VigieCore (host, Notifier) is touched by Epics 2, 3, 9 and 18, and `AgentsSessions` by Epics 4, 5, 8, 9, 14. The splits are kept on purpose: each epic is a roadmap release boundary (feedback from dogfooding v0.1 may change v0.2+), and the per-agent epics depend on research whose outcome is unknown.
- **Validation run 2026-11-07 (step 4, final):** coverage rechecked by script: FR1–FR111 (110 active), PRD FR-1..FR-64 (directly or through the PRD traceability table), NFR1–NFR29 (28 active) and UX-DR1–UX-DR107 (106 active) all reach at least one active story. Epic 20 renumbered so numbers follow the build order (old → new: 20.3 Pomodoro → 20.5, 20.4 Closed-notch time display → 20.6, 20.5 Away service → 20.3, 20.6 Break reminders → 20.4) and the build-order note removed; the Story 12.9 AC for re-opening an installed script's link moved to Story 12.10 (it needs 12.10's update diff); Story 2.10's gear now says Settings is enabled once Story 2.14 lands (as in 2.1); FR-63 traceability row lists 3.2 and 18.3.
- **Sizing risks:** see A47 — a few stories are at the upper end of one dev-agent session and may be split at sprint planning.
- **Architecture compliance:** ACs enforce package boundaries (AD-1), ConfigStore as single config writer (AD-8), SessionStore as single status authority (AD-5), Notifier as the only alert path (AD-13), SecretStore (AD-9), IntegrationInstaller (AD-22), ExecutableResolver and context services (AD-19), and the dev/release isolation (AD-17).

## Assumptions to rule on

Every judgement call made while running the workflow unattended. Format: **id — where — assumption** · *alternative*.

**Status after the PRD (2026-11-06).** The user has not ruled on A1–A78. Items that the final PRD or its memlog now decide are marked **[RESOLVED by …]**, **[PARTLY RESOLVED by …]** or **[SUPERSEDED by …]**, with the deciding source; their text is kept. Unmarked items still await a ruling. A79–A90 are new assumptions forced by the stories added in the reconciliation.

**Status after the rulings (2026-11-06).** The user ruled on every remaining item in one session; each is marked **[RULED 2026-11-06: …]**. Most were accepted as proposed. Changes: Reduce motion in v0.1 (A15, A79); notes hotkey ⌥⌘N (A30); Claude sign-in choice (A57); expanded-view settings icon (A32); no beta channel before the public release (A63, new Story 19.3); Launch at login and the display prompt in v0.1 (A60, A61); Focus-ended replay setting (A21); one summary wake alert (A20); Codex `notify` chaining on confirmation (A71); tap `homebrew-vigie` (A50); yellow for expiry and script warnings (A43); design before build for undesigned surfaces (A32, A35, A38, A39, A83, A87; new Story 1.7). No item awaits a ruling.

**Step 1 — documents and requirement extraction**

- **A1** **[RESOLVED by the PRD: `prds/prd-vigie-2026-11-06/prd.md` (final) is the PRD; this file's FRs are traced to it in PRD traceability]** — Step 1 — `SPEC.md` (draft v0.4) stands in for the PRD; FRs and NFRs were derived from its sections and numbered by me (FR1–FR111, NFR1–NFR28), each citing its SPEC section. · *Alternative: write a proper PRD first (bmad-prd) and re-run.*
- **A2** **[RULED 2026-11-06: accepted as proposed]** — Step 1 — Inputs used: SPEC, Architecture Spine + its `.memlog.md`, DESIGN.md + EXPERIENCE.md, mockups (linked only). Excluded: architecture `reviews/` (pre-final, already applied to the spine), UX `.memlog.md`, `.working/`, `reconcile-*.md`, root `mockups.html` (index page). · *Alternative: also mine the reviews for extra constraints.*
- **A3** **[PARTLY RESOLVED by PRD §0: the detailed documents keep winning on their own ground, except where the PRD deliberately adds or changes scope, where the PRD wins until SPEC is updated]** **[RULED 2026-11-06: remaining conflict rule accepted as proposed]** — Step 1 — Conflict rule: UX spines win on look and behavior (SPEC says so); the Architecture Spine wins on how things are built. Concretely, the wire envelope is AD-7's `{v, topic, sent_at, payload}` (not SPEC §8.1's `{topic, payload}`), the socket may move to a temp dir when its path is too long (AD-17), and EXPERIENCE's "SPEC impacts" table is treated as already applied (SPEC v0.4 matches it). · *Alternative: flag each conflict for a SPEC update before building.*
- **A4** **[PARTLY RESOLVED by PRD FR-27 (quota warning default 80 %) and FR-53 (clipboard clear default 30 s); shelf TTL 7 days still open]** **[RULED 2026-11-06: shelf TTL default 7 days; fully resolved]** — Step 1, Stories 7.6, 9.4, 15.4 — Defaults shown only in mocks are treated as decided: quota warning 80 %, shelf TTL 7 days, clipboard clear 30 s (SPEC §14.19 says "to confirm"). · *Alternative: keep them configurable but confirm values before v0.2.*
- **A5** **[PARTLY RESOLVED by PRD §5: no telemetry and no automatic crash reports are now PRD non-goals; the other architecture-derived NFRs still await a ruling]** **[RULED 2026-11-06: architecture-derived NFRs kept, accepted as proposed]** — Step 1 — NFRs include architecture-derived qualities that SPEC doesn't state (no telemetry, off-main I/O, dev/release isolation, CI test floor). · *Alternative: keep NFRs to SPEC text only and leave these as architecture constraints.*
- **A6** **[RULED 2026-11-06: accepted, except tagged items covered by Story 1.7 design parts]** — Step 1 — Every `[ASSUMPTION]` tag in DESIGN.md and EXPERIENCE.md (e.g. accessibility label format, empty-state copy, `c-light-pace-on`, 540 px reference width) is adopted as a requirement. · *Alternative: resolve each tagged item with the UX designer first.*
- **A7** **[RULED 2026-11-06: accepted as proposed]** — Step 1, Story 1.1 — No starter template; the "starter" is the SwiftPM scaffold, and module/adapter packages are created only by the first story that needs them. · *Alternative: create every package from the Structural Seed in Story 1.1.*

**Step 2 — epic design**

- **A8** **[RULED 2026-11-06: accepted as proposed]** — Step 2 — 19 epics in roadmap order; v0.1 is split into 6 epics (foundation/spikes, notch, alerts, sessions, terminal focus, release). · *Alternative: one epic per roadmap version (5 large epics).*
- **A9** **[RESOLVED by PRD §6.1: the Spikes row includes Ghostty tab focus]** — Epic 1, Story 1.6 — Added a Ghostty focus spike next to the Warp spike (SPEC's spike row names only Warp, but Ghostty is "to be investigated"). Spikes are research stories that end in a decision record. · *Alternative: investigate Ghostty inside Story 5.5.*
- **A10** **[RULED 2026-11-06: accepted as proposed]** — Epics 2–3 — The alerts epic (Notifier, peek) comes before the sessions epic, so session alerts plug into a finished pipeline; a debug-only `dev.sample` module exercises the host until real modules exist. · *Alternative: build sessions first and alerts second.*
- **A11** **[RULED 2026-11-06: accepted as proposed]** — Story 2.3 — In Epic 2, config problems are only logged and exposed; the setup-problem alert for them is wired in Story 3.4. · *Alternative: a temporary system notification in Epic 2.*
- **A12** **[RULED 2026-11-06: accepted as proposed]** — Story 2.10 — Until the Home tab exists (v0.3), the expanded view opens on the first tab (Agents). Tab order uses a new key `[general] tab_order`. · *Alternative: bring a minimal Home tab forward into v0.1.*
- **A13** **[RESOLVED by PRD §6.1 and FR-58: basic Settings in v0.1, full Settings in v0.4]** — Stories 2.14, 17.2 — A basic generated Settings window ships in v0.1 (needed by "Open settings" actions and SPEC §4.4); v0.4 "settings polish" adds the full pane set, entry points and extras. · *Alternative: config-file-only until v0.4.*
- **A14** **[RULED 2026-11-06: accepted as proposed]** — Story 2.4 — v0.1 ships Chrome Hologram in both light and dark plus the forced light/dark setting; custom themes and color overrides wait for v0.4. · *Alternative: dark only in v0.1.*
- **A15** **[RULED 2026-11-06: Reduce motion stops animations from v0.1 (Story 2.15); Story 18.3 only adds forcing calm presence]** — Story 18.3 — Calm presence and "Reduce motion forces calm" arrive in v0.4 (roadmap places presence levels there); v0.1–v0.3 always animate, even with Reduce motion on. · *Alternative: pull Reduce-motion handling into v0.1 for the accessibility floor.*
- **A16** **[RULED 2026-11-06: accepted as proposed]** — Stories 4.10, 4.11 — In Epic 4, Focus only activates the terminal app (the SPEC fallback); exact-tab focus comes with Epic 5. · *Alternative: merge Epics 4 and 5.*
- **A17** **[RESOLVED by PRD §6.1 and FR-24: four terminals in v0.1, each at the level its Spike proves]** — Stories 5.4, 5.5 — All four terminals ship in v0.1 as the roadmap says, each at the best focus level its spike finds. · *Alternative: ship Terminal.app and iTerm2 only in v0.1.*
- **A18** **[RULED 2026-11-06: accepted as proposed]** — Stories 7.4, 8.3 — A provider with only local log data (no plan percentages) draws no ring in the closed notch; it feeds history and cost only. · *Alternative: show a token-count readout instead of a ring.*

**Step 3 — open questions resolved inside stories (SPEC §14 and EXPERIENCE Open Questions)**

- **A19** **[RULED 2026-11-06: accepted as proposed]** — Story 4.9 (§14.17) — When blocked/failed sessions outnumber the slots, the most recent ones fill all slots and `+X` counts the rest; no new visual. · *Alternative: temporarily add slots, or a summary glyph.*
- **A20** **[RULED 2026-11-06: one summary alert on wake (`<n> sessions interrupted by sleep`, Open Agents); Story 4.12]** — Story 4.12 (§14.17, EXPERIENCE OQ6) — On wake with several interrupted sessions: one failed alert per session, queued. · *Alternative: one summary alert.*
- **A21** **[RULED 2026-11-06: user setting `[notify] after_focus = "drop"` (default) or `"replay"` (latest unresolved per module); Story 3.5]** — Story 3.5 (§14.20) — Alerts suppressed by Do Not Disturb are dropped, not replayed when DND ends. · *Alternative: replay the latest one per module when DND ends.*
- **A22** **[RULED 2026-11-06: accepted as proposed]** — Story 12.5 (§14.18) — A script widget in a side slot competes like any module (own `side` and `priority`) and shows one item. · *Alternative: scripts only fill a side nobody else wants.*
- **A23** **[RULED 2026-11-06: accepted as proposed]** — Stories 9.5, 9.6 (§14.16) — Ask AI launch syntax is settled by a research story before implementation; fallback pastes file paths. · *Alternative: ship paste-only first.*
- **A24** **[RULED 2026-11-06: accepted as proposed]** — Story 4.12 (§14.15) — "Host slept" = wake event + session was working at sleep time, accepting that a process that survived sleep is still marked failed. · *Alternative: also probe the process after wake and keep it working if alive.*
- **A25** **[RULED 2026-11-06: accepted as proposed]** — Story 4.14 (§14.14) — Pre-sleep warning is research only; no feature in v1. · *Alternative: drop the research.*
- **A26** **[RESOLVED by PRD FR-2 and §6.2: Dynamic Island Macs use plain mode in v1; the island display mode is after v1]** — Story 2.7, Out-of-scope (§14.10) — Island Macs run plain mode; the island spike is not storied. · *Alternative: add a spike story now for the new MacBook Pro.*
- **A27** **[RESOLVED by PRD §6.2: touch input is later]** — Out-of-scope (§14.12) — Touch input is out of scope for v1. · *Alternative: finger-sized hit targets and tap equivalents in v0.4.*
- **A28** **[RESOLVED by PRD §6.2: menu bar fallback mode is later]** — Out-of-scope (§14.13) — Menu bar fallback mode stays "Later". · *Alternative: include it as an island fallback in v0.4.*
- **A29** **[RESOLVED by PRD FR-60: coexistence warning in v0.4 (detection method still per this assumption)]** — Story 17.5 (§14.8) — Coexistence warning ships in v0.4 using a list of known notch-app bundle ids. · *Alternative: defer to Later.*
- **A30** **[RULED 2026-11-06: default notes hotkey ⌥⌘N (`opt+cmd+n`)]** — Story 15.3 (§14.19) — Default notes hotkey `cmd+shift+n`. · *Alternative: no default, user sets one.*
- **A31** **[RULED 2026-11-06: accepted: sounds off when the onboarding sound step is skipped]** — Stories 10.2, 17.1 (§14.19, EXPERIENCE OQ18) — If the onboarding sound step is skipped, sounds are off; before onboarding exists (v0.2–v0.3) the SPEC §11 example defaults apply (blocked, failed, quota on; done off). · *Alternative: sounds on by default everywhere.*
- **A32** **[RULED 2026-11-06: right-click menu accepted, plus a settings icon in the expanded view (design: Story 1.7a; Stories 2.10, 2.14, 17.2)]** **[SUPERSEDED 2026-11-07 by the Story 1.7a design: DESIGN.md / EXPERIENCE.md, `ux-designs/ux-vigie-2026-11-04/mockups/key-design-pass-1-7.html`]** — Stories 2.1, 17.2 (§14.19 Settings entry points) — New entry point: right-clicking the closed notch shows a small menu with `Settings…` and `Quit Vigie` (an accessory app otherwise has no way to quit). · *Alternative: `vigie settings` / `vigie quit` CLI commands, or Settings only from ⌘, and alerts.*
- **A33** **[SUPERSEDED 2026-11-06 by PRD §9 Q1 and memlog: no donation prompt; Story 17.3 superseded; not reinstated by the 2026-11-25 license change]** — Story 17.3 (§2.1) — "A few weeks" = 21 days; the support message appears once in the expanded view, never as a peek. · *Alternative: 30 days, or a Settings badge only.*
- **A34** **[RESOLVED by PRD FR-7: clicking a card opens that module's Tab]** — Story 11.1 — Clicking a Home card opens that module's tab (EXPERIENCE assumption). · *Alternative: cards are not clickable.*
- **A35** **[RULED 2026-11-06: design first: Story 1.7b; the proposed visuals are placeholders only]** **[SUPERSEDED 2026-11-07 by the Story 1.7b design: DESIGN.md / EXPERIENCE.md, `ux-designs/ux-vigie-2026-11-04/mockups/key-design-pass-1-7.html`]** — Stories 4.8, 14.2 (EXPERIENCE OQ8) — Undesigned visuals: stale = `?` badge in `ink-3` and label `WORKING · ?`; process-only = idle shape in `ink-3` with label `RUNNING`. · *Alternative: get these designed before Epic 4.*
- **A36** **[RULED 2026-11-06: accepted as proposed]** — Story 7.6 (EXPERIENCE OQ9) — Closed-ring quota warning = warning hue arc + triangle replacing the value (DESIGN assumption). · *Alternative: hatch pattern on the ring too.*
- **A37** **[RULED 2026-11-06: accepted as proposed]** — UX-DR2 (EXPERIENCE OQ11) — `c-light-pace-on = #4F6A00` (DESIGN assumption). · *Alternative: pick a new light Volt with the designer.*
- **A38** **[RULED 2026-11-06: design first: Story 1.7f before Story 18.1]** **[SUPERSEDED 2026-11-07 by the Story 1.7f design: DESIGN.md / EXPERIENCE.md, `ux-designs/ux-vigie-2026-11-04/mockups/key-design-pass-1-7.html`]** — Story 18.1 (EXPERIENCE OQ10) — Twin Metal Tactical expanded tabs and notes panel (not mocked) apply the C skin rules to the A layouts; Calendar "now" color is gold. · *Alternative: mock C tabs first.*
- **A39** **[RULED 2026-11-06: design first: Story 1.7d before Story 12.5]** **[SUPERSEDED 2026-11-07 by the Story 1.7d design: DESIGN.md / EXPERIENCE.md, `ux-designs/ux-vigie-2026-11-04/mockups/key-design-pass-1-7.html`]** — Story 12.5 (EXPERIENCE OQ13) — Undesigned script widgets: status = level shape (ring / triangle / ×) + label; text = value + detail; script page = large widget + the script's documentation. · *Alternative: design them before Epic 12.*
- **A40** **[RULED 2026-11-06: accepted as proposed]** — UX-DR44 (EXPERIENCE OQ14) — Empty-state copy proposed in EXPERIENCE is adopted as final. · *Alternative: copy review before release.*
- **A41** **[RULED 2026-11-06: accepted as proposed]** **[SUPERSEDED 2026-11-07 by DESIGN `motion.exit` (200 ms ease-in, provisional); Story 2.10 amended]** — Story 2.10 (EXPERIENCE OQ17) — Collapse uses the same 280 ms as `motion.enter`. · *Alternative: faster collapse (e.g. 200 ms).*
- **A42** **[RULED 2026-11-06: accepted as proposed]** **[SUPERSEDED 2026-11-07 by the DESIGN token scheme: dark `menu_bar` falls back to the black island look until dark virtual-notch tokens exist (OQ15); Story 2.6 amended]** — Story 2.6 (EXPERIENCE OQ15) — Dark-mode `menu_bar` virtual-notch style uses the dark menu-bar material and dark role set. · *Alternative: always black in dark mode.*
- **A43** **[RULED 2026-11-06: shelf-expiry and script warnings use the quota-warning yellow (Stories 9.4, 12.5; DESIGN and EXPERIENCE updated)]** — Story 9.4 (EXPERIENCE OQ22) — Shelf expiry and script warn thresholds keep the working hue (as specified), not the quota-warning yellow. · *Alternative: use quota-warning yellow.*
- **A44** **[RULED 2026-11-06: accepted as proposed]** — Story 4.8 — Ignored paths: all events of a session whose `cwd` is under an ignored path are dropped at SessionStore (no glyph, no alert). · *Alternative: track but hide from the notch.*
- **A45** **[RULED 2026-11-06: accepted as proposed]** — Stories 4.6, 8.1, 14.1 — Agent CLI facts in SPEC are unverified; each adapter story starts by recording real fixtures and confirming capabilities. · *Alternative: a separate research story per adapter.*
- **A46** **[RULED 2026-11-06: accepted as proposed]** — Story 14.3 — Gemini usage may have no usable local source; the story can close with "not available" recorded. · *Alternative: drop Gemini usage from v0.3.*
- **A47** **[RULED 2026-11-06: accepted as proposed]** — Step 4 — Some stories are at the upper end of one dev-agent session (2.5, 2.10, 4.2, 4.5, 7.7, 12.5, 17.1, 18.1) and may need splitting at sprint planning. · *Alternative: split them now.*
- **A48** **[RULED 2026-11-06: accepted as proposed]** — Epics 1, 6 — CI (`ci.yml`) is in Epic 1 so agent work is gated from day one; the signed release pipeline closes v0.1 in Epic 6. · *Alternative: release pipeline first, right after the scaffold.*
- **A49** **[RULED 2026-11-06: accepted as proposed]** — Story 6.1 (§14.9) — Apple and GitHub prerequisites (org Developer ID, App Store Connect key, provisioning profiles, Sparkle keys, `release` environment, GitHub org name such as `vigie-app`) are manual tasks for Romain, documented as a checklist. · *Alternative: a dedicated non-code setup story in Epic 1.*
- **A50** **[PARTLY RESOLVED by PRD FR-62: the cask name `vigie` is confirmed (`brew install --cask vigie`); the tap repository name is still open]** **[RULED 2026-11-06: tap repository renamed `homebrew-vigie` (Story 19.1, SPEC §12)]** — Story 19.1 — Tap repository `homebrew-notch` (as SPEC says) and cask name `vigie`. · *Alternative: rename the tap `homebrew-vigie`.*
- **A51** **[RULED 2026-11-06: accepted as proposed]** — Stories 11.2, 11.3, 12.5, 13.3 — Home cards for modules built earlier are added in Epic 11; Calendar and script cards come with their own epics. · *Alternative: each module epic ships its Home card retroactively.*
- **A52** **[RULED 2026-11-06: accepted as proposed]** — Story 3.2 — Peek rate limiting: one peek visible at a time, others queued by urgency, at least 3 s between two peeks of the same module. · *Alternative: drop queued peeks instead of queueing.*
- **A53** **[RULED 2026-11-06: accepted as proposed]** — Story 3.1 — New global `[notify]` table; `quiet_hours` format `"22:00-08:00"`. · *Alternative: rely on macOS Focus schedules only.*
- **A54** **[RULED 2026-11-06: accepted as proposed]** — Stories 3.1, 4.11 — SPEC §6's `min_working_time` is a Notifier rule condition checked against a `working_duration` metric sent with the event (keeps Notifier the only reader of notify config). · *Alternative: check it inside `agents.sessions`.*
- **A55** **[RULED 2026-11-06: accepted as proposed]** — Story 4.10 — The Agents terminal column shows the app name of the matched terminal adapter. · *Alternative: show `TERM_PROGRAM` as-is.*
- **A56** **[RULED 2026-11-06: accepted as proposed; SUPERSEDED 2026-11-08 by Story 6.5: a signed remote price table for every provider, bundled copy as fallback]** — Story 7.1 — Cost is estimated from a per-model price table bundled with the app (no online pricing, per AD-16). · *Alternative: fetch prices, which would need a new architecture decision.*
- **A57** **[RULED 2026-11-06: user chooses in Settings: paste a token (Keychain) or explicitly allow reuse of Claude Code's stored login (per Mac, revocable, read in memory only, never copied or synced); Story 7.3, AD-9 amended]** — Story 7.3 — Claude plan limits use the unofficial claude.ai endpoint with a credential the user pastes into Settings (stored as a secret). · *Alternative: reuse Claude Code's own stored OAuth credentials.*
- **A58** **[RULED 2026-11-06: accepted as proposed]** — Story 4.7 — Settings › Agents in v0.1 is the generated pane plus Connect/Disconnect buttons per adapter. · *Alternative: hooks installed only via onboarding (v0.4).*
- **A59** **[RULED 2026-11-06: accepted as proposed]** — Stories 4.12, 5.4, 9.6, 16.3, 17.1 — The five UX key flows are used as acceptance journeys on the story that completes each flow. · *Alternative: a separate end-to-end test story per release.*
- **A60** **[RULED 2026-11-06: first-launch display prompt ships in v0.1 (Story 2.7)]** — Story 17.1 — Before onboarding exists, the default display rule applies; the "always ask about non-notch displays" step arrives in v0.4. · *Alternative: a first-launch display prompt in v0.1.*
- **A61** **[RULED 2026-11-06: Launch at login toggle ships in v0.1 (Story 2.14); onboarding only offers it]** — Story 17.1 — Launch at login arrives with onboarding in v0.4 (plus a Settings toggle); earlier versions don't register for login. · *Alternative: a General toggle in v0.1.*
- **A62** **[RULED 2026-11-06: accepted as proposed]** — Story 7.3 — Plan-limit refresh every 5 minutes and when the expanded view opens; a failure raises one setup-problem alert. · *Alternative: refresh every minute; failures shown only on the card.*
- **A63** **[RULED 2026-11-06: no beta channel before the public release; stable only in v0.1 (Stories 6.2, 6.3); beta feed moves to new Story 19.3]** — Story 6.3 — The beta update channel ships in v0.1 together with stable. · *Alternative: stable only until the public release.*
- **A64** **[RESOLVED by PRD FR-24, FR-25 and memlog (Warp fallback rule): a terminal whose Spike fails ships app-level Focus and Settings states its level]** — Stories 5.4, 5.5 — If a spike finds only app-level focus, that terminal ships app-level focus and Settings says so. · *Alternative: drop that terminal from v1.*
- **A65** **[RULED 2026-11-06: accepted as proposed]** — Story 2.1 — The second-instance `app.expand` message works only once the Event Server exists (Epic 4); until then a second launch just quits. · *Alternative: build the socket in Epic 2.*
- **A66** **[PARTLY RESOLVED by PRD §6.2: the island mode, touch input, menu bar fallback, script alerts and sandboxing, Touch ID, full VoiceOver are out of v1, so no stories; the supporter edition is superseded (PRD §9 Q1); release-please and the official homebrew-cask still per this assumption]** **[RULED 2026-11-06: release-please and official homebrew-cask: no stories, accepted]** — Out-of-scope list — "Later" items, the island spike, script alerts and sandboxing, Touch ID, full VoiceOver, release-please, official homebrew-cask and the supporter edition get no stories. · *Alternative: add them as backlog epics now.*
- **A67** **[RULED 2026-11-06: accepted as proposed]** — Story 2.12 — After a denied permission, Vigie re-checks on app activation and every 30 s while a module waits. · *Alternative: re-check only when Settings opens.*
- **A68** **[RESOLVED by PRD FR-41: GitHub PRs, site up/down, CI or deploy status, revenue (Stripe-style) and a text Widget, in the Script repository with a subset bundled; see A85 for the subset]** — Story 12.7 — Example scripts: GitHub PRs (number), site status (status), one text widget. · *Alternative: BugSink and Stripe examples from EXPERIENCE.*
- **A69** **[RULED 2026-11-06: accepted as proposed]** — Story 7.4 — Default provider order = adapter registration order (claude, codex, gemini). · *Alternative: order by most recently used.*
- **A70** **[RULED 2026-11-06: accepted as proposed]** — Story 3.6 — The notifications permission is requested only when a rule uses the `system` output or shelf expiry notification is on. · *Alternative: ask at onboarding.*
- **A71** **[RULED 2026-11-06: offer to chain the existing `notify` program through Vigie's wrapper, only after diff confirmation; never silently (Story 8.1)]** — Story 8.1 — If Codex already has a different `notify` program, Vigie doesn't overwrite it; it explains the conflict and shows manual steps. · *Alternative: chain the existing program through a wrapper.*
- **A72** **[RULED 2026-11-06: accepted as proposed]** — Story 9.6 — With `agents.sessions` disabled there is no Ask AI zone; with Shelf disabled ~~only Stash disappears~~ **Stash, AirDrop and Image to Text disappear (they are Shelf zones) and Ask AI stays (amended 2026-11-07, AD-19)**. · *Alternative: Ask AI lives in Shelf.*
- **A73** **[RULED 2026-11-06: accepted as proposed]** — Story 2.10 — The band's `● Online` means the app is running and the Event Server is bound. · *Alternative: show adapter connection status.*
- **A74** **[RULED 2026-11-06: accepted as proposed]** — Stories 2.10, 11.1 — New config keys invented where SPEC had none: `[general] tab_order`, `[home] cards`, `[notify]` (`min_severity`, `cooldown`), `ignored_paths`, `stale_after`, notes `hotkey`. Listed with defaults in SPEC §11 (v0.8). · *Alternative: confirm names and add them to SPEC §11 first.*
- **A75** **[RULED 2026-11-06: accepted as proposed]** — Story 1.3 — CI lint uses `swift-format` from the toolchain (no SwiftLint, to stay inside the dependency allowlist). · *Alternative: add SwiftLint as a CI-only tool.*
- **A76** **[RULED 2026-11-06: accepted as proposed]** — Story 2.10 — Hover-to-open (opt-in) opens the expanded view without keyboard focus, since only clicks and hotkeys count as deliberate. · *Alternative: hover-open also takes focus.*
- **A77** **[RULED 2026-11-06: accepted as proposed]** — Story 4.3 — Settings › General shows a hint when `~/.local/bin` is not on the login shell PATH (hooks still work through the absolute path). · *Alternative: add it to the shell profile automatically.*
- **A78** **[RULED 2026-11-06: accepted as proposed]** — Step 3 — The workflow's halts (menus [C], approvals, per-story reviews) were skipped as instructed; Advanced Elicitation and Party Mode were not run. · *Alternative: run a review pass (bmad-review or party mode) on this file.*

**PRD reconciliation (2026-11-06) — new assumptions forced by added or changed stories**

- **A79** **[RULED 2026-11-06: accepted, with Reduce motion also in v0.1 (see A15)]** — Stories 2.15, 18.4 — PRD FR-63 ("floor from v0.1") moves Reduce transparency, Increase contrast, the 4.5:1 text check and the non-color-cue check into v0.1 for Chrome Hologram (new Story 2.15); Story 18.4 only extends them to Twin Metal Tactical and custom themes. Reduce motion forcing calm stays in v0.4 as A15 says, because the PRD puts it under FR-37 (Calm mode), not FR-63. · *Alternative: also pull Reduce motion into v0.1 (rule on A15 at the same time).*
- **A80** **[RULED 2026-11-06: accepted as proposed]** — Stories 3.8, 20.3 — The activity log is viewed in Settings › General › Activity log (read-only list, filters, per-day summary, Copy as text); it also records alert resolve and dismiss times and, from v0.3, Present/Away transitions, so SM-2 ("unnoticed for more than 10 minutes while at the Mac") can be computed. · *Alternative: a `vigie log` CLI only, or no Away data in the log.*
- **A81** **[RULED 2026-11-06: accepted as proposed]** — Story 8.4 — `vigie run` reuses the generic-agent path: identity `generic.run:<uuid per invocation>`, the command line as title, the `vigie run` process as the Session PID; `run` is therefore reserved as a `vigie agent --agent` name. · *Alternative: a dedicated `run` adapter with its own wire topic.*
- **A82** **[RULED 2026-11-06: accepted as proposed]** — Story 7.10 — An Account is a user label plus an agent config/log location (e.g. `CLAUDE_CONFIG_DIR`, `CODEX_HOME`); the hook CLI forwards those environment variables so Sessions can be attributed to an Account; the first Account uses the default location and existing setups migrate to it. · *Alternative: Accounts identified from the signed-in email in the agent's own config.*
- **A83** **[RULED 2026-11-06: design first: Story 1.7c before Stories 9.8, 9.9; the proposed placement and readout are placeholders]** **[SUPERSEDED 2026-11-07 by the Story 1.7c design: DESIGN.md / EXPERIENCE.md, `ux-designs/ux-vigie-2026-11-04/mockups/key-design-pass-1-7.html`]** — Stories 9.8, 9.9 — AirDrop and Copy text zones are undesigned: during a drag the leading wing shows Stash then AirDrop and the trailing wing Ask AI then Copy text, each reusing the existing zone look (UX-DR20, UX-DR32); both zones belong to the Shelf module (so they disappear with it); the Copy text confirmation is a 2 s in-notch readout (`COPIED · <n> LINES`), not a Notifier Alert. · *Alternative: get both zones and the confirmation designed first, or confirm through a macOS notification.*
- **A84** **[RULED 2026-11-06: accepted: public in v0.3, no outside pull requests]** — Stories 12.8, 12.9 — The Script repository is a public GitHub repository named `vigie-scripts` (the addendum's example name) under the same owner as the release host; it is set up in v0.3 but accepts no outside pull requests until its license and review policy are decided (PRD §9 Q1, Q3). · *Alternative: another name, or keep it private until those questions are settled.*
- **A85** **[RULED 2026-11-06: accepted as proposed]** — Story 12.7 — The app bundles three of the five PRD FR-41 examples (GitHub PRs, site up/down, text widget); CI or deploy status and revenue (Stripe-style) exist only in the Script repository. · *Alternative: bundle all five.*
- **A86** **[RULED 2026-11-06: accepted as proposed]** — Stories 6.2, 6.3, 19.1 — The public release host is a public, releases-only GitHub repository (e.g. `<org>/vigie-releases`) that holds DMGs, zips, checksums and both appcasts; the code repository stays private. · *Alternative: a static host (GitHub Pages, S3 or similar) for the files and appcasts.*
- **A87** **[RULED 2026-11-06: design first: Story 1.7e before Stories 20.2, 20.4–20.6; other Time details accepted]** **[Time surfaces SUPERSEDED 2026-11-07 by the Story 1.7e design (DESIGN.md / EXPERIENCE.md, `ux-designs/ux-vigie-2026-11-04/mockups/key-design-pass-1-7.html`): Time tab quick start, Pause / Reset / Remove, readout variants, break peek with three actions; other Time details stand]** — Epic 20 — Time details the PRD leaves open: one `time` hotkey with no default binding that opens the Time tab with the new-item field focused; the Timer-end peek offers Open Time (`⌥⌘↵`) and Dismiss; Pomodoro phases advance on their own (**amended 2026-11-07:** work → break waits for Start break; Away pauses a work phase and it resumes on return) and only one Pomodoro runs at a time; break reminders are off by default (PRD FR-49 "when enabled"); the Time tab, closed-notch readout and break peek reuse existing components until UX designs them. · *Alternative: design the Time surfaces first, or give the hotkey a default.*
- **A88** **[RULED 2026-11-06: accepted: automatic detection on by default only where no new permission is needed]** — Stories 12.10, 21.2, 21.3 — In Privacy mode hidden fields render as fixed-width dots in the secret-mask style, and macOS notifications carry only the kind label; automatic detection is on by default where it needs no new permission, and off by default where it needs Screen Recording. Script updates are shown as an "update available" badge on the widget and in Settings › Scripts, with no new Alert kind. · *Alternative: hide fields entirely; always default detection off; raise an Alert for script updates.*
- **A89** **[RULED 2026-11-06: accepted; new keys `[notify] after_focus`, `[general] launch_at_login`, `[updates] channel` (Story 19.3) and Claude `plan_auth` added to SPEC §11]** — Stories 9.8, 9.9, 12.9, 12.10, 17.2, 20.x, 21.3 — New config keys and names invented where SPEC and PRD have none: `[modules.shelf] airdrop`, `copy_text` (renamed `image_to_text` 2026-11-07); `[modules.integrations] update_checks`; `[modules.time]` keys (`closed_notch` — since 2026-11-07 `"off" | "time" | "ring" | "both"` plus `priority`, Pomodoro lengths, `breaks`, `breaks.work`, `breaks.length`, `breaks.style = "peek" | "quiet"` (2026-11-07), `hotkey`); `[privacy] auto` and `force` (local); the dev build registers the `vigie-dev` URL scheme (extends AD-17 isolation); Privacy mode controls live in Settings › General; a Time pane is added. Names aligned with SPEC v0.5 §11, which now lists them. · *Alternative: confirm names and add them to SPEC §11 first (as A74).*
- **A90** **[RULED 2026-11-06: accepted as proposed]** — Epic List, Epics 20, 21 — New epics are numbered 20 (Time, v0.3) and 21 (Privacy mode, v0.2) instead of renumbering; the roadmap table sets build order, and Epic 21 builds only on Epics 1–10. Stories added to existing epics take the next free number in that epic (2.15, 3.8, 7.10, 8.4, 9.8, 9.9, 12.8–12.10). · *Alternative: renumber all epics in roadmap order.*
