# Vigie — Progress

Resumable project state. Read this first. Story definitions live in `docs/epics.md`; binding rules in `docs/architecture/architecture-vigie-2026-11-05/ARCHITECTURE-SPINE.md` (AD-1..AD-26); look and behavior in `docs/ux-designs/ux-vigie-2026-11-04/{DESIGN,EXPERIENCE}.md`; scope in `docs/SPEC.md` and `docs/prds/prd-vigie-2026-11-06/prd.md`.

## Working mode (decided 2026-11-07)

- Claude is project manager: spawns agents (opus for complex stories, sonnet for simple ones), validates their work, commits each story atomically once tests pass, proceeds unattended.
- Blockers that need Romain are **parked** here under "Waiting on Romain" and work continues on independent stories.
- Dev tools (xcodegen, gh, swift-format) may be installed freely; installing apps (terminals, agent CLIs) needs Romain's OK.
- **Signing:** ad-hoc for dev builds for now. Keychain-access-groups features (SecretStore, Story 7.2) wait for a real identity (Apple Development team 4N5C2VUHK8 exists on this Mac).
- Remote `origin` = git@github.com:BaguetteLabs/vigie.git, branch `master`. Push after each commit.
- Tooling decision: XcodeGen (`App/project.yml`) generates the thin Xcode app target; the `.xcodeproj` is generated, not committed.

## Environment

- Mac: macOS 26.5.2, Xcode 26.6, Swift 6.3.3 (spine floor Xcode 26.4 OK; CI pins Xcode 27.1 / Swift 6.4).
- Installed: Warp, Claude Code CLI. Not installed: iTerm2, Ghostty, Terminal spikes targets, Codex CLI, Gemini CLI, gh.

## Story status

Legend: `[ ]` backlog · `[~]` in progress · `[x]` done (committed) · `[P]` parked (needs Romain) · `[-]` superseded

### Epic 1 — Foundation and risk spikes
- [x] 1.1 Scaffold the SwiftPM-first workspace
- [x] 1.2 AppEnvironment and dev build isolation
- [x] 1.3 Continuous integration for pull requests (first runs failed: runner has no Xcode 27.1; pinned 26.6 on 2026-11-07; workflow is **manual-trigger only** until Romain watches a green run, then restore `pull_request` + `push` triggers)
- [x] 1.4 Spike — Claude Code hook reaches a socket listener (record: docs/decisions/spike-hook-path.md; fixtures moved to Packages/Adapters/Claude/Tests/Fixtures/2.1.319 by Story 4.6)
- [P] 1.5 Spike — focus a specific Warp tab (record in docs/decisions/spike-warp-focus.md; deep link found; needs a visual check by Romain)
- [ ] 1.6 Spike — Ghostty tab focus investigation (Ghostty not installed)
- [x] 1.7 UX design pass (done in docs, 2026-11-07)

### Epic 2 — Vigie lives in the notch
- [x] 2.1 Single-instance accessory app shell
- [x] 2.2 Module contracts and registry lifecycle
- [x] 2.3 ConfigStore read path with live reload
- [x] 2.4 Chrome Hologram theme engine
- [x] 2.5 Notch Host on a physical notch (not yet seen on real notch hardware: lid was closed; see Waiting on Romain)
- [x] 2.6 Virtual notch on plain displays (auto-hide menu bar + full-screen hiding verified with fakes only)
- [x] 2.7 Display selection, multi-display and hot-plug (display prompt answered flag lives in UserDefaults `VigieDisplayPromptDone`)
- [x] 2.8 Closed-notch arbitration with multi-slot sides
- [x] 2.9 Hotkeys and user-intent focus control
- [x] 2.10 Expanded view shell (App wiring in integration pass 3)
- [x] 2.11 Shared VigieUI components
- [x] 2.12 Permissions service and needs-permission state
- [x] 2.13 ConfigStore writer (comment-preserving TOML patcher)
- [x] 2.14 Generated Settings window (App wiring in integration pass 3; not yet exercised in the running app)
- [x] 2.15 Accessibility floor in v0.1 (contrast check in CI; docs/accessibility-floor.md)

### Epic 3 — Alerts that never steal focus
- [x] 3.1 Notifier rules engine
- [x] 3.2 Peek presentation (NotchHost ↔ PeekAnchorProvider conformance + AlertSinks wiring in integration pass 3)
- [x] 3.3 Peek actions with temporary global shortcuts
- [x] 3.4 Setup-problem alerts (App wiring in integration pass 3)
- [x] 3.5 Do Not Disturb and Focus modes (App wiring in integration pass 3; sandbox readability of Assertions.json to confirm on first run)
- [x] 3.6 macOS notification output (App wiring in integration pass 3)
- [x] 3.7 Alert settings generated from declared kinds
- [x] 3.8 Local activity log (store + API; Settings › Activity pane deferred to 2.14/17.x)
- [x] 3.9 Peek concurrency and suppression

### Epic 4 — Track Claude Code sessions
- [x] 4.1 Event Server (App wiring pending: start after lock, releaseQueue after registry.start, stop before lock release)
- [x] 4.2 Durable spool and launch order (App must call `EventServer.finishStartup(spool:)` after `registry.start()`; wiring in the integration pass)
- [x] 4.3 CLI install on PATH, `vigie event` and `vigie reload` (App wiring of CLIInstaller.install and app.expand/app.reload handling pending in the integration commit)
- [x] 4.4 Agent adapter contracts and assembly (App assembly of AgentKit/AgentsSessions packages pending in the integration commit)
- [x] 4.5 SessionStore status engine
- [x] 4.6 Claude Code adapter with version gating (App assembly of `ClaudeAdapter()` pending in the integration pass)
- [x] 4.7 Hook installer with diff confirmation
- [x] 4.8 Liveness, stale sessions and ignored paths (`host.ready` must be posted by the App; module also reconciles at start)
- [x] 4.9 Session glyphs in the closed notch
- [x] 4.10 Agents tab
- [x] 4.11 Session alerts
- [x] 4.12 Sleep handling (docs/decisions/host-slept-detection.md)
- [x] 4.13 Generic `vigie agent` reporting
- [ ] 4.14 Research — warning before manual sleep

### Epic 5 — Jump to the exact terminal tab
- [x] 5.1 Focus permissions and terminal selection (Settings › agents.sessions pane should surface `focusPermissionIssues()`; 5.5/17.x)
- [x] 5.2 Terminal.app focus (manual 3×2 tab test blocked on the Automation prompt; see Packages/Terminals/TerminalApp/MANUAL-TEST.md)
- [x] 5.3 iTerm2 focus (iTerm2 not installed: manual test pending; MANUAL-TEST.md)
- [x] 5.4 Warp focus per spike decision (ships `.tabViaURL` unverified; one-line flip after Romain's check)
- [ ] 5.5 Ghostty focus per spike decision

### Epic 6 — Signed releases that update themselves
- [ ] 6.1 Signing and runtime envelope
- [ ] 6.2 Tag-driven release workflow
- [ ] 6.3 Sparkle auto-update
- [x] 6.4 Versioning and build numbers (run `Scripts/version.sh --xcconfig App/Config/Version.xcconfig` before a manual `xcodegen generate`)

### v0.2 — Epics 7 (Usage), 8 (Codex, `vigie run`), 9 (Shelf), 10 (Sounds), 21 (Privacy)
- [ ] 7.1–7.10 · [ ] 8.1–8.4 · [ ] 9.1–9.10 · [x] 10.1–10.2 (listen to the WAVs once) · [ ] 21.1–21.3

### v0.3 — Epics 11 (Home), 12 (Scripts), 13 (Calendar), 14 (Gemini), 20 (Time)
- [x] 11.1 · [ ] 11.2–11.3 · [ ] 12.1–12.11 · [ ] 13.1–13.4 · [ ] 14.1–14.3 · [ ] 20.1–20.6

### v0.4 — Epics 15 (Notes), 16 (Sync), 17 (Onboarding/Settings), 18 (Themes), 19 (Public release)
- [ ] 15.1–15.5 · [ ] 16.1–16.3 · [ ] 17.1, 17.2, 17.4, 17.5 ([-] 17.3 superseded) · [ ] 18.1–18.4 · [ ] 19.1–19.3

## Waiting on Romain

- **Warp focus check (Story 1.5, 5 min, screen unlocked, no permission needed):** open three Warp tabs (one in a second window), run `echo $WARP_FOCUS_URL` in each, then from another tab run `open '<one of those urls>'`. Does the exact tab/pane come to the front? Yes → decision (a) exact focus via deep link; Warp activates but the tab does not switch → (c) app-level. Details and the prototype commands: `docs/decisions/spike-warp-focus.md` § How to re-run.
- **Ghostty (Story 1.6):** Ghostty is not installed. OK to `brew install --cask ghostty` for the spike and later the adapter? Same question for iTerm2 (Story 5.3) and for the Codex and Gemini CLIs (Epics 8, 14).
- **Notch check on hardware (Story 2.5, 2 min):** open the MacBook lid (or make the built-in display active), build and launch the Debug app (`cd App && xcodegen generate && xcodebuild -scheme Vigie -configuration Debug build CODE_SIGN_IDENTITY=- -derivedDataPath .build-dd && open .build-dd/Build/Products/Debug/Vigie\ Dev.app`). Expected: a black island hugging the notch with two wings, a thin iris rim, `Dev sample` in the left wing; right-click shows Settings…/Quit; typing in another app is not disturbed. Tell me what you see. Without a notch, `-VigieSimulateNotch YES` draws a fake one on the main display.
- **CI re-enable:** `.github/workflows/ci.yml` is `workflow_dispatch` only (your request, 2026-11-07 evening, after ~20 failure mails). Cause found from your pasted log: the `macos-26` runner has Xcode 26.0…26.6 only, no 27.1. `.xcode-version` is now `26.6`. When you can watch: trigger the workflow manually from the Actions tab (or `gh workflow run ci`), and if green tell me to restore the triggers.
- **gh auth:** `gh` is installed but not logged in. Run `! gh auth login -w` in this session (or `gh auth login` in a terminal) so CI runs on BaguetteLabs/vigie can be checked. Until then the `ci.yml` first run is unverified.

- Focus/DND detection: the app cannot read the DoNotDisturb Assertions file (privacy-protected). Decide: accept (no Focus suppression in v0.1), or research another detection route.

## Decisions log

- 2026-11-07 — Working mode, signing, installs, remote: see "Working mode" above.
- 2026-11-07 — XcodeGen chosen for the App target project (AD-2 keeps the target thin; no hand-edited pbxproj in git).

- 2026-11-07 — Story 4.5: `statusSince` is the `sent_at` of the entering event and is kept when a status re-enters itself (WORKING · 14M counts from the start of work). Late events only fill missing metadata, never overwrite. Unknown sessions are created by any event except `session.end`. Module state follows SPEC §7.1 (no sessions → ambient, done counts as active). `adapters` setting declared, not enforced yet. `agent.generic` topic is a TODO.
- 2026-11-07 — Story 4.6: support matrix = tested `2.1.0...2.1.319`; same minor with a newer patch → `.assumed` (events flow, settings should warn); other versions → `.unsupported` (no events). `Stop` with running `background_tasks` → `turn.end` (may cause a done→working flip; revisit if noisy). Removal plan matches managed entries by exact command only (AD-22). `CLAUDE_PID` is not on the Wire env whitelist, so the ancestor-name rule applies; consider adding it. SPEC §11 `usage_providers`/`plan_auth` keys deferred to Epic 7. `agents.sessions` must call `adapter.normalize(_:sentAt:support:)` (gated) and raise the setup-problem alert on `.unsupported` (4.11).
- 2026-11-07 — Story 2.15: 259 DESIGN contrast pairs checked, 0 fail, 10 cited exceptions (`Packages/VigieUI/Sources/VigieUI/Theme/ContrastAudit.swift`). Reduce motion still forces Calm presence through `ThemeController` (pre-existing; formally Story 18.3). DESIGN issues for the UX doc: (1) alert-tinted row ratios in the Contrast table match `surface-card`, not `surface-panel` (A light blocked label on panel = 4.36:1, fails); (2) A light `status-done` on panel measures 5.21, not 4.9; (3) clarify whether alpha zone/chip borders are exempt from 3:1 outside Increase contrast.
- 2026-11-07 — Story 4.2: CLI writer re-checks the spool inode after taking the lock (closes the open-before-rename gap). `releaseQueue()` is internal; `finishStartup(spool:)` replays then releases. A crash between publish and delete can replay lines twice (`replayed = true` lets receivers dedupe); never loses. Floor test runs the real `vigie` binary with `CFFIXED_USER_HOME`; ~10 s per run.

- 2026-11-07 — Story 2.10: `KeySurface` is an adapter (`ExpandedSurface`), not the panel. Modules cannot expand without a `UserIntent` (`CoreHostControl.expand(focus: nil)` is a no-op). Hover-opened view + hotkey → focus (not close). Losing key focus (Cmd-Tab) does not collapse. No `expand` motion token: grows over `enter`. Panel scan animation not built (no AC). Live check pending: Tab/←→/⌘1…9 with real key events; possible faint hairlines on the active A tab pill in `cacheDisplay` renders.
- 2026-11-07 — Story 2.14: `SettingControlValue` bridges VigieUI ↔ ConfigStore values (AD-1). Notifications deep link is `com.apple.preference.notifications`. Secret footnote: "Stored in the Keychain. Editing arrives in a later version." Activity log is its own sidebar entry. Login-item state is not reconciled at launch yet. Pane ids: general, activity, appearance, closed (Notch), display, home, notify (Alerts), sounds, sync, updates, then module ids; aliases privacy→general, notch→closed, alerts→notify, displays/virtual_notch→display.
- 2026-11-07 — Story 3.2: `PeekAnchorProvider.anchor(forDisplayUnder:) -> PeekAnchor?` (nil = skip). `ActionButton` label now shrinks before the shortcut. Not built (no AC): live T+ in the kicker, hold-while-expanded, break peek Snooze, sleep-summary kind. Primary button only when the event has an action; Dismiss always shown. DrainLine made the A dwell line a solid hue (was a gradient into iris-3).
- 2026-11-07 — Story 3.4: core alerts use `SetupProblemReporter.manifest` (module id `core`, kind `setup.problem`); the App must `makeNotifier(for:)` it or posts are dropped. `NotifierEvent.category` added (ModuleKit). ConfigStore reports `unknownKey` only for registered module tables.
- 2026-11-07 — Story 3.5: Focus detection reads `~/Library/DoNotDisturb/DB/Assertions.json` (undocumented; folder watch + 15 s poll; unreadable → "not active", logged once). `system` output is still delivered during Focus (macOS applies Focus itself). Notifier now records every outcome in the activity log (3.8 gap closed). `after_focus` option labels fixed to "Drop missed alerts" / "Show the latest per module".
- 2026-11-07 — Story 3.6: `SystemOutputSink` protocol (renamed). Requests `[.alert, .badge]` once on first use. Nothing calls `retract` on resolve yet (AlertCenter owner to add). Clicks on notifications from before a restart are ignored (in-memory id map).
- 2026-11-07 — Story 4.8/4.9: `ProcessLiveness` lives in AgentKit (`SystemProcessLiveness`: sysctl KERN_PROC_PID, start time within 0.5 s). Sessions without `agentProcess` are never removed by liveness. Stale is display-only (`displayStatus`), counts as ambient, recomputed every 10 s. `ignored_paths` matches whole path components; ignored keys capped at 256. Glyph loop animation must stay scoped to the glyph (`loopDoesNotLeakIntoSiblings` guards a SwiftUI pitfall). Accessibility time label is as fresh as the last wing rebuild. `LeftWingItem` → `WingItem` rename still open.

- 2026-11-07 — Integration passes 2 and 3 landed: EventServer + spool replay + `host.ready`, ActivityStore, ExecutableResolver (+ `local.toml [executables]`), ConfigStore-backed notify rules, AlertCenter with PeekPresenter / SystemNotificationSink / SystemFocusModeMonitor / activity recorder, SetupProblemReporter, SettingsController (context menu, gear, ⌘, in the expanded view, alert router), expanded view hotkey + config closures, `AgentAdapters([ClaudeAdapter()])`, CLIInstaller at launch. ConfigStore gained `rawValue(at:in:)`/`rawTable(at:in:)` and reports unknown-table edits on `changes`. `Topic.hostReady` added to Wire. Debug flags: `-VigieSimulateNotch YES`, `-VigieSimulateFocus YES`.
- 2026-11-07 — Known at launch on Romain's Mac: six `setup.problem` alerts from unknown keys in `~/.config/vigie/config.toml` under `modules."agents.sessions"` (`ask_cwd`, `priority`, …; `stale_after`/`ignored_paths` are declared since 4.8). Either declare the remaining SPEC keys in the module manifest as they are implemented, or decide that unknown-key problems should not peek. Also: nothing calls `SystemNotificationSink.retract` on resolve yet; `PeekPresenter` wiring and the ⌘, hook have no automated test.
- 2026-11-07 — Story 3.7: Settings writes always use the `[modules."<id>".notify."<kind>"]` table form; rules in the SPEC §6 inline-table form resolve but cannot be edited (localized "unsupported location"). `ConfigSchema.register` adds `mute`/`outputs`/`reminder` per declared kind. Kind labels come from the catalog (`settings.alerts.kind.<kind>`); manifests declare kinds as plain strings (no per-kind reminder defaults).

- 2026-11-07 — Story 3.3/3.9: peek shortcuts are fixed Carbon hotkeys via KeyboardShortcuts (`peek:primary`, `peek:secondary`), outside `HotkeyCenter`, firing on key-up; conflicting user hotkeys are paused while a peek is visible. Module action entry point is the optional `AlertActionHandler` protocol (ModuleKit `Services.swift`), not a `NotchModule` requirement. `AlertUrgency` is the single rank table (`time.break_reminder` is the canonical break kind); unknown kinds rank after `setup.problem`. `AlertCenter.dismiss` cancels the reminder and keeps the alert active. While the expanded view is open new/queued peeks are suppressed; a peek already on screen stays (needs an expand hook on `NotchHost`).

- 2026-11-07 — Romain asked to work slower (usage budget): from now on one or two agents at a time, merge each before the next.
- 2026-11-07 — Story 2.6/2.7 follow SPEC, not the brief: `[display] display = notched|main|all|<name>` (no pointer mode), `[virtual_notch] width/idle/position/placement/style` (always shown on a selected plain display). `DisplayPrompt` (A60) overlays the expanded view; `HostConfigBridge` reloads the host on `display.*`/`virtual_notch.*`/`closed.max_side_width`/`general.hide_in_fullscreen`. `NotchHost.init(displays:)` replaced `screens:`.
- 2026-11-07 — Story 4.10/4.11: fallback terminal lives in AgentKit (`TerminalAdapters(_:fallback:)`, Modules may not depend on Terminals packages); `GenericTerminalAdapter` activates the app by `__CFBundleIdentifier`/`TERM_PROGRAM`/ancestor, never selects a tab. Alert severities: blocked/failed `.critical`, done `.info`. Blocked body lacks the command (`AgentEvent` has no `tool_input`; Claude adapter follow-up). Failed category is `ERROR`. The tab does not grab keyboard focus on open (shell decision). Alert tint drawn in `Sessions/` (no `RowModifiers` helper).
- 2026-11-07 — Story 5.2/5.3/5.4: `TerminalAdapter.focus` cannot throw, so permission failures surface through `PermissionReportingTerminalAdapter.attemptFocus` (Story 5.1 consumes it). AppleScript runs in-process (`NSAppleScriptRunner`); Automation prompts appear on first Focus and may not survive ad-hoc re-signing. Warp: `WarpAdapter.decision = .tabViaURL`, `decisionConfirmed = false` → Settings statement "Warp: tab focus via session URL (unverified)"; Warp's `AppActivating` renamed `WarpAppActivating` after AgentKit gained one. `openTab` unsupported everywhere so far.
- 2026-11-07 — Story 6.4: `App/Config/Version.xcconfig` is generated (gitignored) and required by xcodegen; dev builds are `0.0.0` + git rev count; release = tag + CI run number. Sparkle (6.3) compares `CFBundleVersion`.
- 2026-11-07 — Story 10.1/10.2: `SoundTable` is the AD-13 table (seven kinds; three keys `"off"` until 20.2/20.4/13.4 and hidden from the Sounds pane until then). WAVs generated by `Scripts/gen-sounds.py` (stdlib), bundled in VigieCore resources. `SoundProblemReporter` posts `setup.problem` category `SOUND`. `SettingsController.sounds` holds the pane model; the App must set its `player` to the shared `AVAudioPlayerSoundPlayer`.

- 2026-11-07 — Integration pass 4 landed (terminal adapters Terminal.app/iTerm2/Warp + Generic fallback, sound sink, Sounds pane player). Observed at launch: "Focus assertions unreadable; treating Focus as off" — the app cannot read `~/Library/DoNotDisturb/DB/Assertions.json` (privacy-protected folder; the shell could because it has Full Disk Access). Focus detection therefore does not work in the app today; options: ask for Full Disk Access (bad), find another signal (`NSWorkspace`/`UNUserNotificationCenter` focus status APIs are not public), or accept the limit. Needs a decision (Story 3.5 follow-up).

- 2026-11-07 — Story 5.1: terminal chosen at session start (`TerminalAdapters.select(env:preferred:)`), `capture` once, locator persisted (`terminal_adapter`/`terminal_locator`). The `terminal` local setting applies only when the env names no terminal (otherwise a Ghostty session would be sent to Terminal.app); unknown terminals go to the generic fallback. Permission failures post `setup.problem` category `PERMISSION` (module declares the kind), resolved on the next focus without a permission error.

- 2026-11-08 — Story 4.7: `IntegrationInstaller` is a ModuleContext service (`context.integrations`), implemented by `CoreIntegrationInstaller` (hash check, timestamped backup, atomic write, `[integrations.<adapter>]` record in local.toml via `ConfigStore.registerIntegration`). Connect/Disconnect live in `AgentsSessionsModule.settingsView()`; a stale preview re-plans up to 3 times. Gaps (ungated normalize fixed 2026-11-08 by `AdapterSupportGate`): `adapters` default `["claude"]` counts Claude as enabled before Connect; Warp focus statement cannot be shown by the module (AD-1).

- 2026-11-08 — Story 4.12: `CorePowerService` (one `.idleSystemSleepDisabled` activity while any request is open and `[general] prevent_idle_sleep` is on; inert tokens otherwise; `TrackedPowerService` per module). `SleepWakeEvent.didWake` has no timestamp (ModuleKit unchanged), so the wake time is receipt time. Sessions with an event after sleep began are not marked failed (extra guard, in the decision record). Keep-awake toggle stays in General with help text; the Agents block links to it. Adapter support gating: `AdapterSupportGate` detects versions at start and on `adapters` changes, holds early events until the first check, `.unsupported` posts `setup.problem` category `AGENT`.

- 2026-11-08 — Story 4.13: `vigie agent --agent <id> --session <id> (--status working|blocked|done|failed|idle | --end) [--cwd] [--message]`; reserved ids (claude, codex, gemini) are logged and dropped; usage errors are the only output (exit 2). Identity `generic.<agent>:<session>`; `AgentID.init?` now also accepts `generic.*` (one-line AgentKit change). Mapping lives in `GenericAgentMapping.swift`; blocked → `needs.input(.permissionPrompt)`; agent pid = first non-shell ancestor. No adapter, no support gate.

- 2026-11-08 — Story 11.1: Home tab (`ExpandedTab.home`) is always first, outside `general.tab_order`; `expand()` lands on Home every time. Cards resolved by `HomeCardSelection.resolve(order:offered:)` from `[home] cards`; unknown ids logged once and preserved when the pane writes. Sizes from DESIGN tokens `components.script-card.width` (222), `components.home-grid.card-height` (138), `spacing.grid-gap` (no new Theme tokens: `base.toml` is generated). Script cards plug in via `NotchHost(additionalHomeCards:)` + `SettingsController.additionalHomeProviders`. 11.2 only needs `homeCard()` in AgentsSessions and Usage. Dev note: `~/.local/bin/vigie-dev` may point at a deleted DerivedData helper until the next dev launch re-points it.

## Notes for the next session

- Spike 1.4 plan: run Claude Code headless (`claude -p`) in a scratch project with **project-level** `.claude/settings.json` hooks, so Romain's global Claude Code settings are never touched.
- 2026-11-07 — Tests run with `swift test --build-system swiftbuild`: the default SwiftPM build system on Swift 6.3 copies `.xcstrings` uncompiled, so catalog lookups return the key. The strict catalog test is kept. CI must use the same flag.
- 2026-11-07 — Story 1.1 deliberately leaves `CFBundleURLTypes`, `NSServices` and `NSCalendarsFullAccessUsageDescription` out of Info.plist; they arrive with the stories that handle them (12.9, 9.10, 13.1). Ad-hoc signing conflicts with AD-17 "never ad-hoc" until a real identity is wired (Story 6.1).
- 2026-11-07 — `Package.resolved` files are committed (reproducible builds). Theme TOML lives in `Themes/` with an identical bundled copy under `Packages/VigieUI/Sources/VigieUI/Resources/Themes/`; `Scripts/theme-regen-check.sh` enforces both. Config color keys (`colors.blocked`) → token roles (`status-blocked`) mapping is left to the ConfigStore story (2.3).
- 2026-11-07 — Story 2.2 choices accepted: `UserIntent.init` is `@_spi(Host)` (only VigieCore imports `@_spi(Host) ModuleKit`; add a grep check later); `ModuleID` keeps string-literal support (traps on invalid literal); `LeftWingItem` has no own state yet — Story 2.8 adds an optional per-item state override so a single warned provider ring can outrank its siblings. App assembly of ModuleRegistry + ConfigStore enablement happens in Story 2.5 / an integration commit after 2.3.
- 2026-11-07 — Spike 1.4 results for Epic 4: `vigie hook` median 6.4 ms incl. fork/exec; `permission_prompt` vs `idle_prompt` distinguishable via `notification_type` (SPEC §14.4 answered: yes); consider the `PermissionRequest` hook event for faster blocked detection (4.6); `claude` process is named by version (`2.1.319`) and is the hook's direct parent (`CLAUDE_PID` also set); `SubagentStop` fires for internal helpers (`agent_type: ""`) — ignore; `Stop` may fire while background subagents run; never forward `CLAUDE_CODE_MESSAGING_TOKEN`. Hook stdio has no TTY: the CLI falls back to the controlling terminal of the ancestors.
- 2026-11-07 — Fixed flake: `ModuleStorageTests` EACCES/no-write failures were caused by the spike `SocketListener` calling `umask(0o177)` process-wide during bind while other suites created temp dirs. Removed; 8 consecutive green runs. Rule: never call `umask` in library or test code.
- 2026-11-07 — Story 2.9 notes: KeyboardShortcuts names cannot contain dots, so `core.expand` is stored as `core:expand`; config wins over its UserDefaults. SPEC has no `[hotkeys]` table: expand hotkey is `[general] expand_hotkey`, module hotkeys are `hotkey` keys under `[modules.<id>]`; the integration commit maps them to `HotkeyCenter.applyConfig`. App bundle now ships KeyboardShortcuts' own localizations (harmless for the locale check). Pending wiring (integration commit after 2.3/2.5): App creates one `HotkeyCenter` + `PermissionsCoordinator`, passes them to `CoreModuleContextFactory` and `ModuleRegistry`, registers `CoreHotkeys.registerDefaults`; Story 2.10 conforms NotchPanel to `KeySurface`.
- 2026-11-07 — Story 2.11 copy written by the agent, to confirm with Romain at the next UX review: Usage empty sentence "Turn on a usage provider for Claude Code, Codex or Gemini CLI in Settings.", Calendar setup sentence "Allow access in System Settings › Privacy & Security › Calendars; Vigie only reads events.", `CHECKED <1 MIN AGO` / `CHECKED 1H52 AGO` qualifiers. `DOWN SINCE 14:44` (no `·`) follows the EXPERIENCE copy table.
- 2026-11-07 — **SPEC §11 defect:** the default config shown in SPEC is invalid TOML: `adapters = [...]` and the table `[modules."agents.sessions".adapters.claude]` define the same key twice. The shipped default file comments the adapters table out ("layout decided with the adapters, Epic 4"). Decide the final layout in Story 4.6/4.7 and fix SPEC §11 (ask Romain to confirm: e.g. rename the table to `adapter_settings.claude` or drop the array and derive it from the tables).
- 2026-11-07 — Story 2.3 choices: `.local` keys are commented in a reference block at the end of the default `config.toml` (active ones would raise `wrongFile`); core tables exactly the SPEC §11 set (no `[hotkeys]`/`[alerts]`/`[cli]`); ranges chosen: `closed.slots` 1–4, `closed.max_side_width` 40–600, `virtual_notch.width` 80–800; `invalidValue` problems carry no line (swift-toml reports lines only for syntax errors); `ConfigProblem.message` is diagnostic English, the UI must build text from `kind`+`key`. Labels live in a separate `Config.xcstrings` table. Executable overrides for Story 4.4 live in `local.toml` `[executables]`.
- 2026-11-07 — Story 2.8 decisions: `+X` sits after the last visible item on both wings (DESIGN "Overflow"); the 2 s COPIED duration is the motion token `confirm-readout`; unrenderable items are not counted in `+X`; `TransientReadout` lives in VigieUI. Deferred to later stories: readout hold on hover, drain line under COPIED, VoiceOver announcement, a module-facing `showTransient` API (ModuleContext), ConfigStore wiring of `closedSlots`. Story 4.9: `agents.sessions` offers one `LeftWingItem` per session (state = urgency) and the host routes them to the right wing; consider renaming `LeftWingItem` → `WingItem` then.
- 2026-11-07 — CI Xcode pin changed from 27.1 (spine) to 26.6: GitHub `macos-26` runners ship 26.0–26.6 only. Revisit when 27.x appears on runners.
- 2026-11-07 — Story 3.1 decisions: quiet hours drop (not defer); default outputs `[peek, sound]` for every severity (never `system` by default, A70); reminders replay peek+sound only (FR29); `min_working_time` compares against metric `working_duration` in seconds (A54); events without `dedupe_key` share one cooldown per kind. Wiring left: ConfigStore → `NotifyRulesProvider`, PeekSink (3.2), SystemNotificationSink (3.6), SoundSink (10.1), a real `AlertActionRouter` in the App.
- 2026-11-07 — Process note: after rebasing a worktree created before a story that added package resources (e.g. 2.3's `Resources/Config`), swiftbuild's incremental build may not copy the new resources into the test bundle, giving bogus 'resource not found' test failures. Always `rm -rf Packages/*/.build` in a worktree after a rebase that brought new resources, and gate merges on the literal `ci-local: OK` line.
- 2026-11-07 — Integration commit landed (ConfigStore, permissions, hotkeys in the App). Still to wire in the next integration pass: EventServer (start after lock, `releaseQueue()` after `registry.start()`, `stop()` before lock release; handle `app.reload` → `configStore.reload()` and `app.expand` → expand, Story 2.10), `CLIInstaller.install()` at launch, `ActivityStore.startDailyPruning`, `AlertCenter` with a real `AlertActionRouter` + ConfigStore-backed `NotifyRulesProvider`, `ExecutableResolverImpl.prime()` + `overrides` from `local.toml [executables]`, AgentKit + AgentsSessions packages in `project.yml` with `AgentAdapters([])`/`TerminalAdapters([])`, `closedSlots` from `closed.slots`.
- 2026-11-07 — Story 4.4 gap: `AdapterContextBox` needs a `SecretStore`; VigieCore's `UnavailableSecretStore` is internal. Story 7.2 (SecretStore) or a public unavailable store is needed before adapters with secrets.
- 2026-11-07 — Story 4.3: CLI catalog lookups use `CLIResources.bundle` (not `bundle: .module`) because `Bundle.module` traps when run through the `~/.local/bin` symlink; the helper's catalog bundle is copied to `Contents/Resources`. `ENABLE_USER_SCRIPT_SANDBOXING = NO` on the app target for the embed step.
