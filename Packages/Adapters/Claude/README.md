# ClaudeAdapter

Claude Code agent adapter (SPEC §8.3, FR82, AD-23). Depends on AgentKit only.

## Version gate

`ClaudeAdapter.supportMatrix` is the single table of supported versions:

- **supported**: inside a tested range (`2.1.0 ... 2.1.319`). The upper bound of each range is a version with
  recorded fixtures in `Tests/Fixtures/<version>/`.
- **assumed**: same `major.minor` as a tested upper bound with a higher patch (e.g. `2.1.400`). Events flow; the
  adapter's settings show a warning.
- **unsupported**: anything else (another minor or major, an unparsable or unreadable version). No events;
  `agents.sessions` raises "Claude adapter: CLI version X unsupported".
- **notInstalled**: `claude` not found.

When a new Claude Code version ships: record its 8 hook payloads into `Tests/Fixtures/<version>/` (with a
`NOTES.md` for the `Notification` subtypes), make the tests pass, then widen `supportMatrix`.
`FixtureCatalogTests` fails if a tested upper bound has no fixture folder.

## Integration

`integrationPlan` / `removalPlan` return a `ConfigDiff` for `~/.claude/settings.json` (or the project's
`.claude/settings.json` with `hooks_scope = "project"`). The managed entry is the exact command
`<~/.local/bin/<cliName>> hook claude` (AD-22); other hooks and key order are kept. Files are written only by
`IntegrationInstaller` (Story 4.7).

### Per-Account locations (Story 7.11)

With several Accounts (Story 7.10), `integrationPlan(context:inputs:account:)` / `removalPlan(context:inputs:account:)`
plan one location at a time: the default Account is the plan above; another Account's plan targets
`<location>/settings.json` only (`~` expanded, trailing slash and symlinks normalised), never another location.
The hook command is the same in every location: Claude Code reads `<location>/settings.json` only when it runs with
`CLAUDE_CONFIG_DIR=<location>`, hands that variable to its hooks, and the hook CLI forwards it (Wire's whitelist), so
`accountLocationHint(env:)` attributes the session to that Account (A82; no match → the default Account). A location
folder with no `settings.json` gets a new file holding only Vigie's hooks; a folder that does not exist throws
`MissingAccountLocation`, which Settings › Agents reports as a setup problem (path hidden in Privacy mode) instead of
creating it. With `hooks_scope = "project"` the project's file serves every Account, so the Account plans are empty.
