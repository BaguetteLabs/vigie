# Validation Report — Vigie

- DESIGN: `/Users/me/Documents/Ideas/notch/ux-designs/ux-vigie-2026-11-04/DESIGN.md`
- EXPERIENCE: `/Users/me/Documents/Ideas/notch/ux-designs/ux-vigie-2026-11-04/EXPERIENCE.md`

Run at: 2026-11-07T18:03:40+01:00

## Overall verdict

**Adequate. Needs a targeted revision before it is a clean contract.** The visual system is strong: every color token has a hex value in all four looks, the frontmatter resolves almost completely, every mockup and import is linked where it is used, and the Story 1.7 surfaces are specified in enough detail to build. The gaps are on the experience side: 3 of 8 user journeys have no Key Flow (UJ-6, UJ-7, UJ-8); Privacy mode, multiple Accounts, install-from-link Confirmation and the closed-notch Calendar glance are missing from both spines; the PRD is not listed as a source; peek concurrency and the quota-warning peek are not designed; and Flow 2 contradicts a decision recorded elsewhere in the same file. A consumer can extract the visuals cleanly. For the gaps above, a consumer would have to invent the behavior.

The accessibility reviewer gives a **conditional pass**: the core palette clears 4.5:1 in every look and no state relies on color alone in the main surfaces, but five high findings block the 1.7 stories (C light quota-warning text fails, no visible A light gear focus, no keyboard path to the drop display and Shelf, no Snooze shortcut, and a missed break peek leaves a stalled Pomodoro with no trace). The consistency reviewer finds the set **not ready to build without a cleanup pass**: the 2026-11-07 rulings reached every headline section, but older restatements in SPEC, epics, one PRD journey and one EXPERIENCE failure path still describe superseded behavior. Both reinforce the rubric's Flow 2, UJ-8 and Privacy mode findings.

## Category verdicts

| Category | Verdict |
|---|---|
| Flow coverage | thin |
| Token completeness | adequate |
| Component coverage | adequate |
| State coverage | thin |
| Visual reference coverage | strong |
| Bloat & overspecification | adequate |
| Inheritance discipline | thin |
| Shape fit | adequate |

## Findings by severity

### Critical (0)

None.

### High (16)

**[Flow coverage + Consistency]** — UJ-8 has no Key Flow, and UJ-8 contradicts FR-49 (§ EXPERIENCE Key Flows; prd.md:69)
Time is a Story 1.7 surface but has no flow. UJ-8 describes a break reminder firing while a Pomodoro runs, but FR-49, PRD §11, SPEC §7.7 and Story 20.6 all say break reminders pause during a Pomodoro. Under the 2026-11-07 ruling a Pomodoro work-phase end shows the break peek and waits for Start break, so "restarts without a click" is not true either.
Fix: Write Flow 6 around a plain break reminder: strength Peek, Away for 5 min counts as the break, the cycle restarts, plus a failure path (snooze, or user does not leave). Ask the PM to rewrite UJ-8 with either no Pomodoro or a Pomodoro only.

**[Flow coverage]** — UJ-7 (install a community script from a link) has no flow and no surface (§ EXPERIENCE Script Modules; IA table)
Nothing describes the Confirmation screen: the "Verified: Vigie Script repository" state, the stronger warning for unsigned or other scripts, the author "claimed by the file", the full-file view, or the update diff with re-Confirmation (FR-42, FR-43). Only the sync case is covered.
Fix: Add a Confirmation surface to the IA with its states (verified / unsigned / invalid signature / update diff / declined), and add Flow 7.

**[Flow coverage + Consistency]** — Flow 2 failure path contradicts the wake-summary ruling (§ EXPERIENCE:235)
Flow 2 says interrupted sessions each become failed and "alerts play once each [ASSUMPTION: no grouped summary alert in v1]". State Patterns (EXPERIENCE:153/162), Open Question 6, SPEC.md:384 and Story 4.12 (epics.md:1983) all say one summary alert: `<n> sessions interrupted by sleep` with `OPEN AGENTS`.
Fix: Rewrite the failure path to use the summary alert and drop the assumption.

**[Component coverage]** — Quota-warning peek and sleep-summary peek have no visual spec or actions (§ EXPERIENCE:34, 153; DESIGN:768–771)
The IA lists the quota-warning peek as a trigger, but DESIGN's Peek variants (blocked / done / failed / Time) omit it: kicker, title, beacon, hue and the two actions (e.g. `OPEN USAGE` / `DISMISS`) are uncommitted. The sleep summary peek (`<n> sessions interrupted by sleep`, `OPEN AGENTS`) has no visual spec either.
Fix: Add both to DESIGN Peek variants and to EXPERIENCE Peek shortcuts.

**[State coverage + Consistency]** — Privacy mode is absent from both spines (§ PRD FR-55; EXPERIENCE:398 (Settings panes); epics A88/A89)
No redacted rendering per surface (session titles, project names, Shelf items, Timer labels, widget text, calendar titles, notes), no indicator, no manual toggle, no "detection unavailable" message, and no Privacy entry in the Settings pane list. A88's "fixed-width dots" is the only source; Epic 21 would invent visuals against the "design first" rule.
Fix: Add a Privacy mode section and state row covering every surface, a redaction rule ("glyphs, rings, numbers only"), and the Settings entry for the force/auto toggles.

**[State coverage]** — Multiple Accounts has no UX (§ FR-29)
The closed ring should show the Account of the most recent Session and the Usage tab should show each account. Provider card anatomy has no account label, and switching is undefined.
Fix: Add an account line to the Usage provider card and to the left-wing ring label, plus a state row.

**[State coverage]** — Peek concurrency is undefined (§ EXPERIENCE:95; SPEC §5.2)
Nothing says what happens when an alert arrives while a peek is visible, while the expanded view is open, or while the drop display is showing. SPEC §5.2's rate limit is superseded with no replacement.
Fix: Commit a rule, e.g. queue by urgency, a newer blocked/failed alert replaces done, a peek is suppressed while expanded is open and the tab marker is shown instead.

**[Inheritance discipline]** — The PRD is not in either spine's `sources` (§ DESIGN, EXPERIENCE frontmatter; EXPERIENCE:380)
EXPERIENCE cites "PRD FR-49" and the PRD declares UJ-1..5 mirror the Key Flows, yet `prds/prd-vigie-2026-11-06/prd.md` is not a source. This is why the FR gaps under Flow and State coverage were not caught.
Fix: Add the PRD to both `sources` and check the spines against FR-1..FR-64.

**[Accessibility]** — C light `quota-warning` `#8A6D00` fails 4.5:1 as text everywhere it is allowed (§ DESIGN Colors → Contrast; Pace and quota-warning table)
4.03 on `c-light-surface-panel` and **4.499 on `c-light-surface-card`**, so the "warning text only on cards" rule still fails; 3.92 on `surface-vn-bottom`. A light: 4.51 on panel (almost no margin) and 4.27 on `a-light-surface-vn-bottom` (fails).
Fix: Split the role: keep `#8A6D00` for non-text fills; add `{a,c}-light-quota-warning-text: #7E6300` (4.69 C panel, 5.23 C card, 4.56 C vn-bottom, 5.24 A panel, 4.96 A vn-bottom), or `#7A6000` for wider margin. Drop the "cards only" rule and update the contrast table.

**[Accessibility]** — Settings gear has no visible keyboard focus in A light (§ DESIGN Settings gear; Elevation & Depth)
The focus is "1px platinum ring at 55% plus 3px cyan halo (dark)". Platinum at 55% on `a-light-surface-panel` measures **1.05:1** (WCAG 2.4.7 / 1.4.11).
Fix: In A light, use `components.selection-ring.a-light` (1px graphite `#161B24`) with no halo. State it in `components.settings-gear` per look.

**[Accessibility]** — Drop display, Send to zones and Shelf have no keyboard or VoiceOver path (§ EXPERIENCE Drop display, Drop zone, Interaction Primitives; DESIGN Drop display)
Stash, Ask AI, AirDrop and Image to Text are reachable only by dragging. The keyboard map has no Shelf actions besides Space for Quick Look; Reveal and Pin are hover chips. This breaks the floor rule "every expanded-view action is reachable when it has focus".
Fix: (1) On a selected Shelf row, `↵` opens a "Send to" menu, plus keys for Reveal and Pin, exposed as VoiceOver custom actions. (2) Add a Services / Share entry "Stash in Vigie" and `⌘V` on the Shelf tab. (3) Label each drop zone for VoiceOver.

**[Accessibility]** — Snooze on the break peek has no shortcut (§ EXPERIENCE Interaction Primitives "Peek shortcuts"; DESIGN Peek → Break)
Peeks never take focus, so a keyboard-only user can Start or Skip a break but cannot snooze it. This breaks the floor rule "peek actions are reachable through the global shortcuts".
Fix: Assign a third global shortcut while the peek is visible (e.g. `⌥⌘Z` or `⌥⌘S`), shown on the button; include each shortcut in the buttons' accessibility labels.

**[Accessibility + Consistency]** — Missed break peek leaves no lasting trace; `BREAK DUE` has no place when `closed_notch = "off"` (§ EXPERIENCE Time, State Patterns "Time · break due", EXPERIENCE:166; SPEC §7.7, SPEC.md:779; Story 20.6 (epics.md:4140))
A Pomodoro break waits for Start break, but the peek retracts after 5 s, the closed Time readout is `off` by default, and with DND on missed peeks are dropped. Quiet style would show nothing at all under the default config. The user ends up with a stalled Pomodoro and no visible sign. The Time tab row (`PAUSE`/`RESET`/`REMOVE`) has no `START BREAK`, though State Patterns says it is available there.
Fix: After the peek retracts, the left wing shows the `BREAK DUE` readout as a temporary left-lane item (like `COPIED`) regardless of `closed_notch`, until the break starts or is skipped. The Time tab row in break-due shows `START BREAK`, `SNOOZE 5M`, `SKIP`; the Time tab gets the attention marker; break-due counts as an unresolved alert for post-DND replay. State the rule in SPEC §7.7, EXPERIENCE and Stories 20.3, 20.4, 20.6.

**[Consistency]** — Per-side module assignment still specified, contradicting the fixed wings (§ SPEC.md:138; epics.md:58, 64; Story 2.8)
`ModuleManifest.defaultSide: NotchSide` and FR4 / FR10 ("assigned to that side or `any`") survive, while the right wing is sessions only and the left wing is the priority lane.
Fix: Remove `defaultSide`/`NotchSide` from SPEC §4.2. Mark FR4 and FR10 **Amended 2026-11-07** like FR9: right wing = `agents.sessions` only; left wing pools items by state, then `priority`, then provider `order`.

**[Consistency]** — Story 9.1 states two different DropZone contracts (§ epics.md:2663, 2683–2685, 222; SPEC.md:190–199)
The first AC uses the superseded `{ id, label, glyph, accentToken, placement, accepts, handler }`; a later AC uses `role`/`DropCell`/`order` per AD-19. The AD-19 summary and SPEC §4.6 still show the old shape.
Fix: Rewrite the first AC to `{ id, label, glyph, accentToken, role, cell: DropCell, order, accepts, handler(DropPayload) }` with `source: .dropDisplay | .shelfTab | .homeWidget | .stashItem`; update the AD-19 summary and SPEC §4.6.

**[Consistency]** — Two-wing closed-notch drop zones still described as current (§ epics.md:94, 111, 295, 324, 471, 613; SPEC.md:357)
FR57, FR40, UX-DR50, UX-DR70 and SPEC §7.1 still describe dropping on the closed notch; Story 9.1 lists FR57 and UX-DR50 as live.
Fix: Mark FR57, UX-DR50 and UX-DR70 superseded or amended to "drag-only drop display (layout B)"; change SPEC §7.1 to "on the drop display".

### Medium (40)

**[Flow coverage]** — UJ-6 (`vigie run -- make deploy`) has no flow (§ EXPERIENCE Key Flows; FR-23)
How a non-agent session appears is not committed: the agent column value, the failed kicker and reason for a non-zero exit (e.g. `FAILED · EXIT 2`), and done vs failed by exit code.
Fix: Add a short Flow 8 and one row in the session-states table.

**[Token completeness]** — Template and glob token refs a resolver cannot expand (§ DESIGN:339–341, 655, 707)
`{colors.<look>-status-idle}`, `{colors.<look>-quota-warning}` and `{colors.<look>-status-failed}` in `components.status-vocabulary`; `components.*-panel.shadow-*`; `typography.*-readout-value`.
Fix: State one resolver rule ("`<look>` is substituted with the active look") in the token-scheme section, or expand the refs per look as `widget-card` does.

**[Token completeness]** — No contrast stated for accent colors used as text (§ DESIGN Contrast, 552–563)
Missing: `a-light-iris-1/2/3` (Time values, `IN 42 MIN`, `ASK AI` label, revealed secret), `c-dark-gold-text`, status labels on alert-tinted rows and on `surface-card`; `c-light-gold-text` 5.5:1 appears only in prose.
Fix: Add an "accent text" row per look, and a row for status labels on `surface-card` and on the tinted rows.

**[Token completeness]** — Only `motion.enter` is defined; no exit, peek or grow durations (§ DESIGN motion; EXPERIENCE:450 (OQ17))
There is no token for collapse or exit, or for peek, drop-display and expanded grow and retract. Story-dev will invent these values.
Fix: Commit provisional values: `exit`, `peek-grow`, `drop-display-grow`.

**[Token completeness]** — No tokens for the dark-mode `menu_bar` virtual notch (§ EXPERIENCE:408 (OQ15))
`surface-vn-*` exists only for light, yet Responsive & Platform says `style = menu_bar` takes the menu-bar material.
Fix: Add `a-dark-surface-vn-*` and `c-dark-surface-vn-*`, or state that dark `menu_bar` falls back to `base-island`.

**[Token completeness + Accessibility]** — Light Time accent / ring arc color is unspecified, and the likely candidate fails 3:1 (§ DESIGN:376–377, 499 (Variant accents → Time accent))
`components.time-ring` gives only dark accents; light values (`#126F8C` text, `filament-1` rims, `c-light-gold`) live only in Colors prose. If A light arcs follow the rim, `filament-1` `#3FA3C4` measures 2.65 on panel and 2.90 on card, below 3:1 for a graphic that carries time left.
Fix: Add `a-accent-light` and `c-accent-light` to `components.time-ring`. State that A light Time arcs and the current-phase pip use `a-light-iris-1` `#126F8C` (5.23 / 5.71); keep `filament-1` for the decorative rim only.

**[Component coverage]** — Several DESIGN components have no Component Patterns row (§ DESIGN:884; EXPERIENCE:335)
Script page, Side-slot item, Phase indicator, Readout, `SEND TO` card, Scroll and reorder affordances, Notes tab: behavior is scattered across module sections.
Fix: Add rows. Script page especially needs tab naming, keyboard, and the `REVEAL` / `OPEN SOURCE` targets.

**[Component coverage]** — Status vocabulary visual spec sits under Colors, not Components (§ DESIGN:517–532)
It is a component (`components.status-vocabulary`) but its shape, sizes and stroke are specified in Colors.
Fix: Move it to Components and leave a pointer in Colors.

**[Component coverage]** — Home widget catalog has no anatomy or sizing rules (§ DESIGN:623; EXPERIENCE:102)
Sessions, quota, shelf, calendar card, GitHub PR count and script widgets have no anatomy; "cards can span two columns" is not tied to a user action.
Fix: List the widget catalog with each widget's span, and state how the user adds and reorders widgets.

**[State coverage + Consistency]** — "More blocked/failed sessions than slots" is both decided and open (§ EXPERIENCE:94, 136, 155, 436 (OQ5); SPEC.md:897 (§14.17); ARCHITECTURE-SPINE.md:379)
SPEC §14.17 and the architecture Deferred table mark it decided; EXPERIENCE still defers it. The rule "`+X` never hides a blocked session" cannot hold with four blocked sessions and three slots.
Fix: Copy the SPEC §14.17 rule into EXPERIENCE and close OQ5. Qualify "never hides" to "never hides one while a lower-urgency session is visible", or give `+X` the blocked hue when it hides an alert.

**[State coverage]** — Usage: stale, loading and day-one states missing (§ FR-30)
No stale indicator when remote limits fail, no first-launch loading state, no empty `HISTORY · 7D` or unavailable `COST · TODAY` on day one.
Fix: Add state rows.

**[State coverage]** — Time: empty state and FR-45/48/49 rules missing (§ EXPERIENCE Time; State Patterns)
No empty state for the Running card; "an end that passed while asleep raises its Alert once on wake" (FR-45) is missing; "break reminders are paused while a Pomodoro runs" and "Away time does not count as work" (FR-49) are not stated; the alert at the end of a Pomodoro break (FR-48) is unspecified.
Fix: Add these to Time and State Patterns.

**[State coverage]** — Script states exist only for the widget (§ EXPERIENCE:161–162)
Side slot and script page have no awaiting-confirmation, errored, never-run, timed-out or update-awaiting-re-Confirmation states (FR-43).
Fix: Extend the state rows to all three surfaces.

**[State coverage]** — Notes: empty, no-results, first-launch and failure states missing (§ EXPERIENCE Notes)
No empty list, no "search finds nothing", no first-launch state for the floating panel, no decrypt or sync failure (E2E keys on a new Mac; iCloud conflict).
Fix: Add state rows.

**[State coverage]** — Drop display: no in-progress, error or all-zones-disabled states (§ EXPERIENCE Drop display)
No in-progress state for Image to Text between drop and `COPIED` (e.g. multi-page PDF OCR), no failure state for AirDrop or Stash (unreadable file, disk full), no rule for when Shelf is off or every zone is disabled.
Fix: Add a `READING…` readout state and an error readout, and state that with no enabled zone no display appears.

**[State coverage]** — Home empty state and Agents tab empty visual still open (§ EXPERIENCE:146–147 (OQ14))
Copy exists only as [ASSUMPTION].
Fix: Commit the copy; the visual can use Empty state block.

**[Bloat & overspecification]** — Module sections restate pattern rows and have drifted (§ EXPERIENCE:110 vs 365)
Usage, Shelf, Calendar, Time, Notes and Script Modules repeat Component and State Patterns rows: "at most 5 events" vs "at most about 5", and the `BREAK` label.
Fix: Keep one home per rule. Module sections hold only what has no row (format, sync, settings).

**[Bloat & overspecification]** — Open Questions carries 14 resolved items and a history paragraph (§ EXPERIENCE:437–463)
Struck-through decided items and "Design before build … Done" duplicate the body.
Fix: Delete resolved items, keep only open ones, move history to `.memlog.md`.

**[Inheritance discipline]** — Glossary drift from the PRD (§ EXPERIENCE:168 and passim)
"Presence levels" vs PRD **Presence mode** / "Calm mode"; "Idle-sleep prevention" vs **Keep-awake**; countdown "to a date" vs "to a clock time"; "Do Not Disturb / Focus mode" where the PRD requires "macOS Focus mode" in full.
Fix: Adopt the PRD terms verbatim.

**[Inheritance discipline]** — FR-50 closed-notch Calendar glance is missing (§ FR-50; EXPERIENCE left-wing lane; SPEC.md impacts)
The left-wing lane lists only rings, scripts and Time, and SPEC.md impacts does not record the conflict.
Fix: Add Calendar as a left-lane item, or record the removal in SPEC impacts and raise it with the PM.

**[Accessibility]** — `ink-3` text on tinted alert rows fails in the dark looks (§ DESIGN Session row; C tabs)
`ink-3` over the 10% blocked/failed fade on `surface-card`: 3.93 / 3.85 in A dark, 4.46 / 4.39 in C dark.
Fix: On alert-tinted rows set the secondary line in `ink-2` (9.1 and 10.6), or lift `a-dark-ink-3` to `#8790A0`; C dark also needs `ink-2` on tinted rows.

**[Accessibility]** — A light idle and done hues fail as text on `a-light-surface-vn-bottom` (§ DESIGN Side-slot item)
`status-idle` `#0E7F57` 4.35 and `status-done` `#1D6FC0` 4.46 in the light `menu_bar` virtual notch; the side-slot `OK` label uses the idle hue.
Fix: Keep left-wing level labels in `ink-1` and color only the glyph, or darken for vn: idle `#0B7651` (4.89), done `#1A68B5` (4.94).

**[Accessibility]** — Drop zone and chip boundaries below 3:1; Increase contrast fallback is generic (§ DESIGN Drop display, Drop zone, Action button; EXPERIENCE Accessibility Floor)
Ask AI dashed: A dark 2.30, A light 1.66, C light 1.88. C struct inner border 1.64 / 1.33. A Stash/AirDrop hairlines 1.24 / 1.17. Chip borders 1.67 / 2.13 / 1.52. A drop target's extent matters during a drag. "Hairlines move to `ink-3`" does not cover dashed, chip or struct borders, pips or the Time track.
Fix: Add an explicit Increase contrast table: zone, chip and card borders become solid 1px `ink-3`; Ask AI border 100% lilac / gold, still dashed; tracks `ink-3` at ≥ 40%; upcoming pips a 1px `ink-3` ring; focus halo dropped and ring 2px.

**[Accessibility]** — Time readout ring-only variant relies on color alone (§ DESIGN Time readout; EXPERIENCE Accessibility Floor)
Away · paused is shown only by the arc turning `ink-3`. Break due (full dashed ring) is hard to tell from a break just started.
Fix: In ring-only mode add a center mark (pause glyph for Away, small triangle or dot for Break due), or force the label while the state is not running.

**[Accessibility]** — Time tab keyboard model and VoiceOver labels undefined (§ EXPERIENCE Time tab, Interaction Primitives; DESIGN Time tab, Phase indicator)
Only `↵` = Start is specified. Focus order, how `PAUSE`/`RESET`/`REMOVE` are triggered on a selected row, keyboard entry for `+ DATE`, and VoiceOver text for rings and pips are undefined. `RESET` and `REMOVE` are destructive, 5px apart, with no undo.
Fix: Define focus order (quick start → minutes → `START` → running list → row chips); row keys Space = Pause/Resume, `⌘⌫` = Remove with undo, `⌘R` = Reset; row label such as "Tea, 5 minute timer, 3 minutes 12 seconds left, ends 14:52, paused"; ring hidden as decoration.

**[Accessibility]** — `COPIED` / `NO TEXT FOUND` readout is 2 s with no lasting or VoiceOver equivalent (§ DESIGN Copied readout; EXPERIENCE Copied readout, State Patterns)
Set at 7.5–8px, no peek, no sound; `NO TEXT FOUND` is the only failure signal.
Fix: Post an `NSAccessibility` announcement, hold the readout while the pointer is over the notch, keep a trace like `LAST · 3 LINES · 14:48` in the `SEND TO` card, and make the duration configurable.

**[Accessibility]** — Peeks not announced to VoiceOver; Timer-end peek leaves no record (§ EXPERIENCE Peek alert panel, Accessibility Floor, Time)
Panels correctly never take focus, so VoiceOver users get nothing without an announcement. A Timer end leaves nothing after the 5 s dwell.
Fix: Announce every peek (kicker + title + primary shortcut). On the Time tab, keep the ended timer as `ENDED 14:48` with `DISMISS` until acknowledged.

**[Accessibility]** — Reduce motion has no static fallback for functional drains or new loops (§ EXPERIENCE Accessibility Floor; DESIGN Presence levels)
"Removes animations" would also remove the peek dwell line, the 2 s `COPIED` drain and the notes clipboard drain, which carry time information. The calm table omits the Time peek rim, Ask AI breathing `+`, card iris filament and drop display rim.
Fix: Under Reduce motion, show drains as a static full line that disappears at the end, or stepped segments. List the new loops explicitly as static in Calm and Reduce motion.

**[Accessibility]** — Release line is set at 7.5px meta size (§ DESIGN Drop display)
`RELEASE TO ASK` / `RELEASE TO SHARE` is the only confirmation of the drop target; it passes contrast but is smaller than the open 7.5–8px legibility question.
Fix: On hover set the release line at label size (9px A / `c-card-title` C), replacing the meta line.

**[Consistency]** — What happens when Shelf is disabled is contradictory (§ ARCHITECTURE-SPINE.md:186; epics.md:4347, 2824; SPEC.md:188, 204–205, 416)
AD-19, A72 and Story 9.6 say only Stash disappears, but SPEC lists AirDrop and Image to Text as Shelf zones, Story 9.8 gates AirDrop on Shelf, and SPEC says Shelf hosts all drop zones while AD-19 makes the host own the drop display.
Fix: Rule that Shelf off ⇒ Stash, AirDrop and Image to Text disappear and Ask AI remains. Update AD-19, A72, SPEC §4.6 and §7.3.

**[Consistency]** — A74 keys missing from SPEC §11 (§ SPEC.md:669–797; epics.md:1256, 2987, 1856, 1860, 1436)
`[general] tab_order`, `[home] cards`, `stale_after`, `ignored_paths`, `[notify]` `min_severity` and `cooldown`.
Fix: Add them to §11 with defaults, or point A74 at where they are defined.

**[Consistency]** — Privacy auto-detection default contradicts A88 (§ SPEC.md:699; epics.md:4366; Story 21.3)
SPEC sets `auto = true` unconditionally; A88 says off where detection needs Screen Recording.
Fix: Annotate the SPEC key and add the default to Story 21.3.

**[Consistency]** — Time sound defaults and coverage disagree (§ SPEC.md:691–692; epics.md:4022, 152; prd.md:256)
`timer_end` is on in SPEC but off in Story 20.2; no story covers `break_reminder`; FR98 says four events and PRD §4.8 lists five.
Fix: Pick one timer-end default, add the break-reminder sound to Story 20.6, update FR98 and PRD §4.8 to six events.

**[Consistency]** — SPEC §5.2 states the two-action peek rule with no exception (§ SPEC.md:237; DESIGN.md:771)
The break peek has three actions and Skip on `⌥⌘⌫` changes state.
Fix: Add the scoped exception to §5.2.

**[Consistency]** — Closed-source drift in the UX spines (§ EXPERIENCE.md:24; DESIGN.md:3)
Both still say open-source / donationware.
Fix: Change both to "closed source for now, business model undecided (SPEC §2.1)".

**[Consistency]** — Stale look still described as a badge (§ SPEC.md:343; epics.md:90 (FR36))
A "'?' badge" could be implemented as an overlay; the 1.7b ruling replaces the glyph with a dashed ring and `?`.
Fix: Update SPEC §7.1 Liveness and FR36 to the 1.7b look.

**[Consistency]** — PRD does not reflect v0.1 rulings A15/A79 and A60/A61 (§ prd.md:398, 265, 378; SPEC.md:870)
Reduce motion v0.1 floor, the v0.1 launch-at-login toggle and first-launch display prompt, and the activity log are missing.
Fix: Add them to FR-63, FR-58/59 and the SPEC §13 v0.1 row.

**[Consistency]** — Epics AD summaries are stale (§ epics.md:212–226)
AD-9, AD-13, AD-20, AD-22 and AD-23 lack amendments; AD-24..26 are missing.
Fix: Regenerate the AD summary block from the current spine.

**[Consistency]** — SPEC §4.5 `ModuleContext` lists 8 services; AD-19 says exactly 16 (§ SPEC.md:173–184; ARCHITECTURE-SPINE.md:185)
Missing `secrets`, `permissions`, `power`, `clipboard`, `executables`, `privacy`, `away`, `activity`.
Fix: Sync the sketch or mark it "see AD-19 (authoritative)".

**[Consistency]** — Pomodoro Resume wording is ambiguous (§ SPEC.md:445; EXPERIENCE.md:165)
"Resume restarts it at once" can be read as resetting the work phase; the ruling and Story 20.3 say "resumes".
Fix: Use "resumes" everywhere.

### Low (37)

**[Flow coverage]** — Flow 1 says "within pace"; UJ-1 says "ahead of pace" (§ EXPERIENCE:216; PRD:62)
The PRD says UJ-1..5 mirror Flows 1–5, so the wording should match.
Fix: Align one of them.

**[Token completeness + Accessibility]** — Non-text contrast rule (≥ 3:1) is not written down (§ DESIGN Colors → Contrast)
DESIGN states only the 4.5:1 text rule. Contrast for the selection ring at 55%, the settings gear in `ink-3` and the stale dashed ring is not stated, and the contrast table does not cover cards, vn surfaces, alert-row tints or alpha borders.
Fix: Add the 3:1 non-text rule and extend the contrast table with those rows (the accessibility review's table supplies the measured values).

**[Token completeness]** — Defined tokens never referenced; prose hardcodes values (§ DESIGN:767)
`spacing.expanded-bar-padding-x`, `grid-padding-x`, `peek-timer-bottom`, `tab-padding-x`, `motion.c-usage-bezel`, `components.time-ring` are unused, while the dwell-timer prose hardcodes "inset 26px, 12px up".
Fix: Reference the tokens from the prose, or drop them.

**[Component coverage]** — Component names drift between the spines (§ EXPERIENCE:84)
EXPERIENCE claims "same names", but: Notes panel / Floating notes panel, Empty state / Empty state block, Drop zone / Drop zone (in panels), Upcoming list + Event track / one combined heading.
Fix: Make them verbatim.

**[Component coverage]** — Phase label differs: `SHORT BREAK · 2/4` vs `BREAK · 2/4` (§ DESIGN:900; EXPERIENCE:375)
The two spines give different strings for the same label.
Fix: Pick one string.

**[State coverage]** — Shelf `REF` item with a moved or deleted original has no state (§ EXPERIENCE Shelf)
A reference item can outlive its file.
Fix: Add one row.

**[State coverage]** — FR-13 (activity log) and FR-60 (other notch apps warning) have no surface (§ FR-13, FR-60)
Neither has a named place in the spines.
Fix: Name where they appear, even if only a Settings pane.

**[Visual reference coverage]** — Imports cited as code paths, not links (§ DESIGN:446, 639, 958; EXPERIENCE:362, 418–424)
Mockups are links; imports are plain paths.
Fix: Make them links for consistency.

**[Visual reference coverage]** — "Not mocked" coverage is scattered as [ASSUMPTION] tags (§ EXPERIENCE:52; DESIGN passim)
C drop display, C script widgets, C Time, light drop display, closed-notch quota warning and the break-reminder kicker are not mocked; DESIGN tags them individually.
Fix: Keep one "not mocked" list in DESIGN Brand & Style next to the mockup list.

**[Bloat & overspecification]** — About 40 "decided 2026-11-0x (Story 1.7x)" stamps (§ DESIGN, EXPERIENCE passim)
Decision stamps clutter the contract.
Fix: Move them to the memlog; the spine states the rule.

**[Bloat & overspecification]** — Hex values repeated in four body tables (§ DESIGN Shared roles, Status, Status vocabulary, Pace)
Repeating frontmatter hex values invites drift.
Fix: The status vocabulary table should cite roles only.

**[Bloat & overspecification]** — SPEC.md impacts lists rows already applied in SPEC v0.7 (§ EXPERIENCE:498, 501)
The table should list only pending SPEC changes.
Fix: Drop the applied rows.

**[Bloat & overspecification]** — Some frontmatter component values are prose strings (§ DESIGN frontmatter)
`status-glyph.stale`, `drop-display.grid`, `pace-marker.ring` are notes rather than tokens.
Fix: Acceptable as notes; consider a `note:` key per the spec's convention.

**[Shape fit]** — EXPERIENCE section order (§ EXPERIENCE:209 vs 402, 415)
Key Flows sits after Accessibility Floor; Responsive & Platform and Inspiration & Anti-patterns follow about 200 lines later. The examples put Responsive and Inspiration before Key Flows.
Fix: Reorder.

**[Shape fit]** — C deltas only in the Twin Metal Tactical roll-up (§ DESIGN Components)
Invented sections (Presence Levels, Sounds, Theming, Sync & Encryption, Settings & Onboarding, SPEC.md impacts) earn their place. The Twin Metal Tactical roll-up is acceptable, but the C deltas would be easier to extract if they also appeared in each component's own entry.
Fix: Repeat each C delta in its component's entry.

**[Accessibility]** — Upcoming phase pips measure 1.33–1.47 (§ DESIGN Phase indicator)
Done and upcoming differ only in lightness; the `WORK · 2/4` label carries the count, so no information is lost.
Fix: Draw upcoming pips as a 1px `ink-3` ring.

**[Accessibility]** — Small, tightly spaced hit targets on chips (§ mockup 1.7d/e; Time row, Script page)
Chips are about 20px tall with 5px gaps (`PAUSE`/`RESET`/`REMOVE`, `REVEAL`/`OPEN SOURCE`).
Fix: Hit area ≥ 24px tall and 8px gaps. Add undo to Remove.

**[Accessibility]** — C process-only vs idle differ only by a thin outer circle (§ DESIGN Status glyph, Stale and process-only)
At 16px without color, and the right wing has no label.
Fix: Make the C process-only dot clearly smaller (e.g. 4px) or a hollow dashed dot; ship the VoiceOver labels with v1.

**[Accessibility]** — Script page and widget keyboard / VoiceOver reach unspecified (§ DESIGN Script page; EXPERIENCE Script Modules)
How `REVEAL` / `OPEN SOURCE` and "click a card opens its tab" are reached by keyboard is unstated.
Fix: Tab order hero → About → Runs → chips; hero label such as "vigie.app, OK, up, 200, 142 ms, checked 2 minutes ago".

**[Accessibility]** — `a-dark-ink-3` on card is 4.56, a thin margin (§ DESIGN Colors)
Any extra overlay (hover brighten, alert tint) drops it below 4.5.
Fix: Lift to `#8790A0` (5.42 on card, 5.98 on panel) or document the margin.

**[Accessibility]** — Status-vocabulary `OK` glyph equals the A idle session glyph (§ DESIGN Status vocabulary)
Kept apart by wing and label; VoiceOver needs the same separation.
Fix: Side-slot labels lead with the module ("vigie.app, OK"), session labels with the project. Keep it when building.

**[Accessibility]** — A drop zone that rejects the item gives no reason (§ DESIGN Drop display)
It simply stays unlit.
Fix: Show a dimmed meta such as `IMAGES AND PDF ONLY` while an unaccepted file is dragged over.

**[Accessibility]** — `←→` in the tab row is ambiguous; tab alert marker unlabeled (§ EXPERIENCE Settings gear)
"Tab / `←→` reach the settings gear" could mean `←→` switches tabs.
Fix: `←→` moves focus without activating; `↵` / Space activates. Tab label reads "Agents, needs attention".

**[Consistency]** — PRD and addendum cite stale architecture range (§ prd.md:15; addendum.md:9)
"AD-1 to AD-23" (now AD-26); addendum says the spine is not amended (it is).
Fix: Update both.

**[Consistency]** — PRD §9 Q4/Q5 list decided items as open (§ prd.md:485–486)
Epics reconciliation, A1–A78 rulings, slot overflow, DND replay vs drop.
Fix: Mark them resolved.

**[Consistency]** — Architecture Deferred table lists "DND replay vs drop" (§ ARCHITECTURE-SPINE.md:374)
Decided: `[notify] after_focus`.
Fix: Strike it.

**[Consistency]** — EXPERIENCE contains stale assumptions (§ EXPERIENCE.md:149, 353, 494)
80% default and 7-day default tags are resolved; "Sounds: four events" is now six.
Fix: Drop the resolved tags and update the count.

**[Consistency]** — `brew install --cask vigie` ignores the tap ruling (§ prd.md:392; EXPERIENCE.md:241; epics.md:3897)
The ruling is a `homebrew-vigie` tap first (SPEC.md:846, A50).
Fix: State the tap step, or note the short form applies after an official cask exists.

**[Consistency]** — PRD beta has no timing (§ prd.md:386–389)
A63 says beta exists only from the public release.
Fix: Add "from the public release".

**[Consistency]** — "Copy text" survives as Image to Text microcopy (§ DESIGN.md:745, 748; EXPERIENCE.md:105; epics.md:2673, 2899)
Meta `COPY TEXT` and `RELEASE TO COPY TEXT` [ASSUMPTION]; the release line is missing from EXPERIENCE and Story 9.1 lists.
Fix: Confirm the wording and list the Image to Text release line in EXPERIENCE and Story 9.9.

**[Consistency]** — Status vocabulary `error` → `DOWN` mapping is implicit (§ SPEC §9.3; epics.md:120)
Script output uses `ok | warn | error`; the UI uses OK / WARN / DOWN.
Fix: State it in SPEC §9.3 and Story 12.5.

**[Consistency]** — Script `priority` defined in two places with no precedence (§ SPEC §9.1; SPEC.md:793–796)
Front matter and config both set it.
Fix: Write down which wins.

**[Consistency]** — UX-DR41 describes the old left wing (§ epics.md:283)
Says "Shelf Stash `1fr` + Ask AI 212"; it is now the priority lane and the `SEND TO` card.
Fix: Amend it.

**[Consistency]** — PRD glossary Alert and Status omit break reminder and stale / process-only (§ prd.md §3)
Completeness gap.
Fix: Add them.

**[Consistency]** — A89 Time key names differ from SPEC (§ epics.md:4367; SPEC.md:775–779)
`work` / `break` vs `breaks.work` / `breaks.length`.
Fix: Align the names.

**[Consistency]** — epics.md frontmatter stale (§ epics.md:23–25)
`updated: '2026-11-06'` despite 11-07 edits; `referencedMockups` omits `key-design-pass-1-7.html`.
Fix: Bump the date and add the mockup.

**[Consistency]** — Story 2.10 / 2.8 cosmetic drift (§ epics.md:1237; Story 2.8)
2.10 lacks "(done 2026-11-07)" on its 1.7a dependency; 2.8 still uses per-side wording.
Fix: Cosmetic alignment.

## Reviewer files

- Rubric: `/Users/me/Documents/Ideas/notch/ux-designs/ux-vigie-2026-11-04/review-rubric.md`
- Accessibility: `/Users/me/Documents/Ideas/notch/ux-designs/ux-vigie-2026-11-04/review-accessibility.md`
- Consistency: `/Users/me/Documents/Ideas/notch/ux-designs/ux-vigie-2026-11-04/review-consistency.md`
