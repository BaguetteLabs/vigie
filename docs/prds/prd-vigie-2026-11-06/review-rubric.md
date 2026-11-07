# PRD Quality Review — Vigie

Reviewed: `prd.md` and `addendum.md` (2026-11-06). Calibration: a solo developer building for himself and a few invited users, with a public release later and the business model undecided. The PRD was written after SPEC.md, the UX docs and the architecture spine, and it deliberately stays at capability level, so the review does not count deferral to those documents against it. It was drafted on the fast path with `[ASSUMPTION]` tags.

## Overall verdict

This is a good PRD for its stakes. It has a clear thesis ("a lookout, not a remote control"), honest non-goals, numeric NFRs, real counter-metrics and a complete Assumptions Index, and it does what it set out to do: add the why, the users, the scope by release and the risks on top of SPEC.md. Three things are at risk. First, the core promise ("get there in one move" to the exact Warp tab) depends on a spike that has not run, and the PRD does not say what happens if it fails. Second, the safety story for unsandboxed community scripts leans on a "curated" repository that FR-41's install-from-any-URL link bypasses. Third, v1 scope grew by about 15 FRs, all with assumed release slots, without a cut line for a single maintainer, while §7 says Vigie does not compete on breadth.

## Decision-readiness — adequate

Most decisions are stated as decisions. Examples: "Focus is the only Session action" (§5), keep-awake "Off by default. Lid close and manual sleep are not covered and the setting says so" (FR-18), "There is no bypass" for Do Not Disturb (FR-11), and the camera and lock-time approaches to presence detection, which the addendum §1 rejects with reasons. Open Question 1 is a model of how to state a decision: it names what the choice decides (license, contributions, CLA) and the deadline ("before accepting any outside pull request"). The Risks table names mitigations tied to FRs.

The gap is that the PRD's most load-bearing unknown is not framed as a decision. UJ-1, SM-1, SM-6 and the "Get there in one move" job all assume exact-tab Focus in Warp, the author's own terminal (§2.2). But §6.1 lists "Warp tab focus" as a spike, FR-23 defers done-ness to "the level its spike proves", and OQ5 lists Warp focus as inherited and open. Nothing says what Vigie does if the spike fails for Warp: accept app-level focus, change the daily terminal, or drop Warp from SM-6. There are no `[NOTE FOR PM]` callouts anywhere, and this is the place one belongs.

### Findings
- **high** Core promise rests on an unrun Warp spike with no fallback decision (§2.1 "Get there in one move", UJ-1, FR-23, SM-6, §6.1 Spikes) — UJ-1 says "one shortcut brings its Warp tab forward" and SM-6 sets "at least 95% ... in Warp", but FR-23 only promises "the level its spike proves". If the spike shows Warp can't target tabs, SM-6 can't be met and the main job fails for the primary user. *Fix:* add a `[NOTE FOR PM]` at FR-23 with the decision rule, e.g. "If Warp exact-tab focus fails the spike, v0.1 ships app-level focus for Warp and SM-6 is measured on iTerm2 and Ghostty only", and run the spike before committing v0.1 scope.
- **high** The script safety mitigation overstates what "curated" protects (FR-41, FR-43, §10 "Community scripts run arbitrary code", §4.9 Feature NFR) — the Risks table lists "curated repository" as a mitigation, but FR-41 says "A link from any website leads to the same Confirmation" and addendum §4 accepts any `https` URL. The "author" shown is self-declared in front matter. A user who clicks a link on a random page sees the same screen as for a reviewed repository script, and the script runs unsandboxed with Keychain secrets. *Fix:* the Confirmation screen states whether the source is the curated Script repository or an arbitrary URL (with a stronger warning for the latter), shows "author" as "claimed by the file", and the Risks row stops counting curation as a mitigation for link installs from outside the repository.
- **low** No `[NOTE FOR PM]` callouts (whole PRD) — the real tensions (Warp spike, Privacy mode detection, breadth vs. §7) are in Open Questions or not flagged at all. *Fix:* add callouts at FR-23, FR-54 and §6.1.

## Substance over theater — strong

Little here is furniture. The Vision is specific to this product: it names 5-hour and weekly quota windows, lid-close deaths and terminal bells, and could not be swapped into another notch app's PRD. There are two personas (Romain and Léa), and both drive journeys. NFRs carry numbers (SM-4: "Idle CPU under 1% and memory under 150 MB ... hooks add under 150 ms"; FR-1: "within 2 s"). The positioning in §7 is grounded in a 154-app catalogue and states what Vigie will not try to win on. Non-goals (§5) are sharp and rule things out ("No animated characters, ever").

### Findings
- **low** Léa is never introduced (§2.2, UJ-3, UJ-7) — she appears in two journeys, but §2.2 names only "the author" and "a few invited developers". *Fix:* one line in §2.2 saying who she is (an invited developer who uses Codex and Slack, later a public user).
- **low** The differentiator 3 claim needs to be narrower (§7 item 3 "no notch app offers this") — research-landscape.md notes DynamicLake's plugin market and MewNotch's bash view. The claim holds only for the specific combination: a folder of scripts, per-Mac Confirmation and a curated repository. *Fix:* "no notch app offers a script-folder plugin model with per-Mac confirmation".

## Strategic coherence — adequate

The thesis is clear and repeated: watch, tell, take you there, never act. The agent features (§4.3–4.6, FR-22) follow from it, and the counter-metrics are good, especially SM-C1 (peeks per hour) against SM-2 and SM-C2 against scope growth. The MVP kind is experience-first for one user, then retention with invited users (SM-3). That is coherent for the stakes.

Coherence weakens at the edges. §7 says "Vigie does not try to win on ... all-in-one breadth" and SM-C2 says "More modules is not better", yet this PRD adds Time with Pomodoro and break reminders, AirDrop, Copy text OCR, Privacy mode, multi-Account and install-from-link on top of the existing shelf, calendar and notes. All of them carry assumed release slots (§6.1 `[ASSUMPTION]`). Nothing says what gets cut if the single maintainer (§10) runs short. The research also points the other way: research-landscape.md calls "an open-source hybrid dev notch ... GPL, agents plus notes, shelf, calendar and scripts" Vigie's "clearest slot". So breadth combined with open source is the actual position, and both halves are muted or left open in the PRD.

### Findings
- **high** v1 scope has no priority order or cut line for a solo maintainer (§6.1, §4.7, §4.10, §4.13, §7 "does not try to win on ... all-in-one breadth", SM-C2) — 60 FRs across four releases, about 15 of them new in this PRD with assumed slots. The thesis features and the "small tools" are not ranked, so slippage will be decided ad hoc. *Fix:* split §6.1 into must-ship-for-thesis (Sessions, Alerts, Focus, Usage, `vigie run`) and can-slip (AirDrop, Copy text, Time, break reminders, Privacy mode), and name what moves out of v1 first.
- **medium** The positioning silently depends on Open Question 1 (§7, §9 OQ1) — the research's "clearest slot" is open source, but §7 lists no open-source differentiator, and OQ1 keeps "closed source with a paywall" open. If OQ1 goes closed, the position against Crowny ("closed") and Vibe Island ("paid") collapses. *Fix:* state in OQ1 that the closed-source option removes the research's primary gap, or add "open source" to §7 conditionally.
- **medium** Several success metrics have no measurement source (SM-2, SM-5, SM-6, SM-C1; §5 "Telemetry") — "no blocked Session goes unnoticed for more than 10 minutes", "Focus succeeds at least 95%" and "Peeks per working hour" all need data. Telemetry is a non-goal and no FR gives a local event log. SM-5 says "logged by the author", which won't reach the 1-in-50 precision over a month by hand. *Fix:* add an FR for a local-only event log (blocked→Focus latency, Focus outcome, peek count) that is never sent anywhere, or restate the SMs as author judgments.

## Done-ness clarity — adequate

The new features (the ones with no SPEC detail behind them) are mostly well specified. FR-22 defines exit-code mapping and pass-through, FR-41 says "a declined install leaves no file behind", and FR-48 defines Away, says what counts as work, and rules out the camera. The inherited FRs rely on SPEC for done-ness (FR-2, FR-6, FR-8, FR-19, FR-35, FR-49). That is acceptable given §0. A few new-feature FRs still leave an engineer guessing, and one testable consequence is false as written.

### Findings
- **medium** FR-4's consequence contradicts FR-59 (FR-4 "makes no network call", FR-59 Sparkle auto-update) — with only the Shelf enabled, Sparkle still checks for updates over the network. AirDrop (FR-32, on by default) is also arguably network activity. *Fix:* "makes no network call other than the update check (FR-59)", or make the update check part of the test setup.
- **medium** Break reminders and Pomodoro interaction is undefined (FR-45, FR-48, UJ-8) — UJ-8 runs both at once. Does a Pomodoro break while Away reset the break-reminder clock? Is the 55-minute reminder suppressed while a Pomodoro is running? Can both peek at the same moment? *Fix:* one rule, e.g. "While a Pomodoro runs, break reminders are suspended" or "a Pomodoro break of at least the break length counts as a taken break".
- **medium** Privacy mode's hidden-field list is narrower than its principle (FR-54 vs §4.13 "nothing that names or quotes user content") — the list leaves out Shelf file names and Quick Look thumbnails, Usage cost "by project" (FR-27 shows project names), and macOS notifications sent by the Notifier (FR-10), which show over a shared screen. *Fix:* state the principle as the requirement ("every surface, including macOS notifications, shows only Status glyphs and numbers") and keep the list as examples.
- **medium** Timer behavior across quit, relaunch and sleep is missing (FR-44, FR-47) — a Countdown to a clock time and a Pomodoro started before sleep or an update relaunch (FR-59) have no stated outcome. *Fix:* "Running Timers and Countdowns survive relaunch and sleep; an end that passed while asleep raises its Alert once on wake."
- **medium** Multi-Account attribution is not defined (FR-28, FR-25) — "for every Provider" assumes Vigie can tell which Account a local-log Session used (e.g. two Claude Code config dirs). The closed-notch rule is an assumption, but how a Session maps to an Account is not stated. *Fix:* a consequence such as "each Account is bound to its log or config location; Sessions are attributed by that location", or point to the addendum.
- **medium** The peek display vs. the user's chosen displays (FR-9, FR-1, UJ-1 "active display", UJ-3 "display under her cursor") — if the pointer is on a display the user excluded under FR-1, the peek location is undefined, and the UJs use different terms. *Fix:* "the Vigie display nearest the pointer" or "under the pointer, else the main Vigie display", and use one term.
- **low** "Returns immediately" is an adjective (FR-15) — the bound lives in SM-4 ("under 150 ms"). *Fix:* put the bound in FR-15 itself.
- **low** Ctrl-C maps to failed (FR-22, second bullet) — a user interrupt is not a failure, and it will trigger a failed peek. *Fix:* consider ending as done-quietly or gone, or say that no Alert fires on a user interrupt.

## Scope honesty — strong

Omissions are explicit. Examples: §2.3 Non-Users, §5 Non-Goals, §6.2 with reasons ("hardware-gated", "by contribution"), FR-18 says what keep-awake does not cover, FR-16 commits to honest "unsupported", and the §4.9 Feature NFR states plainly that scripts run unsandboxed. The open-item density (about 14 assumption tags and 5 open questions) is fine for a solo, pre-public PRD, and every target in §8 is honestly marked assumed.

### Findings
- **medium** "By contribution" conflicts with OQ1 (§6.2 "Community Adapters ... and further terminals: by contribution" vs §9 OQ1 "Decide before accepting any outside pull request to the app") — Adapters are app code, so this out-of-scope line plans on contributions that OQ1 says may not be accepted yet. *Fix:* add "pending OQ1" to the §6.2 line.
- **medium** Dynamic Island Macs are framed as "later" while the hardware ships today (§6.2 "Dynamic Island display mode ... later, hardware-gated", §10 Apple row) — SPEC §14 #10 notes OLED MacBook Pros with a system Dynamic Island ship 2026-11-06, and Vigie runs in plain/fallback mode on them. For the public stage, the newest developer laptops lose the core surface. The Risks row frames this as "Reduced need", which is not the real impact. *Fix:* add a Risks row ("New MacBook Pros have a system island; Vigie falls back to plain mode") with a trigger to revisit before public release.
- **low** The coexistence warning has no FR or release slot (§10 "Coexistence warning (v0.4)") — it appears only as a mitigation and is missing from §4 and §6.1. *Fix:* add an FR or move it to §6.2.

## Downstream usability — adequate

This PRD sits at the top of a chain whose lower links already exist, so downstream usability matters. The IDs are clean: FR-1 to FR-60, UJ-1 to UJ-8 and SM-1 to SM-6 plus SM-C1 to SM-C3 are contiguous and unique. The glossary is good and mostly used verbatim. Features cite their SPEC sections. The main risk is reconciliation. epics.md predates this PRD (OQ4: "A1–A78 await rulings, and the new features here have no stories yet"), and the architecture spine is "not yet amended" (addendum §5). The precedence rule in §0 ("Those documents ... win on their own ground") is ambiguous where this PRD changes something SPEC already defines. Example: SPEC §13 says "2–3 example scripts" while FR-40 lists five, and SPEC's roadmap has none of the new features.

### Findings
- **medium** The precedence rule doesn't cover deliberate changes to SPEC (§0, FR-40 vs SPEC §13, §6.1 vs SPEC §13 roadmap) — story creation will hit conflicts and §0 says SPEC wins. *Fix:* "Where this PRD adds or changes scope (features marked new, §6.1 release slots), the PRD wins until SPEC is updated", and list SPEC sections to amend next to addendum §5.
- **medium** "Focus" collides with macOS Focus (FR-11 "While macOS Do Not Disturb or a Focus is on" vs Glossary "Focus — the only Session action") — the same capitalized word means two different things in the same section. *Fix:* call the macOS one "a macOS Focus mode" everywhere, and add a glossary note.
- **low** UJ-1 to UJ-5 lack "Realizes FR-" lines (§2.4) — UJ-6 to UJ-8 have them. The reverse links exist on the features, but each UJ should stand alone. *Fix:* add the FR lists.

## Shape fit — strong

The shape fits. The product is a single-operator tool with meaningful UX, so a handful of UJs with named protagonists earns its place. The capability-level FRs suit a PRD written on top of a detailed SPEC. Hobby-to-public stakes justify the light rigor, and the substance bar is met. The PRD doesn't over-formalize: no persona matrix, no compliance theater. The addendum is used properly, keeping mechanisms out of the FRs.

No findings.

## Mechanical notes

- **Assumptions Index roundtrip:** every inline `[ASSUMPTION]` in prd.md is indexed in §11. Two addendum tags are not indexed: §1 "Present if input within ~90 s" and §4 "Until confirmed, the old version keeps running". Add them to §11 or mark the index as PRD-only.
- **ID continuity:** FR-1 to FR-60, UJ-1 to UJ-8, SM-1 to SM-6 and SM-C1 to SM-C3 have no gaps or duplicates. The cross-refs to addendum §2 and SPEC §14 resolve.
- **Undefined terms used as if defined:** "Tab" (capitalized, only inside the Expanded view entry), "Session messages" (FR-54), "AI tokens" (FR-56, which probably means Account credentials), "spike" (§6.1, FR-23), "Calm mode" vs. Presence mode "calm" (FR-36 vs. glossary).
- **Term drift:** "active display" (UJ-1) vs. "display under the pointer" (FR-9) vs. "display under her cursor" (UJ-3).
- **Glossary pairing:** "Script module / Widget" defines two different things in one entry (the file and its output). Split them.
- **Release labels:** §6.1 v0.4 says "public release readiness" while SPEC §13 says "public release". Both are compatible with §2.2, but say which one is meant.
- **Required sections:** all are present for the stakes (Vision, Users, UJs, Glossary, FRs, Non-Goals, Scope, SMs with counter-metrics, Open Questions, Risks, Assumptions Index).
