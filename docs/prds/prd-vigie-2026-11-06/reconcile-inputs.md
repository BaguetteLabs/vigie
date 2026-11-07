---
title: Vigie PRD — input reconciliation
created: 2026-11-06
checks: prd.md + addendum.md against SPEC.md, EXPERIENCE.md, DESIGN.md, ARCHITECTURE-SPINE.md, .memlog.md
---

# Input reconciliation

Scope: only (a) uncovered capabilities or behaviors, (b) contradictions, (c) dropped qualitative intent, (d) memlog decisions not reflected. Missing implementation detail and config keys are out of scope on purpose.

Totals: **28 findings**: (a) 6 · (b) 12 · (c) 9 · (d) 1.

## SPEC.md

| # | Type | Source | Finding | Suggested fix |
|---|---|---|---|---|
| S1 | b | SPEC §12.4, §11 `[updates] auto_install = false` | FR-59 says every release "auto-updates"; SPEC checks automatically but asks before installing by default. That also matches the JTBD "nothing installs without the user having said so". | FR-59: "checks for updates automatically and installs only after the user agrees (auto-install is opt-in)". |
| S2 | b | SPEC §2 (License, Funding), §2.1; EXPERIENCE Foundation "Stakes", Settings "Support" pane; memlog line 25 | SPEC and EXPERIENCE record GPL-3.0 and donationware as decided, including an in-app Support item and one dismissible donation prompt. The memlog says the business model is undecided. PRD §9.1 opens the question but does not say which input text is on hold, and the in-app Support prompt is not covered anywhere. | §9.1: add "SPEC §2/§2.1, EXPERIENCE Stakes and the Settings Support pane are on hold until this is decided". |
| S3 | b | SPEC §5, §5.1, §14.18; EXPERIENCE IA (left wing = usage, right wing = sessions), SPEC impacts row §1/§5 | In SPEC, each side shows **one** winning module, which fills that side's slots. The PRD glossary ("slots that modules compete for"), FR-3 and FR-46 ("competing like any module" for a slot) have modules competing per slot. That quietly settles the open question on script widgets in side slots (SPEC §14.18). | Reword FR-3 as "modules compete for each wing; the winning module fills its slots". FR-46: the Time module competes for a wing. Or move the per-slot model to §9 Open Questions. |
| S4 | a | SPEC §5.2 "optional secondary reminder", §6 `reminder`; EXPERIENCE Peek, Flow 1 failure path | FR-10 lists mute, outputs, quiet hours and cooldown but not the per-kind reminder that replays the peek and sound once if the state is unchanged. SM-2 depends on it. | FR-10: add "an optional reminder after a delay" to the per-kind settings. |
| S5 | a | SPEC §8.3 `removalPlan()`; PRD §7 item 5 "reversible hooks" | FR-14 covers installing hooks with a diff but not removing them. Positioning promises reversibility. | FR-14: "...and removes them the same way (diff, backup) when the user disconnects an agent". |
| S6 | a | SPEC §9.2 (non-zero exit), §9.3 `action` (open / run / copy); EXPERIENCE "Script errored" | Two script behaviors no FR covers: widget actions (open a URL, run a command, copy text) and the error state (keep the last good output with a warning badge). | FR-37: add "a Widget can open a URL, run a command or copy text; a failing run keeps the last good output with a warning badge". |
| S7 | a | SPEC §7.1 Liveness (`?` stale badge), §8.3 tier 3 "Process only"; EXPERIENCE Session states | No FR covers the stale marker on a working Session that has gone silent, or presence-only Sessions from process detection. | FR-16: add "a working Session silent past a timeout is marked stale; process-only agents show presence, not Status". |
| S8 | a | SPEC §14.10 (decided 2026-11-04), EXPERIENCE Foundation, Responsive "Island display" | SPEC decided that Macs with a system Dynamic Island run in plain/fallback mode in v1, and that hardware ships today. The PRD only lists an island display mode as "later". It never says such Macs are supported as plain displays. | FR-2: add "Macs with a system Dynamic Island are treated as plain displays (virtual notch) in v1". |
| S9 | a | SPEC §11.1 (notes key, recovery key); AD-9, AD-10 | FR-53 omits user-facing key behavior. A user can export a recovery key. A second Mac waits for the key or asks for the recovery key and never creates a second key. | FR-53: add "a recovery key lets another Mac read the notes; Vigie never creates a second notes key". |
| S10 | c | SPEC §2 "Language"; EXPERIENCE Foundation; AD-15 | The PRD drops "English first, every string localizable from the first commit". | Add to §4.14 or a cross-cutting NFR: "English first; all user-facing text is localizable from v0.1". |
| S11 | c | SPEC §1 Goals "none of them is special-cased in the core" | The agent-neutral principle is missing. The PRD names Claude Code as the v0.1 adapter but never says no agent gets special treatment. | §1 Vision or the FR-13 description: "every agent, Claude Code included, goes through an Adapter; none is special-cased". |

## EXPERIENCE.md

| # | Type | Source | Finding | Suggested fix |
|---|---|---|---|---|
| E1 | c | EXPERIENCE "Accessibility Floor"; SPEC §10.2 | The accessibility floor is dropped. The PRD has only FR-36 (Reduce motion) and FR-8 (keyboard), plus "full VoiceOver" out of scope. Missing: an accessibility label with state on every control and glyph, color never the only cue, Reduce transparency and Increase contrast honored, light-mode text at 4.5:1 or more, peek actions reachable by global shortcut. | Add an FR "Accessibility floor (v1)" listing these, with "color is never the only cue" as its acceptance criterion. |
| E2 | c | EXPERIENCE "Voice and Tone"; DESIGN Brand & Style | The PRD drops tone. Compact UI uses short uppercase technical labels. Messages are terse, factual, complete sentences. No exclamation marks, no personification, and the same wording in every theme. | §1 Vision or §4.3: add "Copy is terse and factual: uppercase labels, no exclamation marks, no personification". |
| E3 | c | EXPERIENCE Interaction Primitives "Banned: … auto-opening the expanded view"; SPEC §10 "The view never opens by itself" | FR-5 covers focus but not the rule that the Expanded view never opens by itself, and that hover only reacts unless hover-to-open is enabled. | FR-5: add "The Expanded view never opens by itself; hover only reacts unless the user enables hover-to-open". |
| E4 | b | EXPERIENCE Flow 2 step 1; SPEC §7.1.2; PRD FR-18 | UJ-2 has the run die on lid close, then says "With keep-awake on, idle sleep would not have happened at all". That implies Keep-awake would have saved the run, but lid close is explicitly not covered. | UJ-2: "Keep-awake prevents idle sleep while agents work; it cannot stop a lid close, which is why the failed alert matters." |
| E5 | b | EXPERIENCE Widget card "User picks widgets and order"; SPEC §10 Home | FR-7 says Home shows "one card per module that offers one". The inputs let the user choose which cards appear and in what order. | FR-7: "Home shows the cards the user picks, in the user's order; clicking a card opens that module's Tab". |
| E6 | b | EXPERIENCE Presence Levels (calm keeps "one simple pulse when something is blocked or failed"); DESIGN Presence levels | FR-36 says calm mode "removes motion and glow" without the exception. | FR-36: "...except one simple pulse on a blocked or failed Session". |
| E7 | b | EXPERIENCE Flow 3 step 8, Responsive "Multiple displays" | UJ-1 says the peek appears "on the active display". The inputs and FR-9 say "the display under the cursor". | UJ-1: replace "active display" with "display under the pointer". |

## DESIGN.md

| # | Type | Source | Finding | Suggested fix |
|---|---|---|---|---|
| D1 | c | DESIGN "Brand & Style" | The PRD drops the intended feel: "software from the future", sci-fi instrument panels in metal, abstract, no radar, targeting or mascot. Only the mascot ban survives, in §5. | §1 Vision or §4.8: one sentence on the posture ("a quiet sci-fi instrument: metal, thin rings, uppercase readouts; never targeting imagery"). |
| D2 | c | DESIGN "Containment", Do's and Don'ts; EXPERIENCE "Rejected — HUD spilling over the menu bar" | The PRD drops strict containment: every pixel stays inside the island or panel outline, with nothing on the menu bar or desktop. It is a core part of "as little space as possible". | §4.1: add an acceptance criterion to FR-3: "Nothing is drawn outside the island or panel outline". |
| D3 | c | DESIGN Brand & Style "a skin only restyles", Do's and Don'ts "Keep wording, layout and slots identical across variants" | FR-35 does not say themes change only the look. | FR-35: add "A theme changes look only; wording, layout and slots are the same in every theme". |

## ARCHITECTURE-SPINE.md

| # | Type | Source | Finding | Suggested fix |
|---|---|---|---|---|
| A1 | b | AD-16 (Sparkle update checks allowed); SPEC §11 `[updates] auto_check = true` | FR-4's acceptance criterion says "With only the Shelf enabled, Vigie … makes no network call". The default Sparkle update check is a network call. | FR-4: "...makes no network call other than the update check, which the user can turn off". |
| A2 | b | AD-23 "Usage identity: one usage provider per adapter (`id` = adapter id) … one ring per provider … `order` and `providers.<id>` key on adapter id" | FR-28 (several Accounts per Provider) conflicts with AD-23's identity, ring and order keys. Addendum §5 only says "config keyed by account" and does not name AD-23 or decide ring per Account vs per Provider. | Addendum §5, FR-28 row: "AD-23 usage identity becomes adapter id + account; decide ring per Account or per Provider". |
| A3 | b | AD-13 "Canonical kinds: session.blocked, session.done, session.failed, usage.quota_warning, shelf.expiring, setup.problem" | The canonical alert kinds are a closed list. FR-47 (Timer, Countdown and Pomodoro ends) and FR-48 (break reminders) add kinds that the list and the `[sounds]` mapping lack. Addendum §5 has no Notifier row. | Addendum §5: add "FR-47/48 → AD-13 canonical kinds and sound mapping gain time and break kinds". |
| A4 | b | AD-20 (Permission cases: accessibility, automation, calendar, notifications; no other entitlements); FR-4 | Privacy mode detection candidates (a ScreenCaptureKit or CGWindow query) may need the Screen Recording permission. AD-20 does not allow it, and addendum §2 does not mention the permission cost. | Addendum §2: "Preferred method needs no new permission; otherwise AD-20 adds Screen Recording and FR-54 says it is requested only when Privacy mode auto-detection is on". |
| A5 | b | AD-6 "exits 0 with no output in every case" | `vigie run` (FR-22, addendum §3) passes the command's output and exit code through, which breaks AD-6 as written. Addendum §5 says "no new host concept" but proposes no AD-6 carve-out. | Addendum §5, FR-22 row: "AD-6 carve-out: `vigie run` returns the child's output and exit code; only its event send follows the socket-else-spool rule". |
| A6 | c | AD-16 "no network calls except: Sparkle, opt-in plan-limit providers, script modules … Diagnostics only by user-triggered Copy diagnostics" | The PRD keeps "no telemetry" but drops the stronger privacy promise: a closed list of network destinations, and diagnostics only on user request with secrets excluded. Script install and update fetches extend that list. | §5 Telemetry non-goal: "Network only for update checks, opt-in usage limits, scripts and script installs/updates; diagnostics only via user-triggered Copy diagnostics, secrets excluded". |

## .memlog.md (session decisions)

| # | Type | Source | Finding | Suggested fix |
|---|---|---|---|---|
| M1 | d | memlog line 13: "Vigie shows status only, never note titles, secrets or session text" | FR-54's list of hidden content is narrower than "status only". It omits Shelf item names, Timer, Countdown and Pomodoro labels, Account names (often emails), cost-by-project names in Usage, and the drop-zone Ask AI folder. The FR-54 description and the FR text also disagree. | FR-54: "shows only Status glyphs, rings and numbers; hides every user-supplied name or text (notes, secrets, Sessions, projects, Shelf items, Timers, Accounts, scripts, calendar)". |

The other memlog decisions (Time module, Keep-awake, `vigie run`, multiple Accounts, escalation after v1, example scripts, the community script flow that supersedes line 17, Copy text off, AirDrop on, break defaults and presence detection, no pets, stakes, business model) all appear in the PRD.
