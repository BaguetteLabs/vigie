---
type: review
lens: adversarial (compliant-but-incompatible unit pairs)
target: ../ARCHITECTURE-SPINE.md
sources: ['../../../SPEC.md', '../../../ux-designs/ux-vigie-2026-11-04/EXPERIENCE.md']
date: '2026-11-05'
---

# Adversarial review — Vigie architecture spine

**Method.** For each hole: two units built by different people (or agents), each obeying every AD and convention to the letter, that still don't fit together. Then the concrete failure, and the AD wording that closes it. Holes the spine already clearly covers are left out.

**Verdict: not yet a safe build substrate.** The microkernel split and the single-writer rules (AD-5, AD-8, AD-9) are sound. But three areas are left for each builder to define on their own, and that is where the incompatibilities come from:

1. **The `ModuleContext` surface.** AD-1 forbids modules from importing VigieCore, yet the services modules need (secrets, drop zones, power, permissions, terminal launch) are not on the context SPEC §4.5 defines.
2. **Startup and event ordering** across the CLI, the spool, the Event Server and `SessionStore`.
3. **Who owns which config key**: synced vs local, module vs Notifier, sessions vs usage.

Four critical holes and eight high holes need a spine edit before parallel building starts.

| # | Severity | Hole | Units in conflict |
|---|---|---|---|
| C1 | critical | Spool replay runs before anything subscribes; the truncate step loses events; replay fires stale alerts | Event Server ↔ AgentsSessions / SessionStore; VigieCLI ↔ Event Server |
| C2 | critical | `ModuleContext` is missing the services AD-1 makes mandatory | ModuleKit (protocol) ↔ VigieCore (implementation) ↔ every module |
| C3 | critical | The hook's parent PID is a short-lived shell, so liveness removes every session | VigieCLI ↔ SessionStore liveness |
| C4 | critical | The notes key splits: a second Mac or a dev build mints a new key in a shared folder | Notes (Mac A) ↔ Notes (Mac B / Vigie Dev) |
| H1 | high | Separate CLI processes deliver events out of order (late `tool.end` after `turn.end`) | VigieCLI ↔ SessionStore |
| H2 | high | Wake handling races liveness; no owner for power/sleep | AgentsSessions ↔ VigieCore power service |
| H3 | high | Usage provider identity, plus adapter config owned by sessions but read by usage | AgentsSessions ↔ AgentsUsage ↔ Adapters |
| H4 | high | Who decides which keys are synced or local; unknown keys across versions | ConfigStore ↔ modules ↔ Settings ↔ an older app on another Mac |
| H5 | high | Alert config has three owners; reminders can't see state; the action type is undefined | Notifier ↔ AgentsSessions / AgentsUsage ↔ `[sounds]` |
| H6 | high | The `DropZone` contract can't carry ⌥, theme colors, placement or security scope | Shelf ↔ AgentsSessions ↔ Notch Host |
| H7 | high | Dev and release hook installers in the same `~/.claude/settings.json` | ClaudeAdapter (release) ↔ ClaudeAdapter (dev) ↔ user's other hooks |
| H8 | high | The CLI can't import `AppEnvironment`; socket ownership across a Sparkle relaunch | VigieCLI ↔ VigieCore; old app ↔ new app |
| M1 | medium | Script ids collide with built-in ids and reserved keys; `manifest` is static | Integrations ↔ Registry ↔ ConfigStore |
| M2 | medium | Terminal choice per session vs config; no "open tab" API; `capture` triggers an Automation prompt | AgentsSessions ↔ TerminalAdapters |
| M3 | medium | Where `vigie agent --status` gets mapped; `idle` can't be reached; id collisions | VigieCLI ↔ AgentsSessions |
| M4 | medium | Focus and hotkey arbitration: notes panel vs expanded view vs peek | Notes ↔ Notch Host ↔ HotkeyRegistry |
| M5 | medium | Theme color override precedence | VigieUI ↔ ConfigStore ↔ custom themes |
| M6 | medium | ConfigStore patches a stale copy when the file changes underneath it (git pull, iCloud) | ConfigStore ↔ external editors ↔ file watcher |
| M7 | medium | Core can't call `normalize`; EventBus payload type is undefined | VigieCore Event Server ↔ AgentKit ↔ ModuleKit |
| L1 | low | AD-11 "storage only" contradicts the notes folder and shelf Trash moves | Notes / Shelf ↔ AD-11 |
| L2 | low | JSON state writes aren't atomic | SessionStore / Shelf ↔ crash reload |
| L3 | low | Sessions and usage each tail the same agent logs with separate cursors | AgentsSessions ↔ AgentsUsage |

---

## Critical

### C1 — Spool replay ordering, the truncate race, and stale alerts on replay

**Units:** Event Server (VigieCore) ↔ `SessionStore` (AgentsSessions); VigieCLI ↔ Event Server.

**How both comply and still clash:**
- AD-6 says the Event Server "on launch … replays the spool in order, then truncates it, before accepting socket traffic". The VigieCore builder does this inside `EventServer.start()`, which the app calls early in launch.
- The AgentsSessions builder subscribes to `agent.hook` in `start(context:)`, as SPEC §4.3 step 4 says. That runs when the Registry starts modules.
- Nothing orders these two steps, so a correct core replays into an EventBus with no subscribers. Every spooled event is dropped, and the spool is then truncated.

**Second failure, the truncate race.** Read-then-truncate isn't atomic.
- A hook that fires between "spool read" and "truncate" finds the socket not yet listening, so it appends to the spool, and the truncate then erases it.
- If the core instead binds the socket after truncating, hooks fired during replay land in a spool that won't be read until the next launch.

**Third failure, stale alerts.** If the app was quit for two days, replay delivers `needs.input` from two days ago.
- `SessionStore` correctly moves the session to blocked and posts `session.blocked`, so a peek and sound fire for a session that ended long ago.
- `T+` is computed from arrival time, because the envelope (AD-7) has no timestamp.

**Fourth failure, reconcile order.** AD-6 says the store reloads, then reconciles with liveness, but the order relative to replay is unstated.
- Reconcile before replay: a dead session is removed, then a spooled `tool.start` brings it back with no `session.start`.

**Close it — replace AD-6's last two sentences with:**
> On launch, in this order: (1) `SessionStore` loads its persisted table; (2) the Event Server binds and listens on the socket, queuing incoming lines without dispatching them; (3) every module that subscribes to events has had `start(context:)` called; (4) the Event Server atomically renames `spool.jsonl` to `spool.replaying.jsonl`, dispatches its lines in file order with `replayed = true`, then deletes it; (5) queued socket lines are dispatched; (6) `SessionStore` runs one liveness reconcile. CLI writers only ever append to `spool.jsonl`, so lines written after the rename survive for the next drain. The Event Server also drains the spool whenever `spool.jsonl` appears while it is running.

**And add to AD-7:**
> Every envelope carries `sent_at` (ISO 8601 UTC, fractional seconds), set by the CLI when the event happens. Consumers compute time-in-state from `sent_at`, never from arrival time. `SessionStore` applies replayed events to state but posts no Notifier event for a replayed transition whose `sent_at` is older than 5 minutes; the closed notch still shows the resulting state.

### C2 — `ModuleContext` is missing the services AD-1 makes mandatory

**Units:** ModuleKit (declares `ModuleContext`) ↔ VigieCore (implements it) ↔ Notes, AgentsUsage, AgentsSessions, Shelf, Integrations.

**How both comply and still clash:**
- AD-1 says a module never depends on VigieCore and interacts "through `ModuleContext` services (events, notifier, drop zones, host)".
- SPEC §4.5 `ModuleContext` lists `settings, storage, scheduler, hotkeys, notifier, events, host, log`. It has no drop zones, no secrets, no permissions, no power and no clipboard.
- AD-9 says "All Keychain access goes through the core `SecretStore`", but the Notes module can't import VigieCore.

So the builders diverge:
- The Notes builder adds `var secrets: SecretStore` to a local protocol extension.
- The AgentsUsage builder passes credentials through its adapter (AgentKit), which has no SecretStore either. It calls the Security framework directly, against AD-9.
- The AgentsSessions builder (AD-4 gives it adapters through its initializer) also needs power assertions and wake notifications. It calls IOKit and NSWorkspace directly, while the core builder writes a "core power service" per Deferred.

Result: two power-assertion owners, Keychain items with different service names, and drop zones registered through three different paths.

**Close it — add a new AD:**
> **AD-19 — ModuleContext is the complete module API.** `ModuleContext` (declared in ModuleKit, implemented only in VigieCore) exposes exactly: `settings`, `storage`, `secrets` (`SecretStore` facade scoped to the module id), `scheduler`, `hotkeys`, `notifier`, `events`, `host` (incl. panel and focus requests), `permissions`, `power` (`preventIdleSleep(reason:) -> Token`, `sleepWake: AsyncStream<SleepWakeEvent>`), `clipboard` (`copy(_:clearAfter:)`), and `log`. Drop zones are declared on the module (`NotchModule.dropZones`) and collected by the host; no module registers them any other way. A module that needs a system facility not on this list gets it added to ModuleKit and VigieCore first; modules never call Security, IOKit power APIs, `NSWorkspace` sleep/wake notifications, `NSPasteboard` writes or TCC request APIs directly. Adapters receive what they need (`SecretStore` facade, `Logger`) from the agent module that owns them, never globally.

### C3 — The hook's parent PID is a short-lived shell, so every session is removed

**Units:** VigieCLI (`vigie hook`) ↔ `SessionStore` liveness (AgentsSessions).

**How both comply and still clash:**
- SPEC §8.2: the CLI "adds the parent PID". The CLI builder sends `getppid()`.
- Claude Code (and most agents) run hook commands through `sh -c`, so the parent is that transient shell, which exits a few milliseconds later.
- SPEC §7.1: "each session stores the PID of the agent process; a periodic check (every 10 s) removes sessions whose process has died". The sessions builder does exactly that.

Result: every session goes `gone` within 10 s of each hook. The CLI can't know which ancestor is the agent: it depends only on Wire, while the agent process name is adapter knowledge.

**Close it — add to AD-5:**
> The CLI sends the ancestor chain of its own process (`[{pid, ppid, name, start_time}]`, up to 8 levels) and never picks the agent PID itself. Each `AgentAdapter.normalize` picks the agent process from that chain (`AgentAdapter.agentProcess(in:)`); the generic `vigie agent` path uses the first ancestor that is not a shell. Liveness compares both PID and process start time, so a reused PID is not seen as alive.

### C4 — The notes key splits: Mac B or Vigie Dev mints a second key in a shared folder

**Units:** Notes on Mac A ↔ Notes on Mac B (or Vigie Dev on the same Mac).

**How both comply and still clash:**
- AD-9: one synchronizable notes key. AD-10: notes encrypted with "the notes key".
- On Mac B, iCloud Keychain hasn't delivered the item yet (minutes to hours). The Notes builder finds no key, so it creates one, which AD-9 allows ("the single notes encryption key").
- AD-17: Vigie Dev has a different bundle ID, so possibly a different keychain access group. It still uses the release config folder by default, and so the same `[modules.notes] folder`. It also finds no key and creates one.

Result: two keys write into one synced folder. Each Mac can read only half the notes, and "last writer wins per file" means a note re-saved on B becomes unreadable on A.

**Close it — add to AD-10:**
> Every note file starts with a plaintext header `{format, key_id}`. The notes module creates a key only when no key is available **and** the notes folder contains no note files; if note files exist with a `key_id` it doesn't have, the module shows a "waiting for notes key / enter recovery key" state and writes nothing. Keychain items use a service name and access group derived from the release identity, shared by Vigie and Vigie Dev; if Vigie Dev can't read the release key, it must use its own notes folder.

---

## High

### H1 — Separate CLI processes deliver events out of order

**Units:** VigieCLI ↔ `SessionStore`.

**How both comply and still clash:**
- SPEC §8.2: `vigie hook` "exits immediately … never slows down … the agent". To guarantee that, the CLI builder forks or detaches the socket write.
- `PostToolUse` (→ `tool.end` → working) and `Stop` (→ `turn.end` → done) fire a few milliseconds apart as two processes, so they reach the socket in either order.
- `SessionStore` applies the transition table strictly in arrival order (AD-5). The session ends up **working** after the turn ended, never alerts "done", and later gets the stale `?` badge.

**Close it — add to AD-6:**
> The CLI completes its socket write (or spool append) synchronously before exiting, with a 100 ms total budget; it never forks, detaches or retries in the background. `SessionStore` ignores, for status purposes, any event whose `sent_at` is earlier than the `sent_at` of the last event it applied to that session (the event may still update metadata such as last action).

### H2 — Wake handling races liveness; no owner for power and sleep

**Units:** AgentsSessions (SessionStore) ↔ VigieCore power service (Deferred: "contained in SessionStore + a core power service").

**How both comply and still clash:**
- Flow 2: sleep kills the agent. On wake, the 10 s liveness timer and the wake notification fire in an arbitrary order.
- If liveness runs first, the session goes `gone` (removed, no alert). The failed `HOST SLEPT` alert, the climax of Flow 2, never happens.
- Even when host-slept fires first, the next liveness tick removes the now-failed session, whose process is dead. Yet `T+` must "keep running after the alert".

Ownership is also split:
- `prevent_idle_sleep` lives in `[general]` (core).
- "Any session working" is known only to the module.
- The core builder adds a power service that reads `[general]` but can't see sessions. The module builder takes its own IOKit assertion. Two assertion owners, or none.

**Close it — add to AD-5:**
> On a wake event (from `context.power.sleepWake`), `SessionStore` first marks every session that was `working` at sleep time as `failed (host_slept)`, with `entered_at = wake time`, and only then resumes liveness. Liveness never removes a `failed` or `blocked` session: one whose process is dead stays visible, marked "process ended", until `session.end`, the user dismisses it from the Agents tab, or 24 h pass. Idle-sleep prevention is requested by `agents.sessions` through `context.power.preventIdleSleep` while any session is working; the `prevent_idle_sleep` key moves to `[modules."agents.sessions"]`.

### H3 — Usage provider identity, and adapter config owned by sessions but read by usage

**Units:** AgentsSessions ↔ AgentsUsage ↔ Adapters.

**How both comply and still clash:**
- AD-4: both modules receive the same adapter instances. But adapter-level config sits under `[modules."agents.sessions".adapters.claude] usage_providers = [...]`, and the enabled adapter list under `[modules."agents.sessions"] adapters = [...]`.
- If `context.settings` is scoped to the calling module, which is the natural reading of "per-module", AgentsUsage can't read either key. It then shows rings for adapters the user disabled, or invents its own `adapters` key.
- Both modules render `AgentAdapter.settings` in their generated Settings panes, so the same adapter has two UIs writing two different key paths.
- Provider identity is undefined. `order = ["claude", "codex"]` and `providers.<id>` use adapter ids, but one adapter returns two providers (`local`, `plan`). The local one has no % to draw a ring, while the plan one has % but no tokens.
  - The usage builder draws one ring per `UsageProvider` (two Claude rings).
  - The adapter builder merges them (one provider).

**Close it — add a new AD:**
> **AD-20 — Agent adapter config and usage identity.** Adapter-level settings (enabled flag, `AgentAdapter.settings`, enabled usage sources) live under `[agents.<adapter id>]`, are owned by the core on behalf of adapters, are edited only on the Settings › Agents pane, and are readable by both agent modules through `context.settings.agents`. Disabling an adapter removes it from both modules. A usage *provider* is per adapter (`id = adapter id`), and it merges that adapter's *sources* (`local` for tokens/cost, `plan` for windows/%); one ring per provider, never per source. `order` and `providers.<id>` key on adapter id.

### H4 — Who decides which keys are synced or local; unknown keys across versions

**Units:** ConfigStore ↔ modules (Notes, Integrations, AgentsSessions) ↔ Settings window ↔ an older Vigie on a second Mac.

**How both comply and still clash:**
- AD-8: "Machine-specific keys (SPEC §11.1) are only ever written to the local file." But the list in §11.1 is prose ("displays, virtual notch, terminal, config folder location, script confirmations"), and SPEC §11 shows `[display]` and `[virtual_notch]` inside `config.toml`.
- The ConfigStore builder hard-codes a list. Module builders add new per-Mac paths with no way to mark them local: `[modules.notes] folder` (the iCloud path differs per Mac), `ask_alt_cwd`, and the script `enabled` flag.
  - SPEC §9.2 says declining a script "disables it on that Mac only", yet `enabled` sits in synced `[modules."github.prs"]`.
  - So the Integrations module writes `enabled = false` through `context.settings`, it goes to the synced file, and the script turns off on every Mac.
- Read precedence when a key appears in both files is undefined.
- The local file's location is undefined. If it is `config.local.toml` in the config folder, iCloud syncs it.

**Cross-version failure.** Mac A runs 0.3 and Mac B runs 0.4, which writes a new key. Nothing says unknown keys are tolerated, so Mac A's "invalid file → last valid config" logic freezes Mac A's config forever.

**Close it — tighten AD-8:**
> Every `SettingDescriptor` declares `scope: .synced | .local`; ConfigStore routes reads and writes by that declaration, never by a hard-coded list. The local file lives at `<Application Support>/local.toml` (inside `AppEnvironment`), never in the config folder. For a key present in both, local wins. Per-Mac script state (`enabled`, confirmed hash) is always local. Unknown keys and tables are preserved on write and ignored on read (logged once); a file is "invalid" only on a TOML parse error. A known key with a wrong type or out-of-range value falls back to its default and raises a setup-problem alert naming the key, while the rest of the file still applies.

### H5 — Alert config has three owners; reminders can't see state; the action type is undefined

**Units:** Notifier (VigieCore) ↔ AgentsSessions / AgentsUsage ↔ `[sounds]`.

**How both comply and still clash:**
- SPEC §7.1 Settings lists "alert settings for blocked / finished / failed" as module settings. SPEC §6 puts rules in `[modules."agents.sessions".notify]`, keyed by kind. `[sounds]` has a third mapping (`blocked`, `failed`, `done`, `quota_warning`).
  - The sessions builder declares `blocked_reminder` as a `duration` SettingDescriptor and passes it on `post`.
  - The Notifier builder reads `notify."session.blocked".reminder`.
  - The reminder fires twice, or not at all.
- "Reminder replays if the state is unchanged" (SPEC §6), but the Notifier can't see module state. The session went back to working and the reminder still plays 10 minutes later.
- `action` ("what clicking does") is untyped. The peek's `⌥⌘↵` must call `TerminalAdapter.focus`, which lives inside AgentsSessions.
  - The Notifier builder makes `action` a URL.
  - The sessions builder passes a closure.
  - Neither one survives the other's design.

**Close it — tighten AD-13:**
> Notifier owns all delivery config: `[notify."<kind>"]` (outputs, reminder, min severity) and `[sounds]` keyed by the same kind names; modules declare their kinds (`NotifierKind` list in the manifest) but never declare alert or sound settings themselves. `post` returns an `AlertHandle`; the module calls `handle.resolve()` when the condition ends, which cancels pending reminders and retracts a visible peek. `action` is `.module(id:, actionID:, payload: Data)` routed back to the posting module's `handle(action:)`, or `.openSettings(pane:)`, or `.openURL`. Canonical kinds: `session.blocked`, `session.done`, `session.failed`, `usage.quota_warning`, `shelf.expiring`, `setup.problem`.

### H6 — The `DropZone` contract can't carry ⌥, theme colors, placement or security scope

**Units:** Shelf ↔ AgentsSessions (Ask AI) ↔ Notch Host (closed-notch drop zones).

**How both comply and still clash:**
- `DropZone.handler: ([URL]) async -> DropResult` has no modifier flags. Ask AI needs ⌥ for `ask_alt_cwd`, but the handler runs after the drop, when `NSEvent.modifierFlags` no longer reflects the drop.
- `accent: Color` is a hard-coded color, which AD-14 forbids in views.
- "Stash left, Ask AI right" is a closed-notch placement the struct can't express. The host builder sorts by registration order and may swap them.
- With Shelf disabled, does the host still show Ask AI on the closed notch? SPEC §4.6 says Shelf "hosts" drop zones, while AD-13 says the host owns the closed notch. One builder makes Ask AI depend on Shelf being enabled, the other doesn't.
- Stash items are security-scoped bookmarks. Shelf passes the resolved URL without `startAccessingSecurityScopedResource` (or stops access when the handler returns before the async launch reads the file). Browser drags arrive as file promises that nobody materializes.
- Under Swift 6, a non-`@Sendable` closure stored in a struct handed to the host doesn't compile across actors. Each builder fixes it differently.

**Close it — add to AD-1 (or the new AD-19):**
> `DropZone` is `Sendable`: `{ id, label: LocalizedStringResource, glyph, accentToken: ThemeColorToken, placement: .leading | .trailing, accepts, handler: @Sendable (DropPayload) async -> DropResult }` with `DropPayload { urls, modifiers: NSEvent.ModifierFlags, source: .closedNotch | .shelfTab | .homeWidget | .stashItem }`. The host collects zones from every enabled module and renders closed-notch zones itself; Shelf only renders them on its tab and Home widget. Shelf disabled ⇒ only Stash disappears. The host materializes file promises into `<Application Support>/drops/` before calling a handler; Shelf starts security-scoped access before calling a handler and ends it only after the handler returns, so handlers must finish reading files before returning.

### H7 — Dev and release hook installers in the same `~/.claude/settings.json`

**Units:** ClaudeAdapter in Vigie ↔ ClaudeAdapter in Vigie Dev ↔ the user's other hooks (e.g. peon-ping) ↔ Claude Code itself writing the file.

**How both comply and still clash:**
- AD-17: dev installs `vigie-dev hook …`. Both builds apply `integrationPlan()` to the same file.
- Each adapter build decides how to recognize "our" entries:
  - Substring `vigie`: the release `removalPlan` deletes the dev hooks.
  - Exact `vigie hook claude`: release can't migrate an older entry written as an absolute path.
- A plan that replaces the `SessionStart` array instead of appending deletes the user's other hooks.
- The diff is computed at T0 and written at T1. If Claude Code (or the user) edited the file in between, the write clobbers that edit.
- Both builds installed means every Claude event runs two CLIs. That's fine, but only if each build's onboarding knows the other's entries aren't "foreign hooks to warn about".

**Close it — add to AD-4 (or a new AD on integrations):**
> An adapter's managed hook entry is identified by its exact command string `<AppEnvironment.cliName> hook <adapter id>` and nothing else; plans only add or remove entries with that exact string, never reorder, replace or remove other entries, and never touch the other build's entries. Applying a plan re-reads the file, verifies its content hash equals the one the diff was computed from (else recomputes and shows the new diff), and writes atomically (temp file + rename) preserving the rest of the JSON/TOML as is.

### H8 — The CLI can't import `AppEnvironment`; socket ownership across a Sparkle relaunch

**Units:** VigieCLI ↔ VigieCore; old app instance ↔ new app instance.

**How both comply and still clash:**
- AD-17: "All paths derive from one `AppEnvironment` value, never from literals". But VigieCLI depends on Wire only, and `AppEnvironment` naturally lands in VigieCore. The CLI builder must either duplicate the paths as literals (against AD-17) or break the layer table.
- macOS `sun_path` is 104 bytes. `/Users/<long name>/Library/Application Support/<bundle id>.dev/vigie.sock` can exceed it, and then bind fails silently. The CLI spools forever, and spool replay only happens at launch.
- Sparkle relaunch: the new instance unlinks the stale socket and binds. The old instance, still terminating, then unlinks *the path* in its cleanup, deleting the new socket. Every hook spools until the next launch.
- Two release copies (Homebrew + a manual copy) running at once both bind.

**Close it — add to AD-17:**
> `AppEnvironment` (bundle id, CLI name, Application Support, socket, spool, local file, config default) lives in `Wire`, and the CLI derives its environment from its own executable name (`vigie` vs `vigie-dev`). The socket path must be ≤ 100 bytes; if the derived path is longer, both sides use `$TMPDIR/<bundle id>/vigie.sock`. At launch the app takes an exclusive `flock` on `<Application Support>/instance.lock` and quits if it can't; it unlinks the socket path on exit only if the inode is still the one it bound.

---

## Medium

### M1 — Script ids collide with built-in ids and reserved keys; `manifest` is static

**Units:** Integrations ↔ Module Registry ↔ ConfigStore.

**How both comply and still clash:**
- Conventions: "scripts use their front-matter `id`".
  - A script with `id: shelf` takes over `[modules.shelf]` and `Application Support/…/modules/shelf/` (AD-11).
  - A script setting named `enabled`, `side` or `priority` shares a key with the host keys in `[modules."github.prs"]`.
  - Two files declaring the same id: AD-18's confirmation, if keyed by id, flips between the two hashes.
- SPEC §4.2 declares `static var manifest`, so script modules (one runtime class, many instances) can't have per-instance manifests. The Registry builder iterates `type(of: m).manifest`; the Integrations builder needs instance manifests.

**Close it — add to AD-18 and Conventions:**
> Script ids must contain a dot and must not equal or start with a built-in id or `agents.`; a duplicate or reserved id puts every file declaring it in an errored state with a setup-problem alert. Host-owned keys `enabled`, `side`, `priority`, `surfaces`, `notify` are reserved; script settings live under `[modules."<id>".settings]`. Confirmations are keyed by file path relative to the config folder plus the SHA-256 of the file bytes. `NotchModule.manifest` is an instance property.

### M2 — Terminal choice per session vs config; no "open tab" API; `capture` triggers an Automation prompt

**Units:** AgentsSessions (Ask AI, Focus) ↔ TerminalAdapters.

**How both comply and still clash:**
- Config has one `terminal = "warp"` (local), but EXPERIENCE shows a terminal column "when sessions span more than one terminal app", which means terminals are detected per session.
  - The sessions builder uses the config value for every session, so focusing an iTerm session through the Warp adapter fails.
  - The adapter builders match on `TERM_PROGRAM`.
- `TerminalAdapter` has only `capture`/`focus`. Ask AI needs "open a new tab running argv in cwd". The sessions builder writes its own AppleScript per terminal, which puts terminal-specific code outside adapters.
- `launchCommand` returns argv, while terminals take a shell string. Nobody owns quoting, so a path with spaces or `'` breaks.
- The iTerm builder's `capture()` makes an AppleScript call on `session.start`. The first Apple Event triggers a TCC Automation prompt on a background hook event, which steals focus and breaks AD-13.

**Close it — add to AD-4:**
> `TerminalAdapter` exposes `matches(env:) -> Bool`, `capture(env:pid:tty:) -> TerminalLocator` (pure: no Apple Events, no AX, no I/O beyond reading the process table), `focus(_:)` and `openTab(argv:cwd:)`. Each session's terminal adapter is chosen by `matches` on its captured env; the config `terminal` key is used only for `openTab` and as a fallback. Shell quoting of `argv` is the terminal adapter's job. Apple Events and AX calls happen only inside `focus`/`openTab`, which are only called from a user action.

### M3 — Where `vigie agent --status` gets mapped; `idle` can't be reached; id collisions

**Units:** VigieCLI ↔ AgentsSessions.

**How both comply and still clash:**
- AD-5: "`vigie agent --status` is converted into the same normalized events". But the CLI can't import AgentKit (Wire only), and nothing says where the conversion happens.
  - The CLI builder adds the event names to Wire.
  - The sessions builder expects a raw `agent.generic` topic.
- `--status idle` has no normalized event: idle is entered only on `session.start` or done-timeout.
- `--status working` maps to `prompt.submit` or `tool.start`, a choice each builder makes differently.
- `--agent claude` yields the session id `claude:<id>`, which collides with real Claude sessions and is normalized by the Claude adapter.

**Close it — add to AD-5:**
> `vigie agent` sends topic `agent.generic` with the raw flags; the mapping lives only in AgentsSessions: `working → prompt.submit`, `blocked → needs.input`, `done → turn.end`, `failed → session.error`, `idle → session.start` (re-entry allowed for generic sessions), `--end → session.end`. Generic session identity is `generic.<agent>:<session>`; `--agent` values equal to a registered adapter id are rejected by the CLI with exit 0 and a log line.

### M4 — Focus and hotkey arbitration: notes panel vs expanded view vs peek

**Units:** Notes ↔ Notch Host ↔ HotkeyRegistry.

**How both comply and still clash:**
- AD-13: the notes panel is "requested through `context.host`", and no surface takes focus "except on a deliberate user action". `HostControl` has no way to prove intent.
  - The Notes builder calls `host.showNotesPanel(focus: true)` from a scheduler or hook path, e.g. to reopen the panel after a sync conflict, and it compiles.
- With the expanded view focused and the notes hotkey pressed, two panels compete for key. Expanded "closes on focus loss", so focus may bounce back, and one Esc might close both.
- `KeyboardShortcuts` registrations are global by `Name` string. Notes and a future module both choose `.toggle` and collide.
  - "Conflict detection" has no policy. With `⌥⌘↵` peek shortcuts active while the notes panel has focus, does `⌥⌘↵` focus a terminal or reach the note?

**Close it — add to AD-13:**
> Focus-taking host calls (`expand(focus:)`, `showPanel(focus:)`) take a `UserIntent` token that VigieCore only issues inside hotkey callbacks, clicks and menu actions; without it they open without focus. At most one Vigie surface is key at a time: opening the notes panel collapses the expanded view, and Esc closes only the key surface. Hotkey names are namespaced `<module id>.<name>`; on a conflict the earlier registration wins and the later module shows a setup-problem alert. Peek shortcuts take precedence over every other Vigie shortcut while a peek is visible.

### M5 — Theme color override precedence

**Units:** VigieUI theme resolver ↔ ConfigStore ↔ custom themes in the config folder.

**How both comply and still clash:**
- AD-14: "user color overrides from config apply on top". But `colors.blocked` is one value, while EXPERIENCE says colors are "configurable per look" (A/C × light/dark).
  - One builder applies the override to all four looks.
  - Another applies it to the current look only.
- Physical notch: "always black, dark tokens, in both appearances". A light-look override then appears on a black notch.
- Increase contrast: does it replace a user color?
- A custom theme file named `chrome-hologram.toml` either shadows the built-in or is ignored, depending on the builder.

**Close it — add to AD-14:**
> Resolution order, last wins: shared base → skin → look (`<theme>.<light|dark>`) → custom theme file → `[appearance.colors]` (all looks) → `[appearance.colors.<light|dark>]` → accessibility adjustments (Increase contrast may raise contrast of any resolved color, never ignore a user override's hue). The physical notch always resolves the dark look. Custom theme ids must not equal a built-in id; a clash is ignored with a setup-problem alert.

### M6 — ConfigStore patches a stale copy when the file changes underneath it

**Units:** ConfigStore ↔ external editors / git pull / iCloud ↔ its own file watcher.

**How both comply and still clash:**
- AD-8 says writes "patch only the changed keys" and pick up external edits by watching. It doesn't say which base the patch applies to.
  - A builder that patches its in-memory parse overwrites an external `git pull` that landed 200 ms earlier and hasn't been picked up yet.
- Its own write fires the watcher, which reloads and notifies observers. A module that writes on change (provider `order` drag) then loops.

**Close it — add to AD-8:**
> Every write re-reads the file, applies the patch to the fresh text, and writes atomically; if the fresh text no longer parses, the write is refused and surfaced. The watcher ignores events whose resulting content hash equals ConfigStore's last write. Observers are notified only for keys whose resolved value changed.

### M7 — Core can't call `normalize`; the EventBus payload type is undefined

**Units:** VigieCore Event Server ↔ AgentKit ↔ ModuleKit `EventBus`.

**How both comply and still clash:**
- The flow diagram shows `ES → AgentAdapter.normalize → SessionStore`, but the layer table forbids VigieCore → AgentKit.
- ModuleKit may depend only on Foundation/SwiftUI, so `EventBus` can't expose Wire types.
  - One builder adds AgentKit to Core to match the diagram, against the layer table.
  - Another types `EventBus` payloads as `[String: Any]`, which isn't Sendable under AD-3.

**Close it — add to AD-7:**
> The Event Server only decodes the envelope and publishes `EventMessage { topic, payload: Data, sentAt, receivedAt, replayed }` (declared in ModuleKit) on `context.events`; it never interprets payloads. Agent modules decode `agent.*` payloads with Wire types and call `normalize` themselves. The architecture diagram's ES → normalize edge means "via AgentsSessions".

---

## Low

### L1 — AD-11 "storage only" contradicts the notes folder and shelf Trash moves

Notes must write to the user-chosen notes folder (AD-10, AD-12), and Shelf moves user files to the Trash. A literal reading of AD-11 ("stores data only through `context.storage`") forbids both, so builders either violate it or tunnel the writes through `storage`.

**Add to AD-11:**
> Exceptions: `notes` writes its notes folder (through `context.storage.userFolder(setting:)`); `shelf` moves expired copies to the Trash via `NSWorkspace.recycle`.

### L2 — JSON state writes aren't atomic

AD-6 persists `sessions.json` "on every change". A crash mid-write leaves truncated JSON, and the reload behavior is undefined: one builder crashes, another silently starts empty.

**Add to Conventions (JSON state files):**
> Written atomically (temp + rename), coalesced to at most one write per 250 ms; an unreadable file is renamed `.corrupt` and the module starts empty with a log entry.

### L3 — Sessions and usage each tail the same agent logs with separate cursors

`transcriptWatcher` (sessions) and usage ingest both watch `~/.claude/projects/**/*.jsonl`, so there are two FSEvents streams and two parsers of the same format that drift apart.

**Add to AD-4:**
> An adapter parses its log format in one place (`AgentAdapter.logReader`), shared by both modules.

---

## Checked and judged covered

- Two writers of session status: closed by AD-5.
- Two config writers: closed by AD-8, with the stale-base and loop caveats in M6.
- Script confirmation hashes in a git-shared folder: AD-18 stores them in the local file; only the keying gap in M1 remains.
- CLI and app wire drift: AD-7 (Wire is the only owner).
- Modules importing each other: AD-1, enforced by `Package.swift`.
