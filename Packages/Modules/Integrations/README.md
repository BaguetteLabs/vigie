# Integrations

The `integrations` module is the runtime of script modules (SPEC §7.4, §9, AD-18). This package holds the script
schema types (Story 12.1, checked against `schemas/script-module.schema.json`), script discovery (Story 12.2) and
per-Mac confirmation (Story 12.3). The runner and the per-script dynamic modules come with Stories 12.4–12.5.

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

**Review.** `openConfirmation(for:)` sets `reviewing`; the module's Settings pane (`settingsView()`, Settings ›
Integrations, grown into Settings › Scripts by Story 12.6) lists every script with its state (`NOT CONFIRMED`
without a glyph, `CONFIRMED`, `DECLINED`, `CAN'T LOAD`) and a Review button, and presents
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
