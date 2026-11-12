---
name: Vigie
description: Theme family for a macOS notch companion (closed source for now, business model undecided; SPEC §2.1). One shared base (geometry, layout, motion grammar) and two built-in variants, Chrome Hologram (default) and Twin Metal Tactical, each in light and dark. Sci-fi instrument aesthetic, strictly contained inside the notch.
status: final
updated: 2026-11-07
sources:
  - ../../SPEC.md
  - ../../prds/prd-vigie-2026-11-06/prd.md
colors:
  # Naming: <scope>-<role>. Scope is `base` (shared by every look) or
  # `<variant>-<mode>` with variant a = Chrome Hologram, c = Twin Metal Tactical
  # and mode dark | light. Roles are identical across the four looks, so a
  # component asks for a role and the active look supplies the value.
  # The hardware island always resolves roles against `<variant>-dark-*`.
  # Status, pace and quota-warning colors are defaults; every one is user-configurable.
  # No color exists for scripts or Time: the shared status vocabulary
  # (components.status-vocabulary) reuses status-idle / quota-warning / status-failed,
  # and Time reuses each variant's "now" accent (A iris-1, C gold / gold-text).
  base-island: '#000000'
  base-band: '#000000'
  base-shadow: '#000000'

  # A · Chrome Hologram · dark
  a-dark-surface-panel: '#0A0E16'
  a-dark-surface-card: '#161A22'
  a-dark-ink-1: '#E8ECF2'
  a-dark-ink-2: '#B4BCC8'
  a-dark-ink-3: '#7A8393'
  a-dark-line: '#232934'
  a-dark-line-silver: '#8A93A2'
  a-dark-iris-1: '#A5EEFF'
  a-dark-iris-2: '#CDB9FF'
  a-dark-iris-3: '#FFC4E1'
  a-dark-status-idle: '#A6F2D2'
  a-dark-status-working: '#FFD9A0'
  a-dark-status-done: '#8FD3FF'
  a-dark-status-blocked: '#FF7B8C'
  a-dark-status-failed: '#E58CFF'
  a-dark-pace-on: '#E8ECF2'        # theme metal (platinum); closed ring draws the iris gradient
  a-dark-pace-ahead: '#FF8A3D'     # Ember
  a-dark-quota-warning: '#FFE14D'  # signal yellow

  # A · Chrome Hologram · light
  a-light-surface-panel: '#F3F5F9'
  a-light-surface-card: '#FFFFFF'
  a-light-surface-vn-top: '#F8F9FB'
  a-light-surface-vn-bottom: '#ECEFF4'
  a-light-ink-1: '#161B24'
  a-light-ink-2: '#454E5D'
  a-light-ink-3: '#5D6676'
  a-light-line: '#D3D8E0'
  a-light-line-silver: '#8A93A2'
  a-light-iris-1: '#126F8C'
  a-light-iris-2: '#6A4FD0'
  a-light-iris-3: '#A8346B'
  a-light-filament-1: '#3FA3C4'
  a-light-filament-2: '#8A6CE8'
  a-light-filament-3: '#D06A9E'
  a-light-status-idle: '#0B7651'   # darkened 2026-11-07 for vn-bottom (4.89)
  a-light-status-working: '#985A00'
  a-light-status-done: '#1A68B5'   # darkened 2026-11-07 for vn-bottom (4.94)
  a-light-status-blocked: '#C8243F'
  a-light-status-failed: '#9B35C4'
  a-light-pace-on: '#161B24'       # theme metal (graphite)
  a-light-pace-ahead: '#B5410A'    # Ember, text-safe
  a-light-quota-warning: '#8A6D00' # signal yellow: hatch, triangle, arc, fills (non-text)
  a-light-quota-warning-text: '#7E6300' # warning text (5.24 panel, 4.96 vn-bottom)

  # C · Twin Metal Tactical · dark
  c-dark-surface-panel: '#0A0E11'
  c-dark-surface-card: '#101417'
  c-dark-ink-1: '#F2F4F5'
  c-dark-ink-2: '#C9CED3'
  c-dark-ink-3: '#7C858C'
  c-dark-line: '#2A3136'
  c-dark-struct: '#C9CED3'
  c-dark-gold: '#D8B45C'
  c-dark-gold-text: '#F2D48A'
  c-dark-status-idle: '#6FD39A'
  c-dark-status-working: '#F0A43C'
  c-dark-status-done: '#4FB8FF'
  c-dark-status-blocked: '#FF4F4F'
  c-dark-status-failed: '#D85CFF'
  c-dark-pace-on: '#C2EA3E'        # Volt (inverted: green = OK)
  c-dark-pace-ahead: '#D8B45C'     # C gold metal
  c-dark-quota-warning: '#FFE14D'  # signal yellow, shared with A

  # C · Twin Metal Tactical · light
  c-light-surface-panel: '#E6E9EB'
  c-light-surface-card: '#F3F5F6'
  c-light-surface-vn-top: '#F1F3F4'
  c-light-surface-vn-bottom: '#E3E6E8'
  c-light-ink-1: '#14181B'
  c-light-ink-2: '#3A434A'
  c-light-ink-3: '#535C63'
  c-light-line: '#C3C8CC'
  c-light-struct: '#5A636A'
  c-light-gold: '#A07418'
  c-light-gold-text: '#765709'
  c-light-status-idle: '#12703F'
  c-light-status-working: '#985200'
  c-light-status-done: '#1462AE'
  c-light-status-blocked: '#BE1A1A'
  c-light-status-failed: '#8E2A9E'
  c-light-pace-on: '#4F6A00'       # darkened Volt; adopted with the 1.7f C light Usage mock (2026-11-07)
  c-light-pace-ahead: '#A07418'    # C light gold (frames, arcs, fills only)
  c-light-quota-warning: '#8A6D00' # signal yellow, shared with A: hatch, triangle, arc, fills (non-text)
  c-light-quota-warning-text: '#7E6300' # warning text (4.69 panel, 5.23 card, 4.56 vn-bottom)
typography:
  # Font stacks. All ship with macOS; no bundled fonts.
  # A: SF Pro (system) light weights + SF Mono for code.
  # C: Avenir Next Condensed (fallback DIN Condensed) for labels, SF Mono for values, SF Pro for prose.
  a-readout-value:
    fontFamily: SF Pro (system)
    fontSize: 14px
    fontWeight: '300'
    lineHeight: 13px
  a-readout-label:
    fontFamily: SF Pro (system)
    fontSize: 7.5px
    fontWeight: '500'
    lineHeight: 8px
    letterSpacing: 0.24em
  a-kicker:
    fontFamily: SF Pro (system)
    fontSize: 9px
    fontWeight: '500'
    letterSpacing: 0.24em
  a-peek-title:
    fontFamily: SF Pro (system)
    fontSize: 19px
    fontWeight: '300'
    lineHeight: 20px
  a-body:
    fontFamily: SF Pro (system)
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  a-action:
    fontFamily: SF Pro (system)
    fontSize: 10px
    fontWeight: '500'
    letterSpacing: 0.14em
  a-tab:
    fontFamily: SF Pro (system)
    fontSize: 11px
    fontWeight: '500'
    letterSpacing: 0.04em
  a-card-title:
    fontFamily: SF Pro (system)
    fontSize: 9px
    fontWeight: '500'
    letterSpacing: 0.26em
  a-row-primary:
    fontFamily: SF Pro (system)
    fontSize: 13px
    fontWeight: '400'
  a-row-status:
    fontFamily: SF Pro (system)
    fontSize: 9px
    fontWeight: '500'
    letterSpacing: 0.2em
  a-numeral-big:
    fontFamily: SF Pro (system)
    fontSize: 38px
    fontWeight: '200'
    lineHeight: 34px
    letterSpacing: -0.02em
  a-code:
    fontFamily: SF Mono
    fontSize: 11px
    fontWeight: '500'
  c-readout-value:
    fontFamily: SF Mono
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 13px
  c-readout-label:
    fontFamily: Avenir Next Condensed
    fontSize: 8px
    fontWeight: '600'
    lineHeight: 8px
    letterSpacing: 0.2em
  c-kicker:
    fontFamily: Avenir Next Condensed
    fontSize: 11px
    fontWeight: '600'
    letterSpacing: 0.24em
  c-peek-title:
    fontFamily: SF Mono
    fontSize: 15px
    fontWeight: '500'
    lineHeight: 20px
  c-body:
    fontFamily: Avenir Next Condensed
    fontSize: 10px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.18em
  c-prose:
    fontFamily: SF Pro (system)
    fontSize: 11.5px
    fontWeight: '400'
    lineHeight: '1.45'
  c-action:
    fontFamily: Avenir Next Condensed
    fontSize: 11px
    fontWeight: '600'
    letterSpacing: 0.18em
  c-tab:
    fontFamily: Avenir Next Condensed
    fontSize: 11px
    fontWeight: '600'
    letterSpacing: 0.18em
  c-card-title:
    fontFamily: Avenir Next Condensed
    fontSize: 11px
    fontWeight: '600'
    letterSpacing: 0.22em
  c-row-primary:
    fontFamily: SF Mono
    fontSize: 12px
    fontWeight: '500'
  c-row-status:
    fontFamily: Avenir Next Condensed
    fontSize: 10px
    fontWeight: '600'
    letterSpacing: 0.2em
  c-numeral-big:
    fontFamily: SF Mono
    fontSize: 32px
    fontWeight: '500'
    lineHeight: 34px
    letterSpacing: -0.02em
  c-code:
    fontFamily: SF Mono
    fontSize: 11px
    fontWeight: '400'
  a-time-value:
    # Time tab row value (Story 1.7e)
    fontFamily: SF Pro (system)
    fontSize: 26px
    fontWeight: '200'
    lineHeight: 26px
    letterSpacing: -0.02em
  c-time-value:
    # [ASSUMPTION] C Time tab not mocked: C numeral style at the A size
    fontFamily: SF Mono
    fontSize: 22px
    fontWeight: '500'
    lineHeight: 26px
    letterSpacing: -0.02em
rounded:
  island-closed: 14px
  peek: 22px
  expanded: 24px
  notes-panel: 16px
  a-card: 16px
  a-setup-card: 14px
  a-zone: 13px
  a-mini-zone: 11px
  a-row: 10px
  a-day-cell: 8px
  a-code: 5px
  c-card: 0px
  c-action: 0px
  full: 9999px
spacing:
  band-height: 34px
  wing-padding-x: 16px
  wing-gap: 9px
  glyph-gap: 7px
  peek-inset-x: 26px
  peek-column-gap: 18px
  peek-timer-bottom: 12px
  expanded-bar-padding-x: 20px
  tabs-margin-x: 16px
  tab-padding-x: 12px
  grid-gap: 10px
  grid-padding-x: 16px
  card-padding-y: 12px
  card-padding-x: 13px
  action-gap: 8px
  row-gap: 10px
  tab-row-gap: 8px
  drop-grid-inset-x: 16px
  drop-grid-top: 44px
  drop-grid-bottom: 16px
  drop-grid-gap: 8px
  drop-band-padding-x: 22px
  mini-zone-gap: 6px
motion:
  # Documented extension (not in the DESIGN.md spec). Shared by both variants.
  enter: 280ms
  exit: 200ms             # [ASSUMPTION] provisional, ease-in; collapse and retract
  peek-grow: 280ms        # [ASSUMPTION] provisional, = enter
  drop-display-grow: 180ms # [ASSUMPTION] provisional
  ambient-loop: 6s
  working-cycle: 1.5s
  blocked-cycle: 1.8s
  failed-cycle: 1.8s
  calm-pulse: 2.6s
  peek-dwell: 5s          # default; user-configurable
  confirm-readout: 2s     # Image to Text COPIED readout
  panel-scan: 7s
  dial-bezel: 14s
  c-usage-bezel: 30s
  a-card-iris: 12s
components:
  island-closed:
    background: '{colors.base-island}'
    width: 540px
    height: '{spacing.band-height}'
    radius: '{rounded.island-closed}'
    padding-x: '{spacing.wing-padding-x}'
  peek-panel:
    band: '{colors.base-band}'
    width: 700px
    height: 150px
    radius: '{rounded.peek}'
    columns: '44px 1fr 176px'
    columns-three-actions: '44px 1fr 196px'   # break peek only (Story 1.7e)
    shadow-dark: '0 18px 40px rgba(0,0,0,.45)'
    shadow-light: '0 18px 40px rgba(0,0,0,.20), 0 2px 6px rgba(0,0,0,.08)'
  expanded-panel:
    band: '{colors.base-band}'
    width: 720px
    height: 420px
    radius: '{rounded.expanded}'
    shadow-dark: '0 28px 60px rgba(0,0,0,.5)'
    shadow-light: '0 28px 60px rgba(0,0,0,.22), 0 2px 8px rgba(0,0,0,.08)'
  notes-panel:
    width: 460px
    height: 372px
    radius: '{rounded.notes-panel}'
    shadow-dark: '0 28px 60px rgba(0,0,0,.5)'
    shadow-light: '0 28px 60px rgba(0,0,0,.22), 0 2px 8px rgba(0,0,0,.08)'
  status-glyph:
    size: 16px
    size-large: 26px
    stale: 'dashed ring (A r 6.6 / 1.1px, dash 2.1 1.8; C r 7 / 1px, dash 1.6 1.6) with a ? inside, ink-3 ring, ink-2 ?'
    process-only: 'plain filled dot, 5.6px, ink-3'
  status-vocabulary:
    # Shared primitive called by every first- or third-party module (Story 1.7d)
    ok: 'hollow ring · {colors.<look>-status-idle} · OK'
    warn: 'triangle · {colors.<look>-quota-warning} · WARN (label text in light looks: {colors.<look>-quota-warning-text})'
    down: 'cross (×) · {colors.<look>-status-failed} · DOWN'
    size-card: 26px
    size-slot: 16px
    size-inline: 10px
  settings-gear:
    size-a: 24px
    size-c: 26px
    icon: '14px outline gear, 1.2px stroke'
    a-radius: '{rounded.full}'
    c-radius: 0px
    inset-right: '{spacing.tabs-margin-x}'
    focus-a-dark: '1px platinum ring at 55% + 3px cyan halo at 14%'
    focus-a-light: '{components.selection-ring.a-light}, no halo'
    focus-c: '{components.selection-ring.c-dark} / {components.selection-ring.c-light}'
  selection-ring:
    a-dark: '1px platinum ({colors.a-dark-ink-1})'
    a-light: '1px graphite ({colors.a-light-ink-1})'
    c-dark: '1px {colors.c-dark-ink-1} at 55%'
    c-light: '1px {colors.c-light-ink-1} at 55%'
  drop-display:
    band: '{colors.base-band}'
    width: 700px
    height: 196px
    radius: '{rounded.peek}'
    grid: 'repeat(4, 1fr) × 2 rows; Stash cols 1–2 rows 1–2, Ask AI col 3 rows 1–2, AirDrop col 4 row 1, Image to Text col 4 row 2'
    inset: '{spacing.drop-grid-top} {spacing.drop-grid-inset-x} {spacing.drop-grid-bottom}'
    gap: '{spacing.drop-grid-gap}'
    zone-radius-a: '{rounded.a-zone}'
    shadow-dark: '0 18px 40px rgba(0,0,0,.45)'
  copied-readout:
    duration: '{motion.confirm-readout}'
    drain: '1px line, 6px above the island bottom'
  time-ring:
    size-closed: 23px
    size-row: 30px
    size-beacon: 26px
    work: 'solid arc'
    break: 'dashed arc (2.2 2)'
    a-accent: '{colors.a-dark-iris-1}'
    a-accent-light: '{colors.a-light-iris-1}'  # arcs and current pip; filament-1 is the decorative rim only
    c-accent: '{colors.c-dark-gold}'  # [ASSUMPTION] C Time not mocked; C "now" color
    c-accent-light: '{colors.c-light-gold}'  # arcs; text in {colors.c-light-gold-text}
    ring-only-away: 'center pause mark, two 1px bars'
    ring-only-break-due: 'center small triangle'
  phase-pips:
    done: '4px dot, ink-1'
    current: '7px ring in the Time accent, hatched during a break'
    upcoming: '4px hollow ring, 1px ink-3'
  quota-dial:
    size: 24px
    size-stacked: 23px
    size-usage-tab: 58px
    a-arc: 'gradient {colors.a-dark-iris-1} → {colors.a-dark-iris-2} → {colors.a-dark-iris-3}'
    c-arc: '{colors.c-dark-gold}'
  pace-marker:
    ring: 'short radial tick with a 1px black keyline'
    bar: '2px platinum bar at elapsed time'
  quota-warning-fill:
    pattern: 'repeating-linear-gradient(135deg, warning 0 3px, warning@40% 3px 5px)'
  action-button:
    height: 30px
    a-radius: '{rounded.full}'
    c-radius: '{rounded.c-action}'
    c-primary-frame: '{colors.c-dark-gold}'
    c-primary-text: '{colors.c-dark-gold-text}'
  widget-card:
    a-radius: '{rounded.a-card}'
    a-background-dark: '{colors.a-dark-surface-card}'
    a-background-light: '{colors.a-light-surface-card}'
    c-radius: '{rounded.c-card}'
    c-background-dark: '{colors.c-dark-surface-card}'
    c-background-light: '{colors.c-light-surface-card}'
    padding: '{spacing.card-padding-y} {spacing.card-padding-x}'
  home-grid:
    # one fixed card size in v1, no spans (decided 2026-11-07)
    columns: 'repeat(3, 1fr)'   # 222px cells in the 720px panel
    card-height: 138px          # = script-card
  session-row:
    height: 30px
    a-radius: '{rounded.a-row}'
    columns: '18px 84px minmax(0,1fr) 62px 104px 76px'
    columns-single-terminal: '18px 84px minmax(0,1fr) 104px 76px'
  tab-bar:
    height: 30px
    a-tab-radius: '{rounded.full}'
    c-active-underline: '{colors.c-dark-gold}'
  setup-card:
    max-width: 380px
    padding: '18px 20px'
    a-radius: '{rounded.a-setup-card}'
  month-grid:
    card-width: 300px
    columns: '22px repeat(7, 36px)'
    cell-height: 37px
    a-today-radius: '{rounded.a-day-cell}'
  send-to-card:
    # Shelf tab right card, headed SEND TO (Story 1.7c; was ask-ai-card)
    width: 212px
    ask-zone-height: 84px
    mini-zone-height: 38px
    mini-zone-gap: '{spacing.mini-zone-gap}'
    a-mini-zone-radius: '{rounded.a-mini-zone}'
  time-tab:
    rows: '84px 1fr'
    item-row: '30px 1fr 92px 196px'
    item-row-height: 62px
  script-page:
    columns: '1fr 212px'
    rows: '118px 1fr'
  script-card:
    width: 222px
    height: 138px
---

## Brand & Style

Vigie (French for a ship's lookout) is a notch companion that watches background work, mostly CLI coding agents, and shows it in the smallest possible space. The posture is *software from the future*: sci-fi holographic computers and spaceship instrument panels, rendered in metal (silver, platinum, gold). The "god's eye view" reference (`imports/ref-gods-eye-hud.png`, a satellite-tracking HUD with thin tick rings, tick scales and uppercase readouts) is an aesthetic source, not a metaphor. There is no radar, no targeting, no mascot. Tick rings and graduated scales stay as currently drawn; they are not reintroduced elsewhere.

The system is a **theme family**: one shared base (geometry, information placement, component slots, motion timing, wording) plus skins.

| Variant | Code | Character | Status in v1 |
|---|---|---|---|
| Chrome Hologram | `a` | Iridescent glass. Light SF type, pastel status tints (dark), rounded pills and cards. Ornament: an iris rim traced inside the island edge plus an interior shimmer. Motion glides, ripples and shimmers. | Built-in, **default** |
| Twin Metal Tactical | `c` | Gunmetal and gold. Condensed caps, mono numerals, square cards with inner corner marks. Ornament: tick bezel, corner marks, gold tracer. Motion ticks, traces and breathes. Sci-fi, not military. | Built-in |

Each variant has a dark and a light look: four looks in total. The look follows macOS appearance by default; a setting can force light or dark (EXPERIENCE.md Theming). Custom themes extend the same base. All four looks use identical wording and identical layout; a skin only restyles. The variant codes `a` and `c` are working names kept as token prefixes; they are not user-facing.

**Mockups.** Visual references live in `mockups/`. Where a mockup and this file disagree, this file wins.

- [`mockups/theme-family-4-looks.html`](mockups/theme-family-4-looks.html): all four looks (closed notch, blocked peek, expanded Home, status system).
- [`mockups/compare-a-vs-c-v3.html`](mockups/compare-a-vs-c-v3.html): shared base, strict containment, calm presence.
- Key screens: [`closed-notch-states`](mockups/key-closed-notch-states.html), [`alert-variants`](mockups/key-alert-variants.html), [`agents-tab`](mockups/key-agents-tab.html), [`notes`](mockups/key-notes.html), [`usage-tab`](mockups/key-usage-tab.html), [`shelf-tab`](mockups/key-shelf-tab.html), [`calendar-tab`](mockups/key-calendar-tab.html). The closed-notch and alert sheets show A and C dark; the expanded-tab and notes sheets show A dark and light only.
- [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html): Story 1.7 design pass (decided 2026-11-07; the banner names the chosen option per part): settings gear, stale and process-only glyphs, drag-only drop display, Send to card and Image to Text readout, script widgets, Time surfaces (A dark), and the Twin Metal Tactical tabs and notes panel (C dark and light). Rejected options stay on the sheet for the record.

## Colors

### Token scheme

Color tokens are named `<scope>-<role>`:

- `base-*` is shared by every look (`base-island`, `base-band`, `base-shadow`, all `#000000`).
- `<variant>-<mode>-*` holds one look: `a-dark-*`, `a-light-*`, `c-dark-*`, `c-light-*`.
- Roles repeat across looks: `surface-panel`, `surface-card`, `ink-1/2/3`, `line`, `status-{idle,working,done,blocked,failed}`, `pace-on`, `pace-ahead`, `quota-warning`, plus variant-specific accents (A: `iris-1/2/3`, `line-silver`, light `filament-1/2/3`; C: `struct`, `gold`, `gold-text`). `surface-vn-top/bottom` and `quota-warning-text` exist only for light looks (virtual notch in `menu_bar` style; warning text). In a dark look, `quota-warning-text` resolves to `quota-warning`. Until dark virtual-notch tokens exist, a dark `menu_bar` virtual notch falls back to the black island look (`base-island` with the dark role set) [ASSUMPTION; EXPERIENCE.md Open Question 15 stays open for a real dark material].

Components reference a role; the active look supplies the value. In prose below, `{colors.<look>-<role>}` (e.g. `{colors.a-dark-ink-1}`) names a concrete value.

**Resolver rule:** `<look>` in a token reference is substituted with the active look (a-dark, a-light, c-dark, c-light); `*` globs mean the same key in every component/typography entry of the active look (e.g. `components.*-panel.shadow-*`, `typography.*-readout-value`).

### The hardware island is always black

On a MacBook with a physical notch, the closed island *is* the notch. It stays `{colors.base-island}` in both appearances and always renders with the dark role set of the active variant (`a-dark-*` or `c-dark-*`), including status glyphs and pace colors. Light mode only changes the menu bar around it. Peek and expanded panels grow out of the notch, so their top `{spacing.band-height}` stays `{colors.base-band}` (wordmark and clock live on it in expanded); only the panel body below switches to the light material. The floating notes panel is not attached to the notch and has no band.

### Shared roles

| Role | A dark | A light | C dark | C light | Use |
|---|---|---|---|---|---|
| surface-panel | `#0A0E16` | `#F3F5F9` | `#0A0E11` | `#E6E9EB` | Peek, expanded and notes panel body |
| surface-card | `#161A22` | `#FFFFFF` | `#101417` | `#F3F5F6` | Widget cards, tab cards, legend cards |
| ink-1 | `#E8ECF2` | `#161B24` | `#F2F4F5` | `#14181B` | Values, titles, project names |
| ink-2 | `#B4BCC8` | `#454E5D` | `#C9CED3` | `#3A434A` | Secondary text, detail lines |
| ink-3 | `#7A8393` | `#5D6676` | `#7C858C` | `#535C63` | Labels, meta, inactive tabs, `+X` overflow |
| line | `#232934` | `#D3D8E0` | `#2A3136` | `#C3C8CC` | Track backgrounds, dividers |

Panel bodies are drawn as subtle vertical gradients in the mocks (A dark `#000` → `#070A10` → `#0A0E16`; A light `#F7F8FB` → `#EEF1F6`; C light `#E9ECEE` → `#E3E6E8`). The flat `surface-panel` value is the token; the gradient is a skin detail. `a-dark-surface-card` is the flat equivalent of a translucent white overlay (5.5% → 1.5%) on the panel.

### Variant accents

- **A iris** (`iris-1/2/3`: cyan, lilac, rose; dark `#A5EEFF #CDB9FF #FFC4E1`, light text `#126F8C #6A4FD0 #A8346B`). Drawn as a moving gradient with `{colors.a-dark-ink-1}` as the fourth stop: the island rim, the top filament of each card, the closed quota arc, meters. In light mode, filaments and the rim use the mid-depth `filament-1/2/3` (`#3FA3C4 #8A6CE8 #D06A9E`, plus `line-silver` `#8A93A2`); text that uses an iris hue uses the deeper `iris-*`. Cyan (`iris-1`) is A's "now" color: countdowns, today outline, now marker, and every Time surface (see Time accent below). Lilac (`iris-2`) marks the Ask AI target, pinned items and drag-hover.
- **A metal** in tab views: `ink-1` (platinum) fills the 5h window, `ink-2` (silver) the weekly window.
- **C gold** (`gold` for frames, arcs, markers; `gold-text` for gold-colored text). Dark `#D8B45C` / `#F2D48A`; light `#A07418` / `#765709`. Gold is reserved for *active and now*: the active tab, the live usage value, the primary action frame, the Ask AI target, the "now" marker on tracks, and ahead-of-pace fills. Never decoration, never session status.
- **C struct** (`#C9CED3` dark, `#5A636A` light): corner marks, ticks, bezels, hairlines, the weekly ring, the pinned-item dashed line.
- **Time accent** (decided 2026-11-07, Story 1.7e). Time surfaces (closed readout ring, phase pips, Time tab rings, Timer-end and break peeks: rim, beacon, kicker, dwell line) use the variant's non-status "now" accent, never a status hue: A `iris-1` (`#A5EEFF` dark; in light, `#126F8C` for text, arcs (closed readout, Time tab ring, peek beacon ring) and the current-phase pip, and `filament-1` `#3FA3C4` for the decorative rim only: as an arc it would measure 2.65:1), C `gold` for rings, rims and beacons and `gold-text` for the kicker [ASSUMPTION: no C Time surface was mocked; gold follows the C rule "gold = active and now"]. Work and break are told apart by label and arc style (solid vs dashed), not by color.

### Status colors

Five session states, each with its own color, glyph shape and label. Shape carries meaning on its own; color reinforces it. **Every status color is user-configurable per look** (color-blind accessibility and power-user customization); the values below are defaults.

| State | A dark | A light | C dark | C light |
|---|---|---|---|---|
| idle | `#A6F2D2` mint | `#0B7651` | `#6FD39A` | `#12703F` |
| working | `#FFD9A0` champagne | `#985A00` | `#F0A43C` | `#985200` |
| done | `#8FD3FF` sky | `#1A68B5` | `#4FB8FF` instrument blue | `#1462AE` |
| blocked | `#FF7B8C` rose | `#C8243F` | `#FF4F4F` | `#BE1A1A` |
| failed | `#E58CFF` orchid | `#9B35C4` | `#D85CFF` magenta | `#8E2A9E` |

Non-quota warnings (the script widget warn level and the shelf expiry warning) use the **quota-warning** color below, always with a triangle (decided 2026-11-06; it was the working hue). Yellow is now the one warning color across Vigie; the working hue means only "working".

Session glyphs also have two neutral, hue-less looks (decided 2026-11-07, Story 1.7b): **stale** and **process-only**, both in `ink-3` (Status glyph below). They never use a status hue, so they never compete with the five states.

### Status vocabulary colors

The shared status vocabulary (OK / WARN / DOWN) reuses the roles `status-idle`, `quota-warning` (text: `quota-warning-text` in light looks) and `status-failed`; it has no colors of its own. Visual spec: Components → Status vocabulary.

### Pace and quota-warning colors

Three usage roles, each user-configurable, each distinct from the status hues:

| Role | A dark | A light | C dark | C light | Meaning |
|---|---|---|---|---|---|
| pace-on | theme metal (iris gradient on the closed ring, `#E8ECF2` platinum on bars) | `#161B24` graphite | `#C2EA3E` Volt | `#4F6A00` darkened Volt | Used ≤ elapsed + tolerance |
| pace-ahead | `#FF8A3D` Ember | `#B5410A` Ember | `#D8B45C` gold metal | `#A07418` gold | Used > elapsed + tolerance |
| quota-warning | `#FFE14D` signal yellow | `#8A6D00` | `#FFE14D` | `#8A6D00` | Usage ≥ warning threshold (hatch, triangle, arc, fills) |
| quota-warning-text | = quota-warning | `#7E6300` | = quota-warning | `#7E6300` | Warning text in light looks (`WARN`, `1 EXPIRING`, `EXPIRES IN 5H`, WARN labels) |

- **C is inverted on purpose.** In A, metal means "fine" and a warm hue means "ahead". In C, the gold metal is already orange-ish, so within pace is Volt (green reads as OK) and ahead falls back to gold (orange reads as warning).
- **Quota warning is shared by A and C.** Signal yellow replaced a first-proposed chartreuse, which clashed with C's Volt (within pace). It is never color-only: it always comes with a hatched fill, a triangle and the `WARN` label.
- **Precedence:** quota warning wins over pace-ahead on the same window.
- Ember is ΔE00 ≥ 22.3 from every A status hue (nearest: working).
- The closed island always uses the `*-dark-*` values.
- `c-light-pace-on` is a text-safe darkened Volt (5.1:1 on `c-light-surface-panel`), since Volt `#C2EA3E` fails on light material. Adopted 2026-11-07 with the C light Usage tab mock ([`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) 1.7f).

### Contrast

Measured against `surface-panel` of the same look (WCAG ratio):

| Look | ink-1 | ink-2 | ink-3 | Lowest status hue | pace-ahead | quota-warning |
|---|---|---|---|---|---|---|
| A dark | 16.3 | 10.1 | 5.1 | blocked 7.8 | 8.2 | 14.8 |
| A light | 15.8 | 7.7 | 5.3 | done 4.9 | 5.2 | text 5.2 (`#7E6300`); fill 4.5 |
| C dark | 17.6 | 12.2 | 5.2 | blocked 6.0 | 9.8 | 14.9 |
| C light | 14.6 | 8.3 | 5.6 | working 4.9 | 3.4 (fill only) | text 4.7 (`#7E6300`); fill 4.0 (non-text) |

On the black island: Ember 9.0, Volt 15.1, signal yellow 16.1.

Further surfaces (WCAG ratio; measured 2026-11-07, `review-accessibility.md`):

| Pair | panel | card | vn-bottom |
|---|---|---|---|
| A light `iris-1` / `iris-2` / `iris-3` (Time values, `IN 42 MIN`, `ASK AI`, revealed secret) | 5.23 / 5.28 / 5.71 | 5.71 / 5.77 / 6.23 | 4.95 / 5.00 / 5.41 |
| A dark `iris-1` / `iris-2` / `iris-3` | 14.97 / 11.02 / 13.09 | 13.51 / 9.94 / 11.81 | — |
| C dark `gold-text` | 13.43 | 12.83 | — |
| C light `gold-text` | 5.49 | 6.12 | 5.34 |
| A light `status-idle` `#0B7651` / `status-done` `#1A68B5` | ≥ 4.89 | ≥ 4.89 | 4.89 / 4.94 |
| A light / C light `quota-warning-text` `#7E6300` | 5.24 / 4.69 | — / 5.23 | 4.96 / 4.56 |
| Status labels in their own hue on their alert tint (all looks) | 4.74–6.67 | | |
| `ink-3` on a 10% blocked/failed row tint: A light / C light | 4.94–5.33 | | |
| `ink-2` on a 10% blocked/failed row tint: A dark / C dark | 9.1 / 10.6 | | |

Rules:

- Every text color, status label included, reaches at least 4.5:1 on its surface.
- **Non-text** UI that carries meaning (glyphs, rings, Time arcs, focus indicators, zone and chip borders) reaches at least **3:1** against its surface (WCAG 1.4.11). Measured: selection ring `ink-1` at 55% 5.43 (A dark) / 5.76 (C dark) / 3.75 (C light); A light graphite ring 15.8; stale ring and process-only dot in `ink-3` ≥ 4.56; A light `iris-1` Time arc 5.71 on card (3.99 against the `line` track); C light `gold` ring 3.44 / 3.84; light `quota-warning` fill 4.03–4.51. Decorative-only elements (A light `filament-*`, `line-silver`, 10–14% tracks, alpha zone borders) are exempt but must reach 3:1 under Increase contrast (Components → Increase contrast).
- **Dark looks, alert-tinted rows:** `ink-3` over the 10% blocked/failed fade drops to 3.85–4.46, so on those rows the secondary line (last action, separators) is set in `ink-2`, never `ink-3`.

`c-light-gold` (`#A07418`, 3.4:1) is therefore restricted to frames, arcs, markers and fills; gold text in C light uses `c-light-gold-text` (5.5:1). Warning-yellow text (`WARN`, `1 EXPIRING`, a `WARN` status label) in A light and C light uses `quota-warning-text` `#7E6300` (same hue, slightly darker), which passes on panel, card and the virtual notch; `#8A6D00` stays for hatch, triangles, arcs and fills. The earlier "C light warning text only on cards" rule is dropped (2026-11-07). User-configured colors are not checked automatically in v1 [ASSUMPTION: the settings window shows the contrast of a custom color but does not block it].

### Calendar colors

Calendar day dots and event dots use the macOS (EventKit) calendar colors. They are user data, not Vigie tokens, and may sit close to status hues. The today outline, the "now" marker and the relative time use the variant's now color: A `iris-1`; C `gold` for the outline and marker and `gold-text` for text (`c-light-gold-text` `#765709` in C light), decided 2026-11-07.

## Typography

All fonts ship with macOS; nothing is bundled.

| Role | A · Chrome Hologram | C · Twin Metal Tactical |
|---|---|---|
| Closed-notch value | `{typography.a-readout-value}` SF Pro 300, tabular numerals | `{typography.c-readout-value}` SF Mono 500 |
| Closed-notch label, provider name under ring | `{typography.a-readout-label}` uppercase, tracked | `{typography.c-readout-label}` Avenir Next Condensed caps |
| Peek kicker (state line) | `{typography.a-kicker}` uppercase, status color | `{typography.c-kicker}` |
| Peek title (session, setup message) | `{typography.a-peek-title}` | `{typography.c-peek-title}` |
| Detail line | `{typography.a-body}` | `{typography.c-body}` condensed caps |
| Actions | `{typography.a-action}` uppercase | `{typography.c-action}` |
| Tabs | `{typography.a-tab}` | `{typography.c-tab}` caps |
| Card title, column headers, day headers | `{typography.a-card-title}` uppercase | `{typography.c-card-title}` |
| Row primary (project, item name, event title) | `{typography.a-row-primary}` | `{typography.c-row-primary}` |
| Row status label, time left, relative time | `{typography.a-row-status}` | `{typography.c-row-status}` |
| Big numeral (usage %, next event, counters) | `{typography.a-numeral-big}` | `{typography.c-numeral-big}` |
| Command, path, last action, revealed secret | `{typography.a-code}` | `{typography.c-code}` in gold text |
| Prose (notes, empty states, setup text, onboarding copy, script documentation) | `{typography.a-body}` | `{typography.c-prose}` |
| Time tab row value (remaining time) | `{typography.a-time-value}` | `{typography.c-time-value}` |
| Status vocabulary label (`OK`, `WARN`, `DOWN`) | `{typography.a-row-status}` in the level hue | `{typography.c-row-status}` in the level hue |

Rules:

- Labels are short uppercase technical words, letter-spaced (0.14–0.26em). Values are numerals; A uses light weights (200–300), C uses mono.
- Numerals are tabular so live values (T+ counters, countdowns, percentages) don't jitter.
- Closed-notch labels and provider names are 7.5–8px in the mocks, set against the 34px band height. Legibility at that size on a real display is unverified (EXPERIENCE.md Open Questions).
- Settings and onboarding windows use native macOS system text styles, not these tokens [ASSUMPTION for onboarding: Settings is decided as a regular macOS window; onboarding's window type is not stated. Only previews inside them use Vigie tokens].

## Layout & Spacing

### Geometry (shared base)

| Surface | Size | Notes |
|---|---|---|
| Closed island | 540 × 34 | Two wings (156px each in the mocks) either side of the 196px hardware cut-out. Height = menu-bar height. |
| Peek | 700 × 150 | Grows out of the notch; top 34px is the black band. |
| Drop display | 700 × 196 | Drag-only. Grows out of the notch while a file is dragged over it; top 34px is the black band; peek width and radius. Replaces the earlier two-wing closed-notch drop zones (Story 1.7c). |
| Expanded | 720 × 420 | Grows out of the notch; top 34px is the black band with wordmark and clock. |
| Floating notes panel | 460 × 372 | Floats below the menu bar, centred; not attached to the notch; no band. |

[ASSUMPTION] 540px is the mock reference width for a 14-inch MacBook Pro. At runtime, wing width comes from the safe area beside the notch, capped by `closed.max_side_width` (SPEC §5.3); on a plain display the virtual notch width is user-set (SPEC §5.3, §5.5).

### Information placement (identical in both variants)

→ [`mockups/key-closed-notch-states.html`](mockups/key-closed-notch-states.html)

- **Closed, left wing:** AI usage, one quota dial per provider (3 slots by default), showing the Account of the most recent Session (PRD FR-29). The name under the ring is `CLAUDE` when the provider has one Account and `CLAUDE · WORK` when it has several [ASSUMPTION: Account name truncated to 6 characters on the wing]. With one provider: dial plus readout (value and label, e.g. `38 %` / `CLAUDE · WEEK`). With two or more: each dial carries its value inside, the provider name in small caps under it, no readout. In C, the bottom ruler and gold tracer start at the hardware cut-out, clear of the name area.
- **Closed, left wing = shared item lane** (decided 2026-11-07): quota rings, script side-slot items and the Time readout are all left-wing items, each with a priority. They are ordered by state (an item in alert first), then priority, fill the slots, and the rest collapse into `+X` exactly like sessions. The transient Image to Text `COPIED` readout sits after the first item for 2 s. None of them ever goes on the right wing. The single-provider readout layout applies only when one ring is the only left-wing item.
- **Closed, right wing:** agent sessions. Status glyphs only (3 slots by default), first slot nearest the notch, then `+X` when sessions overflow. No total count and no alert label. Nothing else ever takes the right wing, so an alert glyph is never hidden.
- **Closed, empty states:** a label only, on the right wing (`NO AGENT CONNECTED` or `NO ACTIVE SESSIONS`). With no provider, the left wing stays black.
- **Peek:** three-column grid `44px | 1fr | 176px`: beacon, text block (kicker, title, detail), action pair. A dwell timer runs along the bottom edge. The setup-problem peek drops the beacon. The break peek alone uses `44px | 1fr | 196px` for three actions.
- **Drop display:** black band (`DROP · 1 ITEM` left, `ESC · CANCEL` right), then a 4 × 2 zone grid (Components → Drop display).
- **Expanded:** black band (wordmark left, status and clock right), tab bar, then the tab body.
  - Home: grid of three equal columns, rows of 138px (`components.home-grid`); every card is one cell, 222 × 138, with no spans (decided 2026-11-07, one fixed card size in v1 [ASSUMPTION: size taken from the script card cell]). Cards fill left to right in the order set in Settings › Home; beyond two rows the grid scrolls inside the panel. Supersedes the mocked `1.2fr 1.2fr 1.1fr` × (162px, 138px) layout with spans.
  - Agents: one full-width card holding the session list.
  - Usage: 50/50. Provider cards on the left half (scrolling list beyond two providers); History · 7D and Cost · today stacked on the right half.
  - Shelf: Stash table card (`1fr`) and `SEND TO` card (212px: Ask AI, AirDrop, Image to Text).
  - Calendar: month card (300px) left, upcoming list right.
  - Time: quick-start card (84px) on top, running items card below.
  - Notes: list (232px) left, note preview right.
  - Script page: hero widget card across the top (118px), documentation card (`1fr`) and runs card (212px) below.
  - Tab row: tab bar, then the settings gear at the far right, apart from the tabs.

### Spacing tokens

Named tokens, no abstract scale: wing padding `{spacing.wing-padding-x}`, wing gap `{spacing.wing-gap}`, glyph gap `{spacing.glyph-gap}`, peek inset `{spacing.peek-inset-x}`, peek column gap `{spacing.peek-column-gap}`, grid gap `{spacing.grid-gap}`, card padding `{spacing.card-padding-y}` × `{spacing.card-padding-x}`, action gap `{spacing.action-gap}`, row gap `{spacing.row-gap}`.

### Containment

Every Vigie pixel is inside the island or panel outline, which clips its own content. In the closed state nothing is drawn below or beside the island: no hairlines, brackets, readouts, glows or grids on the menu bar or desktop. Hover reactions stay inside the island. Drop zones live inside the drop display's outline. Peek, drop display, expanded and notes panels draw only the panel itself, plus a neutral drop shadow. Scroll fades, thumbs and drag ghosts drawn by Vigie stay inside their card. Evidence for this rule: `imports/feedback-v2-still-outside-notch.png` (rejected v2 frames where hairlines and a `VIGIE · ONLINE` readout leaked below the notch).

### Presence mode (visual)

Presence mode is the animation intensity, chosen by the user: full or calm ("Calm mode"; behavior in EXPERIENCE.md, Presence mode).

| Level | A · Chrome Hologram | C · Twin Metal Tactical |
|---|---|---|
| **Full** (default) | Iris rim slides along the island edge (`{motion.ambient-loop}`); shimmer crosses the interior every `{motion.ambient-loop}`; expanded panel scan (`{motion.panel-scan}`); working arc spins; blocked diamond ripples; failed × stutters. | Gold tracer runs along the bottom scale (`{motion.ambient-loop}`); dial bezel turns (`{motion.dial-bezel}`); working tick ring turns; blocked brackets breathe; failed frame stutters. |
| **Calm** (lowest) | No shimmer, rim slide or scan. Iris rim becomes a flat platinum line inside the island edge. Working arc frozen. Quota arcs step back to flat silver. Only a blocked diamond or a failed × moves: one slow halo every `{motion.calm-pulse}`. | No tracer, no turning bezels, no breathing. Bezel and corner marks stay, static and dimmer. Gold steps back to silver (`{colors.c-dark-struct}`). Only a blocked square or a failed X frame pulses, every `{motion.calm-pulse}`. |

In calm, values still update, without transitions. When nothing is blocked or failed the notch is perfectly still. Intermediate settings between full and calm are not designed.

**Static loops (Calm mode and Reduce motion):** the Time peek rim, the breathing Ask AI `+` target, the card iris filament (`{motion.a-card-iris}`) and the drop display rim are static. Under Reduce motion, functional drains (peek dwell line, `COPIED` drain, notes clipboard drain) are never a smooth slide: each shows as a static full line that disappears at the end. Collapse and retract use `{motion.exit}` [ASSUMPTION: provisional]; peek and drop display grow over `{motion.peek-grow}` / `{motion.drop-display-grow}` [ASSUMPTION: provisional]; under Reduce motion they are instant or a short cross-fade. → [`mockups/key-closed-notch-states.html`](mockups/key-closed-notch-states.html) (state i), [`mockups/compare-a-vs-c-v3.html`](mockups/compare-a-vs-c-v3.html).

## Elevation & Depth

- The closed island has no shadow; it is the notch.
- Peek, expanded and notes panels cast a **neutral** drop shadow only (`components.*-panel.shadow-*`). Light looks use a lighter shadow with a tight secondary shadow.
- No colored glow escapes any outline. Inside the outline, dark looks may glow: A status glyphs carry a soft halo in their own hue; the A peek panel has a faint radial tint of the alert hue from below. **Light looks drop all glows**: halos read as smudges on light material, so shape and contrast carry status.
- Depth inside panels comes from tone: `surface-card` over `surface-panel`, with a 1px inner hairline (A: translucent platinum, C: struct corner marks).
- Interaction depth in lists: hover brightens a row (C: a 7% struct tint); keyboard selection adds a 1px ring (A platinum in dark, graphite in light; C `ink-1` at 55% in both modes) that stacks on top of any alert tint and, in C, on the 2px alert bar (`components.selection-ring`). The settings gear uses the same ring on keyboard focus (A light: the 1px graphite selection ring, no halo), plus in A dark a faint 3px cyan halo (14%).

## Shapes

| Token | Value | Use |
|---|---|---|
| `{rounded.island-closed}` | 14px | Closed island, bottom corners only (top is flush with the screen edge) |
| `{rounded.peek}` | 22px | Peek panel, bottom corners |
| `{rounded.expanded}` | 24px | Expanded panel, bottom corners |
| `{rounded.notes-panel}` | 16px | Floating notes panel, all corners |
| `{rounded.a-card}` | 16px | A widget and tab cards |
| `{rounded.a-setup-card}` | 14px | A in-tab setup card |
| `{rounded.a-zone}` | 13px | A drop zones (panels and drop display) |
| `{rounded.a-mini-zone}` | 11px | A AirDrop and Image to Text zones in the `SEND TO` card |
| `{rounded.a-row}` | 10px | A session, shelf and note rows |
| `{rounded.a-day-cell}` | 8px | A calendar today outline and selected-day tint |
| `{rounded.a-code}` | 5px | A inline command chip, secret mask |
| `{rounded.full}` | 9999px | A action buttons, A tab bar and tabs, A settings gear, beacons |
| `{rounded.c-card}`, `{rounded.c-action}` | 0px | C cards and actions: square, defined by inner corner marks |

The panels' radii grow with their size (14 → 22 → 24) so the expansion reads as the notch stretching. A is soft and pill-shaped; C is square with corner marks drawn *inside* its edges, never floating brackets outside.

## Components

Dimensions and slots are shared; skins restyle only.

### Closed island
→ [`mockups/key-closed-notch-states.html`](mockups/key-closed-notch-states.html)

`{colors.base-island}`, `components.island-closed`. Two wings, each `{spacing.wing-gap}` apart internally. Ornament (inside the outline only): A, iris rim 1px along the bottom and sides plus interior shimmer; C, 1px struct hairline inside the edge, small corner marks in the lower corners, a 3px tick scale and a 28px gold tracer along the bottom. On plain displays in `virtual_notch.style = "menu_bar"`, light looks fill the island with `surface-vn-top` → `surface-vn-bottom` and use the light role set.

**Band height.** The 34px `{spacing.band-height}` is the notched-MacBook case; on plain displays the virtual notch is exactly as tall as that display's menu bar (24 pt by default; `notch_overlap` applies to the hardware cut-out only) and closed-notch content scales to it: rings and glyphs cap at the band minus 2 pt per side, two-line readouts scale down together, and a dial drops the name under it (Story 2.16).

**Hover reaction** (inside the outline, enters over `{motion.enter}`): A, the iris rim goes to full strength, the interior lifts and one shimmer passes; C, hairline and corner marks brighten and the gold tracer runs once.

### Quota dial
→ [`mockups/key-closed-notch-states.html`](mockups/key-closed-notch-states.html) (states c, f, g), [`mockups/key-usage-tab.html`](mockups/key-usage-tab.html)

24px (23px in the stacked multi-provider layout; 58px on the Usage tab). Track ring in `line`. One dial per provider, up to three in the closed notch.

- **Nesting:** when two windows are tracked, inner = 5h (thicker, primary fill), outer = weekly (thinner, A silver / C struct). This holds in the multi-provider layout too.
- **Value inside:** the 5h value, or the only window the plan has (weekly for Ultra, daily for Gemini CLI).
- **Single window:** one ring at single-ring size in the primary fill. No empty inner ring.
- **Fill:** within pace = `pace-on` (A: iris gradient in the closed notch, platinum on the Usage tab; C: Volt `{colors.c-dark-pace-on}`). Ahead of pace = `pace-ahead` (A Ember `{colors.a-dark-pace-ahead}`, C gold `{colors.c-dark-pace-ahead}`). Quota warning replaces both with `quota-warning` and puts a triangle on the ring centre.
- **Pace marker:** a short radial tick at the elapsed-time position of the paced window (5h, or weekly when there is no 5h), with a 1px black keyline so it reads over any arc. Within pace (the healthy state), the arc ends at or before the tick, or past it by no more than the tolerance; ahead of pace, it runs further past it.
- C adds a dashed tick bezel (r 11.2) turning every `{motion.dial-bezel}`.
- Calm: arcs step back to flat silver.

[ASSUMPTION] The quota-warning treatment of the closed-notch ring (23–24px) is not mocked: warning hue on the arc plus a triangle in place of the value, mirroring the Usage ring.

### Readout
Value over label (`typography.*-readout-value` / `*-readout-label`). Used on the left wing with a single provider, by the left-wing non-session items (side-slot item, Time readout, `COPIED` readout), and as the label-only empty state on the right wing (`NO AGENT CONNECTED`, `NO ACTIVE SESSIONS`, in `ink-3`).

### Status glyph
16px slot (26px large in legends and peek beacon). Shapes are fixed per variant and never change with color:

| State | A shape | A motion | C shape | C motion |
|---|---|---|---|---|
| idle | Hollow ring | None | Dot in circle | None |
| working | Turning open arc (¼ ring) | Spin `{motion.working-cycle}` | Triangle inside a tick ring | Ring turns `{motion.working-cycle}` |
| done | Ring + check, tinted fill | None | Check in circle | None |
| blocked | Solid diamond (45° square) with ripple outline | Ripple `{motion.blocked-cycle}` | Solid square inside four corner brackets | Brackets breathe `{motion.blocked-cycle}` |
| failed | Cross (×) | Double stutter `{motion.failed-cycle}` | X inside a square frame | Double stutter `{motion.failed-cycle}` |

Failed shares blocked's period because the two share top priority; it stutters (two quick blinks) instead of rippling so the two stay distinct. Light looks: same shapes and motion, no halos.

**Stale and process-only** (decided 2026-11-07, Story 1.7b, Option 3; → [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) 1.7b). Neither borrows a live-state shape, so a stale session is never misread as still working. Both are static in every Presence mode, have no hue, no halo and no motion, and render in all four looks from the look's own `ink-3` / `ink-2` (the island always uses the `*-dark-*` values).

| Look | Stale | Process-only |
|---|---|---|
| A | Dashed ring (r 6.6 in the 16px slot, 1.1px stroke, dash 2.1 / 1.8) in `ink-3`, with a `?` inside (SF Pro 600 9px) in `ink-2`. Replaces the last glyph. | Plain filled dot, 5.6px, in `ink-3`, no ring |
| C | Dashed ring (r 7, 1px stroke, dash 1.6 / 1.6) in `ink-3`, `?` in SF Mono 600 9px in `ink-2` | Same dot as A, in `ink-3` |

In rows the status label is in `ink-3`: `STALE · 18M` (time since the last event) and `RUNNING` (no time). The last-action line reads `LAST EVENT 14:30 · <last action>` for stale and `Process seen · no hook events` for process-only, in `ink-3`. They sort after idle. No row tint.

### Status vocabulary (shared primitive)

→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7d, Direction 2)

One three-level vocabulary for any module that reports a health or result level: scripts (status widgets, side slot, script page) and any first- or third-party module. Modules call the primitive (`components.status-vocabulary`) with a level; they never pick colors. No script- or module-specific colors exist (decided 2026-11-07).

| Level | Shape | Hue (role, per look) | Label |
|---|---|---|---|
| OK | Hollow ring | `status-idle` | `OK` |
| WARN | Triangle | `quota-warning` (glyph); `quota-warning-text` for the label in light looks | `WARN` |
| DOWN | Cross (×) | `status-failed` | `DOWN` |

- Shape, hue and label always travel together; the label may take a qualifier after a `·` (`OK · UP`).
- Sizes: 26px on cards and the script page, 16px in the closed-notch side slot, 10px inline. Stroke 2px (ring) and 3px round-capped (×) at 26px.
- The hues follow the user's status-color settings (they are the same roles), so a recolored `idle` also recolors `OK`.
- Static: no motion in any Presence mode. In the closed notch the item always sits on the left wing with its `OK` / `WARN` / `DOWN` label, which keeps it apart from session glyphs (right wing, no label).

### Overflow count
`+X` after the visible items on either wing, in readout-label style and `ink-3`. Right wing: sessions that don't fit; nothing else on the wing counts sessions. Left wing: lower-priority items that don't fit (rings, script items, Time readout), same style and position (after the last visible item).

### Drop display (drag-only)
→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7c, Option B)

*Supersedes the closed-notch drop zones (two wings swapped for Stash and Ask AI, `key-closed-notch-states.html` state e), decided 2026-11-07.* A dedicated display attached to the notch, shown only while a file is dragged over the notch. It is not the expanded panel and not a peek.

- **Frame:** `components.drop-display`, 700 × 196, peek radius `{rounded.peek}`, 34px black band, neutral peek shadow; body in `surface-panel` (dark looks drawn in the mock; light looks switch the body to the light material like a peek). Ornament as the peek, A iris rim at half strength, no shimmer.
- **Band:** `DROP · 1 ITEM` left (count in `ink-2`, the rest `ink-3`, readout-label style) and `ESC · CANCEL` right, `{spacing.drop-band-padding-x}` from the edges.
- **Grid (layout B):** 4 columns × 2 rows, inset `{spacing.drop-grid-top}` top, `{spacing.drop-grid-inset-x}` sides, `{spacing.drop-grid-bottom}` bottom, gap `{spacing.drop-grid-gap}`.
  - **Stash** (primary): columns 1–2, rows 1–2. 22px tray icon, label `STASH` (A 11px, `ink-1`), meta `KEEP 7 DAYS · 5 ITEMS`. A: 3.5% fill, 1px hairline at 9%.
  - **Ask AI:** column 3, rows 1–2. Dashed 1px border (A lilac at 35%, C gold at 55%), round 22px `+` target, label `ASK AI` (A lilac, C gold text), hint `⌥ ALT FOLDER`.
  - **AirDrop:** column 4, row 1. 18px AirDrop icon, label `AIRDROP`, meta `NEARBY DEVICES`. A: 2% fill, 1px hairline at 7%.
  - **Image to Text:** column 4, row 2. 18px image-with-T icon, label `IMAGE TO TEXT`, meta `COPY TEXT`. Same style as AirDrop.
  - Labels 9px tracked caps in `ink-2`, metas 7.5px in `ink-3` (A); C uses `c-card-title` / `c-row-status` sizes, struct inner borders at 22%, square zones.
  - VoiceOver labels name the zone and its meta, e.g. "Stash, keep 7 days, 5 items", "Ask AI, Claude Code in ~/dev, Option for alternate folder".
- **Reflow when zones are hidden:** a disabled zone is removed and its neighbour takes the space. Image to Text off (the default): AirDrop spans rows 1–2 of column 4. AirDrop off: Image to Text spans rows 1–2 of column 4. Both off: column 4 is removed and the grid becomes 3 columns (Stash 2, Ask AI 1) [ASSUMPTION: only the Image-to-Text-off reflow was mocked].
- **Drag-hover** (any zone): solid 1px border (A lilac, C gold), an inner tint and a 3px inner halo at 10% (A); the label goes to `ink-1` and the meta is replaced by the release line in the accent, set at label size (9px A / `c-card-title` C), not meta size: `RELEASE TO STASH`, `RELEASE TO ASK` (names agent and folder as in panels), `RELEASE TO SHARE`, `RELEASE TO COPY TEXT` [ASSUMPTION: the Image to Text hover line was not mocked]. Over Ask AI with ⌥ held, the hint reads `ALT FOLDER` lit and the drag ghost carries an ⌥ badge.
- A zone that does not accept the dragged item (Image to Text with anything but an image or PDF) stays unlit and shows no release line.
- Cursor and drag ghost are macOS.
- **C** look of the drop display was not mocked [ASSUMPTION: C applies its existing drop-zone rules: struct inner border at 22%, Ask AI dashed gold at 55%, hover solid gold with a 16% gold gradient, release line in `gold-text`].

### Copied readout (Image to Text confirmation)
→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7c)

After a drop on Image to Text, the left wing shows `COPIED · 3 LINES` (readout-label style, `ink-1`) after the first left-wing item (the last visible item steps into `+X` meanwhile) for `{motion.confirm-readout}`, with a 1px line (`ink-1` at 60% over a `line` track, 6px above the island bottom) draining left over the same 2 s. No peek, no sound, no hue. When recognition finds no text the same readout reads `NO TEXT FOUND`. The readout holds while the pointer is over the notch, and posts a VoiceOver announcement ("Copied 3 lines" / "No text found"). Then the wing returns to normal; a lasting trace stays as the Image to Text meta in the `SEND TO` card: `LAST · 3 LINES · 14:48`. Under Reduce motion the drain is a static full line that disappears at the end. The right wing is never touched.

### Peek alert panel
→ [`mockups/key-alert-variants.html`](mockups/key-alert-variants.html)

`components.peek-panel`. Content inset `{spacing.peek-inset-x}`, starting just under the band.
- **Beacon** (44px): A, a round radial tint in the alert hue with a 1px inner ring; C, a faint square with corner brackets in the alert hue. Holds the large glyph.
- **Kicker:** state and reason in the alert hue (`BLOCKED · NEEDS INPUT`, `FAILED · HOST SLEPT`, `DONE`), followed by a live `T+` counter in `ink-3` for blocked and failed only. Done has no counter. Under Reduce motion the counter is static.
- **Title:** `project / branch-or-path` in `ink-1`, separator in `ink-3`.
- **Detail:** agent and pending request or last action; the command sits in a code chip (A: rose text on a 7% rose tint, `{rounded.a-code}`; C: gold text, no chip).
- **Edge:** A, the iris rim takes the alert hue and runs at `{motion.blocked-cycle}`; C, hairline and corner marks take the alert hue.
- **Dwell timer:** 1px line along the bottom (inset 26px, 12px up) draining left over `{motion.peek-dwell}`, in the alert hue (A gradient; C solid, over a tick scale).
- Variants: blocked (blocked hue, diamond / bracketed square), done (done hue, ring + check / check in circle), failed (failed hue, × / X-in-square, stuttering).
  - **Sleep summary** (several sessions interrupted by sleep, one alert on wake): failed hue and × beacon, kicker `FAILED · HOST SLEPT`, title `<n> sessions interrupted by sleep`, actions `OPEN AGENTS ⌥⌘↵` / `DISMISS ⌥⌘⌫`. No `T+` counter.
  - **Calendar reminder** (an event's own Calendar alarm time; decided 2026-11-07) [ASSUMPTION: copy, beacon and hue]: reuses the peek anatomy with the variant's "now" accent, never a status hue or the event's calendar color (A `iris-1` rim, beacon tint and dwell line; C `gold`, kicker in `gold-text`). Beacon: a 26px event-track mark (a short track with the now marker). Kicker `CALENDAR · IN 10 MIN` (`CALENDAR · NOW` at start time) with the start time in `ink-3`; title the event title; detail `14:00–14:30 · <calendar>`, plus a video tag when the event has a link. Two actions: `JOIN CALL ⌥⌘↵` when the event has a video link [ASSUMPTION], else `OPEN CALENDAR ⌥⌘↵`; `DISMISS ⌥⌘⌫`. Standard dwell; nothing stays on the closed notch after it retracts.
  - **Quota warning** (when the provider's warning is set to alert) [ASSUMPTION: copy and beacon]: beacon = triangle in `quota-warning` (A round tint, C bracketed square), kicker `QUOTA · WARN`, title `<PROVIDER> · <WINDOW> 82 %` (Account appended when the provider has several, e.g. `CLAUDE · WORK · 5H 82 %`), detail `RESET 16:40 · IN 1H52`, actions `OPEN USAGE ⌥⌘↵` / `DISMISS ⌥⌘⌫`. Rim and dwell line in `quota-warning`; kicker text in `quota-warning-text` on light bodies.
- Every peek posts a VoiceOver announcement (kicker + title + primary shortcut); each action button's accessibility label includes its shortcut.
- **Time peeks** (Story 1.7e; → [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) 1.7e) use the Time accent instead of a status hue for the rim, beacon tint, kicker and dwell line (A: cyan rim and dwell gradient cyan → lilac, beacon a 16% cyan radial with a 28% cyan inner ring). The beacon holds a 26px time ring.
  - **Timer end:** full solid ring; kicker `TIMER · ENDED` with the end clock time (`14:48`) in `ink-3`; title `Tea / 5 min`; detail `Started 14:43 · ended 14:48`; actions `OPEN TIME ⌥⌘↵` and `DISMISS ⌥⌘⌫`. Standard dwell.
  - **Break** (break reminders and Pomodoro work-phase ends with strength "peek"; a Pomodoro break waits for Start break): full dashed ring; kicker names the source (`POMODORO · LONG BREAK`; for a break reminder `BREAK · DUE` [ASSUMPTION: only the Pomodoro kicker was mocked]); title `4 cycles done / 15 min break`; detail `Focused 1 h 40 min since 13:05`. **Three actions**, the one scoped exception to the two-action peek rule (decided 2026-11-07): `START BREAK ⌥⌘↵` primary across the full action width, then `SNOOZE 5M ⌥⌘Z` and `SKIP ⌥⌘⌫` side by side, sharing the same secondary styling. `⌥⌘Z` is registered only while the break peek is visible. After the peek retracts, the left wing keeps the `BREAK DUE` readout (Time readout below). The action column widens to 196px (`components.peek-panel.columns-three-actions`).

### Setup-problem alert
→ [`mockups/key-alert-variants.html`](mockups/key-alert-variants.html) (variant 4)

Same peek frame and dwell, deliberately unlike an agent alert: no beacon, no status glyph, no status hue, no Focus terminal. Neutral ink and a static neutral rim. Kicker `SETUP` tag plus category (`ADAPTER · VERSION CHECK`); the problem itself is the title (`Codex adapter: CLI version 0.9.2 unsupported`); one factual detail sentence. Actions: `OPEN SETTINGS ⌥⌘↵` and `DISMISS ⌥⌘⌫`, Dismiss styled like the agent alerts' Dismiss. The target pane is named beside the actions in `ink-3` (`SETTINGS › AGENTS › CODEX`).

### Setup card (in-tab)
→ [`mockups/key-calendar-tab.html`](mockups/key-calendar-tab.html) (state 03)

The in-tab equivalent of the setup-problem alert, for a module that can't work (e.g. calendar access not granted). `components.setup-card`: centred, neutral 1px inner outline (A platinum at 16% dark, graphite at 14% light), 2.5% fill, an `i`-in-square mark, a `SETUP · <topic>` kicker, a title, one sentence, two buttons. No status glyph or hue.

### Empty state block
→ [`mockups/key-usage-tab.html`](mockups/key-usage-tab.html), [`mockups/key-shelf-tab.html`](mockups/key-shelf-tab.html)

Centred in the tab body or card: uppercase label in `ink-3` (`NO USAGE PROVIDER`, `STASH EMPTY`, `NO EVENTS TODAY`), one factual sentence in prose style, and an optional button to the relevant Settings pane.

### Action button
`components.action-button`, 30px, two stacked, `{spacing.action-gap}` apart, label left and shortcut (`⌥⌘↵`, `⌥⌘⌫`) right.
- A: pill, 1px platinum border at 22%, faint glass gradient; secondary has no fill and a dimmer border. Light: white → `#EEF1F5` fill with a 1px shadow.
- C: square, 1px struct inner border at 30%; primary has a gold inner frame, gold-text label and a gold gradient fill (16% → 3%).
- Inline variants in rows (`FOCUS ↵`, `JOIN CALL ↵`, `COPY`, `REVEAL`) are small chips in `{typography.a-action}` / `{typography.c-action}`.

### Expanded panel
`components.expanded-panel`. Band: wordmark `VIGIE` (A iris-gradient text, letter-spacing 0.5em; C condensed caps with a gold `·`), then status `● Online · 14:48 · Wed 04 Nov` on the right in `ink-2`, the dot in `status-idle`. A adds a slow vertical scan (`{motion.panel-scan}`) inside the body.

### Tab bar
30px. A: pill container (3.5% white, 1px inner hairline), active tab a raised pill. C: a 1px `line` underline across the whole tab row, active tab in gold text (`gold-text`) with a 2px gold underline. A tab whose module needs attention carries a 5px blocked-hue marker (A diamond, C square); the Time tab uses the same marker while a break is due. VoiceOver reads it as "<tab>, needs attention". Mocked order: `Home · Agents · Usage · Shelf · Calendar · Time · GitHub PRs · Notes` (a script with a page adds its own tab, e.g. `vigie.app`).

### Settings gear
→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7a, Design; 1.7f for C)

Decided 2026-11-07. A detached button at the far right of the tab row, apart from the tab pill, `{spacing.tabs-margin-x}` from the panel edge, `{spacing.tab-row-gap}` from the tabs; always visible on every tab. 14px outline gear, 1.2px stroke (`components.settings-gear`). It is not a tab: it never takes the active state and has no `⌘1–9` slot.
- **A:** 24px round. Default `ink-3`, no container. Hover: a raised pill like an active tab (white 12% → 3% gradient, 1px inner hairline at 16%), icon `ink-1`. Keyboard focus: dark, 1px platinum ring at 55% plus a 3px cyan halo at 14%; light, the A light selection ring (`components.selection-ring.a-light`, 1px graphite `#161B24`), no halo (platinum at 55% would measure 1.05:1).
- **C:** 26px square. Default `ink-3`. Hover: icon `ink-1` and a 1px struct inner border at 30%. Keyboard focus: the C selection ring (`components.selection-ring`).
- The macOS tooltip `Settings (⌘,)` appears after the usual delay (system, not Vigie). Accessibility label `Settings`.

### Widget card
`components.widget-card`. Header row 11px: title (card-title) left, meta (e.g. `RESET 16:40`, `SORTED BY URGENCY`, `1 EXPIRING · TTL 7D`) right in `ink-3`. A: 1px iris filament along the top edge at 45% (80% light), animating every `{motion.a-card-iris}`. C: four 7px inner corner marks in struct at 38%. Tab bodies reuse the same card frame.
- **Home cards** (decided 2026-11-07): one fixed size, 222 × 138 (`components.home-grid`), no spans, no in-place edit mode, no grip on Home (order is set in Settings › Home). Catalog: sessions (most urgent rows, `18px | 92px | 1fr | 64px`), quota (each provider's ring and main window with reset), shelf (stash list with Stash and Ask AI zones), calendar (next event with the event track), script widgets (Script widget below), and any other module that offers `homeCard()`. Content that doesn't fit the cell fades under the bottom mask; the card's tab holds the rest.

### Scroll and reorder affordances
Lists that overflow their card fade the last row under a bottom mask and show a thin thumb inside the card's right edge (2px on Agents, a 3px track on Usage). A `SCROLL ↓` hint may sit in the footer. Reorderable cards carry a 6-dot grip in their header (Usage providers, Shelf rows).

### Session row
→ [`mockups/key-agents-tab.html`](mockups/key-agents-tab.html)

30px. Agents tab grid `18px | 84px | 1fr | 62px | 104px | 76px`: glyph, agent, project with last action below (`{typography.a-code}`-sized mono, `ink-3`), terminal, status label `· T+` (e.g. `BLOCKED · 12M`), Focus chip. Without the terminal column, project · last action takes its width. Home widget rows keep `18px | 92px | 1fr | 64px`.
- Alert rows (blocked, failed) are tinted: A, a 10% horizontal fade in the state hue with a 1px inner outline; C, the same fade plus a 2px left bar in the state hue. In dark looks the secondary line (last action, separators) on a tinted row is set in `ink-2`, not `ink-3` (contrast).
- Hover brightens the row and shows `FOCUS`. Keyboard selection adds the 1px selection ring and the `↵` hint. A row with no pointer or selection on it shows no button.
- Header line: `SESSIONS · 9 · 3 ALERTS`, keyboard hints `↑↓ SELECT · ↵ FOCUS · ⌘1–9 TABS · ESC`, meta `SORTED BY URGENCY`, column headers `AGENT · PROJECT · LAST ACTION · TERMINAL · STATUS · T+`.

### Usage provider card, meter and pace bar
→ [`mockups/key-usage-tab.html`](mockups/key-usage-tab.html)

One card per provider Account: header with grip, provider name (plus ` · <ACCOUNT>` when the provider has several Accounts, e.g. `CLAUDE · WORK`) and meta (`MAX · WARN 80%`, `ULTRA · WEEKLY ONLY`, `DAILY QUOTA ONLY`); a 58px dial with the big value; one bar per window with value, reset (`RESET 16:40 · IN 1H52`) and a pace line (`ELAPSED 63%` + pace label).
- **Bars:** 5h in platinum metal, weekly in darker silver (A); C uses `pace-on` Volt for on-pace fills.
- **Pace marker:** a 2px platinum bar at the elapsed-time position.
- **Threshold marker:** a dashed tick at the warning threshold on every bar.
- **Ahead of pace:** solid `pace-ahead` fill on the bar and its ring, label `AHEAD OF PACE · +9`, no glyph.
- **Within tolerance:** metal fill, label `WITHIN PACE` or `WITHIN PACE · +3`.
- **Quota warning:** `quota-warning` with a hatched fill (`components.quota-warning-fill`, 135°, 3px solid / 2px at 40%), a triangle and `WARN · ≥ 80%`, plus a triangle on the ring centre. Wins over pace-ahead.
- **Right half:** `HISTORY · 7D` tokens chart (all agents, one series per agent, weekday initials) and `COST · TODAY` estimate with per-project rows and source line `FROM LOCAL LOGS · OFFLINE`.
- **Footer** (more than two providers): `DRAG TO REORDER · ALSO IN SETTINGS` and `SCROLL ↓`.

### Drop zone (in panels)
→ [`mockups/key-shelf-tab.html`](mockups/key-shelf-tab.html), [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7c Shelf tab, 1.7f C)

Stash and Ask AI, plus AirDrop and Image to Text on the Shelf tab. Stash: A, 3% fill and 1px hairline; C, plain with file rows ruled by struct hairlines. Ask AI: dashed 1px border (A lilac at 35%, C gold at 55%), a round `+` target (A breathes on `{motion.calm-pulse}` in dark; static in light) and the label `ASK AI`.
- **Drag-hover:** solid lilac border (C gold) with an inner tint; label becomes `RELEASE TO ASK` and names agent and folder. With ⌥ held, the default folder row dims and the `⌥ FOLDER` row lights up; the drag ghost carries an ⌥ badge.

**`SEND TO` card** (Shelf tab right card, decided 2026-11-07; `components.send-to-card`, 212px). Header `SEND TO`, meta `DEFAULTS`. From top:
1. Ask AI zone, shortened from 118 to 84px, with `ASK AI` and `Drop a file to start a session`; its defaults stay below it (`AGENT`, `FOLDER`, `⌥ FOLDER`). The hint sentence that sat under the defaults is dropped.
2. At the bottom of the card, two 38px mini zones, `{spacing.mini-zone-gap}` apart: **AirDrop** (meta `SHARE`) and **Image to Text** (meta `COPY`). Icon, label left, meta right. A: radius `{rounded.a-mini-zone}`, 2% fill, 1px hairline at 8%, label 8.5px tracked caps in `ink-2`, meta in `ink-3`. C: square, struct inner border at 22%, label in `c-card-title` style, meta in SF Mono.
A disabled zone is not drawn (Image to Text is off by default). Drag-hover on a mini zone follows the zone rule above.

### Shelf row
→ [`mockups/key-shelf-tab.html`](mockups/key-shelf-tab.html)

Columns: item (name, then `size · mode` where mode is `REF`, `COPY` or `SAVED`), source app, added, expires. Expires shows time left (`6D LEFT` at 2 days or more, `1D 18H LEFT` under 2 days, `EXPIRES IN 5H` under 24 h) over a thin metal bar for the fraction of TTL left.
- **Expiry warning** (last 24 h): quota-warning yellow (text in `quota-warning-text` on light looks) plus a small triangle on the row, `1 EXPIRING` in the card meta.
- **Pinned:** A, dashed lilac line and `PINNED` in place of the time left. C (no lilac role, and gold is not for "pinned"): a dashed struct line and `PINNED` in `ink-1` (decided 2026-11-07, 1.7f).
- **Hover:** `QUICK LOOK · REVEAL · PIN` chips replace the source and added columns; the grip shows `DRAG · MOVE  ⌥ DRAG · COPY`.
- **Footer:** `DRAG OUT MOVE · ⌥ DRAG COPY · ␣ QUICK LOOK`, then the expiry rule.
- **Home shelf widget:** the expiring item moves to the top of the stash list with a `5H` tag, and a warning line (`1 EXPIRES IN 5H`) runs along the zone's bottom.

### Month grid
→ [`mockups/key-calendar-tab.html`](mockups/key-calendar-tab.html), `imports/ref-itsycal-month.png`

Itsycal structure in a 300px card (`components.month-grid`): header `NOVEMBER 2026` with `‹ ● ›`, weekday initials (Monday first), ISO week-number column, day cells 36 × 37px. One dot per calendar with events that day (macOS calendar color), no count. Adjacent-month days dimmed. A 1px platinum line at 28% traces the month's days, inside the card. Calendar legend under the grid.
- **Today:** 1px outline in the "now" color: A `iris-1`, rounded; C `gold`, square, with the day number in `gold-text` (`c-light-gold-text` in C light). Decided 2026-11-07 (1.7f); the ink-1 alternative was rejected.
- **Selected day:** platinum tint with a hairline. Both show when the selected day is not today.
- **Header dot:** dim when today is in view and selected; lit in the now color when the user can jump back.

### Upcoming list and event track
→ [`mockups/key-calendar-tab.html`](mockups/key-calendar-tab.html)

Grouped by day headers (`TODAY · WED 04 NOV`, `THU 05 NOV · TOMORROW`); all-day events are a chip on their day header. The next event is a hero row: big numeral time, title, relative time (`IN 42 MIN`, A cyan, C `gold-text`), a 1px track from now to the event with a "now" marker (A cyan dot, C gold diamond), and `JOIN CALL ↵` only when the event has a video link. Other rows: time · calendar dot · title (+ video tag) · calendar · relative time. At most 5 events, then `+N LATER THIS WEEK`. The same track serves the Home calendar card.

### Script widget
→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7d, Direction 2)

Rendered by core templates in the card frame (`components.script-card`, Home cell 222 × 138). Three v1 types: **status**, **number**, **short text**. Header: the script's name and target (`SITE · VIGIE.APP`) left, cadence (`EVERY 1M`) right.
- **Status** (decided 2026-11-07): a 26px status-vocabulary glyph, then the level label (`OK` / `WARN` / `DOWN`, row-status style in the level hue) over the value line (`200 · 142 ms`, `{typography.a-peek-title}` in `ink-1`, unit in `ink-2`), on a `26px | 1fr` grid. Under it a meta line in `ink-3`: `CHECKED 2 MIN AGO`, or `DOWN SINCE 14:44` when down.
- **Number:** the mocked `GitHub PRs · 3 open · Warn ≥ 5` uses the big numeral and a segmented 6px bar (A platinum → silver segments, C silver → white), with the warn threshold segment outlined in the quota-warning yellow (the older mock shows the working hue).
- **Short text:** a `TEXT` label in `ink-3` over the value (`Fri 14:00 · release/0.3`, peek-title style, `ink-1`), then `UPDATED 4 MIN AGO`.
- **Errored:** keeps the last good output with a warning badge (SPEC §9.2) [ASSUMPTION: the badge is the status-vocabulary WARN triangle on the meta line; not mocked].
- C applies the same layout with C type and card rules [ASSUMPTION: script widgets were mocked in A dark only].

### Side-slot item
→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7d)

A script (or any module) shown in the closed notch is an item on the **left-wing lane**, placed by its priority (lower ones collapse into `+X`): a 16px status-vocabulary glyph (status scripts) followed by a readout, value over label: the level (`OK`, `WARN`, `DOWN`) in the level hue over the target (`VIGIE.APP`) in `ink-3`. Number and short-text scripts show their value over their label, no glyph. Static.

### Script page
→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7d)

A tab named after the script (`vigie.app`). Grid `components.script-page` (`1fr 212px` × `118px 1fr`):
- **Hero** (full width, 118px): header `SITE · VIGIE.APP` / `STATUS WIDGET · EVERY 1M`; the widget at large size: 26px glyph, label with qualifier (`OK · UP`), value line `200 · 142 ms · https://vigie.app`, and `CHECKED · 2 MIN AGO`.
- **About** (left): header `ABOUT` / `FROM vigie-site.md`; the script's Markdown documentation rendered in prose style (title in peek-title style, lists, inline code in a code chip; `ink-3` for asides).
- **Runs** (right, 212px): a label/value list, labels in card-title style (`ink-3`), values in `ink-1` with a mono sub-line in `ink-3`: `RUNS` (runtime, e.g. `bash`), `LAST RUN` (`14:46:12`, `exit 0 · 0.4 s`), `NEXT RUN` (`14:47:12`, `in 38 s · every 1 m`), `TIMEOUT` (`10 s`), `SOURCE` (`vigie-site.md`, `~/Vigie/scripts/`). Then chips `REVEAL` and `OPEN SOURCE`.

### Time readout (closed notch)
→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7e)

An item on the left-wing lane, placed by the Time module's priority, for the running item nearest its end. Three variants, a user setting: **time only** (readout: `18:42` over `WORK · 2/4`), **ring only** (23px ring, the accent arc = time left, track in `line`), **ring + time**. Arc: solid during work and plain timers, dashed (2.2 / 2) during a break. Values in tabular numerals.
- **Away · paused:** ring and value freeze in `ink-3` / `ink-2`, label `AWAY · PAUSED`. In ring-only mode a center pause mark (two 1px bars) is added, so the state is not told by color alone.
- **Break due** (a break reminder or Pomodoro work-phase end: after the break peek retracts, or at once with strength "quiet"): a full dashed ring, `15:00` over `BREAK DUE`, static, until the break is started or skipped; Snooze keeps it showing. It is a left-lane item in alert state and shows **even when `[modules.time] closed_notch = "off"`**. In ring-only mode a small center triangle is added. A Pomodoro break never starts on its own.
- A light arcs use `iris-1` `#126F8C` (`components.time-ring.a-accent-light`).

### Phase indicator
Pomodoro progress as pips (`components.phase-pips`): done = filled 4px dot in `ink-1`; current = 7px ring in the Time accent, hatched during a break; upcoming = 4px hollow ring in 1px `ink-3` (shape, not only lightness, tells it from done). VoiceOver reads the pips as "Work, cycle 2 of 4". Beside it the phase label and count (`WORK · 2/4`, `BREAK · 2/4`, `LONG BREAK · 4/4`). Used in the Time tab rows and, as label only, in the closed readout.

### Time tab
→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7e)

Grid `components.time-tab`: rows `84px | 1fr`.
- **Quick start** card on top (meta `↵ START`): a `POMODORO` button showing its lengths (`25 · 5 · 15`, accent-tinted border), preset buttons `5 MIN`, `10 MIN`, `25 MIN`, `+ COUNTDOWN` (countdown to a clock time, date optional) [ASSUMPTION: chip label], then a custom field (minutes) with a `START ↵` chip, right-aligned. Buttons are 34px pills (A) with the value in light numerals.
- **Running** card below (`RUNNING · 3`, meta `SORTED BY END TIME`): rows 62px on `30px | 1fr | 92px | 196px`: a 30px time ring (or, for a Countdown, a short track with a now dot); name (`ink-1`) over kind (`5 MIN TIMER`, `WORK · CYCLE 2/4` with pips, `COUNTDOWN · FRI 14 NOV · 14:00`); remaining time (`{typography.a-time-value}`, right-aligned) over `ENDS 14:52` / `IN 191 H`; chips `PAUSE` (or `RESUME`), `RESET`, `REMOVE`. A Countdown has only `REMOVE`. Chips have a hit area at least 24px tall and 8px gaps.
- **Break due:** the row shows `START BREAK` (primary chip, Time accent), `SNOOZE 5M` and `SKIP`; the Time tab carries the attention marker (Tab bar) while a break is due.
- **Ended:** an ended Timer stays as `ENDED 14:48` with a `DISMISS` chip until acknowledged.
- **Away:** the row's ring and value go to `ink-3` / `ink-2`, the kind line reads `AWAY · PAUSED` with a pause mark, the end line reads `PAUSED 14:31`, and `PAUSE` becomes `RESUME`.
- C [ASSUMPTION: not mocked]: C type, square chips and cards, gold accent.

### Twin Metal Tactical expanded tabs and notes panel
→ [`mockups/key-design-pass-1-7.html`](mockups/key-design-pass-1-7.html) (1.7f, C dark and C light)

Decided 2026-11-07: every C surface follows C rules strictly, never A recolored. Same layouts, wording and slots as A; only the skin changes:
- Tab row: a 1px `line` underline across the row, active tab in `gold-text` with a 2px gold underline, square settings gear at the far right.
- Cards: square, four inner corner marks in struct; values in SF Mono, labels in Avenir Next Condensed caps, prose in SF Pro.
- Action chips square with a struct inner border at 30%; inline `FOCUS ↵`.
- Alert rows: the state-hue fade plus a 2px left bar, secondary line in `ink-2` in C dark; keyboard selection ring `ink-1` at 55% stacks on top; hover a 7% struct tint.
- Usage: within pace Volt, ahead gold, quota warning yellow with hatch + triangle + `WARN`; the live usage value in `gold-text`; History today bar in gold.
- Shelf: rows ruled by struct hairlines, pinned = dashed struct line + `PINNED` in `ink-1`; `SEND TO` card with the dashed gold Ask AI zone.
- Notes panel (460 × 372, no band): struct corner marks, title in condensed caps with a gold `·`, mono meta; secret block with a 2px struct left bar; a copied secret gets a gold frame; the clipboard drain line in gold.
- Gold appears only on the active tab, the live usage value, ahead of pace, the Ask AI target, the copied secret, and "now" (Calendar today, now marker, relative time, Time accent).
- C light: brushed-aluminium panel, the black band keeps the dark role set; gold text in `c-light-gold-text` `#765709`, `#A07418` only on frames, underlines, arcs and fills.

### Floating notes panel
→ [`mockups/key-notes.html`](mockups/key-notes.html)

`components.notes-panel`, `surface-panel` body, no black band, the iris filament from widget cards along its top. Header `NOTES · <title>` with `SYNCED · ENCRYPTED · ESC` on the right. Footer: edit time (`EDITED 14:31`) and, after a copy, `COPIED · CLEARS IN 30S` with a 1px line draining over the clipboard-clear delay.

### Secret mask
→ [`mockups/key-notes.html`](mockups/key-notes.html)

- **Inline** (`||…||`): fixed-width dots, so the length is not given away, in a `{rounded.a-code}` chip. Hover brightens the outline and shows `COPY`. Revealed: plain text in the rose code tint (A `iris-3` on its 7% tint). Copied: cyan outline and `COPIED`.
- **Block** (` ```secret `): a card with header `SECRET · 4 LINES`, `REVEAL` and `COPY` chips, and rows of fixed-width dots.
- **Notes tab:** list (232px) with title, last edit and a one-line summary that never shows secret text, only the secret count (`2 SECRETS`); preview on the right with every secret masked; search field and note count on top.

### Privacy mode (visual)

PRD FR-55, epics A88. While Privacy mode is on, every user-supplied name or text (session titles and messages, project names, Shelf items and thumbnails, Timer labels, Account names, Widget text, calendar titles, notes) renders as fixed-width dots in the secret-mask style (Secret mask), in `ink-3`, so length is not given away. Status glyphs, rings, `T+` and numbers stay unchanged. Peeks follow the same rule; macOS notifications carry only the kind label. Indicator [ASSUMPTION]: a small eye-slash glyph in `ink-3` at the right of the expanded tab row (left of the settings gear) and in the peek band; nothing is added to the closed notch.

### Increase contrast

When macOS Increase contrast is on (all looks):

| Element | Default | Increase contrast |
|---|---|---|
| Zone, chip and card borders (Stash, AirDrop, Image to Text hairlines, C struct inner borders, chip borders) | 7–30% alpha | Solid 1px `ink-3` |
| Ask AI border | Dashed, lilac 35% / gold 55% | Dashed, 100% lilac (A) / gold (C) |
| Tracks (Time ring, countdown, quota, pace) | `line` or 10–14% | `ink-3` at 40% or more |
| Upcoming phase pips | 1px `ink-3` ring | Unchanged |
| Focus | 1px ring (+ halo in A dark) | 2px ring, halo dropped |
| Glass gradients | Gradient | Flat `surface-panel` / `surface-card` |

### Settings window, onboarding
Spine-only by choice: no mockup. Both are native macOS windows (Settings decided; onboarding [ASSUMPTION] above). Previews inside them use Vigie tokens.

## Do's and Don'ts

| Do | Don't |
|---|---|
| Draw everything inside the island or panel outline | Draw hairlines, brackets, readouts, clocks, glows or grids on the menu bar or desktop |
| Keep the hardware island `#000000` with dark tokens in both appearances | Tint the hardware island in light mode |
| Keep a 34px black band at the top of every peek and expanded panel | Start the light material at the screen edge; add a band to the floating notes panel |
| Use a neutral drop shadow for panels | Use colored glow outside an outline |
| Pair every status color with its shape and label | Rely on color alone; change a glyph's shape per theme or per color |
| Pair quota warning with hatch, triangle and `WARN` | Signal quota warning by color alone, or trigger it from pace |
| Show only glyphs and `+X` on the right wing | Add a total count or an `N ALERTS` label, or put a script, Time or confirmation item there |
| Call the status vocabulary for any module level (OK / WARN / DOWN) | Invent a module- or script-specific color, or reuse a session glyph to mean a module level |
| Use two peek actions; three only for the break peek (`⌥⌘↵` / `⌥⌘Z` / `⌥⌘⌫`) | Add a third action to any other peek |
| Show the drop display only while a file is dragged over the notch | Open the expanded view or a peek as a drop target for outside drags |
| Drop glows on light looks | Port dark halos to light surfaces |
| Keep wording, layout and slots identical across variants | Give a variant its own labelled layout or extra readouts |
| Reserve C gold for active, now (incl. Time) and ahead of pace | Use gold for decoration, session status or pinned items |
| Keep the setup-problem alert neutral | Give it a status glyph, status hue or beacon |
| Keep sci-fi instrument cues subtle (ticks, corner marks, rims) | Use crosshairs, reticles, radar rings or targeting frames (`imports/feedback-c-peek-crosshair-overkill.png`) |
| Respect Presence mode: calm means static | Add motion outside the documented loops |
| Use gold text `#765709` on C light; warning text `#7E6300` in light looks | Set text in `#A07418` (3.4:1) or `#8A6D00` (warning fill only) |
| Mask secrets at a fixed width | Let the mask length reveal the secret length; show secret text in list summaries |
| Keep Vigie abstract | Add a mascot, avatar or character |
