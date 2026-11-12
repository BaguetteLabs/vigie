# Vigie — Specification

> Name: Vigie (decided 2026-11-04). Status: draft v0.9 (updated 2026-11-07). v0.2: agent support generalized from Claude Code to any CLI agent through adapters. v0.3: plain-display behavior specified, Dynamic Island Macs and touch added as open questions. v0.4: UX spines integrated (multi-item closed notch, done/failed states, peek actions, click-to-open, pace and quota warning, Markdown script modules, encrypted notes, iCloud sync, themes, sounds, onboarding). v0.5: aligned with the PRD (closed source for now, business model undecided, `vigie run`, multiple Accounts, AirDrop and Copy text drop zones, Privacy mode, `time` module with break reminders, activity log, script install from link with signatures and updates, private code repository with public releases). v0.6: open questions ruled (Reduce motion and launch at login in v0.1, first-launch display prompt in v0.1, notes hotkey ⌥⌘N, Claude plan sign-in choice, settings icon in the expanded view, replay after Focus as a setting, one summary alert on wake, Codex `notify` chaining on confirmation, beta channel only from the public release, tap `homebrew-vigie`, yellow for expiry and script warnings, design before build for undesigned surfaces). v0.7 (2026-11-07): UX Story 1.7 design pass integrated: Copy text zone renamed Image to Text (key `image_to_text`); closed-notch drop zones replaced by the drag-only drop display; left wing becomes a shared item lane (quota rings, script side-slot items, Time readout) ordered by per-item `priority` with `+X` overflow, right wing sessions only; Pomodoro breaks wait for Start break; Away pauses a Pomodoro work phase; Time `closed_notch` readout variant and `breaks.style` (peek | quiet). v0.8 (2026-11-07): review findings applied: `defaultSide` removed; DropZone sketch aligned with AD-19 (role, cell, order, `DropPayload` sources incl. `.paste` and `.service`); Shelf off hides Stash, AirDrop and Image to Text (Ask AI stays); non-drag paths to drop zones (Send to menu, `⌘V` on the Shelf tab, Services entry `Stash in Vigie`); break peek Snooze shortcut `⌥⌘Z` and three-action exception in §5.2; `BREAK DUE` stays on the left wing until the break is started or skipped, even with `closed_notch = "off"`; ended timers stay listed until dismissed; Timer-end sound off by default; `[privacy] auto` default conditional on permissions (A88); A74 keys added to §11 (`tab_order`, `[home] cards`, `stale_after`, `ignored_paths`, `[notify]` rule keys); stale look per UX 1.7b; v0.1 roadmap completed. v0.9 (2026-11-07): user rulings: no closed-notch calendar glance; a calendar event raises a `calendar.reminder` alert (peek) at its own EventKit alarm times (`[modules.calendar] reminders`, `lead_time` removed, `[sounds] calendar_reminder` off by default); Home cards are chosen and ordered in Settings › Home, one fixed card size, no in-place edit mode; the healthy pace state is named "within pace".

A modular macOS notch companion. It works on Macs with a physical notch and on plain displays, where it shows a virtual notch. Macs with a system Dynamic Island are treated as plain displays in v1 (§14). Everything is a module, every module can be turned off, and the whole configuration lives in plain-text files.

**Architecture.** Build rules (packages, dependency direction, state, storage, wire format, config writes, secrets): [`architecture/architecture-vigie-2026-11-05/ARCHITECTURE-SPINE.md`](architecture/architecture-vigie-2026-11-05/ARCHITECTURE-SPINE.md).

**PRD.** Why, users, scope by release, success measures, positioning and risks: [`prds/prd-vigie-2026-11-06/prd.md`](prds/prd-vigie-2026-11-06/prd.md) (mechanisms and research in its [addendum](prds/prd-vigie-2026-11-06/addendum.md)).

**UX.** This file says *what* Vigie does. Look and behavior details (layout, components, states, copy, motion, tokens, flows) are owned by the UX spines: [`ux-designs/ux-vigie-2026-11-04/DESIGN.md`](ux-designs/ux-vigie-2026-11-04/DESIGN.md) (visual) and [`ux-designs/ux-vigie-2026-11-04/EXPERIENCE.md`](ux-designs/ux-vigie-2026-11-04/EXPERIENCE.md) (behavior). Where they are more detailed than this file, they win.

---

## 1. Goals and non-goals

### Goals
- **Show what matters at a glance, using as little space as possible.** Each side of the closed notch shows a few items (3 slots by default, configurable): on the left, quota rings and other non-session items by priority; on the right, session glyphs only. Overflow collapses into `+X`.
- **Never steal focus.** Vigie panels are non-activating. Vigie takes keyboard focus only when the user opens a surface deliberately (click, shortcut), never on alerts.
- **Modular by design.** Each feature is a module that can be turned off. A user who turns off everything except the shelf gets a file shelf and nothing else: no extra permissions, no background work.
- **Easy to extend without Swift.** Anyone can add an integration by dropping a script, in any language, into a folder.
- **AI coding agents first.** Session status, usage, and filtered notifications for CLI coding agents (Claude Code, Codex CLI, Gemini CLI, …) are the main use case. Each agent is supported through an adapter, and none of them is special-cased in the core. Any other long command can report the same way (`vigie run`, §7.1).
- **Small tools that belong at the top of the screen.** Around the agent core: a file shelf with drop zones (Stash, Ask AI, AirDrop, Image to Text), timers, countdowns, Pomodoro and break reminders (`time`), calendar reminders and a month view, quick encrypted notes, and script widgets. Each is a module that can be turned off.
- **Config as code.** Shared settings live in one human-editable file, in a config folder whose location the user chooses, so it can be kept in git with their dotfiles or synced through iCloud. Machine-specific settings stay in a local file; secrets stay in the Keychain (§11.1). The settings window edits the same files.

### Non-goals (v1)
- Launcher, command palette, or calculator (Raycast territory).
- Approving, denying, or otherwise acting on an agent session from the notch. The only session action is Focus.
- Mascots or personification. No animated companions or pets, ever (not only in v1).
- Showing live agent conversations in the notch.
- Media controls (possibly a later module).
- Loading compiled third-party Swift plugins at runtime.
- Mac App Store distribution (sandboxing would block hooks, Accessibility and running scripts).

---

## 2. Platform and stack

| | |
|---|---|
| OS | macOS 15+ (decided 2026-11-04: support the current release and two major versions back) |
| Language / UI | Swift, SwiftUI, AppKit where needed (`NSPanel`) |
| Distribution | Developer ID signed + notarized DMG built by GitHub Actions on tagged releases in the private code repository, published to a public releases location with the Sparkle appcast, Homebrew cask (§12) |
| Bundle ID | `fr.baguettelabs.vigie` (dev build: `fr.baguettelabs.vigie.dev`), fixed from v0.1 |
| License | None for now: closed source, all rights reserved (decided 2026-11-06, supersedes GPL-3.0). No outside contributions to the app. GPL code (e.g. Boring Notch) can't be reused. The Script repository is public with its own license (§9.6) |
| Business model | Undecided: paid or free at public release (§2.1) |
| Config | Config folder, default `~/.config/vigie/` (`config.toml`). Location user-choosable so it can live in a git repo or be synced (§11.1) |
| Machine-specific settings | Local, never synced (§11.1) |
| Data | `~/Library/Application Support/Vigie/` (shelf files, caches) |
| Notes | Notes folder, end-to-end encrypted (§7.6) |
| Scripts | `<config folder>/modules/` |
| Secrets | Keychain only (AI auth tokens, script settings marked secret); never in config files, never synced |
| Language | English first; every string goes through i18n from the first commit |

### 2.1 License and business model
- **Closed source for now** (decided 2026-11-06). The app's code repository is private and has no license (all rights reserved). This supersedes the GPL-3.0 and donationware model of earlier drafts, and the Settings "Support" pane in EXPERIENCE.md.
- **No outside contributions to the app.** Community adapters and further terminals wait until contributions are accepted.
- **Business model undecided:** paid or free at public release (§14). Until it is chosen, nothing in the app depends on it: no donation links, no support prompt, no paywall.
- **Script repository:** public, with its own license (to choose, §14). Community contributions go there (§9.6).
- **Private code, public releases.** DMGs, update archives and the Sparkle appcast must be publicly downloadable even though the code repository is private (§12).

---

## 3. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                         Vigie.app                            │
│                                                              │
│  ┌───────────────┐   ┌──────────────────────────────────┐    │
│  │ Notch Host    │◄──│ Module Registry                  │    │
│  │ - panel/window│   │ - built-in modules (Swift)       │    │
│  │ - closed view │   │ - script modules (any language)  │    │
│  │ - expanded    │   └──────────────┬───────────────────┘    │
│  │ - arbitration │                  │ ModuleContext          │
│  └───────────────┘                  ▼                        │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Core Services                                          │  │
│  │ Settings · Scheduler · Hotkeys · Notifier · Storage    │  │
│  │ Permissions · Event Server (Unix socket) · Drop Zones  │  │
│  └────────────────────────────────────────────────────────┘  │
└───────────────────────────────▲──────────────────────────────┘
                                │ JSON over Unix socket
                     ┌──────────┴──────────┐
                     │  `vigie` CLI        │  ◄── agent CLI hooks, scripts, user
                     └─────────────────────┘
```

- **Notch Host**: owns the window (non-activating `NSPanel` above the menu bar), the closed/expanded state, multi-display placement, and decides which module appears in the closed notch (§5).
- **Module Registry**: discovers, enables/disables, starts/stops modules based on config.
- **Core Services**: the only way modules interact with the system or each other. Modules never reference each other directly.
- **`vigie` CLI**: a small binary bundled in the app and symlinked into `PATH`. It sends events to the running app (`vigie event …`, `vigie hook <agent>`, `vigie agent …`, `vigie run -- <cmd>`, `vigie reload`).

---

## 4. Module system

### 4.1 Two kinds of modules

| | Built-in modules | Script modules |
|---|---|---|
| Written in | Swift, compiled into the app | Any language (bash, Python, Node, …) |
| Capabilities | Full: custom views, hotkeys, drop zones, permissions | Data only: periodic JSON output rendered by core templates |
| Use for | Agents, Shelf, Calendar, Notes, … | Integrations: APIs, status checks, counters |
| Distribution | Ships with the app | Drop a Markdown file in `<config folder>/modules/`, or install from a `vigie://install` link (§9) |

### 4.2 Built-in module protocol

```swift
protocol NotchModule: AnyObject, Identifiable {
    static var manifest: ModuleManifest { get }

    /// Current relevance; observed by the host for arbitration.
    var state: ModuleState { get }

    /// Closed-notch view for a given size. Return nil if the module can't render at that size.
    func compactView(size: CompactSize) -> AnyView?

    /// Optional summary card shown on the Home tab.
    func homeCard() -> AnyView?

    /// Optional full tab in the expanded notch.
    func expandedView() -> AnyView?

    /// Optional drop zones, laid out by the host's drop display (§4.6).
    var dropZones: [DropZone] { get }

    func start(context: ModuleContext)
    func stop()
}

struct ModuleManifest {
    let id: String                     // "agents.sessions"
    let name: String
    let icon: String                   // SF Symbol
    let permissions: Set<Permission>   // .accessibility, .calendar, .microphone, .notifications, …
    let settings: [SettingDescriptor]  // §4.4
}
// No per-module side: the right wing is agents.sessions only, the left wing is the host's item lane (§5).

enum ModuleState: Comparable { case hidden, ambient, active, alert }
enum CompactSize { case icon, short, wide }
```

### 4.3 Lifecycle

1. Module is registered (built-in) or discovered (script).
2. If `enabled = false` in config: never started, its permissions are never requested.
3. On enable: required permissions are checked and requested **only now**. If one is denied, the module is shown as "needs permission" in settings and stays stopped.
4. `start(context:)` is called. The module registers hotkeys, scheduled jobs, and event subscriptions through the context.
5. On disable or quit: `stop()` is called and the context automatically removes everything the module registered.

### 4.4 Settings schema

Modules describe their settings, and the core generates the settings UI from that description. Supported types:

| Type | Example |
|---|---|
| `bool` | Show cost in closed notch |
| `int` / `double` (min, max, step) | Alert threshold (%) |
| `string` | Label |
| `secret` | API token (stored in the Keychain, never in the config file, never synced) |
| `enum` (options) | Display mode: percent / bar / both |
| `duration` | Refresh interval: `5m` |
| `hotkey` | `opt+cmd+n` |
| `path` | Notes folder |
| `list<T>` | Ignored project paths |

A built-in module can provide a custom SwiftUI settings view **in addition to** the generated one, never in place of it, so every setting can still be edited in `config.toml`.

### 4.5 ModuleContext (core services)

Sketch only. The authoritative, complete service list is AD-19 in the architecture spine (adds `secrets`, `permissions`, `power`, `clipboard`, `executables`, `privacy`, `away`, `activity`).

```swift
protocol ModuleContext {
    var settings: ModuleSettings { get }          // typed read, change observation
    var storage: ModuleStorage { get }            // per-module directory + small key/value store
    var scheduler: Scheduler { get }              // every(interval), at(date), cron-like
    var hotkeys: HotkeyRegistry { get }           // global shortcuts, conflict detection
    var notifier: Notifier { get }                // §6
    var events: EventBus { get }                  // subscribe to Event Server topics (§8)
    var host: HostControl { get }                 // request peek/expand, open own tab
    var log: Logger { get }
}
```

### 4.6 Extension points: drop zones

Modules declare drop zones; the **host** owns and lays out the drop display (AD-19 is authoritative). Each drop zone is visually distinct (glyph, accent token, label).

```swift
struct DropZone: Sendable {
    let id: String
    let label: LocalizedStringResource   // "Ask AI"
    let glyph: String
    let accentToken: String
    let role: DropRole                   // .primary (exactly one: Stash) | .secondary
    let cell: DropCell                   // preferredColumn, preferredRow, span (columns, rows)
    let order: Int
    let accepts: [UTType]
    let handler: @Sendable (DropPayload) async -> DropResult
}
struct DropPayload { let urls: [URL]; let modifiers: EventModifiers; let source: DropSource }
enum DropSource { case dropDisplay, shelfTab, homeWidget, stashItem, paste, service }
```

Built-in:
- **Stash** (Shelf, §7.3).
- **Ask AI** (Agents module, §7.1).
- **AirDrop** (Shelf): opens the macOS AirDrop picker for the dropped items. On by default.
- **Image to Text** (Shelf, formerly Copy text): recognizes the text of a dropped image or PDF on the Mac (Vision, no network) and copies it to the clipboard, with a brief confirmation. No image leaves the Mac. Off by default.

Other examples a module could add: "Upload & copy link", "Convert to PDF", "Attach to note".

Drop zones appear in three places: in the **drop display**, a drag-only panel the host grows out of the notch only while a file is dragged over it (Stash, Ask AI, plus AirDrop and Image to Text when enabled; Esc cancels; it is not the expanded view, which collapses on focus loss; layout in the UX spines), and, rendered by the Shelf, on the Shelf tab (`SEND TO` card) and in the Home shelf widget. The host hides zones whose module or setting is off and reflows the grid. **Shelf disabled** ⇒ Stash, AirDrop and Image to Text disappear everywhere (they are Shelf zones); Ask AI stays in the drop display while `agents.sessions` is on. With no enabled zone, no drop display appears.

**Non-drag paths** (accessibility; §7.3): a `Send to` menu on Shelf items (source `.stashItem`), `⌘V` on the Shelf tab (source `.paste`), and the macOS Services entry `Stash in Vigie` (source `.service`). All need the Shelf on.

---

## 5. Closed-notch arbitration

The closed notch has two **sides** (leading and trailing, i.e. left and right of the physical or virtual notch), each showing up to `closed.slots` items (default 3, max about 4) plus a `+X` overflow (decided 2026-11-07, UX Story 1.7):
- **Trailing (right): sessions only.** `agents.sessions` renders one glyph per session plus `+X` (§7.1). No other module ever takes this side, so an alert glyph is never hidden.
- **Leading (left): a shared item lane.** Every left-wing item has a `priority`: each provider quota ring (`agents.usage`), each script side-slot item (§9), and the Time readout (§7.7). Items from all these modules are pooled and the lane shows the first `closed.slots`; the rest collapse into `+X`, exactly like sessions. Transient readouts (the Image to Text `COPIED` confirmation, §4.6) sit after the first item for their 2 s and push the last visible item into `+X` meanwhile.

### 5.1 Algorithm

Trailing side: `agents.sessions` when its `state != hidden` (urgency order inside, §7.1).

Leading side:
1. Candidates: every item offered by an enabled module whose `state != hidden` (one per provider ring, one per script with `side` in its surfaces, one for Time when `closed_notch != "off"`, or while a break is due, whatever `closed_notch` says, §7.7).
2. Sort by the item's module `state` (descending, so an `alert` item such as a quota warning comes first), then by item `priority` (ascending number = higher), then by provider `order` for rings.
3. Show the first `closed.slots` items, each asked for its compact view at the largest size the width allows, falling back to smaller sizes; the rest are counted in `+X` (readout-label style, `ink-3`), which never hides an item in `alert` while a lower one is visible.

If no module wants a side, that side is empty. On a physical notch, an empty notch is just black. On a plain display, the virtual notch shrinks to its minimum width or hides, depending on the `virtual_notch.idle` setting.

### 5.2 Alerts and peek

When a module moves to `alert`, the host may **peek**: a short partial expansion out of the notch, like an iPhone Live Activity. Peeks can be turned off globally or per module.

- **Once per event.** Each peek plays once, with an optional secondary reminder after a configurable delay. After the dwell it retracts; the closed notch keeps the state.
- **Where:** on the display under the pointer, or on the main Vigie display if the display under the pointer doesn't show Vigie.
- **Dwell:** default 5 s, configurable, paused while hovered.
- **Two actions**, each with a global shortcut registered only while the peek is visible: primary `⌥⌘↵` (e.g. Focus terminal), `⌥⌘⌫` Dismiss. Dismiss retracts the peek and cancels its reminder; it never changes module state. Never bare Esc or other common keys.
- **Exception, break peek only** (§7.7): three actions, `⌥⌘↵` Start break, `⌥⌘Z` Snooze 5m, `⌥⌘⌫` Skip. Here `⌥⌘⌫` changes state (Skip starts a new work cycle). `⌥⌘Z` is registered only while the break peek is visible. Each button shows its shortcut and its accessibility label includes it.
- **One peek at a time** [ASSUMPTION]: a newer blocked or failed alert replaces a visible peek of lower urgency; other alerts queue by urgency (blocked/failed > break due / timer end / calendar reminder > quota warning > done > setup problem) and show after the current dwell; a queued alert whose state resolved is dropped. While the expanded view is open no peek shows (the tab marker does; sounds follow the rules); while the drop display is open, peeks wait until it closes. Every peek posts a VoiceOver announcement (kicker, title, primary shortcut).
- **Never takes focus.** The app the user is typing in keeps it.
- **Settings per alert kind:** blocked, finished (done) and failed sessions each have their own on/off and reminder settings; quota warning chooses alert or visual-only (§7.2); timer end (Timer, Countdown or Pomodoro break end) and break reminder (break reminders and Pomodoro work-phase ends, §7.7) each have their own on/off, sound and reminder settings; calendar reminder (§7.5) has its own on/off and sound settings.
- **Setup-problem alert:** unsupported adapter/CLI version, invalid config, missing permission. Same frame and dwell, neutral styling, never an agent state. Actions: Open settings (on the relevant pane) and Dismiss.
- **Do Not Disturb / macOS Focus mode:** peeks and sounds are suppressed; the closed notch still updates. No bypass option. When the macOS Focus mode ends, missed alerts are dropped by default; the user can choose instead to see the latest still-unresolved alert per module (`[notify] after_focus`).
  - **Detection (Story 3.10, `docs/decisions/spike-focus-detection.md`):** Vigie ships a Focus filter, "Silence Vigie" (App Intents `SetFocusFilterIntent`, no permission or entitlement). The user adds it to each Focus that should silence Vigie (System Settings › Focus › *mode* › Focus Filters); macOS tells Vigie when that Focus turns on and off, whatever turned it on, and Vigie reads the current filter at launch. Vigie never reads the private Do Not Disturb files (they need Full Disk Access and miss scheduled Focus). Until the filter has run once (`[notify] focus_filter_ran`, local), Settings › Alerts shows a Focus row in a needs-setup state with "Open Focus settings" and a three-step how-to; nothing is shown at launch.
  - **Shortcuts fallback:** `vigie event app.focus '{"active":true}'` / `'{"active":false}'` from two Shortcuts automations per Focus ("When Turning On" / "When Turning Off", Run Immediately, Allow Running Scripts on) feeds the same state; an "on" with no later message for 12 h counts as off. Settings › Alerts shows the recipe.

Behavior details: EXPERIENCE.md (Component Patterns, Interaction Primitives).

### 5.3 Available width

- **Physical notch**: the side width is the width of the safe-area region beside the notch (from `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea`), capped by `closed.max_side_width`.
- **Virtual notch**: width set by the user. Default: same size as a MacBook notch.

### 5.4 Displays
- `display = "main" | "notched" | "all" | "<display name>"` (machine-specific, §11.1). Default: the notched display if there is one, otherwise the main display. With the MacBook lid closed (clamshell), this falls back to the main external display.
- Hidden on a display that has a full-screen app open (configurable).
- **Display kinds.** The host classifies each display as `physical` (hardware notch), `plain` (no notch, virtual notch drawn), or `island` (a Mac whose macOS draws its own Dynamic Island; behavior TBD, see §14).
- **Hot-plug.** Connecting or disconnecting a display, changing resolution or arrangement, and opening or closing the lid re-run placement live, without a restart.
- **Multiple displays (`all`).** Every notch shows the same state. The expanded view and peeks appear only on the display under the cursor (peeks fall back to the main Vigie display when that display doesn't show Vigie, §5.2).

### 5.5 Plain displays (virtual notch)
- **Menu bar overlap.** On a plain display, the menu bar has real content under the top center, and apps with long menus (Xcode, Office, Adobe) can reach it. Mitigations:
  - When idle, the virtual notch uses its minimum width (or hides, per `virtual_notch.idle`).
  - `virtual_notch.position = "center" | "right"`: `right` places it just left of the status items, away from app menus.
  - `virtual_notch.placement = "menu_bar" | "below"`: `below` puts it just under the menu bar so that it never covers menu items.
- **Height.** The virtual notch is exactly as tall as that display's menu bar (`notch_overlap` applies to the hardware cut-out only); closed-notch content scales to the band.
- **Style.** `virtual_notch.style = "black" | "menu_bar"`. `black` looks like a hardware notch. `menu_bar` matches the menu bar's material, so it doesn't stand out on light or translucent menu bars.
- **Auto-hidden menu bar.** When "Automatically hide menu bar" is on, the virtual notch hides with the menu bar and comes back with it. Alerts still peek.
- **Hover target.** The hover zone is the whole top-center strip, a few points tall and wider than the pill, so that a mouse pushed to the top edge reliably hits it.

---

## 6. Notifications pipeline

All user-facing alerts go through the core `Notifier`, never directly through macOS notifications.

```
module → Notifier.post(event) → rules (global + per-module) → outputs
```

**Event fields:** `module`, `kind` (module-specific, e.g. `session.blocked`), `severity` (`info|warn|critical`), `title`, `body`, `action` (what clicking does), `dedupe_key`.

**Rules** (in config): mute a `kind`, set a minimum severity, quiet hours, cooldown per `dedupe_key`, and a choice of outputs.

**Outputs** (combinable): `peek` (notch), `system` (macOS notification), `sound`. Rules can add a `reminder` delay (replays the peek and sound once if the state is unchanged).

Example: the cause of the Peon Ping noise is configured away explicitly:

```toml
[modules."agents.sessions".notify]
"session.blocked"   = { outputs = ["peek", "sound"], reminder = "10m" }
"session.done"      = { outputs = ["peek"], min_working_time = "30s" }
"session.failed"    = { outputs = ["peek", "sound"] }
"subagent.stopped"  = { outputs = [] }

[modules.time.notify]
"time.timer_end"      = { outputs = ["peek", "sound"] }   # Timer, Countdown or Pomodoro break end
"time.break_reminder" = { outputs = ["peek"], reminder = "10m" }
```

**Alert kinds** (canonical list in the architecture spine, AD-13): `session.blocked`, `session.done`, `session.failed` (§7.1), `usage.quota_warning` (§7.2), `shelf.expiring` (§7.3), `time.timer_end` and `time.break_reminder` (§7.7), `calendar.reminder` (§7.5), `setup.problem` (§5.2).

**Privacy mode** applies to every output, including macOS notifications (§10.3).

**Activity log.** Vigie keeps a local-only log of alerts, peeks, reminders and Focus outcomes for 30 days, viewable by the user from Settings. It is never synced or sent anywhere and holds no secrets. It is the data source for the PRD's success metrics.

---

## 7. Built-in modules (v1)

### 7.1 `agents.sessions`: AI agent sessions

Tracks every running CLI coding agent session (Claude Code, Codex CLI, Gemini CLI, …) and shows them all in one place. Each agent is supported through an **agent adapter** (§8.3). The module itself only deals with the normalized events and statuses below.

**Normalized events** (adapters translate the agent's native events into these):

| Event | Meaning |
|---|---|
| `session.start` | Agent session started |
| `prompt.submit` | User sent a prompt |
| `tool.start` / `tool.end` | Agent started or finished a tool call (also used as a heartbeat) |
| `subagent.end` | A subagent finished (parent may still be working) |
| `needs.input` | Agent is waiting for the user: permission request or question |
| `turn.end` | Agent finished its turn and is waiting for the next prompt |
| `session.error` | Agent reports a run-breaking error: connection lost, login required |
| `session.end` | Session closed |

**Status model**

| Status | Entered on | Alert |
|---|---|---|
| idle | `session.start`; from done after `done_to_idle` (default 15 min) | None |
| working | `prompt.submit` (also from done), `tool.start`, `tool.end`, `subagent.end` | None |
| done | `turn.end` | Once ("finished" setting) + optional reminder |
| blocked | `needs.input` | Once + optional reminder |
| failed | `session.error`; host went to sleep while the session was working (§7.1.2) | Once + optional reminder |
| gone | `session.end`, or liveness check fails (never for a failed session: it stays until dismissed or 24 h) | None (removed) |

- Colors and glyph shapes are defined per theme look (DESIGN.md) and are all user-configurable. Color is never the only cue: each state also has a shape and a text label.
- **Done → idle** happens only after the delay: no hook can tell that the user has read the reply. Focusing or dismissing doesn't change the state; a new prompt moves the session to working.
- **T+**: blocked and failed show the time since entering the state (since wake for host-slept), and it keeps running after the alert.
- **Urgency order** (closed notch, Agents tab): blocked and failed (shared top priority, most recent first) > done > working > idle.

Not every adapter can emit every event (§8.3). If an adapter can't detect `needs.input` or `session.error`, its sessions can never turn blocked or failed, and the UI says so in that adapter's settings instead of showing an inaccurate status.

**Process only:** agents known only from their process (integration tier 3, §8.3) show presence (a plain grey dot, label `RUNNING`, no hue, sorted after idle), never a status.

**Liveness:** each session stores the PID of the agent process. A periodic check (every 10 s) removes sessions whose process has died. If a session stays `working` with no events for longer than `stale_after` (default 10 min), it's shown **stale**: its glyph is replaced by a dashed ring with a `?` inside (`ink-3`, no hue, static), label `STALE · <time since last event>`, sorted after idle, no alert, until the next event returns it to its real state (UX Story 1.7b).

**`vigie run -- <cmd>`:** any command can be watched like an agent session (e.g. `vigie run -- make deploy`).
- The session (agent `run`, the command as its title) is working while the command runs, then **done** on exit code 0 and **failed** on any other code, with the same alerts and Focus as agent sessions.
- The command runs as a child with inherited stdio: its output and exit code pass through unchanged, and `vigie run` exits with the command's code.
- Ctrl-C passes the signal to the command and ends the session **without an alert**: a user interrupt is not a failure.
- If Vigie isn't running, the command still runs normally; the events are spooled like hook events (§8.2).
- Focus targets the terminal tab of the calling shell. Built on the generic agent path (§8.4); no adapter needed.

**Closed notch:** one status glyph per session (animated, shape-coded per state), in urgency order, most urgent nearest the notch, up to `closed.slots`; the rest collapse into `+X`. `+X` never hides a blocked or failed session while a lower-urgency session is visible; when blocked and failed sessions outnumber the slots, the most recent fill all slots and `+X` counts the rest (§14.17). No session count and no project name. Empty states: `NO AGENT CONNECTED` (no adapter set up) and `NO ACTIVE SESSIONS` (nothing running).
**Module state:** `alert` if any session is blocked or failed, `active` if any is done or working, `ambient` if only idle sessions exist or none (so the empty-state label shows).

**Expanded tab (Agents):** dense list sorted by urgency: agent, project (from `cwd`), last action, status with time in status, and the terminal app only when sessions span more than one terminal app. The only action is **Focus** (click the row or ↵ on the selection), which focuses the session's terminal tab (§7.1.1). Vigie never acts on a session on the user's behalf.

**Drop zone "Ask AI":** dropping files (on the drop display, the Shelf tab, a stash item dragged onto the zone, or `Send to › Ask AI` on a stash item) opens a new terminal tab running the default agent (`ask_default_agent`), with **no dialog**. The working folder is `ask_cwd` (`home`, the dropped file's folder, or a custom path); holding ⌥ while dropping uses `ask_alt_cwd`. The files are attached, or their paths prefilled in an unsent prompt; the user types the question in the terminal. If the CLI can't start with an attachment or an unsent prompt, the paths are pasted for the user to complete (§14). Agent not installed → setup-problem alert. Example commands (each adapter defines its exact syntax; to be checked against each CLI):
- `claude "@<file1> @<file2>"`
- `codex "<file paths>"`
- `gemini -i "@<file1>"`

**Settings:** enabled adapters, terminal app (`terminal` / `warp` / `ghostty` / `iterm`; other terminals later), default agent and folders for Ask AI, alert settings for blocked / finished / failed, `done_to_idle` delay, Keep-awake, ignored paths (`ignored_paths`), stale timeout (`stale_after`), plus each adapter's own settings.

#### 7.1.1 Terminal focus (highest technical risk)

The goal: clicking a session brings its exact terminal tab to the front. This doesn't depend on the agent, only on the terminal.

Each terminal is supported through a `TerminalAdapter` with `capture(env, pid, tty) -> TerminalLocator` (called on `session.start`) and `focus(locator)`.

| Terminal | Approach | Confidence |
|---|---|---|
| iTerm2 | AppleScript / Python API using the session ID from `ITERM_SESSION_ID` | High |
| Terminal.app | AppleScript, match tab by `tty` | High |
| Warp | No tab API known. Plan: Accessibility API, finding the tab by its title (set by the agent or by a hook that sets a unique title) and pressing it. If the spike fails, v0.1 ships app-level focus for Warp (§14) | **Unknown, spike first** |
| Ghostty | To be investigated | Unknown |

If focusing fails, activate the terminal app without selecting a tab. Focus needs the Accessibility permission for some terminals; if it's missing, a setup-problem alert says so.

v1 supports exactly these four terminals.

#### 7.1.2 Sleep

- **Keep-awake** (opt-in, off by default, key `prevent_idle_sleep`): while any session is working, Vigie prevents idle sleep. It can't cover lid close or manual sleep.
- **Interrupted by sleep:** on wake, local sessions that were working when the Mac slept become **failed** (`FAILED · HOST SLEPT`, with the interrupted action) and raise one failed alert for the wake: the usual alert with Focus when one session was interrupted, or a single summary (`<n> sessions interrupted by sleep`, action Open Agents) when several were. Each session is still marked failed in the Agents tab. Detection method and a pre-sleep warning are open (§14).

### 7.2 `agents.usage`: AI usage

Each agent adapter can provide one or more **usage providers**, which can be turned on separately. Every provider returns the same shape: token counts and estimated cost over time, and optionally plan limits (percentage used and reset time for each window, e.g. 5-hour and weekly).

| Agent | Local logs | Plan limits |
|---|---|---|
| Claude Code | `~/.claude/projects/**/*.jsonl` (same approach as `ccusage`) | Unofficial claude.ai endpoint (see Claude-Usage-Tracker) |
| Codex CLI | Session logs in `~/.codex/sessions/` (to be confirmed: these appear to include token counts and rate-limit snapshots) | Possibly from the same logs, to be confirmed |
| Gemini CLI | To be investigated (local telemetry / session files) | To be investigated |

- Local-log providers work offline and need no sign-in.
- Plan-limit providers that use unofficial endpoints must be enabled explicitly (per Account), may break without notice, and store credentials in the Keychain. A failed fetch shows a stale indicator, never a wrong number.
- **Claude sign-in** (per Account, per Mac): the user chooses in Settings between pasting a token (stored in Vigie's Keychain items) and allowing Vigie to reuse the login Claude Code already stored on this Mac. Reuse needs an explicit `Allow` in Settings (macOS may also ask), is revocable, is never synced, and the credential is read once per launch and held in process memory for the session (re-read only when it has expired or the endpoint rejects it): never copied to disk, written, renewed or logged. A refused Keychain prompt raises one setup problem and Vigie waits an hour before asking again. An expired login raises a setup-problem alert; Vigie never renews it.

**Multiple Accounts.** Every provider (not only Claude) can have several **Accounts**, each with its own usage.
- Each Account is bound to its own agent config or log location (e.g. a second Claude Code config folder). Sessions and log entries are attributed to an Account by that location.
- Usage is kept per Account and never merged across Accounts. Credentials are per Account, in the Keychain (owner `adapter.<id>`, one key per Account, e.g. `plan_token.work`; ruled 2026-11-08).
- Accounts are declared in the adapter's table in `local.toml` (`[modules."agents.sessions".adapter.<id>] accounts` + `account.<id>.{label,location,usage_providers,plan_auth}`), not under `agents.usage`, so both agent modules read one list (ruled 2026-11-08).
- With no Account configured, a provider has one implicit Account at the agent's default location.

**Closed notch:** one quota ring per provider in use, on the left-wing item lane (§5) with the module's `priority` (per-provider override in `providers.<id>`), in user order, with the provider name under each ring (a single provider shows a ring plus a value/label readout instead). For a provider with several Accounts, the ring shows the Account of the most recent session; the others are on the Usage tab. Setting `rings = "5h" | "5h+weekly"`: with both, the rings are nested (5h inside). Only the windows the plan has are shown (5h, weekly, daily); no empty ring. With no provider, the left wing is empty.

**Quota warning:** one threshold per provider (`warn_threshold`, % used only, never pace). The user chooses `warn_action = "alert"` (peek + optional sound, state `alert`) or `"visual"` (visual change only, state `active`). Own color, plus non-color cues. Wins over pace-ahead on the same window.

**Pace indicator** (optional, `pace = true`): marks elapsed time in the paced window (5h, or weekly when the plan has no 5h). "Within pace" (the healthy state) when used is at or under the elapsed marker, or over it by no more than `pace_tolerance`; "ahead of pace" when used > elapsed + `pace_tolerance` (default 5 points). Pace-on and pace-ahead colors are configurable. Visual only: never alerts, never plays a sound.

**State:** `ambient` normally, `active` or `alert` above `warn_threshold` per `warn_action`.
**Expanded tab (Usage):** provider cards, one per Account (ring, one bar per window with reset time, elapsed %, pace label, threshold tick) on one half, scrolling beyond two providers, ordered by the user (drag on the tab or reorder in Settings); 7-day token history (all agents) and today's estimated cost by project (from local logs) on the other half. Empty state: `NO USAGE PROVIDER`.

### 7.3 `shelf`: file shelf

- Provides the Stash, AirDrop (`airdrop`, on by default) and Image to Text (`image_to_text`, off by default) zones and renders every zone on its tab (`SEND TO` card) and Home widget. The **host** owns the drop display (§4.6): dragging a file from any app over the notch opens it with Stash and Ask AI, plus AirDrop and Image to Text when enabled. Shelf disabled ⇒ Stash, AirDrop and Image to Text disappear; Ask AI stays while `agents.sessions` is on.
- **Stash zone:** stores files temporarily. Default is to store a **reference** (bookmark) to the file. A `copy` mode stores a copy instead, so the original can be deleted. Text, URLs and images dragged in from other apps are **saved** as files. Each row shows its mode (`REF` / `COPY` / `SAVED`), which tells the user what expiry will do.
- **Item actions:** drag out = move, ⌥-drag = copy; Quick Look (Space), Reveal in Finder, Pin. Stash items can be dragged onto Ask AI, AirDrop and Image to Text in the `SEND TO` card.
- **Non-drag paths** (keyboard and VoiceOver):
  - **Send to menu** on a Shelf item: right-click on a row (tab and Home widget), or `↵` on the selected row, lists Ask AI, Ask AI in the alternate folder, AirDrop, Image to Text (enabled zones only), plus Quick Look, Reveal, Pin / Unpin. The same entries are VoiceOver custom actions. Source `.stashItem`.
  - **`⌘V` on the Shelf tab** (expanded view focused) stashes the clipboard contents (files, image, text, URL) like a Stash drop. Source `.paste`.
  - **Services entry `Stash in Vigie`** (Finder and any app; files and text), declared with `NSServices` in the app's Info.plist; it calls the Stash handler. Source `.service`. No new target. If the Shelf is off, it raises a setup-problem alert `Shelf is off` with Open settings [ASSUMPTION]. A Share extension is not in v1 [ASSUMPTION: Services instead, avoids a new target].
  - Each zone has a VoiceOver label, e.g. "Stash, keep 7 days, 5 items", "Ask AI, Claude Code in ~/dev, Option for alternate folder".
- **Expiry:** items expire after `ttl`, a number of days (default 7 days), unless pinned. 24 h before expiry, a visual warning (quota-warning color plus a triangle) on the row, the shelf card and the Home shelf widget; optional macOS notification (off by default); no sound. On expiry, references leave the shelf (file untouched); copies and saved items go to the **Trash**. Nothing is deleted permanently.
- **State:** `ambient` with an item count when the shelf isn't empty, otherwise `hidden`.

### 7.4 `integrations`: script modules runtime

Runs script modules (§9). Each script appears as its own module in arbitration, settings, and tabs. "Integrations" is only the runtime that executes them.

### 7.5 `calendar` (nice-to-have, v0.3)

- Uses EventKit, so it reads every account in the macOS calendar store.
- **No closed-notch glance** (decided 2026-11-07): the module offers no left-wing item and no compact view; its state stays `hidden` except while a reminder alert is unresolved (`alert`).
- **Reminders** (`reminders = true`): at each alarm time set on an event in Calendar (EventKit alarms, relative or absolute), the module raises `calendar.reminder` through the Notifier, which peeks like any alert (§5.2). Events without alarms raise nothing. Location-based alarms are ignored [ASSUMPTION]. DND / macOS Focus mode suppresses it like every alert, and `[notify] after_focus` applies (drop or replay); the alert stays unresolved until the event ends [ASSUMPTION], so a replay only shows reminders for events not yet over. An alarm that passed while the Mac slept raises once on wake if its event has not ended [ASSUMPTION]. Vigie does not suppress Calendar's own macOS notifications.
- **Reminder peek:** two actions (§5.2): primary `⌥⌘↵` **Join call** when the event has a video link (Meet, Zoom, Teams) [ASSUMPTION], otherwise **Open Calendar** (the Calendar tab, upcoming list at that event); `⌥⌘⌫` Dismiss. Sound off by default (`[sounds] calendar_reminder`) [ASSUMPTION].
- **Expanded tab:** month grid (one dot per calendar per day in macOS calendar colors, ISO week numbers, month navigation, return to today) and an upcoming list from now or from the clicked day, at most about 5 events then `+N LATER`, next event highlighted with a countdown. `JOIN CALL` on events with a video link (user-triggered). Missing calendar access shows a setup card in the tab. Week view: maybe later.
- **Settings:** calendars to include, reminders on/off, hide all-day events (a hidden all-day event raises no reminder [ASSUMPTION]).

### 7.6 `notes`: quick notes (nice-to-have, v0.4)

- A global hotkey opens a floating, Raycast-style panel for writing a note (takes focus; Esc closes).
- Mostly temporary memos, plus quick copy/paste of secrets and passwords.
- Markdown, with secret syntax: inline `||…||` and multi-line ` ```secret ` blocks. Secrets render masked at a fixed width, click to reveal; `COPY` copies without revealing, and the clipboard is cleared after a configurable delay (default 30 s, to confirm, §14). List summaries never show secrets, only how many a note holds. Touch ID unlock: after v1.
- Notes are saved in a folder the user chooses, **end-to-end encrypted** (only Vigie can decode them), and synced via iCloud when sync is on (§11.1). They are therefore **not** plain Obsidian-compatible files.
- **Expanded tab:** notes list with search and a preview of the selected note.
- No closed-notch presence.

### 7.7 `time`: timers, Pomodoro and breaks (v0.3)

- **Timers** (for a duration) and **Countdowns** (to a clock time): several at once, named, started, paused and cancelled from the Time tab or a hotkey.
- **Pomodoro:** work/break cycles with configurable lengths. Default 25 min work, 5 min break, a 15 min long break every 4 cycles. When a work phase ends, the break **waits** for the user: it is announced like a break reminder (break peek with Start break / Snooze 5m / Skip, or the quiet `BREAK DUE` readout, per `breaks.style`) and starts only on Start break; a break that ends returns to work on its own. While the user is **Away** during a work phase, the work count **pauses** (`AWAY · PAUSED`) and resumes on its own when the user is Present again; Resume resumes it at once (decided 2026-11-07).
- **Survive relaunch and sleep.** Running items are persisted; an end that passed while the Mac was asleep raises its alert once on wake.
- **End alerts:** a Timer or Countdown ending, or a Pomodoro break ending, raises `time.timer_end`; a Pomodoro work phase ending raises `time.break_reminder` (break peek with Start break / Snooze 5m / Skip, the break-reminder sound, `BREAK DUE` until started or skipped; decided 2026-11-07). Both are routed by the Notifier like any alert (peek, macOS notification, sound if configured; the Timer-end sound is off by default, §6). An ended Timer or Countdown stays in the Time tab as `ENDED 14:48` with `DISMISS` until the user acknowledges it.
- **Closed notch** (optional, `closed_notch`, `"off"` by default): the running item nearest its end shows on the left-wing item lane (§5) with the module's `priority`, as remaining time (`"time"`), a ring (`"ring"`) or both (`"both"`).
- **State:** `hidden` with nothing running or closed-notch display off, `active` while an item runs, `alert` on an end.
- **Break reminders** (`breaks.enabled`):
  - After `breaks.work` of presence (default 55 min), Vigie raises `time.break_reminder`. The break counts as taken once the user has been **Away** for `breaks.length` (default 5 min); the cycle then restarts with no action.
  - **Strength** (`breaks.style`): `"peek"` (default) shows a break peek with three actions, Start break (primary, `⌥⌘↵`), Snooze 5m (`⌥⌘Z`), Skip (`⌥⌘⌫`) (§5.2); `"quiet"` shows no peek and plays no sound.
  - **`BREAK DUE` persists** (reminder or Pomodoro break): after the break peek retracts, or at once with `"quiet"`, the left wing shows the `BREAK DUE` readout (full dashed ring + label) as a left-lane item in `alert` state, **even when `closed_notch = "off"`**, until the break is started or skipped. Snooze keeps it showing and re-raises the peek after 5 min. The Time tab row in break-due state shows `START BREAK` (primary), `SNOOZE 5M` and `SKIP`, and the Time tab carries the alert marker. Break due counts as an unresolved alert for `[notify] after_focus = "replay"`.
  - **Away** = no keyboard, mouse or trackpad input for `breaks.away_after` (default 90 s, input idle time), or screen locked, screensaver on, or display asleep. Keep-awake (§7.1.2) does not affect it. **No camera, ever.** Away comes from a shared host service, not from the module itself.
  - Time Away during a work period doesn't count as work. Long passive reading or video looks Away, so a reminder may come late, never early.
  - While a Pomodoro runs, break reminders pause; the Pomodoro's own breaks replace them.
- **Expanded tab (Time):** running and paused items with remaining time, start controls, Pomodoro phase and cycle count; ended items until dismissed; break-due row with its three actions.
- **Later:** natural-language entry ("25m tea").

---

## 8. Event Server and agent integration

### 8.1 Event Server
- Listens on the Unix socket `~/Library/Application Support/Vigie/vigie.sock`, accessible only to the current user (permissions 0600).
- Message: one JSON object per line: `{ "topic": "agent.hook", "payload": { … } }`.
- Modules subscribe to topics through `context.events`.
- The `vigie` CLI is the client: `vigie event <topic> [json]`.

### 8.2 `vigie hook <agent>`

The single entry point that agent hooks call:
- reads the agent's native event (from stdin or arguments, depending on the agent)
- adds the parent PID, the TTY, and relevant environment variables (`TERM_PROGRAM`, `ITERM_SESSION_ID`, `WARP_*`, …)
- sends it to the socket tagged with the agent ID, where the adapter normalizes it (§7.1)
- **exits immediately with code 0 and no output**, so it never slows down or blocks the agent, even when the app isn't running.

### 8.3 Agent adapters

An adapter is the only agent-specific code. Adapters are compiled into the app (like built-in modules), and adding one never requires changes to the sessions or usage modules.

```swift
protocol AgentAdapter {
    static var id: String { get }                  // "claude", "codex", "gemini"
    static var name: String { get }
    var capabilities: AgentCapabilities { get }    // which normalized events it can emit, usage support
    var settings: [SettingDescriptor] { get }

    /// Integration install/uninstall (e.g. edit the agent's config file). Always returns a diff for the user to confirm.
    func integrationPlan() throws -> ConfigDiff
    func removalPlan() throws -> ConfigDiff

    /// Native event → normalized events.
    func normalize(_ raw: RawAgentEvent) -> [AgentEvent]

    /// Optional: watch transcript/log files when hooks are unavailable or incomplete.
    func transcriptWatcher() -> TranscriptWatcher?

    func usageProviders() -> [UsageProvider]

    /// Command for the "Ask AI" drop zone: start the agent interactively with the files
    /// attached or prefilled in an unsent prompt (§7.1). The user types the question.
    func launchCommand(files: [URL], cwd: URL) -> [String]
}
```

**Integration tiers.** Adapters use the best method each agent offers, falling back to the next one down:

1. **Hooks**: the agent calls `vigie hook <agent>` on lifecycle events. Gives the most accurate status.
2. **Transcript watching**: follow the agent's session log files as they're written and infer events from them.
3. **Process only**: detect that the agent process is running. Shows presence only (one grey dot), with no idle/working/blocked status.

**Initial adapters** (all facts below must be checked during implementation):

| Agent | Integration | Expected status coverage |
|---|---|---|
| Claude Code | Hooks in `~/.claude/settings.json`: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SubagentStop`, `SessionEnd`; with several Accounts (§11), also in each Account's `<location>/settings.json`, with the same command (the Account comes from the `CLAUDE_CONFIG_DIR` the hook CLI forwards) | Full |
| Codex CLI | `notify` program in `~/.codex/config.toml` (called on turn completion; if another `notify` program is already set, Vigie offers to run both through its wrapper, applied only after diff confirmation, and Disconnect restores the original), plus transcript watching of `~/.codex/sessions/` for working/blocked; use native hooks if the installed version has them | Probably full (to be confirmed) |
| Gemini CLI | Hooks if the installed version supports them, otherwise transcript watching | To be investigated |
| Others (OpenCode, Aider, Cursor CLI, …) | Later; community adapters not before outside contributions are accepted (§2.1) | — |

Claude Code hook config written by the installer (shown as a diff before writing):

```json
{
  "hooks": {
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "vigie hook claude" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "vigie hook claude" }] }],
    "PreToolUse":       [{ "hooks": [{ "type": "command", "command": "vigie hook claude" }] }],
    "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "vigie hook claude" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "vigie hook claude" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "vigie hook claude" }] }],
    "SubagentStop":     [{ "hooks": [{ "type": "command", "command": "vigie hook claude" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "vigie hook claude" }] }]
  }
}
```

### 8.4 Generic agent (no adapter needed)

Any tool can report a session directly, so unsupported agents and custom wrappers work without Swift:

```sh
vigie agent --agent mytool --session "$ID" --status working --cwd "$PWD"
vigie agent --agent mytool --session "$ID" --status blocked --message "Needs approval"
vigie agent --agent mytool --session "$ID" --end
```

The PID and TTY are captured automatically, so liveness checks and terminal focus work too. `vigie run -- <cmd>` (§7.1) wraps this path for any single command.

---

## 9. Script modules

### 9.1 Discovery and format

Every `*.md` file in `<config folder>/modules/` is a script module: a Markdown file with YAML front matter, **exactly one** fenced code block (the script), and free Markdown documentation around it. The file is not executable, so it can't be run directly; Vigie runs the code block with the declared `runtime`. Files stay readable (never encrypted) so they can be committed to git and shared; settings marked `secret` live in the Keychain.

````markdown
---
id: github.prs
name: GitHub PRs
icon: arrow.triangle.pull
interval: 5m
runtime: python3
widget: number                    # status | number | text
surfaces: [home, side, page]      # Home widget, closed-notch side slot (left-wing item lane), full page
priority: 5                       # left-wing item priority (lower = shown first); [modules."<id>"] priority in config overrides it [ASSUMPTION]
settings:
  - { key: token,   type: secret, label: "GitHub token" }
  - { key: repo,    type: string, label: "Repository (owner/name)" }
  - { key: warn_at, type: int,    label: "Warn when open PRs ≥", default: 5 }
---

Counts open PRs on one repository. Needs a token with `repo:read`.

```python
import os, json
…
```
````

### 9.2 Execution
- **Confirmation per Mac.** A script runs only after the user confirms it on this Mac, after seeing the whole file (documentation, front matter and code). A script that arrives through sync (§11.1), a git pull or a link (§9.4), or whose content changes in any way, shows as "awaiting confirmation" and does not run until confirmed; declining disables it on that Mac only. Secrets must be entered on each Mac.
- Runs every `interval`, plus once at startup and whenever the user clicks "refresh".
- Settings are passed as environment variables: `VIGIE_SETTING_TOKEN`, `VIGIE_SETTING_REPO`, … Secrets are read from the Keychain at run time.
- Timeout: `min(interval, 30s)`. stderr goes to the module log. A non-zero exit code marks the module as errored and keeps showing the last good output with a warning badge.
- Scripts run as the user, with no sandbox. The README and the confirmation screen must say so clearly: only install scripts you trust.

### 9.3 Output (stdout, JSON)

v1 widget types: **status** (e.g. a website health check), **number** (stats), **short text**. No lists.

```json
{
  "state": "active",
  "widget": { "type": "number", "value": "3", "label": "OPEN PRS", "detail": "2 awaiting review", "level": "warn" },
  "action": { "open": "https://github.com/me/project/pulls" }
}
```

- `state`: `hidden | ambient | active | alert`. Default `ambient`.
- `widget`: rendered by core templates on every surface the script enables (Home widget, closed-notch side slot, full page). `type` matches the front matter `widget`. `status` widgets carry a level (`ok | warn | error`) instead of a number; it maps to the shared status vocabulary as `ok` → `OK`, `warn` → `WARN`, `error` → `DOWN`.
- `action`: `{ "open": url }`, `{ "run": [argv] }`, `{ "copy": text }`.
- **Script-raised alerts** (`notify`) are wanted but deferred after v1; v1 ignores the field.
- A JSON Schema is published at `schemas/script-module.schema.json`. Exact field names are fixed with the schema.

### 9.4 Install from link

- Vigie registers the `vigie` URL scheme. Opening `vigie://install?url=<https URL of the .md file>` (optionally `&sig=<signature URL>`) from any website fetches the script over HTTPS only and shows the **full confirmation**: the whole file, its source URL and author. Nothing is installed without it; a declined install leaves no file behind.
- A confirmed install writes the file to `<config folder>/modules/` with its source metadata, and the script then follows §9.2.
- **Signature.** Scripts merged into the Script repository are signed by its CI (Ed25519, detached `<script>.md.sig` over the exact file bytes, key held in a protected environment). Vigie verifies the signature against the public keys built into the app (rotated by an app update).
  - Valid signature: the confirmation shows **"Verified: Vigie Script repository"**.
  - Any other script (unsigned, invalid signature, other site) gets a **stronger warning**, and its author is shown as "claimed by the file".
  - A signature proves where a script comes from and that it was reviewed, not that it is safe. The confirmation always shows the full file.

### 9.5 Script updates

- A script installed from a link records its source. Vigie checks it for updates **at most once a day** (can be turned off).
- If the content differs, Vigie verifies the signature again, shows a **diff**, and asks for a **new confirmation**. Until the update is confirmed, the old version keeps running; then the file is replaced.

### 9.6 Script repository

- Community scripts live in a separate, curated, **public** GitHub repository (name TBD, e.g. `vigie-scripts`) with its own license (§14): one folder per script, pull requests reviewed by the maintainer, CI that validates front matter against the JSON schema and signs merged scripts (§9.4). Review policy is open (§14).
- **Examples:** GitHub PRs, site up/down, CI or deploy status, revenue (Stripe-style), and a text widget. They live in the repository; the app bundles a small subset.
- **Later:** a public website (static, generated from the repository) with install buttons.

---

## 10. Expanded view

- **Opens on click** (or tap) on the notch, or with the global expand hotkey, always on **Home**, and takes keyboard focus. Hovering the closed notch only gives a small reaction. Hover-to-open (`open_on_hover`, with `hover_delay`) is opt-in. Touchscreens have no hover; see §14.
- **Closes** on click outside, Escape (when focused), or the hotkey again. Close-on-mouse-leave (`close_on_leave`) is opt-in.
- **Focus:** keyboard focus only when opened deliberately (click, hotkey). Opened any other way (e.g. during a drag), it takes no focus and only global shortcuts work. The view never opens by itself.
- **Tab bar:** **Home** first, then one tab for each enabled module that has an `expandedView`, plus one per script that enables a full page. The order is set by the user. A tab with an active alert carries a marker.
- **Home:** a grid of `homeCard()` widgets, all one fixed card size in v1 (no spans). The user picks which appear and in what order in Settings › Home: a list of modules and scripts with a checkbox each, dragged into order (decided 2026-11-07). Home has no in-place edit mode.
- Keyboard (when focused): `⌘1…9` switches tabs, `↑↓` moves the selection in lists, `↵` acts on it (Focus, Join call, Send to menu on a Shelf item), Space = Quick Look and `⌘V` = stash the clipboard on the Shelf, Esc closes.
- **Empty and setup states:** every tab has an empty state (label, one sentence, a button to the relevant Settings pane where useful) and a setup card when its module lacks a permission.

### 10.1 Settings window and onboarding

- **Settings** is a regular macOS window with native controls that edits the config files (§4.4, §11). Panes are listed in EXPERIENCE.md. Reached from setup-problem alerts, empty states, `⌘,`, a settings icon in the expanded view, and the menu shown by right-clicking the closed notch (`Settings…`, `Quit Vigie`).
- **Onboarding** (first launch, guided, each step skippable): theme, agent connections and hooks (diff confirmation, §8.3), Accessibility permission, display choice (always asks about non-notch displays, whatever the setup), sounds on/off (skipping it leaves sounds off), launch at login (preselected on). Vigie never shows a Dock icon.
- **Before onboarding exists (v0.1–v0.3):** a first launch on a Mac with a display without a notch shows a one-time prompt in the expanded view asking where Vigie should appear, and Settings › General has a `Launch at login` toggle.

### 10.2 Appearance and sounds

- **Themes:** a theme family with a shared base (geometry, layout, motion, wording) and skins. Built in: **Chrome Hologram** (default) and **Twin Metal Tactical**, each with light and dark looks. Appearance follows macOS unless forced to light or dark. Custom themes extend the shared base. Theme and appearance changes apply live, with no restart. Visual specs: DESIGN.md.
- **User-configurable colors:** every status color, pace on / ahead, quota warning.
- **Presence mode:** `full` (default: ambient loops, live glyph animation) and `calm` (static; one simple pulse on blocked or failed). macOS Reduce motion removes animations from v0.1 and, once Presence mode exists, forces `calm`; Reduce transparency and Increase contrast are honored from v0.1.
- **Sounds:** fully optional (asked at onboarding). Seven events: blocked, failed, done, quota warning, timer end, break reminder, calendar reminder, each on/off with its own sound file (timer end, break reminder and calendar reminder off by default). Built-in sounds are under 1 s; custom files of any length. Sounds play once with the alert, replay with a reminder, and follow Do Not Disturb. Pace and shelf expiry never play a sound.
- **Accessibility floor (v1):** every control and glyph has an accessibility label with its state; color is never the only cue. Full VoiceOver experience: v2.

### 10.3 Privacy mode (v0.2)

- **While the screen is shared or recorded**, every Vigie surface shows only status glyphs, rings and numbers, and hides every user-supplied name or text. This includes peeks and the **macOS notifications** Vigie sends.
- Hidden, for example: notes and secrets, session titles and messages, project names (also in cost by project), shelf items and thumbnails, timer labels, Account names, widget text, calendar titles.
- It turns on and off by itself, with no user action. The user can also force it on (`[privacy] force`).
- **Detection** method is unproven (§14). Where it isn't possible on a macOS version, Settings says so and offers the **manual toggle** instead. If the method needs the Screen Recording permission, it is requested only when automatic detection is turned on.
- Implemented once in the host as a display filter; modules mark their sensitive fields and can't opt out.

---

## 11. Configuration file

`<config folder>/config.toml` (default `~/.config/vigie/config.toml`). The settings window writes to this file. Edits made outside the app are picked up live, with no restart. Invalid config raises a setup-problem alert and the app keeps the last valid config.

Sections marked *local* below are machine-specific: they live in a local file that is never synced (§11.1).

```toml
[general]
hide_in_fullscreen = true
open_on_hover = false         # click to open by default
close_on_leave = false
hover_delay = "150ms"
expand_hotkey = "cmd+shift+space"
prevent_idle_sleep = false    # while an agent is working (§7.1.2)
launch_at_login = false       # local; onboarding preselects it on
tab_order = []                # module ids in tab order after Home; empty = default order (A74)
home_after = "2m"             # re-open within this delay keeps the last tab; "never" | "0s" (Story 11.4)

[appearance]
theme = "chrome-hologram"     # chrome-hologram | twin-metal-tactical | <custom>
mode = "system"               # system | light | dark
presence = "full"             # full | calm
# colors.blocked = "#…"       # any status, pace or warning color can be overridden

[sounds]
enabled = true
blocked = "builtin:blocked"   # off | builtin:<name> | path to a custom file
failed = "builtin:failed"
done = "off"
quota_warning = "builtin:warn"
timer_end = "off"             # off by default; e.g. "builtin:timer"
break_reminder = "off"
calendar_reminder = "off"     # off by default (§7.5)

[notify]
quiet_hours = ""              # e.g. "22:00-08:00"; empty = none
after_focus = "drop"          # drop | replay (latest unresolved alert per module when the macOS Focus mode ends)
min_severity = "info"         # info | warn | critical; also per kind in [modules."<id>".notify] with cooldown, outputs, reminder (§6, A74)
cooldown = "0s"               # per dedupe_key
# focus_filter_ran = false    # local (local.toml), written by Vigie once its Focus filter has run (§5.2, Story 3.10)

[privacy]                     # local (§10.3)
auto = false                  # detect screen sharing/recording; manual toggle where impossible. Default true only if the detection method needs no new permission; false if it needs Screen Recording (A88, method from spike 21.1)
force = false                 # always on

[home]
cards = []                    # Home cards in order, written by Settings › Home, e.g. ["agents.sessions", "agents.usage", "shelf"]; empty = default set; one card size, no spans (A74)

[sync]
icloud = false                # config/personalization and notes only (§11.1)

[updates]
auto_check = true
check_interval = "24h"
auto_install = false
channel = "stable"          # stable | beta (beta available from the public release)
prices = true               # fetch the signed per-provider price table at check_interval (Story 6.5); false = bundled table only

[closed]
max_side_width = 120
# notch_overlap = 2          # local (local.toml); points added below the reported notch height (0-12), physical notch only
# notch_side_inset = 4       # local (local.toml); points added each side of the notch slot (0-16), physical notch only
slots = 3                     # items per side, max about 4; the rest collapse into +X
peek = true
peek_duration = "5s"          # dwell, paused on hover

[display]                     # local
display = "notched"           # main | notched | all | "<name>"

[virtual_notch]               # local
width = 200
idle = "shrink"               # shrink | hide | keep
position = "center"           # center | right
placement = "menu_bar"        # menu_bar | below
style = "black"               # black | menu_bar

[modules."agents.sessions"]
enabled = true
priority = 1
adapters = ["claude", "codex", "gemini"]
done_to_idle = "15m"
stale_after = "10m"           # working with no event this long → stale look
ignored_paths = []            # sessions whose cwd is under these paths are ignored
ask_default_agent = "claude"
ask_cwd = "file_folder"       # home | file_folder | "<path>"
ask_alt_cwd = "~/Code"        # used when ⌥ is held on drop

[modules."agents.sessions".local]   # local
terminal = "warp"             # terminal | warp | ghostty | iterm

[modules."agents.sessions".adapter.claude]   # singular: `adapters` above is the list (TOML forbids both on one key; 2026-11-08)
usage_providers = ["local", "plan"]
plan_auth = "token"           # local, per Account: token | claude_code (reuse Claude Code's login, after Allow)

[modules."agents.usage"]
enabled = true
priority = 2                  # left-wing item priority of every provider ring; override in providers.<id>
order = ["claude", "codex"]   # provider order (also set by drag on the Usage tab; breaks priority ties)
rings = "5h+weekly"           # 5h | 5h+weekly
pace = true
pace_tolerance = 5            # points
warn_threshold = 80           # %, per provider override: [modules."agents.usage".providers.<id>]
warn_action = "alert"         # alert | visual

# Accounts live in the adapter table (local.toml), so sessions and usage attribute alike (ruled 2026-11-08):
# [modules."agents.sessions".adapter.claude]
# accounts = ["work"]            # extra Accounts; the implicit default Account needs no entry (§7.2)
# [modules."agents.sessions".adapter.claude.account.work]
# label = "Work"
# location = "~/.claude-work"    # agent config/log location; sessions and logs here belong to this Account
# usage_providers = ["local"]    # add "plan" for opt-in remote limits, per Account
# plan_auth = "token"

[modules.shelf]
enabled = true
ttl = "7d"                    # days
mode = "reference"
expiry_notification = false
airdrop = true                # AirDrop drop zone
image_to_text = false         # Image to Text drop zone (on-device text recognition)

[modules.time]
enabled = false
closed_notch = "off"          # off | time | ring | both: nearest-to-end item on the left wing
priority = 3                  # left-wing item priority
# hotkey = "…"                # optional global hotkey, no default

[modules.time.pomodoro]       # (table, not inline: Settings writes it)
work = "25m"
short_break = "5m"
long_break = "15m"
long_every = 4                # work periods before a long break

[modules.time.breaks]
enabled = false
work = "55m"                  # presence before a reminder
length = "5m"                 # Away time that counts as a break
away_after = "90s"            # input idle threshold
style = "peek"                # peek | quiet (no peek, no sound: BREAK DUE in the closed notch)

[modules.notes]
enabled = false
hotkey = "opt+cmd+n"
folder = "~/Notes/Vigie"
clipboard_clear = "30s"

[modules.calendar]
enabled = false
reminders = true              # peek at each event's own Calendar alarm times; no closed-notch glance (§7.5)

[modules.integrations]
update_checks = true          # scripts installed from a link, at most once a day (§9.5)

[modules."github.prs"]        # script module
enabled = true
priority = 5
repo = "me/project"
```

### 11.1 Sync and secrets

| Data | Where | Sync |
|---|---|---|
| Config and personalization (theme, presence, colors, alert and sound settings, module settings) | Config folder | iCloud, optional |
| Machine-specific settings (displays, virtual notch, terminal, config folder location, script confirmations) | Local | Never |
| AI auth tokens (per Account), settings marked `secret` | Keychain | Never |
| Activity log (30 days), running timers | Application Support | Never |
| Script modules | Config folder, readable Markdown | With the config folder; confirmation required on each Mac before first run (§9.2) |
| Notes | Notes folder, end-to-end encrypted | iCloud when sync is on |

- Turning iCloud sync on moves the config and notes folders into `iCloud Drive/Vigie/`; turning it off moves them back.
- The notes key is created only when the user sets up notes; on another Mac, Vigie waits for it to sync through iCloud Keychain or asks for the recovery key, never creating a second key.
- The config folder location is user-choosable so it can be committed to git (with or without iCloud sync). Script files stay readable for the same reason; their secrets stay in the Keychain.

---

## 12. Build, release and updates

### 12.1 Where builds happen

The code repository is **private** (§2.1); releases are **public**. All release builds run on **GitHub Actions macOS runners** in the private repository (macOS minutes there count against the account's allowance, unlike public repositories). Nothing is built or signed on a developer's machine, so every release can be reproduced from a tagged commit.

**Public releases host.** DMGs, update zips, checksums and the Sparkle appcast are published to a public location: a public, releases-only GitHub repository (decided 2026-11-06, e.g. `<org>/vigie-releases`). No source is published there. The Homebrew cask and the app's feed URL point only to it.

| Workflow | Trigger | Does |
|---|---|---|
| `ci.yml` | Pull request, push to `master` | Build, unit tests, adapter fixture tests, lint. **No secrets, no signing.** |
| `release.yml` | Push of a tag matching `v*.*.*` | Build, sign, notarize, package, publish the release on the public releases host, update the appcast, bump the Homebrew cask |

### 12.2 Release trigger

A release is published when **a `vX.Y.Z` tag is pushed on a commit that is on `master`**.

- `release.yml` first checks that the tagged commit is part of `master` (`git merge-base --is-ancestor $TAG origin/master`) and that the tag matches the version in the Xcode project. If either check fails, the release stops.
- Tags with a suffix (`v1.2.0-beta.1`) publish a **pre-release**, which only reaches users who opted into the beta channel (§12.4). The beta channel starts with the public release; before that, only stable releases are offered.
- Optional later: use **release-please** to open a "release PR" that bumps the version and changelog. Merging it creates the tag automatically, which makes "merge to master" the only manual step.

### 12.3 `release.yml` steps

1. Check out the tag and verify it (§12.2).
2. Import the **Developer ID Application** certificate into a temporary keychain. The certificate is stored as a base64-encoded `.p12` in a repository secret.
3. `xcodebuild archive` + `-exportArchive` (Developer ID export), with hardened runtime enabled. The bundled `vigie` CLI is signed as well.
4. **Notarize** with `xcrun notarytool submit --wait`, using an App Store Connect API key (stored as secrets), then `xcrun stapler staple`.
5. Package two files: `Vigie-X.Y.Z.dmg` for people downloading by hand, and `Vigie-X.Y.Z.zip` for Sparkle updates. Notarize and staple the DMG too.
6. Sign the zip with Sparkle's **EdDSA** key (`sign_update`, private key stored as a secret) and generate `appcast.xml` (`generate_appcast`), using release notes taken from the tag message or `CHANGELOG.md`.
7. Create the release on the public releases host (a GitHub Release in the releases-only repository, using a token scoped to that repository and stored as a secret) and attach the DMG, the zip, `appcast.xml` and SHA-256 checksums.
8. Open a pull request on the Homebrew tap (a `homebrew-vigie` repository, `brew tap <org>/vigie`, at first; the official homebrew-cask repository later) with the new version and checksum.

**Secrets** are stored in a GitHub **environment** called `release`, which requires a maintainer's approval and only allows tags as the source. Workflows triggered by forks or pull requests can never read them.

### 12.4 Auto-update (in the app)

- Uses **Sparkle 2**, the standard update framework for Mac apps distributed outside the App Store. It handles checking, downloading, verifying the EdDSA signature, installing and relaunching.
- **Appcast URL:** `https://github.com/<org>/<releases repo>/releases/latest/download/appcast.xml`, on the public releases-only repository (§12.1), never the private code repository. GitHub always redirects this URL to the newest stable release.
- **Beta channel** (from the public release, not in v0.1–v0.4 previews): pre-release tags publish a separate `appcast-beta.xml` that includes both betas and stable releases. Turning on "beta updates" in settings switches the feed URL. A GitHub Pages copy of the feed can replace this later if the redirect approach turns out to be limiting.
- **Settings** (in `[updates]`): `auto_check = true`, `check_interval = "24h"`, `auto_install = false` (ask first by default), `channel = "stable" | "beta"`.
- Updates are verified twice: the EdDSA signature (Sparkle) and the Developer ID signature plus notarization (macOS Gatekeeper). The public EdDSA key is built into the app's `Info.plist`.
- **Homebrew users:** the cask declares `auto_updates true`, so Sparkle and `brew upgrade` don't conflict.

### 12.5 Versioning
- Semantic versioning. `CFBundleShortVersionString` is `X.Y.Z`, and `CFBundleVersion` is a build number that always increases (CI run number), which Sparkle uses to compare versions.
- The JSON schema for script modules and the adapter event format have their own version numbers. Breaking changes to them need a major version bump.

---

## 13. Roadmap

| Version | Scope |
|---|---|
| **Spike** | `vigie hook claude` sends to a socket listener, which logs the event. Focus a specific **Warp** tab from a session. Decision point for the Warp approach. Same check for a **Ghostty** tab. |
| **v0.1** | Notch Host (physical + virtual, multi-display), arbitration with multi-slot sides, module protocol, config file, `agents.sessions` with the adapter protocol and the **Claude Code** adapter (full status model incl. done/failed, sleep handling, focus on the four terminals, peek with actions and setup-problem alerts, notifications pipeline, hook installer), generic `vigie agent` CLI, Chrome Hologram theme, i18n scaffolding, Reduce motion honored (animations removed), Settings › General `Launch at login` toggle, first-launch display prompt on displays without a notch, local activity log, **CI + release pipeline + Sparkle** (so every version after v0.1 updates itself) |
| **v0.2** | `agents.usage` (Claude local logs first, then plan limits; rings, pace, quota warning; **multiple Accounts** per provider), **Codex CLI** adapter, **`vigie run`**, `shelf` with Stash + Ask AI + **AirDrop** + **Image to Text** zones, **Privacy mode**, sounds |
| **v0.3** | Markdown script modules + JSON schema + per-Mac confirmation, **install from link** with signatures and **updates**, Script repository with the example scripts (a subset bundled), **`time`** (timers, countdowns, Pomodoro, break reminders), `calendar`, Home tab, **Gemini CLI** adapter |
| **v0.4** | `notes` (encrypted, secrets), iCloud sync, onboarding, settings window polish, Twin Metal Tactical theme, Presence mode (calm), Homebrew cask, public release |
| **Island spike** | Once hardware or the macOS 27 SDK is available: window layering against the system Dynamic Island, `NSScreen` auxiliary areas on island Macs, ActivityKit availability on macOS. Decides the `island` display mode (§14). |
| **Later** | Escalation to phone (ntfy, Pushover) after a session stays blocked, public script website with install buttons, natural-language timer entry, window management, clipboard history, dictation, translation, media, menu bar fallback mode |

---

## 14. Open questions and risks

1. **Warp tab focus.** This may not be possible reliably. It's the reason for the spike. **Fallback decided** (2026-11-06, PRD FR-24): if the Warp spike fails, v0.1 ships app-level focus for Warp, and the focus success metric is measured on iTerm2 and Ghostty.
2. **Plan-limit usage endpoints are unofficial** (for each provider). They may break or change. Keep them optional, isolated per adapter, and quick to patch.
3. ~~**Name.**~~ Decided: **Vigie** (French for a ship's lookout). Known namesakes in other fields: Vincoll/vigie (alpha endpoint-monitoring tool on GitHub), Neovigie VigieApp (lone-worker safety), ViGIE 3 (healthtech), Vigie (French Android call blocker). No Mac app found; Homebrew `vigie` is free; `github.com/vigie` is taken, so use an org like `vigie-app`. Still to do: INPI/EUIPO trademark search (class 9) and domain (`vigie.app` / `vigie.dev`). License: none for now, closed source (§2.1).
4. **Detecting "blocked" and "failed" per agent.** Claude Code: confirm which `Notification` subtypes it sends (permission prompt vs idle prompt), so "blocked" isn't triggered by a plain idle reminder. Codex and Gemini: confirm whether hooks or transcripts expose approval requests at all. All adapters: confirm which errors (connection lost, login required) can be detected for `session.error`.
5. **Agent CLIs change quickly.** Hook names, config formats and log formats can change between releases. Each adapter should detect the installed CLI version and report "unsupported version" instead of showing wrong statuses. Adapter test fixtures (recorded event samples) are needed for each supported version.
6. ~~**Minimum macOS version.**~~ Decided: macOS 15+ (current release and two major versions back). Revisit when a new major macOS ships.
7. ~~**Script module security.**~~ Decided (v0.4): every script requires confirmation on each Mac, showing the whole file, before it first runs (§9.2). Scripts still run unsandboxed.
8. **Coexisting with other notch apps.** Detect them and warn, since two apps can't share the notch.
9. **Signing identity.** Releases are signed with the maintainer's **organization** Developer ID, so Gatekeeper shows the organization's name. Decide whether the project's GitHub org/branding should match that name, and who in the organization can create and revoke the Developer ID certificate and the App Store Connect API key used by CI (use a key with the minimum role that allows notarization).
10. ~~**Macs with a system Dynamic Island.**~~ Decided for v1 (confirmed by the PRD, FR-2): island Macs are treated as plain displays (virtual notch); the `island` mode is revisited before public release. Background: the OLED touchscreen MacBook Pro (announced 2026-10-28, ships 2026-11-06) runs a system Dynamic Island on macOS 27 (Live Activities, Spotlight, Siri, system alerts), in the same top-center area Vigie uses. SwiftUI and the `NSPanel` approach still work. Unknowns: whether a third-party panel can draw over or beside the island, whether `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` still describe the usable space, and how Vigie peeks avoid colliding with system island animations. Candidate modes for `island` displays: draw beside the system island; hide and publish Live Activities instead; or menu bar fallback. **Decided (2026-11-04):** officially supported displays are `physical` and `plain` only. Island Macs run in plain/fallback mode until someone with the hardware runs the island spike (§13); it is not part of v0.1.
11. **ActivityKit on macOS.** Apple's WWDC 2026 material says Mac apps can create Live Activities shown in the Dynamic Island (or the menu bar on other Macs), but a developer reading the macOS 27 SDK reports it as `@available(macOS, unavailable)` (the local 26.5 SDK also marks it unavailable). Even if it is available, Live Activities only allow fixed templated layouts with limited updates: agent status and usage would fit; the shelf, drop zones and Ask AI would not.
12. **Touch input.** The new MacBook Pro has a touchscreen. Hover-driven behavior (open on hover, close on mouse leave, peek) needs tap equivalents. Hit targets in the closed notch need to be finger-sized.
13. **Menu bar fallback mode.** An optional mode with no floating pill: a status item that opens the same expanded view as a dropdown, for users who don't want anything over their menu bar. Also a possible fallback for `island` displays.
14. **Warning before manual sleep.** Keep-awake (§7.1.2) can't cover lid close or a user-initiated sleep. Research whether macOS allows intercepting or delaying it to warn while agents are working.
15. **Detecting "host went to sleep".** How to mark a session failed reliably after sleep (wake notification + session was working, vs. a process that survived the sleep).
16. **Ask AI launch.** Can Claude Code, Codex CLI and Gemini CLI start interactively with a file attached or a prefilled, unsent prompt? If not, the fallback pastes the paths for the user to complete (§7.1).
17. ~~**More blocked/failed sessions than slots.**~~ Decided (2026-11-06): the most recent fill all slots and `+X` counts the rest; on wake, one summary alert for several interrupted sessions (§7.1.2).
18. ~~**Script widgets in a closed-notch side slot.**~~ Decided (2026-11-07): non-session items share the left wing by per-item `priority`, the rest in `+X`; the right wing is sessions only (§5).
19. ~~**Defaults set only in UX mocks.**~~ Decided (2026-11-06): quota warning 80%, shelf TTL 7 days, clipboard clear 30 s; sounds off when onboarding's sound step is skipped; notes hotkey `opt+cmd+n` (⌥⌘N); Settings from `⌘,`, alerts, empty states, the expanded-view settings icon and the right-click menu on the closed notch.
20. ~~**Alerts suppressed by Do Not Disturb.**~~ Decided (2026-11-06): dropped by default; the user can choose to see the latest unresolved one per module when Focus ends (`[notify] after_focus`).
21. **Privacy mode detection** (§10.3). Whether macOS 15+ lets Vigie reliably detect screen sharing and recording. Excluding Vigie's windows from capture is reportedly ignored by ScreenCaptureKit on recent macOS, so it can't be relied on alone. Candidates: the system recording indicator state, known conferencing apps sharing the screen, a CGWindow/ScreenCaptureKit query. Prefer a method needing no new permission; pick in a spike, fall back to the manual toggle.
22. **Script repository review policy** (§9.6): what is accepted and who may merge, and its license. Decided (2026-11-06): named `vigie-scripts`, public from v0.3, no outside pull requests until the policy and license exist.
23. **Paid or free at public release** (§2.1). The app is closed source with no license for now; the business model is open. The public releases host is decided: a releases-only GitHub repository (§12.1).
