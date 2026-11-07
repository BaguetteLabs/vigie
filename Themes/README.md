# Themes

Generated TOML themes (from DESIGN.md tokens by the VigieUI `themegen` target); never hand-edited, see AD-14.

- Regenerate: `Scripts/themegen.sh` (writes here and to `Packages/VigieUI/Sources/VigieUI/Resources/Themes/`,
  the identical copy bundled with VigieUI; SwiftPM resources cannot point outside the package).
- Check: `Scripts/theme-regen-check.sh` (CI step `theme-regen-diff`) fails on any difference.

## Layout (`schema = 1`)

| File | Holds |
| --- | --- |
| `base.toml` | `colors` shared by every look (`island`, `band`, `shadow`), shared `rounded`, `spacing`, shared `motion`, raw `components` specs |
| `<variant>.toml` | `id`, `name`, `extends = "base"`, variant `typography.<role>`, variant `rounded` and `motion` overrides, `looks.dark.colors`, `looks.light.colors` |

Generation rules from the DESIGN.md frontmatter:

- `colors.base-<role>` → `base.toml [colors] <role>`; `colors.<v>-<dark|light>-<role>` → `<variant>.toml [looks.<look>.colors] <role>`.
- `typography.<v>-<role>` → `<variant>.toml [typography.<role>]` (values kept as strings: `14px`, `'300'`, `0.24em`, `1.45`).
- `rounded` / `motion` keys with a `<v>-` prefix go to the variant file with the prefix stripped (`a-card` → `card`,
  `a-card-iris` → `card-iris`); the others stay in `base.toml`.
- `spacing` and `components` go to `base.toml` unchanged (component values are raw strings, references such as
  `{rounded.a-zone}` included).
- Variant prefixes: `a` = `chrome-hologram`, `c` = `twin-metal-tactical`.

```toml
# chrome-hologram.toml (excerpt)
schema = 1
id = "chrome-hologram"
name = "Chrome Hologram"
extends = "base"

[looks.dark.colors]
ink-1 = "#E8ECF2"
quota-warning = "#FFE14D"

[rounded]
card = "16px"

[typography.readout-value]
fontFamily = "SF Pro (system)"
fontSize = "14px"
fontWeight = "300"
lineHeight = "13px"
```

Resolution (AD-14, last wins): `base.toml` → variant → look → custom theme file → `[appearance.colors]` →
`[appearance.colors.<look>]` → accessibility adjustments (lightness only, never a hue). In a dark look
`quota-warning-text` resolves to `quota-warning`. The physical notch always resolves the dark look.

Custom themes (config folder) use the variant layout, every table optional; `extends` may name a built-in id
to start from that skin. A custom id equal to a built-in id, or a `schema` newer than the app reads, is
ignored and reported as a setup problem.
