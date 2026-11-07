---
title: Vigie PRD — input extraction
created: 2026-11-06
sources:
  - SPEC.md (draft v0.4, 2026-11-05)
  - ux-designs/ux-vigie-2026-11-04/DESIGN.md
  - ux-designs/ux-vigie-2026-11-04/EXPERIENCE.md (final, 2026-11-05)
  - architecture/architecture-vigie-2026-11-05/ARCHITECTURE-SPINE.md (final, 2026-11-06)
  - epics.md (unattended run; FR1–FR111, NFR1–NFR28, A1–A78)
---

# Vigie — extracted PRD inputs

Abbreviations: SPEC = SPEC.md, EXP = EXPERIENCE.md, DES = DESIGN.md, ARCH = ARCHITECTURE-SPINE.md, EP = epics.md. Nothing below is new content; every line points to its source.

Note: epics.md says SPEC.md "stands in for the PRD" and that its FR/NFR numbering was derived from SPEC by the facilitator (EP A1). There is no PRD upstream of these documents.

## 1. Vision / problem statement (as stated)

- "An open-source, modular macOS notch companion. It works on Macs with a physical notch and on plain displays, where it shows a virtual notch. [...] Everything is a module, every module can be turned off, and the whole configuration lives in plain-text files." (SPEC intro)
- "Vigie (French for a ship's lookout) is a notch companion that watches background work, mostly CLI coding agents, and shows it in the smallest possible space." (DES Brand & Style)
- Goals, quoted (SPEC §1 Goals):
  - "Show what matters at a glance, using as little space as possible."
  - "Never steal focus."
  - "Modular by design. [...] A user who turns off everything except the shelf gets a file shelf and nothing else: no extra permissions, no background work."
  - "Easy to extend without Swift. Anyone can add an integration by dropping a script, in any language, into a folder."
  - "AI coding agents first. Session status, usage, and filtered notifications for CLI coding agents [...] are the main use case. [...] none of them is special-cased in the core."
  - "Config as code."
- Problem, as stated in the primary flow: "Core pain: keeping track of several concurrent agent sessions and the Claude 5h/weekly quota." (EXP Flow 1)
- Sleep pain: "Without Vigie, nothing would have reminded him." (EXP Flow 2, climax)
- Noise pain (implicit): the notifications example exists so that "the cause of the Peon Ping noise is configured away explicitly" (SPEC §6). No further explanation of Peon Ping anywhere.
- Posture: "software from the future: sci-fi holographic computers and spaceship instrument panels" (DES Brand & Style).
- Stakes: "Hobby / dogfooding, open-source public release, donationware" (EXP Foundation).
- No standalone problem statement, no "why now" (see §8).

## 2. Target users, protagonists, journeys

Stated users:
- Developers running CLI coding agents (Claude Code, Codex CLI, Gemini CLI, ...) on macOS 15+ (SPEC §1, §2).
- Implicit secondary: people who want a file shelf, calendar, notes or script widgets in the notch (SPEC §7.3–7.6, §9).
- No persona section. Two named protagonists only (EXP Key Flows):

| Protagonist | Description (as stated) | Flows |
|---|---|---|
| **Romain** | "solo developer, 3–10 sessions open, 2–4 active"; Claude Code + Codex, all in Warp; MacBook + Mac Studio; writes scripts (GitHub PRs, BugSink, Stripe, Umami: EXP Script Modules) | 1, 2, 4, 5 |
| **Léa** | "backend developer, MacBook Pro 14 + 27-inch external"; Codex CLI for work, Claude Code for a side project, both in iTerm2; "finds Vigie on GitHub" | 3 |

Romain is also the project author/maintainer (EP A49: manual Apple/GitHub tasks "for Romain"; EP Out of scope: trademark search "Non-code task for Romain").

Key flows (EXP Key Flows; EP A59 uses them as acceptance journeys):
1. **Multi-session day** (Romain): glyphs per session in urgency order, quota rings + pace; a session turns blocked, peek appears once without taking focus, `⌥⌘↵` brings the exact terminal tab forward; done → idle after 15 min. Failure paths: missed peek (glyph + marker persist, reminder), tab not locatable (app activates), DND (no peek/sound).
2. **Wake after sleep** (Romain): lid closed mid-run, on wake the session is `FAILED · HOST SLEPT` with peek and Focus. Several sessions → one alert each [ASSUMPTION].
3. **First week** (Léa): `brew install --cask vigie` [ASSUMPTION: cask name], onboarding (theme, agent hook diffs, Accessibility, displays, sounds); later a Codex approval peeks on the display under her cursor while Slack keeps focus. Failure paths: Accessibility skipped, unsupported Codex version.
4. **Ask AI drop** (Romain): drag a file → closed notch shows Stash / Ask AI → drop → new terminal tab with default agent, file attached, no dialog. Variants: ⌥ alternate folder, stash item onto Ask AI.
5. **Script arrives via sync** (Romain, second Mac): synced Markdown script shows "awaiting confirmation", user reviews whole file, confirms, enters secret per Mac, widget runs.

## 3. Feature groups / modules (capability level) and release

Release mapping from SPEC §13 Roadmap and EP Epic List.

| Group | Capabilities | Release |
|---|---|---|
| **Risk spikes** | Hook event reaches a socket listener; focus a specific Warp tab (EP adds Ghostty spike, A9) | Spike (EP Epic 1) |
| **Notch host** (SPEC §5, §10) | Draw around the physical notch or a virtual notch on plain displays; display choice (main / notched / all / named), hot-plug, clamshell; hide in full-screen; two wings with arbitration by state + priority, multi-slot sides (3 default, max ~4), `+X` overflow; virtual notch idle / position / placement / style options | v0.1 (EP Epic 2) |
| **Expanded view** (SPEC §10) | Click or hotkey opens; tab per module; keyboard navigation; empty and setup states. Home grid of widget cards | Shell v0.1; Home tab v0.3 (EP A12, Epic 11) |
| **Alerts / Notifier** (SPEC §5.2, §6) | Peek once per event with two global shortcut actions, dwell, optional reminder; per-kind rules (mute, severity, quiet hours, cooldown, outputs peek/system/sound); setup-problem alert; DND respected | v0.1 (EP Epic 3) |
| **`agents.sessions`** (SPEC §7.1, §8) | Track all CLI agent sessions via adapters; status model idle / working / done / blocked / failed / gone; liveness, stale badge; sleep-interrupted → failed; opt-in idle-sleep prevention; Agents tab (only action: Focus); generic `vigie agent` CLI for any tool; hook installer with diff confirmation; version gating per adapter | v0.1 with Claude Code adapter (EP Epic 4) |
| **Terminal focus** (SPEC §7.1.1) | Bring the session's exact tab forward in Terminal.app, iTerm2, Warp, Ghostty; fallback: activate app | v0.1 (EP Epic 5) |
| **Release & updates** (SPEC §12) | Signed, notarized DMG via GitHub Actions on tags; Sparkle auto-update, beta channel | v0.1 (EP Epic 6; beta channel in v0.1 per A63) |
| **`agents.usage`** (SPEC §7.2) | Per-provider quota rings (5h / weekly, nested); pace indicator (visual only); quota warning threshold (alert or visual); Usage tab with per-window bars, 7-day token history, today's estimated cost by project; local-log providers offline, plan-limit providers opt-in via unofficial endpoints | v0.2 (EP Epic 7) |
| **Codex CLI adapter** | Sessions + usage for Codex | v0.2 (EP Epic 8) |
| **`shelf` + drop zones** (SPEC §4.6, §7.3) | Stash by reference / copy / saved; Quick Look, reveal, pin; TTL expiry with warning, never permanent deletion; Ask AI drop zone launches default agent in a new tab | v0.2 (EP Epic 9) |
| **Sounds** (SPEC §10.2) | Four events (blocked, failed, done, quota warning), built-in or custom, optional, follow DND | v0.2 (EP Epic 10) |
| **Script modules** (SPEC §7.4, §9) | Markdown file with front matter + one code block, any language; status / number / short-text widgets on Home, side slot, full page; per-Mac confirmation of exact content; secrets in Keychain; JSON schema; 2–3 examples | v0.3 (EP Epic 12) |
| **`calendar`** (SPEC §7.5, "nice-to-have") | EventKit; state by lead time; month grid + upcoming list; Join call | v0.3 (EP Epic 13) |
| **Gemini CLI adapter** | Sessions (+ usage if available); process-only presence for agents without hooks/logs | v0.3 (EP Epic 14) |
| **`notes`** (SPEC §7.6, "nice-to-have") | Global-hotkey floating panel; Markdown with masked secrets, copy without reveal, clipboard clear; end-to-end encrypted, iCloud sync; Notes tab with search | v0.4 (EP Epic 15) |
| **Config & sync** (SPEC §11) | Human-editable TOML, live reload, user-chosen folder (git-able), optional iCloud sync of config + notes; machine-specific settings local; secrets in Keychain | Config file v0.1; iCloud sync v0.4 (EP Epic 16) |
| **Onboarding & settings** (SPEC §10.1) | First-launch guided sequence; native Settings window generated from module schemas; Support item; diagnostics; notch-app coexistence warning | Basic Settings v0.1 (EP A13); onboarding + polish v0.4 (EP Epic 17) |
| **Themes & presence** (SPEC §10.2, DES) | Chrome Hologram (v0.1) and Twin Metal Tactical (v0.4), light/dark; custom themes; user colors; presence full / calm | v0.1 partial, v0.4 (EP A14, Epic 18) |
| **Public release** | Homebrew cask, README (script trust), accessibility floor verified | v0.4 (SPEC §13, EP Epic 19) |
| **Island spike** | Dynamic Island layering, ActivityKit; decides `island` display mode | Unscheduled, hardware-gated (SPEC §13) |
| **Later** | Window management, clipboard history, dictation, translation, media, menu bar fallback mode | Later (SPEC §13) |

## 4. Non-functional requirements (stated anywhere)

Focus and interruption
- Never steal focus: non-activating panels; focus only on deliberate open (click, shortcut), never on alerts (SPEC §1, §5.2, §10; EXP Interaction Primitives; ARCH AD-13 `UserIntent` token; EP NFR2).
- Peek shortcuts registered only while visible; "Never bare Esc or other common keys" (SPEC §5.2).
- Do Not Disturb / Focus: peeks and sounds suppressed, closed notch still updates, "No bypass option" (SPEC §5.2; EXP State Patterns). Replay vs drop open (SPEC §14.20); EP A21 decides drop.
- Never auto-opens the expanded view (EXP Interaction Primitives "Banned").

Performance and footprint
- Hook CLI never slows or blocks the agent: exits immediately, code 0, no output, even if the app is not running (SPEC §8.2); 150 ms total budget, spool fallback, never forks (ARCH AD-6; EP NFR3).
- Disabled modules cost nothing: no permissions, no background work (SPEC §1, §4.3; EP NFR4).
- All I/O off the main actor (ARCH AD-3; EP NFR24). State writes coalesced ≤ 1 per 250 ms (ARCH Conventions).
- Script timeout `min(interval, 30s)` (SPEC §9.2).
- No other stated performance targets (CPU, memory, energy, launch time): see §8.

Privacy and security
- No telemetry, no automatic crash reporting; network only for Sparkle, opt-in plan-limit providers, user scripts (ARCH AD-16; EP NFR7). Not stated in SPEC itself (EP A5).
- Secrets only in Keychain; never in config, logs, diagnostics, synced folders (SPEC §2, §11.1; ARCH AD-9; EP NFR6).
- Socket 0600, current user only (SPEC §8.1).
- Notes end-to-end encrypted, plaintext only in memory (SPEC §7.6; ARCH AD-10; EP NFR20).
- Scripts run unsandboxed as the user, only after per-Mac confirmation of exact content; README must warn (SPEC §9.2; ARCH AD-18; EP NFR19).
- Agent config edits shown as a diff before writing, with backup (SPEC §8.3; ARCH AD-22).
- Vigie never acts on a session on the user's behalf (SPEC §1 Non-goals; EP NFR26).
- Signed, notarized, hardened runtime, unsandboxed; minimal entitlements (SPEC §12; ARCH AD-20; EP NFR11). Updates verified twice (SPEC §12.4).
- Release secrets only in a protected GitHub environment; fork CI never sees secrets (SPEC §12.1, §12.3; EP NFR12).

Reliability and data safety
- No lost hook events across quit/crash/update (spool + replay) (ARCH AD-6).
- Module failure never crashes the host; invalid config keeps last valid one (SPEC §11; ARCH Conventions; EP NFR15).
- Shelf never deletes permanently (SPEC §7.3; EP NFR16).
- Never show wrong statuses on unsupported agent CLI versions (SPEC §14.5; ARCH AD-23; EP NFR18). Adapters that can't detect blocked/failed say so (SPEC §7.1).
- Unofficial plan-limit endpoints optional, isolated, quick to patch (SPEC §14.2; EP NFR27).
- Config edits preserve comments and unknown keys byte-for-byte (ARCH AD-8; EP NFR17).
- Changes apply live, no restart (SPEC §5.4, §10.2, §11; EP NFR14).

Accessibility
- v1 floor: every control and glyph labelled with state; color never the only cue; Reduce motion forces calm, Reduce transparency and Increase contrast honored; full VoiceOver v2 (SPEC §10.2; EXP Accessibility Floor; EP NFR9–10).
- Text contrast ≥ 4.5:1, one known gap (DES Contrast).
- EP A15 delays Reduce-motion handling to v0.4 (v0.1–v0.3 always animate).

Platform, localization, license
- macOS 15+ (current + two majors back) (SPEC §2, §14.6). English first, i18n from first commit (SPEC §2; ARCH AD-15). GPL-3.0 (SPEC §2). No Dock icon (SPEC §10.1; ARCH AD-21). Dev/release build isolation (ARCH AD-17).

## 5. Goals, success signals, business model, distribution

- Goals: SPEC §1 Goals (quoted in §1 above). They are design principles, not measurable targets.
- Success metrics: none stated in any input.
- Implicit signals only: "Later, only if the project gains users" (SPEC §2.1) — no threshold defined. Stakes "Hobby / dogfooding" (EXP Foundation).
- Business model — donationware (SPEC §2.1):
  - "Fully open source, free signed builds for everyone. No feature is locked behind payment."
  - Donations: GitHub Sponsors plus Ko-fi or Buy Me a Coffee, linked from README and app.
  - In-app: "Support" item in settings, "at most one dismissible message after a few weeks of use"; EP A33 sets 21 days, shown in expanded view, never as a peek.
  - Later optional paid "supporter" edition (Gumroad or Paddle), identical apart from a thank-you badge.
  - GPL-3.0 rationale: "nobody can sell a closed-source copy that undercuts the project."
- Distribution (SPEC §2, §12): Developer ID signed + notarized DMG from GitHub Actions on `vX.Y.Z` tags on `master`; Sparkle 2 auto-updates from GitHub Releases (stable + beta appcast); Homebrew cask in a `homebrew-notch` tap first, official homebrew-cask later (`auto_updates true`). Not the Mac App Store. Public release at v0.4 (SPEC §13).
- Every version after v0.1 updates itself (SPEC §13 v0.1).

## 6. Non-goals and out of scope

SPEC §1 Non-goals (v1):
- Launcher, command palette, calculator ("Raycast territory").
- Approving, denying or acting on an agent session; only action is Focus.
- Mascots or personification.
- Live agent conversations in the notch.
- Media controls (possibly later).
- Loading compiled third-party Swift plugins at runtime.
- Mac App Store distribution.

Banned interactions (EXP Interaction Primitives): acting on a session, mascots, auto-opening expanded view, taking focus on alerts, bypassing DND. Rejected patterns: single-session tracking, military targeting visuals, HUD spilling over the menu bar (EXP Inspiration & Anti-patterns).

Deferred / later (SPEC §13 Later; ARCH Deferred; EP Out of scope):
- Island display mode, ActivityKit, menu bar fallback, touch input.
- Window management, clipboard history, dictation, translation.
- Script-raised alerts, script sandboxing, list widgets.
- Touch ID for notes, full VoiceOver, UI snapshot tests.
- Calendar week view, intermediate presence levels.
- release-please, official homebrew-cask, paid supporter edition, GitHub Pages appcast.
- Community adapters (OpenCode, Aider, Cursor CLI) and terminals beyond the four.
- Notes are not Obsidian-compatible (consequence of encryption, SPEC §7.6).

## 7. Open questions and unresolved [ASSUMPTION]s

SPEC §14 (open unless marked decided):
1. Warp tab focus feasibility (spike).
2. Unofficial plan-limit endpoints may break.
4. Detecting blocked/failed per agent (Claude `Notification` subtypes; Codex/Gemini approvals; error detection).
5. Agent CLIs change fast: version detection + fixtures.
8. Coexisting with other notch apps.
9. Signing identity: org Developer ID vs project branding; who controls certs/keys.
10–11. Dynamic Island Macs and ActivityKit availability (plain mode until spike).
12. Touch input.
13. Menu bar fallback mode.
14. Warning before manual sleep.
15. Reliable host-slept detection.
16. Ask AI launch with attachment / unsent prompt per CLI.
17. More blocked/failed sessions than slots; one alert vs summary on wake.
18. Script widgets in side slots vs arbitration.
19. Defaults to confirm: quota 80 %, shelf TTL 7 d, clipboard clear 30 s; sounds default if onboarding skipped; notes hotkey; Settings entry points.
20. DND-suppressed alerts: replay or drop.
- §14.3 Name: decided, but trademark search (INPI/EUIPO class 9) and domain (`vigie.app` / `vigie.dev`) still to do; GitHub org `vigie-app` suggested.
- Codex log contents and Gemini usage sources "to be confirmed / investigated" (SPEC §7.2, §8.3).

EXP Open Questions 1–24: research (pre-sleep warning, Ask AI launch, host-slept detection, 7.5–8 px label legibility); edge cases (= SPEC 17, 20); design gaps (stale/process-only visuals, closed-ring quota warning, C variant tabs, `c-light-pace-on`, C light warning contrast 4.0:1, script widgets, empty states, dark `menu_bar` style, intermediate presence, collapse timing); decisions to confirm (sounds default, script side slots, notes shortcut / Settings entry points, mock-only defaults, expiry hue, calendar color clash, all `[ASSUMPTION]` tags).

[ASSUMPTION] tags in EXP: Settings entry points; Home card click opens tab; empty-state copy (×4); quota 80 % default; shelf TTL 7 d; calendar-missing copy; focus-fail no toast; Accessibility-skip alert; agent-missing alert; cask name; confirmation shows whole file; one alert per interrupted session; label format; reduce-motion pulse; reduce-transparency treatment; onboarding steps skippable; sounds step position; reminder replays sound; custom themes token-only; presence applies to all surfaces; clipboard 30 s; Settings pane list.
[ASSUMPTION] tags in DES: `c-light-pace-on`, custom-color contrast not blocked, onboarding window type, 540 px reference width, closed-ring quota warning, C "now" color.

EP "Assumptions to rule on" A1–A78: all unratified by a human (EP Overview: produced unattended). Product-relevant ones a PRD should rule on:
- A1 SPEC stands in for PRD; A3 conflict rule; A4 mock defaults treated as decided; A5 architecture-derived NFRs; A6 all UX [ASSUMPTION]s adopted.
- A12/A13/A14/A15 scope shifts across versions (no Home until v0.3; basic Settings in v0.1; Chrome Hologram light+dark in v0.1; Reduce motion ignored until v0.4).
- A17/A64 terminals ship at whatever focus level spikes find.
- A18 local-only providers draw no ring.
- A19–A22 resolve SPEC §14.17, 14.18, 14.20 (most-recent fill slots; one alert per session; DND drops; scripts compete like modules).
- A24 host-slept heuristic accepts false "failed"; A25 pre-sleep warning research only; A26–A28 island, touch, menu bar fallback out of v1; A29 coexistence warning in v0.4.
- A30 notes hotkey `cmd+shift+n`; A31 sounds off if onboarding step skipped; A32 right-click menu with Settings / Quit; A33 donation prompt at 21 days.
- A52 peek queueing / rate limit; A53 quiet hours format; A56 bundled price table for cost; A57 plan limits via user-pasted credential; A60/A61 display prompt and launch-at-login only in v0.4; A62 plan-limit refresh 5 min; A63 beta channel in v0.1; A70 notification permission on demand; A71 no overwrite of existing Codex `notify`; A72 Ask AI disappears if sessions disabled; A74 invented config keys.

## 8. Gaps (what a PRD needs that no input covers)

1. **Success metrics and counter-metrics.** No measurable target anywhere: no adoption goal (installs, stars, active users), no donation target, no quality bar (missed-alert rate, false "blocked"/"failed" rate, focus-success rate per terminal), no counter-metrics (interruptions per hour, CPU/battery cost, alert fatigue). "Only if the project gains users" (SPEC §2.1) has no threshold.
2. **Competitive positioning.** Competitors appear only as visual inspiration or rejected patterns (Notchi, Claude-Usage-Tracker, ccusage, Itsycal, Boring Notch, GrokBot, Coucou, Peon Ping; EXP Inspiration, SPEC §7.2, §6). No comparison against other notch apps (e.g. paid notch utilities), agent dashboards, or terminal-native notifications; no differentiation statement or reason to switch.
3. **Why now / problem evidence.** No market or timing rationale (rise of multi-session CLI agents, quota-based plans, Dynamic Island Macs shipping 2026-11-06), and no evidence of the pain beyond the author's own flows.
4. **Target users beyond the author.** Only Romain (author) and Léa (one illustrative flow). No segmentation (solo vs team devs, agent mix, terminal mix, notch vs external-display users), no sizing, no non-developer users of shelf/calendar/notes, no stated primary vs secondary audience.
5. **Product risks and assumptions register at PRD level.** SPEC §14 lists technical unknowns, but nothing on product risks: dependency on unofficial endpoints and fast-changing agent CLIs as an existential risk, Apple shipping a native equivalent (system Dynamic Island / Live Activities), maintainer bus factor and sustainability of donationware, notch-app conflicts, trademark. No mitigation owner or kill criteria.
6. Also missing: quantified performance/energy budget (idle CPU, memory, battery impact), release-level acceptance criteria / definition of done per version (beyond epics), scope priority (MoSCoW) explaining why calendar/notes ("nice-to-have") are in v1 at all, contribution/community model and governance for community adapters, support/feedback channel, and a privacy statement aimed at users (no-telemetry lives only in ARCH AD-16).
