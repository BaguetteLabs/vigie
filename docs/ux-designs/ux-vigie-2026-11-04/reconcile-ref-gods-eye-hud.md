# Reconcile: imports/ref-gods-eye-hud.png

**What it shows (qualities):** near-monochrome white-on-dark HUD over satellite imagery; thin hairline geometry; concentric tick rings around a central reticle; vertical tick-mark scales with a sliding pointer (CRS / FTO gauges); dense uppercase monospace data tables; terse status readout ("Status: online" in green); coordinates/telemetry (X/Y/Z, location); depth from a photographic backdrop behind translucent overlays.

**Kept**
- Overall register: "(decision) Direction: 'God's eye view' / military dashboard / tactical HUD look and feel", reframed by "(decision) God's eye is an aesthetic, not a literal metaphor: think sci-fi holographic computers, spaceship HUDs".
- Thin lines / tick rings: C keeps a ticked bezel on the usage dial and per-session "triangle in tick ring" glyph (theme-family-4-looks.html legend, `--t-bezel:14s`).
- Uppercase technical labels: "(decision) Voice: short uppercase technical labels for compact UI".
- Mono data readouts: mono font + letter-spaced uppercase labels throughout both variants; T+ elapsed timer on peek.

**Intentionally dropped**
- Radar / targets / reticle / crosshair: "(decision) ... no radar/targets metaphor required"; "(decision) C feedback: military theme goes too far — big reticle/crosshair ... overkill"; v2 event "C reticles/crosshairs removed ... radar rings removed".
- Readouts and ornaments around the screen ("Status: online", clock): "(override) Containment rule tightened ... no hairlines, brackets, readouts (e.g. 'VIGIE · ONLINE', clock)".
- Monochrome white: replaced by "(decision) Color: 'metal' palette — silver, gold".

**Silently dropped / at risk**
- Vertical tick scale with sliding pointer (linear gauge) - no decision; not used anywhere (quota is a ring, pace a bar), so a signature HUD instrument is gone without a call.
- Dense multi-row telemetry tables (the "lots of data" feel) - only short labels survive; no decision on whether expanded view/Agents tab should carry that data-dense HUD look.
- Photographic/imagery depth behind translucent overlays - no decision; panels are flat glass/aluminium.
- "System online" heartbeat - removed from C with the outside readouts; no decision whether an in-island "alive" cue replaces it (A ambient 6s may cover it, unstated).
