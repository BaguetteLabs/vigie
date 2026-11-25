# Copy diagnostics

Settings › General › **Copy Diagnostics** (Story 17.4, AD-16) puts a plain-text report on the clipboard for a bug report. The row then reads `COPIED · <size>` for the theme's `confirm-readout` duration. If the unified log could not be read, the report is still copied and the row says so in red.

It is built only when you click the button, from in-process state, and **nothing is sent over the network**: the collector (`VigieCore/Diagnostics/`) receives closures over the module registry, `ConfigStore`, the Notifier, `ProcessInfo`, `sysctl`, `NSScreen`, the code signature of the running app and this process's own unified log (`OSLogStore(scope: .currentProcessIdentifier)`). A test fails if any file in that folder mentions `URLSession`, `URLRequest`, `NWConnection`, `NWPath`, `CFNetwork`, `curl`, `Process(` or `import Network`.

The clipboard copy goes through the core clipboard service **without** the clear-after timer used for secrets: the text holds none, and you may paste it minutes later.

Opening reads this process's log, which can take a few seconds; the button is disabled meanwhile.

Log lines come from the running app process only (`OSLogStore` scope `currentProcessIdentifier`), so the CLI and hook processes are not included. The report body is always in English, whatever the app language: it is a bug-report payload.

## What is included

The sections, in order, each under an `== NAME ==` header:

| Section | Content |
| --- | --- |
| App | Name, version (build), bundle id, `dev` or `release`, signing (`ad-hoc`, `Developer ID (<team id>)`, or the certificate kind and team id; never the holder's name), install path with the home folder as `~` |
| System | macOS version string, Mac model (`hw.model`), chip (`machdep.cpu.brand_string`), architecture (`arm64`, `x86_64`, `x86_64 (Rosetta)`), locale, Reduce motion, Reduce transparency and Increase contrast |
| Displays | Count; per display: physical notch, virtual notch on an external display, or virtual notch on a built-in display without a notch; size in points and scale; `main`; `vigie` on the display(s) Vigie draws on. Display names are not collected |
| Modules | Every built-in module: id, enabled, status (running, disabled, errored with its message, needs permission), arbitration state, declared alert kinds. Script modules: id and status, then one line per script file from the integrations module: id, parse status, enabled flag, confirmation state on this Mac (never its code, documentation, output, settings or source URL) |
| Agents | From `agents.sessions` while it runs: per adapter, the detected CLI version, the support status (supported, assumed, unsupported, not installed) and whether its hook is installed; per terminal adapter, whether its app is installed |
| Setup problems | The open `setup.problem` alerts (time, module, category, title) and the last 20 resolved during this launch (time and module; the Notifier keeps no title once resolved) |
| Config | Config folder (`~`), sync on or off, iCloud Drive available, number of config problems; then the keys present in `config.toml` / `local.toml` (`(local)` marks the latter) with their values, except: every declared `secret` setting prints `<set>` or `<unset>` (present in a file or not), `path` settings print `<path>`, lists print `<list of N>` |
| Logs | Up to the last 200 lines from the last 15 minutes logged by Vigie's subsystems (the bundle id, `fr.baguettelabs.vigie…`, `vigie`), with time, level and category. `%{private}` fields are already `<private>` |

The footer reads `Generated <ISO date> · Vigie diagnostics contain no secrets; review before sharing.`

## What is never included

- **Secret values** (Keychain items of modules, adapters and scripts) and external credentials: only `<set>` / `<unset>`.
- **Note titles and bodies**: the Notes module contributes nothing; only its id, status and state appear. A test seeds a running module holding a sentinel note and checks the text.
- **Environment variables**, raw script output, script code, session titles, prompts, file paths of configured settings.
- Display names, the signing certificate holder's name.

## Redaction gate

After the report is assembled, every line goes through `DiagnosticsRedactor`, in this order:

1. **Known secret values**, exact match on the whole report (so a multi-line value matches too, also in its one-line JSON-escaped form with `\n`), longest first, replaced by `<redacted>`: the Keychain value of every declared `secret` setting (module owner, or `adapter.<id>` for adapter settings) and every value a running module hands over through `DiagnosticsContributing.diagnosticsSecretValues()` (the integrations module: each script's `secret` settings). Values shorter than 4 characters are not scrubbed exactly (they would match ordinary words); the patterns below still apply.
2. `Authorization:` / `Authorization=` header values (the rest of the line) and `Bearer …` / `Basic …` tokens.
3. `key = value`, `key: value`, `"key": "value"` where the key contains `token`, `password`, `passwd`, `secret`, `api_key`, `api-key` or `apikey` (except the `<set>` / `<unset>` / `<redacted>` / `<path>` markers). A quoted value is redacted up to its closing quote (or the end of the line if unclosed), so `password = "two words"` leaks nothing; an unquoted value stops at the next space.
4. Token shapes: JWTs (`eyJ…​.…`), `sk-…` (OpenAI, Anthropic), Slack `xoxb-` / `xoxa-` / `xoxp-` / `xoxr-` / `xoxs-`, GitHub `ghp_` / `gho_` / `ghu_` / `ghs_` / `ghr_` / `github_pat_`, AWS `AKIA` + 16, runs of 32+ hex digits, runs of 40+ base64 / base64url characters mixing digits, upper and lower case (a path starting with `/` is not one).
5. URL userinfo: `scheme://user:pass@host` and `scheme://token@host` become `scheme://<redacted>@host`; host and path stay.
6. Email addresses: the local part becomes `<redacted>`, the domain is kept.
7. The home folder becomes `~`, and so does any other `/Users/<name>` (except `/Users/Shared`).

## Before sharing

The report is meant to be safe to paste in a public issue, but read it first: a module error message or a log line could still name something you'd rather keep private (a project folder name, a calendar name). Edit the text before you post it.

`Save to file…` is not offered: Settings has no save-panel seam yet (the Config folder row only has an open panel). Paste the text into a file if you need one.
