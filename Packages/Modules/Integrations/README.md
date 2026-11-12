# Integrations

The `integrations` module is the runtime of script modules (SPEC §7.4, §9, AD-18). This package holds the script
schema types (Story 12.1, checked against `schemas/script-module.schema.json`) and script discovery (Story 12.2).
Confirmation, the runner and the per-script dynamic modules come with Stories 12.3–12.5.

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
`errored(ScriptParseError)`) and `enabled` (`[modules."<id>"] enabled`, default true).

## Errors

A file is errored when it is not UTF-8, has no or unclosed front matter, invalid YAML, a schema error (the message
names the key path, e.g. `settings[0].key`), zero or several code blocks, or an unclosed fence. Across files, an
`id` equal to a built-in module id (`context.scriptFolder.builtInModuleIDs`: the modules the app ships plus
`ModuleID.specBuiltIns`), starting with `agents.`, or declared by several files errors every file declaring it.

Each errored file raises one `setup.problem` alert (dedupe key `script:<file name>`, category `SCRIPTS`, opens the
module's settings). The title names the file and the body gives its path and the problem; both are sensitive, so
Privacy mode masks them. The alert is replaced when the problem changes and resolved when the file parses again,
disappears, or the module stops. Errored files do not change the module's state.
