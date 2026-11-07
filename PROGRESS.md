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
- [ ] 1.2 AppEnvironment and dev build isolation
- [ ] 1.3 Continuous integration for pull requests
- [ ] 1.4 Spike — Claude Code hook reaches a socket listener
- [ ] 1.5 Spike — focus a specific Warp tab
- [ ] 1.6 Spike — Ghostty tab focus investigation (Ghostty not installed)
- [x] 1.7 UX design pass (done in docs, 2026-11-07)

### Epic 2 — Vigie lives in the notch
- [ ] 2.1 Single-instance accessory app shell
- [ ] 2.2 Module contracts and registry lifecycle
- [ ] 2.3 ConfigStore read path with live reload
- [ ] 2.4 Chrome Hologram theme engine
- [ ] 2.5 Notch Host on a physical notch
- [ ] 2.6 Virtual notch on plain displays
- [ ] 2.7 Display selection, multi-display and hot-plug
- [ ] 2.8 Closed-notch arbitration with multi-slot sides
- [ ] 2.9 Hotkeys and user-intent focus control
- [ ] 2.10 Expanded view shell
- [ ] 2.11 Shared VigieUI components
- [ ] 2.12 Permissions service and needs-permission state
- [ ] 2.13 ConfigStore writer (comment-preserving TOML patcher)
- [ ] 2.14 Generated Settings window
- [ ] 2.15 Accessibility floor in v0.1

### Epic 3 — Alerts that never steal focus
- [ ] 3.1 Notifier rules engine
- [ ] 3.2 Peek presentation
- [ ] 3.3 Peek actions with temporary global shortcuts
- [ ] 3.4 Setup-problem alerts
- [ ] 3.5 Do Not Disturb and Focus modes
- [ ] 3.6 macOS notification output
- [ ] 3.7 Alert settings generated from declared kinds
- [ ] 3.8 Local activity log
- [ ] 3.9 Peek concurrency and suppression

### Epic 4 — Track Claude Code sessions
- [ ] 4.1 Event Server
- [ ] 4.2 Durable spool and launch order
- [ ] 4.3 CLI install on PATH, `vigie event` and `vigie reload`
- [ ] 4.4 Agent adapter contracts and assembly
- [ ] 4.5 SessionStore status engine
- [ ] 4.6 Claude Code adapter with version gating
- [ ] 4.7 Hook installer with diff confirmation
- [ ] 4.8 Liveness, stale sessions and ignored paths
- [ ] 4.9 Session glyphs in the closed notch
- [ ] 4.10 Agents tab
- [ ] 4.11 Session alerts
- [ ] 4.12 Sleep handling
- [ ] 4.13 Generic `vigie agent` reporting
- [ ] 4.14 Research — warning before manual sleep

### Epic 5 — Jump to the exact terminal tab
- [ ] 5.1 Focus permissions and terminal selection
- [ ] 5.2 Terminal.app focus
- [ ] 5.3 iTerm2 focus
- [ ] 5.4 Warp focus per spike decision
- [ ] 5.5 Ghostty focus per spike decision

### Epic 6 — Signed releases that update themselves
- [ ] 6.1 Signing and runtime envelope
- [ ] 6.2 Tag-driven release workflow
- [ ] 6.3 Sparkle auto-update
- [ ] 6.4 Versioning and build numbers

### v0.2 — Epics 7 (Usage), 8 (Codex, `vigie run`), 9 (Shelf), 10 (Sounds), 21 (Privacy)
- [ ] 7.1–7.10 · [ ] 8.1–8.4 · [ ] 9.1–9.10 · [ ] 10.1–10.2 · [ ] 21.1–21.3

### v0.3 — Epics 11 (Home), 12 (Scripts), 13 (Calendar), 14 (Gemini), 20 (Time)
- [ ] 11.1–11.3 · [ ] 12.1–12.11 · [ ] 13.1–13.4 · [ ] 14.1–14.3 · [ ] 20.1–20.6

### v0.4 — Epics 15 (Notes), 16 (Sync), 17 (Onboarding/Settings), 18 (Themes), 19 (Public release)
- [ ] 15.1–15.5 · [ ] 16.1–16.3 · [ ] 17.1, 17.2, 17.4, 17.5 ([-] 17.3 superseded) · [ ] 18.1–18.4 · [ ] 19.1–19.3

## Waiting on Romain

(none yet)

## Decisions log

- 2026-11-07 — Working mode, signing, installs, remote: see "Working mode" above.
- 2026-11-07 — XcodeGen chosen for the App target project (AD-2 keeps the target thin; no hand-edited pbxproj in git).

## Notes for the next session

- Spike 1.4 plan: run Claude Code headless (`claude -p`) in a scratch project with **project-level** `.claude/settings.json` hooks, so Romain's global Claude Code settings are never touched.
- 2026-11-07 — Tests run with `swift test --build-system swiftbuild`: the default SwiftPM build system on Swift 6.3 copies `.xcstrings` uncompiled, so catalog lookups return the key. The strict catalog test is kept. CI must use the same flag.
- 2026-11-07 — Story 1.1 deliberately leaves `CFBundleURLTypes`, `NSServices` and `NSCalendarsFullAccessUsageDescription` out of Info.plist; they arrive with the stories that handle them (12.9, 9.10, 13.1). Ad-hoc signing conflicts with AD-17 "never ad-hoc" until a real identity is wired (Story 6.1).
