# Integrations

The `integrations` module is the runtime of script modules (SPEC §7.4, §9, AD-18). This package holds the script
schema types (Story 12.1, checked against `schemas/script-module.schema.json`), script discovery (Story 12.2) and
per-Mac confirmation (Story 12.3), the runner (Story 12.4) and Settings › Scripts (Story 12.6). The per-script
dynamic modules come with Story 12.5.

## Where scripts live

Every `*.md` file directly in `<config folder>/modules/` is a script module. The folder comes from the host
(`context.scriptFolder.url`, built from `AppEnvironment.scriptModulesFolderURL`, AD-17); Vigie never creates it.
Subfolders and hidden files are ignored. The folder is watched (AD-12: the directory, plus each `*.md` file as a
hint for in-place writes) and rescanned on every change; files are read off the main actor through
`NSFileCoordinator`, and an iCloud file not downloaded yet keeps its last read.

## File layout

````markdown
---
id: github.prs
name: GitHub PRs
interval: 5m
runtime: python3
widget: number
---

Documentation, any Markdown.

```python
print("...")
```
````

- **Front matter:** the file's first line is `---`; the YAML runs to the next `---` (or `...`) line and is decoded
  with Yams into `ScriptFrontMatter` (strict: unknown keys and host-owned setting keys are errors).
- **Code:** exactly one CommonMark fenced block (```` ``` ```` or `~~~`, three or more, indented at most three
  spaces). The first word of the info string is the language tag. A fence that is never closed is an error.
  Indented code blocks are documentation.
- **Documentation:** everything after the front matter except the code block, trimmed.

Each file becomes a `ScriptModuleDefinition`: URL, `relativePath` (`modules/<file>`), `contentHash` (SHA-256 of
the file bytes, what Story 12.3 confirms), front matter, code, language, documentation, `status` (`ok` or
`errored(ScriptParseError)`), `enabled` (`[modules."<id>"] enabled`, default true), and for review the front
matter as written (`frontMatterText`) and the whole file as text (`source`).

## Errors

A file is errored when it is not UTF-8, has no or unclosed front matter, invalid YAML, a schema error (the message
names the key path, e.g. `settings[0].key`), zero or several code blocks, or an unclosed fence. Across files, an
`id` equal to a built-in module id (`context.scriptFolder.builtInModuleIDs`: the modules the app ships plus
`ModuleID.specBuiltIns`), starting with `agents.`, or declared by several files errors every file declaring it.

Each errored file raises one `setup.problem` alert (dedupe key `script:<file name>`, category `SCRIPTS`, opens the
module's settings). The title names the file and the body gives its path and the problem; both are sensitive, so
Privacy mode masks them. The alert is replaced when the problem changes and resolved when the file parses again,
disappears, or the module stops. Errored files do not change the module's state.

## Confirmation

A script runs only after the user confirmed its exact bytes on this Mac (SPEC §9.2, AD-18). Each definition has a
`ScriptLocalState`, published in `IntegrationsModule.localStates` (by file name) and read with
`localState(for:)`; both are recomputed on every scan and every record change:

| State | When | Runs |
|---|---|---|
| `awaitingConfirmation` | no record matches the file's current SHA-256 (new file, or any byte changed) | no |
| `confirmed` | the confirmed hash equals the current hash | yes, if enabled and parsed |
| `declined` | the declined hash equals the current hash | no, on this Mac only |

`isEligible(_:)` (what the runner checks, Story 12.4) is `status == .ok && enabled && state == .confirmed`. A byte
change voids a decline as well as a confirmation, so changed content is always reviewed again. If both records
name the current hash (a hand edit), the decline wins.

**Records.** Written only through `context.scriptFolder.confirmations` (`ScriptConfirmationStore`, implemented in
VigieCore by `ConfigScriptConfirmations` over ConfigStore), in `local.toml` only, never in the synced
`config.toml`; a `[scripts]` table in `config.toml` confirms nothing. Keyed by the path relative to the config
folder:

```toml
[scripts.confirmations."modules/github.md"]
sha256 = "<lowercase hex SHA-256 of the confirmed bytes>"

[scripts.declined."modules/other.md"]
sha256 = "<lowercase hex SHA-256 of the declined bytes>"
```

Confirming removes the file's decline and declining removes its confirmation. Records of deleted files stay
(harmless: they only match the same bytes at the same path).

**Review.** `openConfirmation(for:)` sets `reviewing`; Settings › Scripts (`settingsView()`, see Settings below)
lists every script with its state and a Review button, and presents
`VigieUI.ScriptConfirmationView` as a sheet while `reviewing` is set. The sheet shows the file name and path, the
SPEC §9.2 warning ("Scripts run as the user, with no sandbox. Only install scripts you trust."), the documentation
(headings and inline Markdown), the front matter and the code (monospaced, with the language tag), and the whole
file as text on demand (rendered Markdown can hide text). Escape cancels without recording; Return does nothing,
so Confirm and Decline take an explicit click. Confirm records the hash of the bytes that were shown: if the file
changed meanwhile, the new bytes stay awaiting confirmation. In Privacy mode the file is masked and Confirm is
disabled.

Island surfaces (widget, side-slot item, page: Stories 12.5, 12.11) show `VigieUI.ScriptStateLabel` (`NOT
CONFIRMED` in `ink-3`, no level glyph); its action should call `openConfirmation(for:)` and open Settings on the
`integrations` pane.
## Running

`ScriptRunner` (Story 12.4, AD-18) is the only code that executes script code blocks. The module creates it on
start, feeds it `scripts` after every scan, and stops it on stop. A script runs when it parsed cleanly and
`IntegrationsModule.isScriptEligible` says so (Story 12.3 sets it to confirmed on this Mac and enabled; until then
it is `enabled`); call `updateRunner()` after eligibility changes.

- **When:** once when the script becomes eligible, then every `interval` from the start of the previous run
  (`context.scheduler`, at least 1 s apart), and on Refresh (`refresh(scriptID:)`, `refreshAll()`). Runs of one
  script never overlap: a Refresh during a run is dropped, and the next run is scheduled only when a run ends. A
  failed run waits for the next interval like any other (no retries). A new content hash cancels the run in
  progress and the schedule and starts over from `WAITING · FIRST RUN`; a removed or no longer eligible script is
  stopped and its state dropped.
- **Launch:** `runtime` is resolved through `context.executables` (not found: the run is recorded as
  `RUNTIME NOT FOUND`, nothing starts). The code block is written to a file with mode 0600 in
  `<module storage>/runs/` (mode 0700), named with the language's extension (`.py`, `.sh`, `.swift`, ...), and
  removed after the run. The process is `<runtime> <file>`, started with `posix_spawn` on the resolved absolute
  path, working directory `<config folder>/modules/`, stdin on `/dev/null`, no inherited descriptors, default
  signal handlers, and its **own process group**.
- **Environment:** only `PATH` (the login shell's, as captured by `context.executables`; without one, the
  runtime's folder then `/usr/bin:/bin:/usr/sbin:/sbin`), `HOME`, `LANG` (Vigie's, else `en_US.UTF-8`), and
  `VIGIE_SETTING_<KEY>` for each setting (`warn_at` → `VIGIE_SETTING_WARN_AT`) with its configured value, else its
  front-matter default: booleans `true`/`false`, numbers as written, durations in the config grammar (`1h30m`),
  paths with `~` expanded, lists as a JSON array of strings; a `path` without value is left unset. A `secret` is
  read from SecretStore at each run under `<script id>.<setting key>` and exists only in the child's environment
  (never in the code file, on disk or in the log); an absent secret leaves its variable unset. Configured values
  are read at each run from `context.scriptFolder.settings` (`Dependencies.configuredValue`, Story 12.6), so a
  change in Settings or in `config.toml`, and a new secret, apply at the next run.
- **Timeout:** `min(interval, 30s)`. When it hits, the whole process group gets `SIGKILL` (`kill(-pgid)`), so
  children the script started die with it; the run is recorded as `TIMED OUT · <n>S`.
- **Result:** exit 0 with a stdout that decodes as the output schema and declares the front matter's widget type
  is a good run: it replaces the last good output and clears the errored state. Anything else errors the script and
  keeps the last good output for the warning badge: a non-zero exit (`EXIT <code>`; killed by another signal:
  `128 + signal`), invalid output (`INVALID OUTPUT`, with the reason: empty, not JSON, a schema error naming the
  key, another widget type, more than 1 MB), or a launch failure. stdout and stderr are captured to files, not
  pipes, so a background job that keeps them open cannot hold a run.
- **State:** `runner.states[<file name>]` is a `ScriptRunState`: `phase` (`waitingFirstRun`, `ok(output, at:)`,
  `errored(outcome, lastGoodOutput:, at:)`), `isRunning`, `nextRunAt`, and the last 20 `ScriptRunRecord`s
  (`startedAt`, `duration`, `outcome`, `stderrExcerpt`), newest first. `ScriptRunLabel` builds the mono labels
  from the String Catalog.
- **Logged** (`context.log`, private): the end of each run's stderr (last 4 KB, every secret value replaced by
  `••••`), each failed run with its label and reason, an unresolved runtime, a launch failure. Never the
  environment or a secret.

## Settings

Settings › Scripts (Story 12.6, UX-DR74) is the module's pane (`settingsView()`; pane id `integrations`, titled
"Scripts"). It sits under the module's own `enabled` switch, which turns the whole runtime on or off.

- **List:** one row per file, in file order (`paneRows()`, a `ScriptPaneRow` each): name (or file name), the
  relative path, the state label and `Last run <relative time>` (`Not run yet` before the first run of this launch).
  States, most urgent first: `CAN'T LOAD` (parse problem in its help text), `DECLINED`, `NOT CONFIRMED` (opens the
  review), `DISABLED`, `RUNNING`, `WAITING · FIRST RUN`, `OK`, or the failed run's label (`EXIT 2`,
  `TIMED OUT · 30S`, ...). Actions: **Refresh** (`refresh(scriptID:)`; enabled only for an eligible script that is
  not running), **Review…** (the Script Confirmation sheet) and the **Enabled on this Mac** switch.
- **Detail:** expanding a row shows the script's declared settings as the generated controls every module pane
  uses (`VigieUI.SettingRow`): bool switch, int field and stepper within min/max/step, double slider when bounded
  (else a number field), string field, enum picker, duration field in the config grammar (`1h30m`), path field
  with Choose…, list editor (one row per item; Choose… for lists of paths), and a secure field for `secret`.
  Labels and help are the script's own text, shown as written. Numbers are clamped to min/max before they are
  written. Reset to default (context menu) removes the key.
- **Enabled on this Mac** (AD-8): `context.scriptFolder.settings.setEnabled`, kept in `local.toml` by file, never
  synced; absent means enabled. A change (from Settings or an edit of `local.toml`) arrives on
  `settings.changes()` and updates `enabled` and the runner at once, without a rescan.

  ```toml
  [scripts.enabled]
  "modules/github.md" = false
  ```
- **Configured values:** `[modules."<script id>"] <key>` in the synced `config.toml`, through ConfigStore. After
  every scan the module registers each usable script's declared settings (`settings.register`), replaces them when
  the declarations change, and unregisters them when the file goes away or errors (values stay in the file).
  `ScriptRunner` reads them at each run.
- **Secrets:** a `secret` setting is never registered and never written to TOML. The secure field saves to the
  module's `context.secrets` under `<script id>.<setting key>` (the key the runner reads), on this Mac only; the
  field stays blank, shows "Stored" once set, and offers Set and Clear. Secrets must be entered on each Mac.
- **Footer:** "More examples in the Script repository" (SPEC §9.6, A84: `vigie-scripts` under the releases owner).
  The owner is still the `OWNER` placeholder (A49), so `ScriptRepository.url` is nil and the text shows disabled.
## Examples

Story 12.7 (A85, PRD FR-41). The app bundles three example scripts in `Sources/Integrations/Resources/Examples/`;
the others (CI or deploy status, revenue) live in the Script repository.

| File | Id | Widget | Runtime | Settings |
|---|---|---|---|---|
| `github-prs.md` | `github.prs` | number (open PRs, opens the PR list) | `sh` + `curl` | `repo` (string), `token` (secret, `VIGIE_SETTING_TOKEN`) |
| `site-status.md` | `site.status` | status (`OK` / `WARN` / `DOWN`, detail `200 · 142 ms`) | `sh` + `curl` | `url` (string) |
| `uptime.md` | `system.uptime` | text (`3d 4h`), no network | `sh` | none |

Each prints one JSON document to stdout and exits non-zero with a message on stderr when it cannot work (a missing
`repo`, an unreadable boot time). Each has a `<name>.sample.json` next to it (a sample of its stdout, not bundled).
`Scripts/check-example-scripts.sh` (CI and `ci-local`) validates every example's front matter and its sample
against `schemas/script-module.schema.json` and checks for exactly one code block; `ExamplesTests` parses them with
`ScriptMarkdown` and runs `uptime.md` for real through `ScriptProcessLauncher`.

`IntegrationsModule.bundledExamples` lists them (`BundledExample`: URL and parsed definition).
`addExample(_:)`, behind Settings › Scripts › **Add example…**, copies one into `<config folder>/modules/` (creating
the folder if needed) and rescans. It never overwrites a file (`ExampleAddError.exists`) and refuses an example whose
id another file already declares (`.idInUse`). The copy is a new file, so it is awaiting confirmation and does not
run until you review and confirm it.

**Scripts run unsandboxed, as you, with your files and network. Only install scripts you trust**, bundled or not:
read the whole file in the review sheet, which says the same, before you confirm.

## Surfaces

Story 12.5 (AD-18, SPEC §7.4, DESIGN "Script widget" and "Side-slot item").

- **One module per script:** after every scan and every confirmation change, each file that parsed and is not
  declined on this Mac becomes a `ScriptModule` (manifest from the front matter: `id`, `name`, `icon`), registered
  through `context.host.registerDynamicModule`. A file awaiting confirmation is registered too (its surfaces show
  `NOT CONFIRMED`) but never runs. Removal, a parse error or a decline cancels the registration token; a
  front-matter change re-registers the module; a code or documentation change keeps it. Registration does not
  depend on `enabled`. VigieCore's `ModuleRegistry.registerDynamic` lists the module right after `integrations`,
  so arbitration, Home, the tabs and Settings › Home see it like a built-in; it goes away when `integrations` stops.
- **State** (arbitration): awaiting confirmation or not run yet → `ambient`; a good run → the output's `state`; a
  failed run → the last good output's `state`, at least `ambient`.
- **`home`:** the script card (VigieUI `ScriptCard`, `components.script-card`, 222 × 138): `NAME · TARGET` and
  `EVERY 1M`; status = 26 px glyph, level (`OK · <detail>`) over the value, `CHECKED <n> MIN AGO` or
  `DOWN SINCE <time>`; number = numeral and label, the segmented bar (5 segments, the last outlined in the
  quota-warning yellow), the detail, `UPDATED <n> MIN AGO`; text = label (`TEXT` without one) over the value,
  `UPDATED <n> MIN AGO`. A status widget's `label` is its target. After a failure the last good output stays with
  the WARN triangle and the failure (`EXIT 3`) on the meta line.
- **`side`:** one left-wing item (`script`) with the front matter's `priority` (default 5): 16 px glyph and level
  over the target (status), or value over label (number, text). VoiceOver: "<name>, <level>". Clicking the closed
  notch opens Home as always (EXPERIENCE).
- **`page`:** a tab named after the script; its body is a placeholder until Story 12.11.
- **Actions** (a click on the widget body, confirmed scripts only, on the last good output): `open` →
  `NSWorkspace.open`; `copy` → `context.clipboard`; `run` → `ScriptRunner.run(argv:for:)`: `argv[0]` resolved
  through `context.executables` (an absolute path as is), same environment, working directory, timeout and
  process-group rules as the script's runs, recorded in its runs with `action` set and outcome `EXIT <code>`; the
  widget keeps its output. `NOT CONFIRMED` opens the Script Confirmation (`openConfirmation(for:)`).
- **Privacy mode** (AD-24): every script-provided string (target, values of status and text widgets, labels,
  details) renders as the fixed-width dots, with no opt-out; levels, numbers and the script's name stay.
