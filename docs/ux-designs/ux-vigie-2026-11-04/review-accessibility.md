# Accessibility & contrast review — Vigie Story 1.7 design pass

Reviewed 2026-11-07 against `DESIGN.md` and `EXPERIENCE.md` (both `updated: 2026-11-07`). The mockups, mainly `mockups/key-design-pass-1-7.html`, were used only as evidence of intent; where they conflict, the spines win. Review only; no spine was edited.

Method: WCAG 2.x relative-luminance ratios, computed by script for every text and non-text color token on every surface the spines place it on, in all four looks. Alpha values were composited onto the stated surface. Scripts are in the session scratchpad: `contrast.py`, `qwarn.py`, `de.py`. Thresholds: text ≥ 4.5:1 (the DESIGN.md rule). Non-text UI (glyphs, rings, focus rings, zone borders) ≥ 3:1 (WCAG 1.4.11; DESIGN.md does not state this rule yet, see L9). WCAG ratios are not rounded, so 4.499 counts as a fail.

## Verdict

**Conditional pass.** Every look keeps the core palette (ink-1/2/3 and status hues on panel and card) at or above 4.5:1. Every session state, module level and quota state has a shape and a label, not just a color. Five high findings need fixing before the 1.7 stories are built:

- The C light quota-warning value fails, including on cards, so the "cards only" workaround does not hold.
- A light has no visible keyboard focus on the settings gear.
- The drop and Send to features cannot be reached by keyboard.
- Snooze on the break peek has no shortcut.
- The break peek is a waiting state with no lasting equivalent when it is missed.

There are no critical findings.

## Findings

### High

- **[high]** C light `quota-warning` `#8A6D00` fails 4.5:1 for text everywhere it is allowed (DESIGN.md Colors → Contrast; Pace and quota-warning table). It measures 4.03 on `c-light-surface-panel` and **4.499 on `c-light-surface-card`**, so the decided "warning text only on cards" rule still fails. It also measures 3.92 on `surface-vn-bottom`, where a side-slot `WARN` label can sit in `menu_bar` style. A light uses the same `#8A6D00`: 4.51 on panel (passes with almost no margin) and 4.27 on `a-light-surface-vn-bottom` (fails). *Fix:* split the role, as C already does with gold and gold-text:
  - Keep `#8A6D00` for hatch, triangle and arc fills (non-text, 4.03 or more, passes 3:1).
  - Add `{a,c}-light-quota-warning-text: #7E6300`, the same hue (47°) and saturation, slightly darker. It measures 4.69 on C panel, 5.23 on C card, 4.56 on C vn-bottom, 5.24 on A panel and 4.96 on A vn-bottom.
  - For a wider margin, use `#7A6000` (4.92 on C panel, 4.78 on C vn-bottom).
  - CIEDE2000 distance to working stays ≥ 11.6. Distance to `c-light-gold-text` drops from 8.7 to 5.0, which is acceptable because warning text always comes with a triangle and `WARN`.
  - With this split, warning text can also sit on the C light panel; drop the "cards only" rule. Update the contrast table (it reads "4.5 on surface-card").
- **[high]** The settings gear has no defined keyboard focus in A light (DESIGN.md Settings gear; Elevation & Depth). A focus is specified as "1px platinum ring at 55% plus 3px cyan halo (dark)". Platinum at 55% on `a-light-surface-panel` measures **1.05:1**, so it is invisible (WCAG 2.4.7 / 1.4.11). *Fix:* in A light, use `components.selection-ring.a-light` (1px graphite `#161B24`) with no halo. State it in `components.settings-gear` per look.
- **[high]** The drop display, the Send to zones and the Shelf have no keyboard or VoiceOver path (EXPERIENCE.md Drop display, Drop zone, Interaction Primitives; DESIGN.md Drop display). Stash, Ask AI, AirDrop and Image to Text can be reached only by dragging over the notch or dragging a stash item onto the `SEND TO` card. The keyboard map has no Shelf actions other than Space for Quick Look. Reveal and Pin appear only as hover chips. This breaks the floor rule "every expanded-view action is reachable when it has focus". *Fix:*
  1. On a selected Shelf row: `↵` opens a "Send to" menu (Ask AI, ⌥ Ask AI in the alternate folder, AirDrop, Image to Text), plus key equivalents for Reveal and Pin. Expose the same as VoiceOver custom actions (`accessibilityCustomActions`).
  2. Give a way in without dragging: a macOS Services / Share menu entry "Stash in Vigie" and `⌘V` on the Shelf tab to stash the clipboard file or text.
  3. Label each drop zone for VoiceOver, e.g. "Stash, keep 7 days, 5 items" and "Ask AI, Claude Code in ~/dev, Option for alternate folder".
- **[high]** Snooze on the break peek has no shortcut (EXPERIENCE.md Interaction Primitives "Peek shortcuts"; DESIGN.md Peek alert panel → Break). Peeks never take focus, so a keyboard-only user can Start or Skip a break but cannot snooze it. This breaks the floor rule "peek actions are reachable through the global shortcuts". *Fix:* assign a third global shortcut, registered only while the peek is visible, e.g. `⌥⌘Z` or `⌥⌘S`, shown on the button like the other two. Each of the three buttons' accessibility labels should include its shortcut.
- **[high]** The break peek has no lasting equivalent (EXPERIENCE.md Time; State Patterns "Time · break due"). A Pomodoro break waits for Start break, but the peek retracts after 5 s. The closed Time readout is `off` by default, the spines never say the readout shows `BREAK DUE` after a peek retracts, and with DND on, missed peeks are dropped by default. A user who misses the 5 s window ends up with a Pomodoro that is stalled with no visible sign. The Time tab row spec (`PAUSE`/`RESET`/`REMOVE`) has no `START BREAK`, even though State Patterns says Start break is available "in the Time tab". *Fix:*
  - After the break peek retracts, the left wing shows the `BREAK DUE` readout (full dashed ring, label), even when `closed_notch = "off"`, until the break starts or is skipped.
  - The Time tab row in break-due state shows `START BREAK` (primary), `SNOOZE 5M` and `SKIP` chips.
  - The Time tab gets the attention marker that the Agents tab uses.
  - Break-due counts as an "unresolved alert" for the post-DND replay setting.

### Medium

- **[medium]** `ink-3` text on tinted alert rows fails in the dark looks (DESIGN.md Session row; C tabs). The last-action line and separators in `ink-3` over the 10% blocked/failed fade on `surface-card` measure 3.93 / 3.85 in A dark and 4.46 / 4.39 in C dark, at the strongest end of the fade. *Fix:* on alert-tinted rows, set the secondary line in `ink-2` (9.1 and 10.6), or lift `a-dark-ink-3` to `#8790A0` (5.42 on card, 4.58 or more on tint). C dark would also need ink-2 on tinted rows.
- **[medium]** A light `status-idle` (`#0E7F57`) and `status-done` (`#1D6FC0`) fail as text on `a-light-surface-vn-bottom` in the light `menu_bar` virtual notch: 4.35 and 4.46. The side-slot `OK` label is set in the idle hue (DESIGN.md Side-slot item). *Fix:* either keep left-wing level labels in `ink-1` and color only the glyph, or darken them for vn: idle `#0B7651` (4.89 on vn-bottom) and done `#1A68B5` (4.94). Both also pass on panel and card.
- **[medium]** The A light Time ring arc color is unspecified, and the likely candidate fails (DESIGN.md Variant accents → Time accent). The spine gives A light "`#126F8C` text and `filament-1` `#3FA3C4` rims". If the ring arcs (closed readout, Time tab 30px ring, peek beacon ring) follow the rim, filament-1 measures **2.65** on panel and 2.90 on card. That is below 3:1 for a graphic that carries meaning (time left). *Fix:* state that A light Time arcs and the current-phase pip use `a-light-iris-1` `#126F8C` (5.23 / 5.71; 3.99 against the `line` track). Keep filament-1 for the decorative rim only.
- **[medium]** Drop zone and chip boundaries fall below 3:1, and the Increase contrast fallback is generic (DESIGN.md Drop display, Drop zone, Action button; EXPERIENCE.md Accessibility Floor `[ASSUMPTION]`). Measured:
  - Ask AI dashed border: A dark lilac 35% = 2.30, A light iris-2 35% = 1.66, C light gold 55% = 1.88. C dark gold 55% = 3.64 passes.
  - C struct inner border 22% = 1.64 dark / 1.33 light.
  - A Stash and AirDrop hairlines 9% / 7% = 1.24 / 1.17.
  - Chip borders: A platinum 18% = 1.67, C struct 30% = 2.13 dark / 1.52 light.

  The zone labels name them, so this is not a strict 1.4.11 failure. However, a drop target's extent matters during a drag, and low-vision users cannot see it. "Hairlines move to `ink-3`" does not cover dashed borders, chip borders, struct borders at 22%, the 14% pips or the 10% Time track. *Fix:* add an explicit Increase contrast table to DESIGN.md. All zone, chip and card borders become solid 1px `ink-3` (≥ 4.5), and the Ask AI border becomes 100% lilac / gold, still dashed. Tracks become `ink-3` at 40% or more. Upcoming pips become a 1px `ink-3` ring. The focus halo is dropped and the ring set to 2px.
- **[medium]** In the Time readout's ring-only variant, two states depend on color alone (DESIGN.md Time readout; EXPERIENCE.md Accessibility Floor "Time work vs break is solid vs dashed arc plus label"). In ring-only there is no label. Away · paused is shown only by the arc turning from cyan or gold to `ink-3`, which is color only. Break due (full dashed ring) is hard to tell apart from a break that has just started (almost-full dashed arc). *Fix:* in ring-only mode, add a center mark: a pause glyph (two 1px bars) for Away and a small triangle or dot for Break due. Alternatively, force the label (switch to ring + time) while the state is not "running".
- **[medium]** The Time tab keyboard model and VoiceOver labels are undefined (EXPERIENCE.md Time tab; Interaction Primitives; DESIGN.md Time tab, Phase indicator). Only `↵` = Start is specified. Not defined:
  - focus order across Pomodoro, the presets, `+ DATE`, the minutes field and `START ↵`;
  - how `PAUSE` / `RESET` / `REMOVE` are triggered on a selected running row (`↵` is ambiguous);
  - keyboard entry for `+ DATE`;
  - VoiceOver text for the rings and pips.

  `RESET` and `REMOVE` are destructive, sit 5px apart and have no undo. *Fix:*
  - Focus order: Tab cycles quick start (←→ inside the button group), then the minutes field, `START`, the running list (`↑↓`), and the row chips.
  - Row keys: Space = Pause/Resume, `⌘⌫` = Remove (with undo), `⌘R` or a menu item = Reset.
  - Row label, e.g. "Tea, 5 minute timer, 3 minutes 12 seconds left, ends 14:52, paused". The pips read "Work, cycle 2 of 4". The ring is hidden from VoiceOver as decoration.
- **[medium]** The `COPIED · N LINES` / `NO TEXT FOUND` readout lasts 2 s and has no lasting equivalent or VoiceOver output (DESIGN.md Copied readout; EXPERIENCE.md Copied readout, State Patterns). It is set at 7.5–8px on the closed notch, with no peek and no sound by design. A low-vision or VoiceOver user may not know whether the clipboard changed, and `NO TEXT FOUND` is the only failure signal. *Fix:*
  - Post an `NSAccessibility` announcement ("Copied 3 lines" / "No text found").
  - Hold the readout while the pointer is over the notch.
  - Keep a lasting trace: `LAST · 3 LINES · 14:48` as the Image to Text mini-zone meta in the `SEND TO` card, or an activity entry.
  - Allow the duration to be set alongside peek dwell.
- **[medium]** Peeks are not announced to VoiceOver, and the Timer-end peek leaves no lasting record (EXPERIENCE.md Peek alert panel, Accessibility Floor, Time). Panels never take focus (correct), so VoiceOver users get nothing unless an announcement is posted. Session peeks leave the glyph and tab marker behind. A Timer end leaves nothing once the 5 s dwell ends: the spine does not say what happens to the ended row. *Fix:* post an announcement for every peek (kicker + title + primary shortcut). On the Time tab, keep the ended timer as `ENDED 14:48` with `DISMISS` until it is acknowledged.
- **[medium]** Reduce motion has no static fallback for functional drains or for the new loops (EXPERIENCE.md Accessibility Floor; DESIGN.md Presence levels). "Removes animations" would also remove these drains, which carry time information:
  - the peek dwell line, including the Time and break peeks;
  - the 2 s `COPIED` drain;
  - the notes clipboard drain.

  The calm table also leaves out the new loops: the Time peek rim (runs like the alert rim), the breathing Ask AI `+` target, the card iris filament (12 s) and the drop display rim. *Fix:* under Reduce motion, show drains as a static full line that disappears at the end, or as stepped segments, never as a smooth slide. List the Time peek rim, Ask AI breathing, card filament and drop display rim explicitly as "static" in Calm and Reduce motion.
- **[medium]** The release line, the only confirmation of the drop target, is set at 7.5px meta size (DESIGN.md Drop display "metas 7.5px in `ink-3` (A)"). On drag-hover, the meta becomes `RELEASE TO ASK` / `RELEASE TO SHARE` in the accent color. It passes contrast (lilac on hover tint: 9.68 dark, 4.74 light) but is smaller than the already-open legibility question for 7.5–8px. *Fix:* on hover, set the release line at label size (9px A / `c-card-title` C). It can replace the meta line rather than add to it.

### Low

- **[low]** Upcoming phase pips (`ink-1` at 14%) measure 1.33–1.47 against every surface, and "done" and "upcoming" differ only in lightness (DESIGN.md Phase indicator). The `WORK · 2/4` label carries the count, so no information is lost. *Fix:* draw upcoming pips as a 1px `ink-3` ring (hollow vs filled is a shape difference).
- **[low]** Several hit targets are small or easy to mis-click (mockup 1.7d/e chips: 8px text, 6px vertical padding, about 20px tall, 5px gaps). These are the Time row `PAUSE`/`RESET`/`REMOVE` and the script page `REVEAL`/`OPEN SOURCE`. The gear (24 / 26px), the 30px peek actions (break secondaries about 94 × 30) and the 38px mini zones are fine. *Fix:* give chips a hit area of at least 24px tall and 8px gaps. Add undo to Remove.
- **[low]** In C, process-only and idle are told apart only by a thin outer circle at 16px without color (DESIGN.md Status glyph, Stale and process-only). C idle is "dot in circle" and process-only is "plain filled dot". The right wing has no label. In A, the hollow ring vs the filled dot is clear, and stale has its `?`. *Fix:* make the C process-only dot clearly smaller (for example 4px) or use a hollow dashed dot. Make sure the VoiceOver labels ("…, running, no status available") ship with v1.
- **[low]** Keyboard and VoiceOver reach for the script page and script widget is unspecified (DESIGN.md Script page; EXPERIENCE.md Script Modules). This covers how the `REVEAL` / `OPEN SOURCE` chips and the "click a card opens its tab" `[ASSUMPTION]` are reached by keyboard. *Fix:* Tab order hero → About → Runs → chips. The hero label reads, e.g., "vigie.app, OK, up, 200, 142 ms, checked 2 minutes ago".
- **[low]** `a-dark-ink-3` on `a-dark-surface-card` measures 4.56, a thin margin for 7.5–9px labels. Any extra overlay (hover brighten, alert tint) drops it below 4.5. *Fix:* lift it to `#8790A0` (5.42 on card, 5.98 on panel) or accept it and document the margin.
- **[low]** The status-vocabulary `OK` glyph is the same shape and hue as the A idle session glyph (hollow ring, `status-idle`). They are kept apart by wing and label, and VoiceOver needs the same separation. *Fix:* side-slot labels lead with the module ("vigie.app, OK"), session labels with the project. The spine already says this; keep it when building.
- **[low]** A drop zone that does not accept the item gives no reason; it simply stays unlit (DESIGN.md Drop display). *Fix:* show a dimmed meta such as `IMAGES AND PDF ONLY` on Image to Text while a file it cannot take is dragged over it.
- **[low]** `←→` in the tab row is ambiguous (EXPERIENCE.md Settings gear). "Tab / `←→` reach the settings gear" could also mean `←→` switches tabs. The tab alert marker (5px diamond or square) also needs a VoiceOver label. *Fix:* `←→` moves focus without activating a tab, and `↵` / Space activates. The tab label reads "Agents, needs attention".
- **[low]** DESIGN.md states only the 4.5:1 text rule (Colors → Contrast). Non-text contrast (glyphs, rings, focus indicators, zone borders ≥ 3:1) is not written down, and the contrast table does not cover cards, the vn surfaces, alert-row tints or alpha borders. *Fix:* add the 3:1 non-text rule and extend the table with the rows below.

**Counts:** critical 0 · high 5 · medium 10 · low 9.

## Contrast table

Ratios are WCAG; ! = fail. Text needs ≥ 4.5; non-text needs ≥ 3.0.

### Text tokens on stated surfaces

| Look | Token | Value | panel | card | vn-top | vn-bottom | band / island `#000` |
|---|---|---|---|---|---|---|---|
| A dark | ink-1 | `#E8ECF2` | 16.29 | 14.70 | — | — | 17.71 |
| A dark | ink-2 | `#B4BCC8` | 10.09 | 9.10 | — | — | 10.97 |
| A dark | ink-3 | `#7A8393` | 5.05 | 4.56 | — | — | 5.50 |
| A dark | iris-1 / -2 / -3 | | 14.97 / 11.02 / 13.09 | 13.51 / 9.94 / 11.81 | — | — | 16.27 / 11.98 / 14.24 |
| A dark | idle / working / done | | 14.95 / 14.43 / 11.89 | 13.49 / 13.02 / 10.73 | — | — | ≥ 12.9 |
| A dark | blocked / failed | | 7.78 / 8.76 | 7.02 / 7.91 | — | — | 8.46 / 9.53 |
| A dark | pace-ahead / quota-warning | | 8.24 / 14.83 | 7.43 / 13.39 | — | — | 8.95 / 16.13 |
| A light | ink-1 | `#161B24` | 15.82 | 17.26 | 16.39 | 14.98 | — |
| A light | ink-2 | `#454E5D` | 7.69 | 8.40 | 7.97 | 7.29 | — |
| A light | ink-3 | `#5D6676` | 5.30 | 5.79 | 5.50 | 5.02 | — |
| A light | iris-1 | `#126F8C` | 5.23 | 5.71 | 5.42 | 4.95 | — |
| A light | iris-2 | `#6A4FD0` | 5.28 | 5.77 | 5.47 | 5.00 | — |
| A light | iris-3 | `#A8346B` | 5.71 | 6.23 | 5.92 | 5.41 | — |
| A light | status-idle | `#0E7F57` | 4.59 | 5.01 | 4.76 | **4.35 !** | — |
| A light | status-working | `#985A00` | 5.07 | 5.53 | 5.25 | 4.80 | — |
| A light | status-done | `#1D6FC0` | 4.71 | 5.14 | 4.88 | **4.46 !** | — |
| A light | status-blocked | `#C8243F` | 5.09 | 5.56 | 5.27 | 4.82 | — |
| A light | status-failed | `#9B35C4` | 5.20 | 5.68 | 5.39 | 4.92 | — |
| A light | pace-ahead | `#B5410A` | 5.16 | 5.64 | 5.35 | 4.89 | — |
| A light | quota-warning | `#8A6D00` | 4.51 | 4.92 | 4.67 | **4.27 !** | — |
| C dark | ink-1 | `#F2F4F5` | 17.56 | 16.78 | — | — | 19.03 |
| C dark | ink-2 | `#C9CED3` | 12.23 | 11.68 | — | — | 13.25 |
| C dark | ink-3 | `#7C858C` | 5.16 | 4.93 | — | — | 5.59 |
| C dark | gold-text | `#F2D48A` | 13.43 | 12.83 | — | — | 14.56 |
| C dark | idle / working / done | | 10.57 / 9.30 / 8.89 | 10.10 / 8.89 / 8.49 | — | — | ≥ 9.6 |
| C dark | blocked / failed | | 5.98 / 6.36 | 5.71 / 6.08 | — | — | 6.48 / 6.89 |
| C dark | pace-on / pace-ahead / quota-warning | | 13.96 / 9.78 / 14.88 | 13.34 / 9.35 / 14.22 | — | — | 15.13 / 10.60 / 16.13 |
| C light | ink-1 | `#14181B` | 14.64 | 16.33 | 16.04 | 14.24 | — |
| C light | ink-2 | `#3A434A` | 8.27 | 9.22 | 9.06 | 8.05 | — |
| C light | ink-3 | `#535C63` | 5.59 | 6.24 | 6.13 | 5.44 | — |
| C light | gold-text | `#765709` | 5.49 | 6.12 | 6.01 | 5.34 | — |
| C light | status-idle | `#12703F` | 5.04 | 5.62 | 5.52 | 4.90 | — |
| C light | status-working | `#985200` | 4.86 | 5.42 | 5.33 | 4.73 | — |
| C light | status-done | `#1462AE` | 5.08 | 5.67 | 5.57 | 4.94 | — |
| C light | status-blocked | `#BE1A1A` | 5.14 | 5.73 | 5.63 | 5.00 | — |
| C light | status-failed | `#8E2A9E` | 5.79 | 6.45 | 6.34 | 5.63 | — |
| C light | pace-on | `#4F6A00` | 5.07 | 5.66 | 5.56 | 4.94 | — |
| C light | pace-ahead / gold | `#A07418` | 3.44 (fill only, OK as non-text) | 3.84 | 3.77 | 3.35 | — |
| C light | quota-warning | `#8A6D00` | **4.03 !** | **4.499 !** | **4.42 !** | **3.92 !** | — |
| proposed | light quota-warning-text | `#7E6300` | C 4.69 / A 5.24 | C 5.23 | — | C 4.56 / A 4.96 | — |
| proposed | (wider margin) | `#7A6000` | C 4.92 / A 5.50 | C 5.49 | — | C 4.78 / A 5.20 | — |

### Text on tints

| Pair | Ratio |
|---|---|
| A dark `ink-3` on 10% blocked / failed row tint (card) | **3.93 ! / 3.85 !** |
| C dark `ink-3` on 10% blocked / failed row tint (card) | **4.46 ! / 4.39 !** |
| A light / C light `ink-3` on alert tints | 4.94–5.33 |
| Status label in its own hue on its tint | 4.74–6.67 (pass) |
| A release line lilac on 8% lilac hover tint (dark / light) | 9.68 / 4.74 |

### Non-text (≥ 3.0)

| Element | Ratio |
|---|---|
| Selection ring `ink-1` at 55%: A dark / C dark / C light (panel) | 5.43 / 5.76 / 3.75 |
| Gear focus, A dark platinum at 55% | 5.43 |
| Gear focus, A light, if platinum at 55% | **1.05 !** |
| Stale ring and process-only dot in `ink-3` (any look, any surface) | ≥ 4.56 |
| A light `filament-1` `#3FA3C4` (Time rim; arc if reused) on panel / card | **2.65 ! / 2.90 !** |
| A light `iris-1` as Time arc on card; vs `line` track | 5.71; 3.99 |
| A light `filament-2` / `filament-3` / `line-silver` on panel | 3.57 / 3.08 / **2.84** (decorative only) |
| C light `gold` ring or frame on panel / card | 3.44 / 3.84 |
| A dark Time arc cyan vs 10% track; Away arc `ink-3` vs track | 10.12; 3.42 |
| Time ring track white 10% on card; date-countdown track 14% | **1.33 / 1.53** (supplemental) |
| Upcoming phase pip `ink-1` at 14% (all looks) | **1.33–1.47 !** |
| Ask AI dashed: A dark lilac 35% / A light iris-2 35% / C dark gold 55% / C light gold 55% | **2.30 !** / **1.66 !** / 3.64 / **1.88 !** |
| C struct inner border 22% (dark / light) | **1.64 / 1.33 !** |
| A Stash / AirDrop hairline 9% / 7% | **1.24 / 1.17 !** |
| Chip border: A platinum 18% / C struct 30% dark / light | **1.67 / 2.13 / 1.52 !** |
| `COPIED` drain `ink-1` at 60% vs `line` track on island | 4.42 |
| `quota-warning` triangle or fill, light `#8A6D00` (panel) | 4.03–4.51 (pass as non-text) |
