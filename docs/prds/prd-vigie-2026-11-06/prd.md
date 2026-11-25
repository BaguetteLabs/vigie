---
title: Vigie PRD
status: final
created: 2026-11-06
updated: 2026-11-25
---

# PRD: Vigie

## 0. Document Purpose

This PRD states what Vigie must do and why, at capability level. It was written after the detailed documents it sits above, to fill what they lack: the why, the users, scope by release, success measures, positioning and risks. Those documents stay the source for detail and win on their own ground. The exception is where this PRD deliberately adds or changes scope (features marked new, §6.1 release slots, FR-41 examples): there the PRD wins until SPEC is updated. Addendum §5 lists the SPEC sections to amend.

- [SPEC.md](../../SPEC.md): behavior detail, config keys, CLI, release pipeline.
- [DESIGN.md](../../ux-designs/ux-vigie-2026-11-04/DESIGN.md) and [EXPERIENCE.md](../../ux-designs/ux-vigie-2026-11-04/EXPERIENCE.md): look and behavior.
- [ARCHITECTURE-SPINE.md](../../architecture/architecture-vigie-2026-11-05/ARCHITECTURE-SPINE.md): build rules (AD-1 to AD-26).
- [epics.md](../../epics.md): stories, reconciled with this PRD (§9, question 4).

Features are grouped in §4 with globally numbered requirements (FR-1…). Terms are defined once in §3 and used verbatim. Inferred content, since confirmed by the user, is listed in §11. Technical mechanisms and research live in [addendum.md](addendum.md).

## 1. Vision

Developers now run several AI coding agents at once, each in its own terminal tab, each stopping at unpredictable moments to ask for approval, finishing quietly, or dying when the laptop lid closes. Plan quotas reset on 5-hour and weekly windows nobody can see. Today the only signals are terminal bells, scattered system notifications, and checking each tab by hand.

Vigie (French for a ship's lookout) turns the MacBook notch into a lookout post for that background work. The closed notch shows, in a few pixels, which sessions need you and how much quota is left. When a session is blocked, Vigie says so once, without stealing focus, and one shortcut brings the exact terminal tab forward. Around that core, Vigie keeps a few small tools that benefit from living at the top of the screen: a file shelf, timers and breaks, calendar reminders and a month view, quick encrypted notes, and Widgets anyone can write as a script.

Everything is a module, every module can be turned off, and a module that is off costs nothing. Every agent, Claude Code included, goes through an Adapter; none is special-cased. The whole configuration is plain text. Vigie never acts on a session in the user's place: it watches, tells, and takes you there.

It should feel like a quiet sci-fi instrument: metal, thin rings, uppercase readouts, everything contained inside the notch outline, never targeting imagery. Its words are terse and factual: no exclamation marks, no personification.

## 2. Target User

### 2.1 Jobs To Be Done

- **Know without looking.** "With 3 to 10 agent sessions open, I want to know at a glance which one needs me, so I stop cycling through tabs."
- **Get there in one move.** "When an agent is blocked, I want to land on its exact tab without hunting for it."
- **Don't lose work to sleep.** "I want to know when a run died because the Mac slept, and ideally keep it awake while agents work."
- **Pace my quota.** "I want to see how fast I'm burning my plan's 5-hour and weekly limits, across every account and agent I use."
- **Watch any long job.** "I want builds, deploys and other long commands to report like agents do."
- **Keep small tools at hand.** Files in transit, a Timer or Pomodoro, a reminder to take a break, the next meeting, a quick note with a secret in it, a custom metric.
- **Stay in control.** Nothing installs, runs, syncs or interrupts without the user having said so.

### 2.2 Audience and Stages

1. **Now:** the author, Romain (solo developer, MacBook and Mac Studio, Claude Code and Codex in Warp).
2. **Next:** a few invited developers, before any public release. Léa (UJ-3, UJ-7) stands for them: a backend developer on a MacBook Pro with an external display, Codex for work and Claude Code on the side, in iTerm2.
3. **Later:** public release once stable. The app is licensed under the GNU GPLv3 (decided 2026-11-25, §9); paid or free is undecided (§9).

Primary user at every stage: a developer on macOS 15+ running CLI coding agents. Secondary: anyone who wants only the Shelf, Time, Calendar or Notes modules; they must get those and nothing else (FR-4).

### 2.3 Non-Users (v1)

- People who want to approve or answer agents from the notch (deliberate non-goal, §5).
- Users of IDE-embedded agents only (Cursor, Copilot in an editor) with no CLI session.
- Teams wanting a shared dashboard of other people's agents.
- Mac App Store users.

### 2.4 Key User Journeys

UJ-1 to UJ-8 mirror EXPERIENCE.md Key Flows 1–8, where full beats and edge cases live.

- **UJ-1. Romain keeps a multi-session day under control.** Several Sessions run; one turns blocked; a peek appears once on the display under the pointer without taking focus; one shortcut brings its Warp tab forward. Quota rings show he is within pace. Realizes FR-9, FR-14, FR-24, FR-26.
- **UJ-2. Romain learns his run died when the lid closed.** On wake, the Session shows failed because the Mac slept, with a peek and Focus. Keep-awake prevents idle sleep while agents work, but it cannot stop a lid close, which is why the failed Alert matters. Realizes FR-18, FR-19.
- **UJ-3. Léa installs Vigie and gets her first useful alert.** Homebrew install, onboarding (theme, agent hooks shown as a diff, Accessibility, displays, sounds); later a Codex approval peeks on the display under the pointer while Slack keeps focus. Realizes FR-5, FR-9, FR-15, FR-58, FR-62.
- **UJ-4. Romain drops a file on Ask AI.** He drags a log onto the notch, drops it on Ask AI, and a new terminal tab opens with his default agent and the file attached. Realizes FR-32.
- **UJ-5. A script arrives on Romain's second Mac.** A synced script shows "awaiting confirmation"; he reviews the whole file, confirms, enters its secret for this Mac, and the Widget starts. Realizes FR-39, FR-40, FR-57.
- **UJ-6. Romain watches a deploy like an agent.** He runs `vigie run -- make deploy`. The notch shows it working; ten minutes later it fails and peeks, and Focus takes him to the tab. Realizes FR-23.
- **UJ-7. Léa installs a community script.** On the Script repository she finds a CI status script and clicks its install link. Vigie shows the full file, its source and author; she confirms; the Widget appears. A week later an update arrives, Vigie shows what changed, and she confirms again. Realizes FR-42 to FR-44.
- **UJ-8. Romain takes his break.** No Pomodoro is running. After 55 minutes at the keyboard, a break reminder peeks; he walks away; when he has been Away 5 minutes the break counts as taken and the cycle restarts without a click. (While a Pomodoro runs, its own breaks replace reminders, FR-49.) Realizes FR-49 (and FR-45 to FR-48 through the Pomodoro variant in EXPERIENCE.md Flow 8).

## 3. Glossary

- **Notch host** — the app shell that draws around the physical notch, or a virtual notch on displays without one.
- **Closed notch** — the always-visible compact state: two wings beside the notch.
- **Wing / Slot** — the left and right areas of the closed notch, each with a few slots (3 by default). The right wing shows Sessions only; on the left wing, quota rings, script items and the Time readout share the slots by priority.
- **Peek** — a one-time, non-focus-taking expansion of the closed notch announcing an Alert.
- **Alert** — an event a module raises (blocked, done, failed, quota warning, timer end, break reminder, calendar reminder, setup problem…), routed by the Notifier to peek, macOS notification and/or sound.
- **Notifier** — the single place that applies alert rules, quiet hours and Do Not Disturb.
- **Expanded view** — the panel opened by click or hotkey.
- **Tab** — one page of the Expanded view; one per module that offers it, plus Home.
- **Module** — a unit of functionality that can be turned off. Built-in modules are in Swift; Script modules are user files.
- **Session** — one run of a CLI coding agent (or of a command under `vigie run`) in a terminal tab.
- **Status** — a Session's state: idle, working, done, blocked, failed, gone. A stale Session (working, no event for a while) and a process-only Session have their own neutral looks, not a Status.
- **Adapter** — the per-agent integration that turns that agent's hooks or logs into Session events.
- **Focus** — the only Session action: bring the Session's terminal app, and when supported its exact tab, forward. Not to be confused with a **macOS Focus mode** (Do Not Disturb and similar), always written in full.
- **Provider / Account** — a usage source (Claude, Codex, Gemini…) and one login with it; a Provider can have several Accounts.
- **Quota ring / Pace** — the visual for usage of a limit window, and whether usage keeps up with elapsed time: **within pace** (usage at or under the elapsed-time marker, within the tolerance; the healthy state) or **ahead of pace** (usage past the marker by more than the tolerance).
- **Shelf / Stash** — the temporary file shelf and the act of putting something on it.
- **Drop zone** — a target that appears in the drop display, which grows out of the notch while a file is dragged over it (Stash, Ask AI, AirDrop, Image to Text); also on the Shelf tab.
- **Script module** — a user Markdown file with front matter and one code block, any language.
- **Widget** — what a Script module's output renders as: status, number, short text, or a page.
- **Confirmation** — the per-Mac user approval of a Script module's exact content; any content change requires it again.
- **Script repository** — the curated GitHub repository of community Script modules.
- **Timer / Countdown / Pomodoro** — a duration timer, a count to a clock time, and a work/break cycle.
- **Away** — the user is not at the Mac: no keyboard or pointer input for a threshold, or screen locked, screensaver on, or display asleep.
- **Keep-awake** — opt-in prevention of idle sleep while any Session is working.
- **Privacy mode** — the reduced display used while the screen is shared or recorded.
- **Presence mode** — full or calm motion and glow (a theme setting; not related to Away). "Calm mode" means Presence mode set to calm.
- **Spike** — a short time-boxed experiment that proves or disproves a risky capability before it is built.

## 4. Features

The release in each feature heading follows SPEC §13 (v0.1 to v0.4); v0.4 completes v1. Features new in this PRD are marked new; their release slots are confirmed in §11.

### 4.1 Notch host and closed notch (v0.1)

**Description:** Vigie draws around the physical notch, or shows a virtual notch on plain displays, on the displays the user chooses. The right wing shows Sessions; on the left wing, items from several modules share the slots by state and priority; overflow shows `+X`. It hides in full-screen apps and follows display changes live. Detail: SPEC §5, EXPERIENCE.md. Realizes UJ-1, UJ-3.

#### FR-1: Display placement
The user can choose which displays show Vigie (main, notched, all, named), with hot-plug and clamshell handled live.
- Plugging or unplugging a display re-places Vigie within 2 s with no restart.

#### FR-2: Virtual notch
On displays without a notch, Vigie shows a virtual notch with configurable idle look, position and style.
- Macs with a system Dynamic Island are treated as plain displays (virtual notch) in v1.

#### FR-3: Wing arbitration
The right wing shows Session glyphs only. On the left wing, every item (each provider quota ring, each script side-slot item, the Time readout) has a priority; items are ordered by state then priority, fill the wing's slots, and a `+X` count shows what doesn't fit (decided 2026-11-07).
- A blocked or failed Session always outranks idle content.
- Nothing is drawn outside the notch or panel outline: no menu bar or desktop overlay.

#### FR-4: Disabled modules cost nothing
A disabled module requests no permission and does no background work.
- With only the Shelf enabled, Vigie asks for no permission and makes no network call other than the update check, which the user can turn off.

#### FR-5: Never steal focus
No Vigie surface takes keyboard focus except after a deliberate user action (click or Vigie hotkey).
- An Alert arriving while typing in another app never moves the caret or the active app.
- The Expanded view never opens by itself; hover only highlights the notch unless the user enables hover-to-open.

### 4.2 Expanded view and Home (v0.1 shell, Home v0.3)

**Description:** A click or hotkey opens the Expanded view with one Tab per enabled module, full keyboard navigation, empty and setup states, and a Home tab of Widget cards. Detail: SPEC §10.

#### FR-6: Tabs per module
Each enabled module with a Tab appears in the Expanded view, in a user-set order.

#### FR-7: Home
Home shows the cards the user picks, in the user's order; clicking a card opens that module's Tab.
- The user picks and orders cards in Settings › Home: a list of modules and Script modules to tick, dragged into order (decided 2026-11-07).
- Every card has the same size in v1; Home has no in-place edit mode.

#### FR-8: Keyboard operation
Every Expanded view action is reachable from the keyboard.

### 4.3 Alerts and Notifier (v0.1)

**Description:** Modules raise Alerts; the Notifier decides, per alert kind, whether to peek, send a macOS notification, play a sound, or stay silent, with quiet hours and cooldowns. Do Not Disturb always wins. Detail: SPEC §5.2, §6. Realizes UJ-1, UJ-2.

#### FR-9: Peek
An Alert can peek once on the display under the pointer (or the main Vigie display if that display doesn't show Vigie), with Focus and Dismiss shortcuts registered only while the peek is visible.
- Peek shortcuts never use bare Esc or other common unmodified keys.

#### FR-10: Alert rules
The user can set, per alert kind: mute, outputs (peek, macOS notification, sound), quiet hours, cooldown, and an optional reminder that repeats the peek once after a delay if the state hasn't changed.

#### FR-11: Do Not Disturb respected
While macOS Do Not Disturb or another macOS Focus mode is on, no peek or sound happens; the closed notch still updates. There is no bypass.

#### FR-12: Setup problems
Configuration and permission problems surface as a setup-problem Alert with a way to fix them.
- Invalid config keeps the last valid config running.

#### FR-13: Local activity log
Vigie keeps a local-only log of Alerts, peeks, reminders and Focus outcomes for 30 days, viewable by the user and never sent anywhere. It is the data source for §8.

### 4.4 Agent sessions (v0.1 Claude Code, v0.2 Codex, v0.3 Gemini)

**Description:** Vigie tracks every CLI agent Session through Adapters fed by agent hooks or logs, shows Status in the closed notch and the Agents tab, and alerts on blocked, done and failed. Any other tool can report through the `vigie agent` CLI. Detail: SPEC §7.1, §8. Realizes UJ-1, UJ-2, UJ-3.

#### FR-14: Session tracking
Vigie tracks all concurrent Sessions of supported agents with Status idle, working, done, blocked, failed or gone.
- A Session whose agent process is gone is marked gone; a failed Session stays until dismissed or for 24 h.
- A working Session silent past a timeout shows a stale marker; agents known only from their process show presence, not Status.

#### FR-15: Hook installation with consent
Vigie offers to install agent hooks, showing the exact diff and keeping a backup, and removes them the same way when the user disconnects an agent; it never edits agent config silently.

#### FR-16: Hooks never slow agents
The hook command returns within 150 ms and never blocks the agent, even when Vigie is not running; events sent while Vigie is down are delivered on next launch.

#### FR-17: Honest status
On an unsupported agent version, or for an agent whose Adapter cannot detect blocked or failed, Vigie says so instead of showing a wrong Status.

#### FR-18: Host-slept detection
A Session interrupted by sleep is shown failed with the reason "host slept". Realizes UJ-2.

#### FR-19: Keep-awake (opt-in)
When enabled, Vigie prevents idle sleep while at least one Session is working, and releases it when none is.
- Off by default. Lid close and manual sleep are not covered and the setting says so.

#### FR-20: Agents tab
The Agents tab lists Sessions with Status, project, terminal and age; Focus is the only action.

#### FR-21: Generic agent CLI
Any tool can create and update a Session with `vigie agent` (status, message), without an Adapter.

#### FR-22: Ignored folders
The user can list folders whose Sessions are ignored.

#### FR-23: `vigie run`
The user can run any command as `vigie run -- <command>`: Vigie shows it as a working Session, then done or failed by exit code, with the same Alerts and Focus as agent Sessions. Ships in v0.2 with the Codex adapter epic. Realizes UJ-6.
- Exit code 0 gives done, any other gives failed; the command's own output and exit code pass through unchanged.
- Interrupting `vigie run` (Ctrl-C) passes the signal to the command and ends the Session without an Alert: a user interrupt is not a failure.

### 4.5 Terminal focus (v0.1)

**Description:** Focus brings the Session's exact terminal tab forward in Terminal.app, iTerm2, Warp and Ghostty; where a terminal can't target tabs, it activates the app and says so. Detail: SPEC §7.1.1. Realizes UJ-1.

#### FR-24: Exact-tab focus
Focus brings the Session's terminal tab forward in each supported terminal, at the level its Spike proves.
- Warp is the author's terminal. If the Warp Spike fails, v0.1 ships app-level Focus for Warp, and SM-6 is measured on iTerm2 and Ghostty.

#### FR-25: Graceful fallback
When the terminal tab can't be located, Focus activates the terminal app and Settings states that terminal's focus level.

### 4.6 Usage (v0.2)

**Description:** Quota rings and Pace for each Provider and Account; a Usage tab with per-window bars, 7-day history and today's estimated cost by project. Local-log Providers work offline; plan-limit Providers that need unofficial endpoints are opt-in. Detail: SPEC §7.2.

#### FR-26: Quota rings and Pace
The closed notch can show nested 5-hour and weekly rings with a Pace marker per Provider.

#### FR-27: Quota warning
The user sets a warning threshold (default 80%); crossing it raises an Alert or a visual-only warning.

#### FR-28: Usage tab
The Usage tab shows per-window bars, 7-day token history and today's estimated cost by project.

#### FR-29: Multiple Accounts
The user can add several Accounts per Provider, for every Provider, and see each one's usage separately.
- Each Account is bound to its own agent config or log location; Sessions are attributed to an Account by that location.
- The closed notch shows the Account of the most recent Session; the Usage tab shows the others.

#### FR-30: Opt-in remote limits
Fetching plan limits from a Provider's servers is off until the user enables it per Account; a failure shows a stale indicator, never a wrong number.

### 4.7 Shelf and drop zones (v0.2)

**Description:** Dragging anything over the notch opens Drop zones. Stash keeps files on the Shelf (by reference, copy or saved), expiring after a TTL with warning, never deleting permanently. Ask AI starts the default agent with the file. AirDrop and Image to Text are new zones. Without dragging, a Send to menu on Shelf items (right-click, keyboard, VoiceOver actions), `⌘V` on the Shelf tab and a macOS Services entry "Stash in Vigie" reach the same zones. Detail: SPEC §4.6, §7.3; look and behavior in the UX spines (Story 1.7c). Realizes UJ-4.

#### FR-31: Stash
Dropping on Stash puts items on the Shelf, with Quick Look, reveal, pin and expiry warning.
- Expiry never deletes a user's original file.
- Stash and the other zones are also reachable without dragging: a Send to menu on Shelf items, `⌘V` on the Shelf tab, and the Services entry "Stash in Vigie" (accessibility, FR-8).

#### FR-32: Ask AI
Dropping on Ask AI opens a new terminal tab with the default agent and the file attached, with no dialog. An alternate folder is available with ⌥.

#### FR-33: AirDrop drop zone
Dropping on AirDrop opens the macOS AirDrop picker for the dropped items. On by default. Ships in v0.2 with the Shelf.

#### FR-34: Image to Text drop zone
Dropping an image or PDF on Image to Text recognizes its text on the Mac and copies it to the clipboard, with a brief confirmation. Off by default. Ships in v0.2.
- No image leaves the Mac.

### 4.8 Sounds and themes (sounds v0.2, themes v0.1 / v0.4)

**Description:** Optional sounds for blocked, failed, done, quota warning, timer end, break reminder and calendar reminder (the last three off by default), built-in or custom, following Do Not Disturb. Two theme families (Chrome Hologram v0.1, Twin Metal Tactical v0.4), light and dark, custom themes, user colors, full or calm Presence mode. Detail: SPEC §10.2, DESIGN.md.

#### FR-35: Sounds
Each sound-capable Alert kind can play a built-in or custom sound, or none.

#### FR-36: Themes
The user can pick a theme and light/dark/auto, and override any status color.
- A theme changes look only: wording, layout and slots are the same in every theme.

#### FR-37: Calm Presence mode
Calm mode removes motion and glow, except one simple pulse on a blocked or failed Session; macOS Reduce motion forces it.

### 4.9 Script modules and community scripts (runtime v0.3)

**Description:** A Script module is a Markdown file with front matter and one code block in any language. Its output becomes a status, number or short-text Widget on Home, a slot, or a full page. It runs only after Confirmation of its exact content on each Mac, with secrets in the Keychain. Scripts can be installed from the Script repository by link, and update with a diff and new Confirmation. Detail: SPEC §7.4, §9. Realizes UJ-5, UJ-7.

#### FR-38: Script format and widgets
A dropped-in Script module produces a Widget from its JSON or plain output, on its interval, with a timeout.
- A Widget can open a URL, run a command or copy text when clicked.
- A failing run keeps the last good output with a warning badge.

#### FR-39: Confirmation per Mac
A Script module never runs before the user confirms its full content on that Mac; any content change requires a new Confirmation.

#### FR-40: Script secrets
A Script module can declare secrets; the user enters them per Mac and they live only in the Keychain.

#### FR-41: Example scripts
Vigie ships example scripts: GitHub PRs, site up/down, CI or deploy status, revenue (Stripe-style), and a text Widget. The examples live in the Script repository; the app bundles a small subset.

#### FR-42: Install from link
Opening a `vigie://install` link downloads the script and shows its full content, source URL and author before Confirmation; nothing installs without it. Ships in v0.3. Realizes UJ-7.
- Scripts merged into the Script repository are signed by its CI after review; Vigie verifies the signature against public keys built into the app.
- The Confirmation shows "Verified: Vigie Script repository" for a valid signature; any other script (unsigned, invalid signature, other site) gets a stronger warning, and its author is shown as "claimed by the file".
- A signature proves where a script comes from and that it was reviewed, not that it is safe; the Confirmation still shows the full file.
- A link from any website leads to the same Confirmation; a declined install leaves no file behind.

#### FR-43: Script updates
A script installed from a link records its source; Vigie checks it for updates, shows what changed, and asks for a new Confirmation before running the new version.
- Update checks happen at most once a day and can be turned off.

#### FR-44: Script repository
Community scripts live in a separate, curated GitHub repository; contributions arrive as pull requests reviewed by the maintainer. A public website with install buttons comes later.

**Feature NFR:** Script modules run unsandboxed with the user's rights; the README and Confirmation screen say so plainly.

### 4.10 Time (new, v0.3 with Calendar)

**Description:** A Time module with Timers (for a duration), Countdowns (to a clock time) and Pomodoro cycles, plus break reminders driven by whether the user is actually at the Mac. Running items can show in the closed notch if the user wants. Ends raise Alerts routed like any other, sound included if configured. Realizes UJ-8.

#### FR-45: Timers and Countdowns
The user can start, pause and cancel several named Timers and Countdowns from the Time tab or a hotkey.
- Running items survive relaunch and sleep; an end that passed while asleep raises its Alert once on wake.

#### FR-46: Pomodoro
The user can run work/break cycles with configurable lengths (default 25/5, long break 15 every 4).
- When a work phase ends, the break waits for the user: it is announced (break peek with Start break, Snooze and Skip, or a quiet `BREAK DUE` in the closed notch) and starts only when the user starts it. A break that ends returns to work on its own.
- While the user is Away during a work phase, the Pomodoro pauses, and it resumes when the user is back.

#### FR-47: Closed-notch display (optional)
When enabled, the nearest-to-end running item shows on the left wing as remaining time, a ring, or both (user choice), sharing the slots by priority. Off by default.

#### FR-48: End alerts
A Timer, Countdown or Pomodoro phase ending raises an Alert routed by the Notifier.

#### FR-49: Break reminders
When enabled, after a configurable time spent at the Mac (default 55 min) Vigie raises a break Alert; the break counts as taken once the user has been Away for the break length (default 5 min), and the cycle restarts with no action.
- Being Away is detected from input idle time and lock, screensaver or display sleep; Keep-awake does not affect it. No camera is ever used.
- Time Away during a work period does not count as work.
- While a Pomodoro runs, break reminders are paused; the Pomodoro's own breaks replace them.
- The user chooses how strong the reminder is: a peek with Start break, Snooze and Skip, or a quiet closed-notch `BREAK DUE` with no peek or sound.

**Out of Scope:** natural-language entry ("25m tea") is a later enhancement.

### 4.11 Calendar (v0.3)

**Description:** Reminder Alerts at each event's own reminder times, with no persistent calendar display in the closed notch; Calendar tab with month grid, upcoming list and Join call. Detail: SPEC §7.5.

#### FR-50: Calendar reminders and tab
Vigie shows a month grid with upcoming events, from macOS calendars the user selects. The closed notch has no persistent calendar display; instead, an event raises an Alert (peek), like a blocked Session does, at each reminder time set on it in Calendar (decided 2026-11-07).
- Events without a reminder raise nothing.
- Calendar Alerts follow Do Not Disturb, macOS Focus modes and the after-Focus setting (drop or replay) like every Alert (FR-11).
- The peek has two actions: Join call when the event has a video link, otherwise Open Calendar; and Dismiss.

#### FR-51: Join call
Events with a video link offer Join call, user-triggered only.

### 4.12 Notes (v0.4)

**Description:** A floating notes panel from a global hotkey, Markdown with masked secrets, end-to-end encrypted, synced through iCloud if enabled. Detail: SPEC §7.6.

#### FR-52: Quick notes panel
A global hotkey opens a notes panel over any app; closing it returns focus where it was.

#### FR-53: Secrets in notes
Secret spans render masked; Copy copies without revealing and clears the clipboard after a delay (default 30 s).

#### FR-54: Encrypted notes
Notes are encrypted at rest and in sync; plaintext exists only in memory.
- A recovery key lets another Mac read the notes; Vigie never creates a second notes key.

### 4.13 Privacy mode (new, v0.2)

**Description:** While the screen is shared or recorded, Vigie shows only Status glyphs and numbers; nothing that names or quotes user content.

#### FR-55: Privacy mode
While Vigie detects screen sharing or recording, every Vigie surface, including peeks and the macOS notifications it sends, shows only Status glyphs, rings and numbers and hides every user-supplied name or text. Examples: notes and secrets, Session titles and messages, project names (also in cost by project), Shelf items and thumbnails, Timer labels, Account names, Widget text, calendar titles.
- Turning Privacy mode on and off needs no user action; the user can also force it on.
- If detection is not possible on a macOS version, Settings says so and offers the manual toggle.

> **[NOTE FOR PM]** Detection method and its permission cost are unproven (addendum §2). If it needs the Screen Recording permission, it is requested only when automatic detection is turned on.

### 4.14 Configuration, sync and settings (config v0.1, sync v0.4)

**Description:** All configuration in a human-editable TOML file, live-reloaded, in a user-chosen (git-able) folder; machine-specific settings stay local; secrets stay in the Keychain. Optional iCloud sync of config, scripts and notes. A native Settings window generated from module settings; first-launch onboarding. Detail: SPEC §10.1, §11.

#### FR-56: Config as code
Every setting lives in a plain-text file the user can edit; changes apply live; Vigie's own edits keep comments.

#### FR-57: iCloud sync
When enabled, config, Script modules and notes sync across the user's Macs; machine-specific settings, secrets and Account credentials never sync.

#### FR-58: Settings and onboarding
A Settings window covers every module setting; onboarding walks through theme, agent hooks, permissions, displays, sounds and launch at login, every step skippable.
- From v0.1, before onboarding exists: a first launch with a display without a notch shows a one-time prompt asking where Vigie should appear, and Settings › General has a Launch at login toggle.

#### FR-59: Single instance and login
Only one Vigie runs per user; launch at login is a Settings toggle from v0.1 and is offered in onboarding (v0.4), preselected; Vigie never shows a Dock icon.

#### FR-60: Other notch apps
When another known notch app is running, Vigie warns once and explains how to avoid overlap (v0.4).

### 4.15 Distribution and updates (v0.1 pipeline, public v0.4)

**Description:** Signed and notarized builds from CI, Sparkle auto-updates with an opt-in beta channel, Homebrew cask. Detail: SPEC §12.

#### FR-61: Signed builds and updates
Every release is signed and notarized. Vigie checks for updates automatically and installs only after the user agrees (automatic install is opt-in); the user can opt into betas from the public release.

#### FR-62: Homebrew
Vigie installs with Homebrew from the `homebrew-vigie` tap (`brew tap <org>/vigie`, then `brew install --cask vigie`); the short `brew install --cask vigie` applies only once an official cask exists.

### 4.16 Accessibility and language (floor from v0.1)

**Description:** The v1 accessibility floor from EXPERIENCE.md, and localization readiness. Full VoiceOver is after v1.

#### FR-63: Accessibility floor
Every control and glyph has an accessibility label that includes its state; Reduce motion removes animations from v0.1; Reduce transparency and Increase contrast are honored; text contrast is at least 4.5:1; peek actions work by global shortcut.
- Color is never the only cue: every Status also differs by shape, glyph or text.

#### FR-64: Localizable from the start
The interface ships in English, and every user-facing string is localizable from v0.1.

## 5. Non-Goals (Explicit)

- **Acting for the user.** Vigie never approves, denies, answers or types into an agent Session. Focus is the only Session action.
- **Mascots, companions, pets.** No animated characters, ever.
- **Launcher or palette.** No app launcher, command palette or calculator.
- **Live agent conversations in the notch.**
- **Media, clipboard history, dictation, translation, window management** (later at most).
- **Third-party compiled plugins** loaded at runtime. Extension is by scripts.
- **Mac App Store.**
- **Telemetry.** No analytics or automatic crash reports. Network only for update checks, opt-in usage limits, Script modules, and script installs and updates; diagnostics only through a user-triggered Copy diagnostics, secrets excluded.
- **Camera-based presence.**

## 6. MVP Scope

"v1" is the state after v0.4. v0.1 is the first build the author uses daily.

### 6.1 In Scope (v1)

| Release | Contents |
|---|---|
| Spikes | Hook-to-socket, Warp tab focus, Ghostty tab focus |
| v0.1 | Notch host, Expanded view shell, Alerts, Sessions with Claude Code, Keep-awake, terminal focus (4 terminals), config file, basic Settings, Chrome Hologram, signed releases with auto-update |
| v0.2 | Usage with multiple Accounts, Codex adapter, `vigie run`, Shelf with Stash / Ask AI / AirDrop / Image to Text, Privacy mode, sounds |
| v0.3 | Home, Script modules with install-from-link and updates, example scripts, Time module with breaks, Calendar, Gemini adapter |
| v0.4 | Notes, iCloud sync, onboarding, full Settings, Twin Metal Tactical and custom themes, Calm mode polish, Homebrew, public release readiness |

Release slots of the new features (`vigie run`, Privacy mode, multiple Accounts, AirDrop, Image to Text, Time, install-from-link) are as shown and confirmed (§11).

No cut line: scope stays as listed; implementation will be mostly AI-generated.

### 6.2 Out of Scope for v1

- Escalation to phone (ntfy, Pushover) after a Session stays blocked: accepted, after v1.
- Public script website with install buttons: after v1 (the repository and links ship in v1).
- Natural-language timer entry: later.
- Dynamic Island display mode, touch input, menu bar fallback mode: later, hardware-gated.
- Community Adapters (OpenCode, Aider, Cursor CLI) and further terminals: not before outside contributions are accepted (no outside contributions to the app for now, 2026-11-06; the license is the GNU GPLv3, decided 2026-11-25).
- Script-raised alerts, script sandboxing, list widgets; Touch ID for notes; full VoiceOver; calendar week view; Home card sizes and an in-place Home edit mode.

## 7. Positioning

Research: [research-landscape.md](research-landscape.md), [research-macmenubar.md](research-macmenubar.md) (154 notch apps catalogued).

The notch space is crowded: roughly 35 agent-focused notch apps and 45 all-in-one notch utilities. Nearly all agent apps center on approving requests from the notch; general apps center on media and shelves. The closest overlaps are Crowny (closed, agents plus time tools, notes, shelf, calendar), CodeIsland (open source, agents only, broad agent coverage) and Vibe Island (paid, agents and quota).

Vigie's position: **a lookout, not a remote control.** It differentiates on:
1. **Watch, never act**, so it is safe to leave running; Focus takes you to the real terminal.
2. **Any long job, not just agents** (`vigie run`, `vigie agent`).
3. **Scripts as plugins** with per-Mac Confirmation and the curated Script repository; no notch app offers a script-folder plugin model with per-Mac Confirmation.
4. **Local-first usage** across Providers and Accounts, with remote limits opt-in.
5. **Clean, reversible hooks** installed with a diff and backup.
6. **Privacy by construction:** no telemetry, Keychain secrets, encrypted notes, Privacy mode.
7. **Light footprint**, measured (SM-4).

Vigie does not try to win on agent count or on all-in-one breadth. The app is licensed under the GNU GPLv3 (decided 2026-11-25; it started closed source), and its source repository `BaguetteLabs/vigie` is public since 2026-11-25 (was private from 2026-11-06, AD-20). The research's "open-source hybrid" slot was not claimed because the source was private; it stays unclaimed for now (positioning unchanged, open for the user to revisit) and positioning rests on items 1 to 7.

## 8. Success Metrics

No input document set these targets; this PRD proposes them, confirmed in §11.

**Primary**
- **SM-1: Daily use by the author.** Romain uses Vigie every working day on both Macs for 30 consecutive days after v0.1 and turns off other agent notifications. Validates FR-9, FR-14, FR-24.
- **SM-2: No missed blocked Session.** Over a month of use, no blocked Session goes unnoticed for more than 10 minutes while Romain is at the Mac. Validates FR-9, FR-14.
- **SM-3: Invited users stay.** Before public release, at least 3 of 5 invited developers still run Vigie after 4 weeks.

**Secondary**
- **SM-4: Footprint.** Idle CPU under 1% and memory under 150 MB with Sessions, Usage and two Script modules enabled; hooks add under 150 ms to an agent step. Validates FR-4, FR-16.
- **SM-5: Correct Status.** False blocked or failed under 1 in 50 transitions, logged by the author during dogfooding. Validates FR-14, FR-17, FR-18.
- **SM-6: Focus works.** Exact-tab Focus succeeds at least 95% of the time in Warp and iTerm2. Validates FR-24.

**Counter-metrics (do not optimize)**
- **SM-C1: Interruptions.** Peeks per working hour; a rising number means rules are too loose, not that Vigie is more useful. Counterbalances SM-2.
- **SM-C2: Feature count.** More modules is not better; every module must survive SM-4. Counterbalances scope growth.
- **SM-C3: Stars and downloads before stability.** Public numbers are not a goal before v1 is stable. Counterbalances SM-3.

## 9. Open Questions

1. **Business model.** Decided 2026-11-25: the app is licensed under the GNU GPLv3 only (`GPL-3.0-only`; supersedes the 2026-11-06 decision "closed source with no license, all rights reserved"). Unchanged: no outside contributions to the app for now (2026-11-06, not changed by the license) and the code repository public since 2026-11-25 (was private from 2026-11-06). Still open: paid or free at public release, and the Script repository's own license (it is public). Distribution consequence: releases and the update feed must be hosted publicly (addendum §4; the code repository was private when this was decided and is public since 2026-11-25, the hosting decision is unchanged). Donationware and the EXPERIENCE.md Settings Support pane stay superseded (2026-11-06) until a model is chosen; the 2026-11-25 license change does not reinstate them.
2. **Privacy mode detection.** Whether macOS 15+ lets Vigie reliably detect screen sharing and recording (addendum §2).
3. **Script repository review policy** (what is accepted, who may merge); its license is part of question 1.
4. ~~**Epics reconciliation.**~~ Resolved: epics.md is reconciled with this PRD and all assumptions A1–A90 are ruled.
5. Inherited from SPEC §14: Warp and Ghostty tab focus, blocked/failed detection per agent, unofficial endpoints, signing identity, Dynamic Island Macs, manual-sleep warning, Ask AI launch per CLI. (Slot overflow and DND replay vs drop are decided: SPEC §14.17, §14.20.)

## 10. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Agent CLIs change hooks or log formats often | Wrong or missing Status | Version gating, fixtures per Adapter, honest "unsupported" (FR-17) |
| Unofficial usage endpoints break or rate-limit | Wrong quota | Opt-in, isolated, stale indicator (FR-30); local logs first |
| Apple ships native agent or Live Activity features in the notch | Reduced need | Stay focused on what Apple won't do: cross-agent, scripts, terminal focus |
| Single maintainer; no outside contributions to the app for now | Stalls; no outside fixes to the app | Plain-text config, scripts as extension point (public Script repository), small dependency list |
| Community scripts run arbitrary code | User harm, reputation | Confirmation per Mac, diff on update, plain warning; repository review covers only repository scripts, and links from other sites get a stronger warning (FR-42) |
| New MacBook Pros have a system Dynamic Island | Vigie falls back to a virtual notch on the newest laptops | Virtual notch in v1 (FR-2); revisit the island display mode before public release |
| Crowded market | Few users | Not a goal before v1 (SM-C3); positioning §7 |
| Conflicts with other notch apps | Overlap, confusion | Coexistence warning (FR-60, v0.4) |

## 11. Confirmed Assumptions

All inferred items below were confirmed by the user on 2026-11-06.

- §4.3 FR-13 — local activity log, 30 days.
- §4.4 FR-23 — `vigie run` ships in v0.2.
- §4.4 FR-23 — Ctrl-C ends the Session without an Alert.
- §4.6 FR-29 — closed notch shows the Account of the most recent Session.
- §4.7 FR-33, FR-34 — AirDrop and Image to Text (formerly Copy text, renamed 2026-11-07) drop zones ship in v0.2.
- §4.9 FR-41 — examples live in the Script repository, a subset bundled.
- §4.9 FR-42, FR-43 — install-from-link in v0.3; update checks daily, can be turned off.
- §4.10 — Time module in v0.3; Pomodoro defaults 25/5/15×4; closed-notch display off by default.
- §4.10 FR-49 — break reminders paused during a Pomodoro.
- §4.13 — Privacy mode in v0.2; manual toggle where detection is impossible.
- §6.1 — release slots of all new features.
- §8 — every success-metric target.
- addendum §1 — Present if input within ~90 s.
- addendum §4 — until an update is confirmed, the old version keeps running.
- addendum §4 — Ed25519 detached signatures, keys built into the app.
