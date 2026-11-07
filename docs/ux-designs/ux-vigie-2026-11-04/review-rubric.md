# Spine Pair Review — Vigie

Reviewed 2026-11-07: `DESIGN.md` (963 lines) + `EXPERIENCE.md` (502 lines), against PRD `prds/prd-vigie-2026-11-06/prd.md` (UJ-1..UJ-8, FR-1..FR-64) and `SPEC.md`. Review only; no spine was edited.

## Overall verdict

**Adequate. Needs a targeted revision before it is a clean contract.** The visual system is strong: every color token has a hex value in all four looks, the frontmatter resolves almost completely, every mockup and import is linked where it is used, and the Story 1.7 surfaces (settings gear, stale and process-only glyphs, drop display, `SEND TO` card, `COPIED` readout, status vocabulary, script widgets and page, Time, Twin Metal Tactical tabs and notes) are specified in enough detail to build. The gaps are on the experience side:

- 3 of 8 user journeys have no Key Flow (UJ-6, UJ-7, UJ-8). UJ-8 is the Time surface designed in this pass.
- Several PRD features with UX impact are missing from both spines: Privacy mode, multiple Accounts, install-from-link Confirmation, and the closed-notch Calendar glance.
- The PRD is not listed as a source.
- Peek concurrency and the quota-warning peek are not designed.
- Flow 2 contradicts a decision recorded elsewhere in the same file.

A consumer can extract the visuals cleanly. For the gaps above, a consumer would have to invent the behavior.

## 1. Flow coverage — thin

Extracted UJs: UJ-1 → Flow 1, UJ-2 → Flow 2, UJ-3 → Flow 3, UJ-4 → Flow 4, UJ-5 → Flow 5. Each has a named protagonist, numbered steps, a **Climax** beat and a failure path. UJ-6, UJ-7 and UJ-8 have no flow.

### Findings
- **[high]** UJ-8 ("Romain takes his break") has no Key Flow, although Time is a Story 1.7 surface (EXPERIENCE Key Flows; PRD §2.4 line 69). The UJ also conflicts with FR-49 inside the PRD: it describes a break reminder firing while a Pomodoro runs, but FR-49 says reminders are paused while a Pomodoro runs. The Pomodoro break also waits for Start break, so "restarts without a click" is not true for it. *Fix:* write Flow 6 around a plain break reminder: strength Peek, Away for 5 min counts as the break, the cycle restarts. Give the failure path (snooze, or user does not leave). Ask the PM to correct UJ-8.
- **[high]** UJ-7 (install a community script from a link, then update it) has no flow and no surface. Nothing describes the Confirmation screen: the "Verified: Vigie Script repository" state, the stronger warning for unsigned or other scripts, the author shown as "claimed by the file", the full-file view, or the update diff with re-Confirmation (FR-42, FR-43). EXPERIENCE Script Modules and the IA table cover only the sync case. *Fix:* add a Confirmation surface to the IA, add its states (verified / unsigned / invalid signature / update diff / declined), and add Flow 7.
- **[high]** Flow 2's failure path says "each becomes failed; alerts play once each [ASSUMPTION: no grouped summary alert in v1]" (EXPERIENCE:235). This contradicts the decision recorded in State Patterns "Interrupted by sleep" (EXPERIENCE:153) and Open Question 6 (EXPERIENCE:437): one summary alert, `<n> sessions interrupted by sleep` with `OPEN AGENTS`. *Fix:* rewrite the failure path to use the summary alert.
- **[medium]** UJ-6 (`vigie run -- make deploy`) has no flow. How a non-agent session appears is not committed: the agent column value, the failed kicker and reason for a non-zero exit (for example `FAILED · EXIT 2`), and done vs failed by exit code (FR-23). *Fix:* add a short Flow 8 and one row in the session-states table.
- **[low]** Flow 1 step 2 says "within pace", but UJ-1 says "ahead of pace", and the PRD says UJ-1..5 mirror Flows 1–5 (EXPERIENCE:216; PRD:62). *Fix:* align one of them.

## 2. Token completeness — adequate

Extracted: 80 color tokens (3 `base`, plus full role sets for `a-dark`, `a-light`, `c-dark`, `c-light`), 27 typography, 14 rounded, 23 spacing, 12 motion (documented extension), 25 components. Every color token has a hex value. Every role is defined in all four looks; `surface-vn-*` exists only for light, by design. DESIGN prose uses 94 distinct `{…}` refs; 90 resolve. EXPERIENCE uses 7, and all 7 resolve. A contrast table covers ink-1/2/3, the lowest status hue, pace-ahead and quota-warning against `surface-panel` for every look.

### Findings
- **[medium]** Some references are templates or globs that a resolver cannot expand:
  - `{colors.<look>-status-idle}`, `{colors.<look>-quota-warning}` and `{colors.<look>-status-failed}` in the `components.status-vocabulary` frontmatter (DESIGN:339–341)
  - `components.*-panel.shadow-*` (DESIGN:655)
  - `typography.*-readout-value` (DESIGN:707)

  *Fix:* either state one resolver rule ("`<look>` is substituted with the active look") in the token-scheme section, or expand the refs per look, the way `widget-card` does.
- **[medium]** No contrast is stated for the accent colors used as text:
  - `a-light-iris-1/2/3`: Time values, countdown `IN 42 MIN`, `ASK AI` label, revealed secret
  - `c-dark-gold-text`
  - status labels on alert-tinted rows and on `surface-card`
  - `c-light-gold-text`: 5.5:1 appears only in prose

  (DESIGN Contrast, 552–563.) *Fix:* add an "accent text" row per look, and a row for status labels on `surface-card` and on the tinted rows.
- **[medium]** Only `motion.enter` (280ms) is defined. There is no token for collapse or exit, or for the peek, drop-display and expanded grow and retract durations; collapse is Open Question 17 (EXPERIENCE:450). Story-dev will invent these values. *Fix:* commit provisional values: `exit`, `peek-grow`, `drop-display-grow`.
- **[medium]** There are no tokens for the dark-mode `menu_bar` virtual notch (`a-dark-surface-vn-*`, `c-dark-surface-vn-*`; Open Question 15). Yet Responsive & Platform says `style = menu_bar` takes the menu-bar material (EXPERIENCE:408). *Fix:* add the dark pair, or state that dark `menu_bar` falls back to `base-island`.
- **[low]** Contrast for non-text elements is not stated: selection ring at 55%, settings gear in `ink-3`, stale dashed ring in `ink-3` (3:1 target). *Fix:* one line in Contrast.
- **[low]** Several tokens are defined but never referenced: `spacing.expanded-bar-padding-x`, `grid-padding-x`, `peek-timer-bottom`, `tab-padding-x`, `motion.c-usage-bezel`, `components.time-ring`. Meanwhile the dwell-timer prose hardcodes "inset 26px, 12px up" (DESIGN:767). *Fix:* reference the tokens from the prose, or drop them.
- **[low]** `components.time-ring` gives only dark accents (DESIGN:376–377). The light Time accent values (`#126F8C` text, `filament-1` rims, `c-light-gold`) exist only in the Colors prose (DESIGN:499). *Fix:* add `a-accent-light` and `c-accent-light`.

## 3. Component coverage — adequate

Each of EXPERIENCE's 33 Component Patterns rows has a visual counterpart in DESIGN: either its own heading or a named sub-part (Pace marker, Quota warning and Dwell timer sit inside Quota dial, Usage and Peek). The Story 1.7 components all have both a visual spec and a behavioral row: settings gear, status vocabulary, drop display, drop zone / `SEND TO`, copied readout, script widget, Time readout, Time tab.

### Findings
- **[high]** Two peeks have neither a visual spec nor actions:
  - The **quota-warning peek**. The IA lists it as a peek trigger (EXPERIENCE:34), but DESIGN's Peek variants (blocked / done / failed / Time) do not include it (DESIGN:768–771). Kicker, title, beacon (triangle?), hue and the two actions (for example `OPEN USAGE` / `DISMISS`) are all uncommitted.
  - The **sleep summary peek** (`<n> sessions interrupted by sleep`, `OPEN AGENTS`; EXPERIENCE:153) has no visual spec.

  *Fix:* add both to DESIGN Peek variants and to EXPERIENCE Peek shortcuts.
- **[medium]** Several DESIGN components have no Component Patterns row, so their behavior is scattered across module sections: Script page (DESIGN:884; behavior only in EXPERIENCE:335), Side-slot item, Phase indicator, Readout, `SEND TO` card (folded into Drop zone), Scroll and reorder affordances, Notes tab. *Fix:* add rows. Script page especially needs tab naming, keyboard, and the `REVEAL` / `OPEN SOURCE` targets.
- **[medium]** The status vocabulary's visual spec (shape, sizes, stroke, static) sits under DESIGN **Colors** (517–532). It is not in Components, although it is a component (`components.status-vocabulary`). *Fix:* move it to Components and leave a pointer in Colors.
- **[medium]** Home is a configurable grid, but widget types beyond the baseline have no anatomy or sizing rules: sessions, quota, shelf, calendar card, GitHub PR count, script widget. "Cards can span two columns" is not tied to a user action (DESIGN:623; EXPERIENCE:102). *Fix:* list the widget catalog with each widget's span, and state how the user adds and reorders widgets.
- **[low]** EXPERIENCE claims "same names" (EXPERIENCE:84), but some names drift: Notes panel / Floating notes panel, Empty state / Empty state block, Drop zone / Drop zone (in panels), Upcoming list + Event track / one combined heading. *Fix:* make them verbatim.
- **[low]** The phase label is `SHORT BREAK · 2/4` in DESIGN (DESIGN:900) but `BREAK · 2/4` in EXPERIENCE (EXPERIENCE:375). *Fix:* pick one string.

## 4. State coverage — thin

Surfaces walked: closed left and right wings, drop display, peek, the expanded tabs (Home, Agents, Usage, Shelf, Calendar, Time, Notes, script pages), floating notes panel, setup alert, Settings and onboarding. Well covered:
- session states, plus stale and process-only
- the no-agent and no-session empty states
- quota warning, pace and absent windows
- shelf expiry
- missing calendar permission
- Time away and break due
- Do Not Disturb, full-screen apps, sleep
- drop display hover, cancel and unaccepted item
- the `COPIED` / `NO TEXT FOUND` readout
- keyboard focus (selection ring, gear)

### Findings
- **[high]** **Privacy mode** (PRD FR-55, glossary, v0.2) is absent from both spines. Nothing defines the redacted rendering per surface (session titles, project names, Shelf items, Timer labels, widget text, calendar titles, notes), whether an indicator shows, the manual toggle, or the "detection unavailable" message in Settings. *Fix:* add a Privacy mode state row covering every surface, a redaction rule ("glyphs, rings, numbers only"), and the Settings entry.
- **[high]** **Multiple Accounts** (FR-29, v0.2) has no UX. The closed ring should show "the Account of the most recent Session", and the Usage tab should show each account. Provider card anatomy has no account label, and switching is undefined. *Fix:* add an account line to the Usage provider card and to the left-wing ring label, plus a state row.
- **[high]** **Peek concurrency** is undefined. Nothing says what happens when an alert arrives while a peek is visible, while the expanded view is open, or while the drop display is showing (Peek row EXPERIENCE:95; SPEC §5.2's rate limit is superseded with no replacement). *Fix:* commit a rule, for example queue by urgency, the newer blocked/failed alert replaces done, a peek is suppressed while expanded is open and the tab marker is shown instead.
- **[medium]** There are more blocked or failed sessions than slots is deferred (Open Question 5; EXPERIENCE:136), yet the Overflow rule promises that `+X` never hides a blocked session (EXPERIENCE:94). That promise cannot hold with four blocked sessions and three slots. *Fix:* commit the rule now, for example "`+X` takes the blocked hue when it hides an alert".
- **[medium]** Usage: the stale indicator when remote limits fail (FR-30), the first-launch loading state before any data arrives, and an empty `HISTORY · 7D` or unavailable `COST · TODAY` on day one are all missing. *Fix:* add state rows.
- **[medium]** Time:
  - no empty state for the Running card
  - "an end that passed while asleep raises its Alert once on wake" (FR-45) is missing
  - "break reminders are paused while a Pomodoro runs" and "Away time does not count as work" (FR-49) are not stated
  - the alert behavior at the end of a Pomodoro break (FR-48: every phase end raises an Alert) is unspecified

  *Fix:* add these to Time and State Patterns.
- **[medium]** Script states exist only for the widget (EXPERIENCE:161–162). Nothing covers the side slot and the script page when a script is awaiting confirmation, errored, has never run, timed out, or has an update awaiting re-Confirmation (FR-43). *Fix:* extend the state rows to all three surfaces.
- **[medium]** Notes: no empty list, no "search finds nothing" state, no first-launch state for the floating panel, and no decrypt or sync failure (E2E keys on a new Mac; iCloud conflict). *Fix:* add state rows.
- **[medium]** Drop display: no in-progress state for Image to Text between the drop and `COPIED` (OCR of a multi-page PDF). No failure state for AirDrop or Stash (unreadable file, disk full). No rule for when the Shelf module is off or every zone is disabled. *Fix:* add a `READING…` readout state and an error readout, and state that with no enabled zone no display appears.
- **[medium]** The Home empty state (no widgets) and the Agents tab empty visual are open (Open Question 14). Copy exists only as [ASSUMPTION] (EXPERIENCE:146–147). *Fix:* commit the copy; the visual can use Empty state block.
- **[low]** Shelf: a `REF` item whose original file was moved or deleted has no state. *Fix:* one row.
- **[low]** FR-13 (viewing the local activity log) and FR-60 (warning about other notch apps) have no surface. *Fix:* name where they appear, even if that is only a Settings pane.

## 5. Visual reference coverage — strong

Files found:
- `mockups/` (10): compare-a-vs-c-v3, key-agents-tab, key-alert-variants, key-calendar-tab, key-closed-notch-states, key-design-pass-1-7, key-notes, key-shelf-tab, key-usage-tab, theme-family-4-looks. All 10 are linked inline from the sections they illustrate.
- `imports/` (5): all 5 are cited in context.
- `wireframes/`: none.

There are no orphans. The `key-design-pass-1-7` links name their part (1.7a–f), the chosen option is in the sheet's banner, and the superseded state e and the stale number-widget hue are called out. The "spines win" rule is stated in both files (DESIGN:457, EXPERIENCE:13), consistently.

### Findings
- **[low]** Imports are cited as code paths, not links (DESIGN:446, 639, 958; EXPERIENCE:362, 418–424). *Fix:* make them links for consistency.
- **[low]** Coverage that is not mocked is listed in EXPERIENCE:52 but scattered as [ASSUMPTION] tags in DESIGN: the C drop display, C script widgets, C Time, the light drop display, the closed-notch quota warning, and the break-reminder kicker. *Fix:* keep one "not mocked" list in DESIGN Brand & Style next to the mockup list.

## 6. Bloat & overspecification — adequate

### Findings
- **[medium]** EXPERIENCE's module sections (Usage Tab, Shelf, Calendar, Time, Notes, Script Modules) restate Component Patterns and State Patterns rows, and have already drifted. For example, "at most 5 events" (EXPERIENCE:110) vs "at most about 5" (EXPERIENCE:365), and the `BREAK` label (§3). *Fix:* keep one home per rule. Module sections should hold only what has no row (format, sync, settings).
- **[medium]** Open Questions carries 14 struck-through decided items and a "Design before build … Done" history paragraph (EXPERIENCE:437–463), all of which the body already contains. *Fix:* delete the resolved items, keep only the open ones, and leave the history in `.memlog.md`.
- **[low]** About 40 "decided 2026-11-0x (Story 1.7x)" stamps are spread through both spines. *Fix:* move them to the memlog; the spine states the rule.
- **[low]** DESIGN repeats the hex values in four body tables (Shared roles, Status, Status vocabulary, Pace) on top of the frontmatter, which invites drift. *Fix:* the status vocabulary table should cite roles only.
- **[low]** SPEC.md impacts includes rows already applied in SPEC v0.7 (EXPERIENCE:498, 501). *Fix:* drop the applied rows so the table lists only pending SPEC changes.
- **[low]** Some frontmatter component values are prose strings, not tokens: `status-glyph.stale`, `drop-display.grid`, `pace-marker.ring`. *Fix:* acceptable as notes; consider a `note:` key per the spec's convention.

## 7. Inheritance discipline — thin

Sources: `../../SPEC.md` resolves. EXPERIENCE's token refs all resolve to DESIGN (7/7). Component names are mostly identical (§3).

### Findings
- **[high]** The PRD (`prds/prd-vigie-2026-11-06/prd.md`) is not in either spine's `sources`. Yet EXPERIENCE cites "PRD FR-49" (EXPERIENCE:380), and the PRD declares that UJ-1..5 mirror the Key Flows. That is why the FR gaps in §1 and §4 were not caught. *Fix:* add the PRD to both `sources` and check the spines against FR-1..FR-64.
- **[medium]** Glossary drift from the PRD:
  - "Presence levels" vs PRD **Presence mode** / "Calm mode"
  - "Idle-sleep prevention" vs **Keep-awake**
  - Countdown "to a date" vs PRD "to a clock time"
  - "Do Not Disturb / Focus mode" (EXPERIENCE:168), while the PRD requires "macOS Focus mode" to be written in full to keep it apart from the Focus action

  *Fix:* adopt the PRD terms verbatim.
- **[medium]** FR-50 calls for a closed-notch Calendar glance ("next-event state by lead time in the closed notch"). The spines' left-wing lane lists only rings, scripts and Time, and SPEC.md impacts does not record the conflict. *Fix:* either add Calendar as a left-lane item or record the removal in SPEC impacts and raise it with the PM.

## 8. Shape fit — adequate

DESIGN: body sections follow the canonical order (Brand & Style → Colors → Typography → Layout & Spacing → Elevation & Depth → Shapes → Components → Do's and Don'ts). The frontmatter extensions are documented (`motion`) or harmless (`status`, `updated`, `sources`). EXPERIENCE: all required sections are present.

### Findings
- **[low]** EXPERIENCE order: Key Flows sits after Accessibility Floor, and Responsive & Platform and Inspiration & Anti-patterns follow about 200 lines later (EXPERIENCE:209 vs 402, 415). The examples put Responsive and Inspiration before Key Flows. *Fix:* reorder.
- **[low]** Invented sections that earn their place: Presence Levels, Sounds, Theming & Customization, Sync & Encryption, Settings & Onboarding, SPEC.md impacts. The module sections overlap the canonical ones (see §6). The DESIGN "Twin Metal Tactical expanded tabs and notes panel" roll-up is a skin summary inside Components. It is acceptable, but the C deltas would be easier to extract if they also appeared in each component's own entry.

## Mechanical notes

- **Finding counts:** critical 0 · high 8 · medium 19 · low 16 (43 total).
- **Token resolution:** DESIGN has 94 distinct `{…}` refs. 4 are unresolved templates (`colors.<look>-*`). 2 glob-style component and typography refs fall outside that count. EXPERIENCE: 7/7 resolve.
- **Frontmatter counts:** colors 80 · typography 27 · rounded 14 · spacing 23 · motion 12 · components 25.
- **Color tokens referenced only by role in tables, never as `{colors.x}`:** most `*-status-*`, `*-ink-2/3` and light accents. This is acceptable under the role scheme in DESIGN:466–474.
- **UJ → flow:** UJ-1..5 → Flows 1..5. UJ-6, UJ-7 and UJ-8 are missing.
- **PRD FRs with no UX in the spines:** FR-13, FR-23 (partly), FR-29, FR-30, FR-42, FR-43, FR-45 (sleep end), FR-49 (Pomodoro pause), FR-50 (closed glance), FR-55, FR-60.
- **Story 1.7 surfaces:**
  - **Strong:** gear (1.7a), stale and process-only (1.7b), C tabs and notes (1.7f).
  - **Adequate:** drop display, `SEND TO` and `COPIED` (1.7c): missing an in-progress state, the C and light looks, and a rule for when every zone is disabled. Status vocabulary and script widgets/page (1.7d): token templates, missing script-page states, C look not mocked.
  - **Thin on behavior:** Time (1.7e): no flow, no empty state, FR-45/49 rules missing, phase label drift.
- **Workspace files outside `mockups/` and `imports/`:** `reconcile-*.md` and `.working/` are not referenced by the spines. This is expected for working files; consumers should ignore them.
