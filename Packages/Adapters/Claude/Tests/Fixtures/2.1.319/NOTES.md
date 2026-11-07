# Claude Code 2.1.319 fixtures

Recorded by spike 1.4 (`docs/decisions/spike-hook-path.md`) from real sessions: raw hook stdin, with the home
folder rewritten to `/Users/romain`. File names are `<hook_event_name>.json` or `<hook_event_name>.<variant>.json`.
All 8 SPEC §8.3 events are present.

## Notification subtypes (SPEC §14.4)

| `notification_type` | `message` | Meaning | Normalized |
|---|---|---|---|
| `permission_prompt` | `Claude needs your permission` | A permission dialog is open (sent ~6 s after it appears) | `needs.input` (`permission_prompt`) |
| `idle_prompt` | `Claude is waiting for your input` | Idle reminder, 60 s after `Stop` with no input | nothing |

Only `permission_prompt` means blocked. No error notification type was observed in this version, so no fixture
yields `session.error`.

## Other variants

- `SubagentStop.internal.json`: `agent_type: ""`, Claude Code's internal helper (next-prompt suggestion). Ignored.
- `Stop.background_tasks.json`: `Stop` while a background subagent still runs. Still `turn.end`.
- `UserPromptSubmit.agent_message.json`: synthetic `<agent-message …>` prompt after a background subagent hands
  back. `prompt.submit`: Claude works again.
- `SessionStart.print.json` / `SessionEnd.print.json`: headless `claude -p` (no `model`; `reason: "other"`).
