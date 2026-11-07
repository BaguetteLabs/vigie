# Accessibility floor

The minimum every Vigie surface meets from v0.1 (PRD FR-63, NFR9, NFR10; UX-DR13, UX-DR63–66, UX-DR94–96;
Story 2.15). Behavior is defined in `docs/ux-designs/ux-vigie-2026-11-04/EXPERIENCE.md` ("Accessibility
Floor"); colors and the Increase contrast table in `DESIGN.md` (Colors › Contrast, Components › Increase
contrast).

**Every later story that adds a surface is done only when that surface passes these checks.**

## The checks

1. **Label with state.** Every control and glyph has an accessibility label that includes its state, built
   with the `AccessibilityLabel` helper in VigieUI (Story 2.11): `AccessibilityLabel.session(…)` ("vigie /
   api-refactor, blocked, 2 minutes"), `.item(name:level:)` ("vigie.app, OK"), `.control(_:shortcut:)`
   (buttons include their shortcut). Status marks and labels already set theirs; a new glyph or control sets
   one too. Decorative views (filaments, drains, scroll thumbs) are `accessibilityHidden`.
2. **Color is never the only cue.** Each state has a distinct glyph shape or text label: session statuses
   (`SessionStatus.glyph` / `tacticalGlyph`), run statuses and levels (`RunStatus.glyph`, `StatusLevel.glyph`,
   labels from `StatusLabelFormatter`), pace (`PaceState.cue`: `AHEAD OF PACE`) and quota (`QuotaState.cue`:
   hatch, triangle, `WARN`). A new state adds its glyph or label; `NonColorCueTests` enforces distinctness.
3. **Contrast.** Text at least **4.5:1** on every surface it is used on; non-text UI that carries meaning
   (status glyphs, rings, Time arcs, focus rings, zone and chip borders) at least **3:1** (WCAG 1.4.11).
   Warning text in light looks uses `quota-warning-text` (`#7E6300`); `quota-warning` (`#8A6D00`) is only for
   hatch, triangles, arcs and fills. A new surface or a new text/role pairing adds its pairs to
   `ContrastAudit` (see below).
4. **Keyboard reachability.** Every expanded-view action is reachable by keyboard when the view has focus
   (selection ring via `keyboardSelectionRing`, actions via `ActionButton` with their shortcut).
5. **Peek actions by global shortcut.** Panels never take focus, so every peek action is reachable through a
   global shortcut, and every peek posts a VoiceOver announcement.
6. **macOS display settings win**, applied live when the setting flips (see below).

## macOS settings

All three flags are read once, in `ThemeController` (it re-resolves both the panel theme and the island
theme on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`), and resolved last in the theme
(AD-14). Surfaces never read `NSWorkspace`; they read **`theme.a11y`** (`AccessibilityRules`) and the theme
helpers, so Expanded, Peek and Settings inherit the rules:

| Rule | API | Increase contrast | Reduce transparency | Reduce motion |
|---|---|---|---|---|
| Flat fills instead of glass gradients | `a11y.flatSurfaces`, `theme.glassFill(_:flat:)` | yes | yes | — |
| Hairlines, zone/chip/card/struct borders solid 1 px `ink-3` | `a11y.solidHairlines`, `theme.borderColor(_:opacity:)` | yes | — | — |
| Ask AI dashed border at 100 % lilac / gold | `a11y.fullStrengthAccentBorders`, `theme.accentBorderColor(_:opacity:)` | yes | — | — |
| Tracks (Time ring, countdown, quota, pace) `ink-3` ≥ 40 % | `a11y.minTrackOpacity`, `theme.trackColor(_:opacity:)` | yes | — | — |
| Focus / selection ring 2 px, halo dropped | `a11y.focusRingWidth`, `a11y.haloEnabled` | yes | — | — |
| Decorative elements ≥ 3:1, text roles ≥ 4.5:1 (lightness only, hue kept, user overrides raised never discarded) | resolver (`AccessibilityAdjustments.apply`) | yes | — | — |
| Upcoming phase pips | unchanged | — | — | — |
| No looping or transitional animation | `a11y.motionEnabled`, `theme.animation(_:)` (nil), `theme.loopAnimation(_:)` (nil), `theme.transition(_:)` (opacity) | — | — | yes |
| Grows (`peek-grow`, `drop-display-grow`, `exit`) instant or a short cross-fade | `theme.animation(_:reducedMotion: .crossFade)` | — | — | yes |
| Functional drains: static full line that disappears at the end | `a11y.drainStyle`, `DrainLine` | — | — | yes |
| Island rim, shimmer, card iris filament static | `IslandOrnaments(motionEnabled:)`, `theme.loopsEnabled` | — | — | yes |

The island stays black under every setting. Rules for view code:

- Never call `withAnimation(.easeOut(duration: …))` directly: use `withAnimation(theme.animation(.enter))`.
- Never build a loop with `.repeatForever` without `theme.loopAnimation(_:)` (or a `theme.loopsEnabled` guard),
  and stop it with a transaction that disables animations when it turns off.
- Never compare `accessibility.increaseContrast` in a view: use the `a11y` rule or helper that names the effect.
- The Time peek rim, Ask AI `+`, drop display rim and peek/drop grows use the same helpers as they arrive.

"Reduce motion forces Calm presence" (and the Settings warning explaining it) is **Story 18.3**, once presence
levels exist. (The `ThemeController.effectivePresence` path that already does this predates Story 2.15; the
Story 2.15 motion rules do not depend on it.)

## Contrast check

`Scripts/check-contrast.sh` runs the `contrastcheck` executable (VigieUI package) on the repository themes
(`Themes/*.toml`). It resolves Chrome Hologram dark and light (plain and with Increase contrast) and Twin
Metal Tactical dark and light, and measures every pair in `ContrastAudit.pairs`
(`Packages/VigieUI/Sources/VigieUI/Theme/ContrastAudit.swift`). Each pair cites the DESIGN row it comes from.

```sh
Scripts/check-contrast.sh          # every pair with its ratio
Scripts/check-contrast.sh --quiet  # failures, exceptions and the summary only (CI)
```

- **FAIL** (exit 1): a Chrome Hologram pair below its minimum. Do not edit `Themes/*.toml` by hand (they are
  generated from DESIGN.md by `themegen`): take the pair and its ratio to the DESIGN doc.
- **ALLOWED**: a DESIGN-acknowledged exception (e.g. `c-light-gold` is never text, A light `filament-1` is
  the decorative rim only, dark alert-tinted rows use `ink-2` for the secondary line). Listed with the
  citation; never fails.
- **ADVISORY**: a Twin Metal Tactical pair below its minimum; reported only until Story 18.1.
- A note lists ratios that differ from the value DESIGN states by more than 0.1 (documentation drift).

CI runs it as the `contrast-check` step; `Scripts/ci-local.sh` runs it too. `ContrastAuditTests` runs the same
table against the bundled themes. User-configured colors are not checked (DESIGN: the settings window shows
the contrast of a custom color but does not block it); under Increase contrast the resolver raises them.
