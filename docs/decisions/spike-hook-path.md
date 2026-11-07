# Spike 1.4: Claude Code hook path

Date: 2026-11-07. Story 1.4 (FR78, FR79 spike scope, NFR3, AD-6, AD-7). Result: **the path works end to end.**
Claude Code ran with `vigie hook claude` on all 8 events. Each invocation reached the spike listener over the
dev socket as one `agent.hook` envelope. With no listener, every invocation spooled in under 11 ms.

## Setup

- **Claude Code:** `2.1.319 (Claude Code)`. Model reported by `SessionStart`: `claude-fable-5-1`.
- **macOS 26.5, Xcode 26.6, Swift 6.3.3.** Terminal: Warp (`TERM_PROGRAM=WarpTerminal`).
- **CLI:** `Packages/VigieCLI`, debug build (dev flavor, `VIGIE_DEV`), built with
  `swift build --build-system swiftbuild` to `Packages/VigieCLI/.build/out/Products/Debug/vigie`. The product is
  still named `vigie`, not `vigie-dev`. Renaming the dev product belongs to packaging, so the hooks called the
  binary by its absolute path.
- **Socket:** `AppEnvironment.current.socketURL`, i.e. `/Users/romain/Library/Application Support/Vigie Dev/vigie.sock`.
  That is 60 bytes here (61 with `romain`), under the 100-byte limit, so the temp-dir fallback was not used. The listener created it as
  `srw-------` (0600).
- **Listener:** `spikes/hook-listener` (its own SwiftPM package) ran the spike `SocketListener`
  (since replaced by `VigieCore.EventServer`, Story 4.1; the runner now uses it).
- **Hook config:** a scratch project's `.claude/settings.json` (never the global one) registered
  `<abs path>/vigie hook claude` on `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
  `Notification`, `Stop`, `SubagentStop` and `SessionEnd`, with matcher `"*"` where the event takes a matcher.
  Claude Code was started with `--setting-sources project`, so the user's own global hooks did not run.
- **Sessions:** all real, none synthetic.
  1. `claude -p "Run the shell command: echo vigie-spike-ok, then reply with the single word done" --allowedTools Bash --max-turns 3`
     (headless, no TTY).
  2. An interactive session in a pty driven by `expect`: run `touch spike.txt`, launch a `general-purpose`
     subagent, stay idle for 2 min, `/exit`.
  3. An interactive session with `--permission-mode default`: run `rm -f spike.txt`, keep the permission
     dialog open 8 s, approve, `/exit`.

## Observed payloads (stdin JSON, `raw` in the envelope)

**Common to every event:** `session_id`, `transcript_path`, `cwd`, `hook_event_name`.

- Interactive sessions also send `scratchpad_dir` on every event.
- From the first prompt on, events carry `prompt_id`.
- Turn events (tools, `Stop`, `SubagentStop`) carry `effort: {level}`.

| Event | Fields seen (besides the common ones) |
|---|---|
| `SessionStart` | `source` (`startup`), `model` (interactive only) |
| `UserPromptSubmit` | `prompt`, `prompt_id`, `permission_mode` |
| `PreToolUse` | `tool_name`, `tool_input`, `tool_use_id`, `permission_mode`, `effort`; `agent_id`, `agent_type` when run inside a subagent |
| `PostToolUse` | as `PreToolUse` plus `tool_response` (Bash: `stdout`, `stderr`, `interrupted`, `isImage`, `noOutputExpected`), `duration_ms` |
| `Notification` | `notification_type`, `message`, `prompt_id` |
| `Stop` | `last_assistant_message`, `stop_hook_active`, `background_tasks` (array of `{id, type, agent_type, description, status}`), `session_crons`, `permission_mode`, `effort` |
| `SubagentStop` | `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message` (sometimes absent), `stop_hook_active`, `background_tasks`, `session_crons`, `permission_mode` |
| `SessionEnd` | `reason`: `other` from `-p`, `prompt_input_exit` from `/exit` |

`permission_mode` values seen: `default` (from `-p`, and with `--permission-mode default`) and `auto` (the
interactive default in this setup).

## `Notification` subtypes and SPEC §14.4

| `notification_type` | `message` | When |
|---|---|---|
| `permission_prompt` | `Claude needs your permission` | 6.0 s after the `PreToolUse` that opened the dialog, while it was still open |
| `idle_prompt` | `Claude is waiting for your input` | 60 s after `Stop` with no input |

**§14.4 answer: yes.** A permission prompt can be told from an idle reminder by `notification_type`.
`blocked` should map only from `permission_prompt` (and probably `elicitation_dialog` and `agent_needs_input`,
listed in the docs but not observed). `idle_prompt` must not raise `blocked`.

Caveat: the permission notification arrives about 6 s after the dialog appears. For faster `blocked` detection,
use the `PermissionRequest` hook, which the docs list but this spike did not register (it is not among SPEC's 8
events). Story 4.6 should evaluate it.

## Environment

Whitelisted keys forwarded in this environment:

- `TERM_PROGRAM` (`WarpTerminal`), `TERM_PROGRAM_VERSION`, `SHELL`, `PWD`.
- `WARP_*`: `WARP_TERMINAL_SESSION_UUID`, `WARP_FOCUS_URL` (`warp://session/<uuid>`), `WARP_CLIENT_VERSION`,
  `WARP_IS_LOCAL_SHELL_SESSION`, `WARP_CLI_AGENT_PROTOCOL_VERSION`, `WARP_HONOR_PS1`,
  `WARP_PROMPT_NODE_VERSION_ENABLED`, `WARP_SSH_REUSE_CONTROL_MASTER`, `WARP_USE_SSH_WRAPPER`.
- `ITERM_SESSION_ID`, `TERM_SESSION_ID`, `TMUX` and `GHOSTTY_*` were not set: this was Warp, without tmux.

A temporary hook dumped the full environment key list (keys only). Claude Code also sets, among others:

- `CLAUDE_PID`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_PROJECT_DIR`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDECODE`.
- `CLAUDE_CODE_EXECPATH`, `CLAUDE_EFFORT`, `CLAUDE_ENV_FILE`.
- `CLAUDE_CODE_MESSAGING_SOCKET`, `CLAUDE_CODE_MESSAGING_TOKEN` (secret-like, must never be forwarded).
- `AI_AGENT`, `COLUMNS`, `LINES`.

These are not whitelisted. `CLAUDE_PID` would identify the agent process directly; see "Next stories".

## TTY

- Claude Code runs hooks with stdin, stdout and stderr all piped. `ttyname` on fds 0, 1 and 2 finds nothing.
- In run 2 the CLI only tried those fds, and `tty` was `null` even though `claude` had a pty.
- The CLI now falls back to the controlling terminal (`kinfo_proc.kp_eproc.e_tdev` → `devname`) of itself, then
  of each ancestor. In run 3 that gave `/dev/ttys003`, the `expect` pty that `claude` ran on.
- In the headless run (1) no process had a terminal, and `tty` was correctly `null`.

## Ancestor chain

Run 3 (`expect` pty), parent first:

| # | pid | name | role |
|---|---|---|---|
| 1 | 85068 | `2.1.319` | **the `claude` process** |
| 2 | 85067 | `expect` | the spike's pty driver (a terminal shell in real use) |
| 3 | 85066 | `zsh` | |
| 4 | 48474 | `2.1.319` | the outer Claude Code session running this spike |
| 5 | 31124 | `zsh` | |
| 6 | 801 | `stable` | Warp |
| 7 | 717 | `stable` | Warp |

- The hook's direct parent is the `claude` process. No shell sits between them: Claude Code runs the hook command
  without an intermediate `sh`, or the shell execs it.
- The `claude` process name is its version, `2.1.319`, not `claude`. `proc_name` returns the executable's file
  name, and `~/.local/bin/claude` is a symlink to `~/.local/share/claude/versions/2.1.319`. Warp's processes are
  named `stable`.
- The chain stops before launchd (pid 1). Its length was ≤ 8 everywhere, and every entry had a `start_time`.

## Timing (AD-6, NFR3)

`echo '{"hook_event_name":"Stop","session_id":"x"}' | vigie hook claude`, 100 runs each, wall time measured
around `fork` and `exec` from a Python driver (debug build):

| Case | min | median | p95 | max | stdout/stderr | exit |
|---|---|---|---|---|---|---|
| App not running, stale socket file (`ECONNREFUSED`) → spool | 6.1 ms | 6.4 ms | 6.9 ms | 8.9 ms | none | 0 ×100 |
| App not running, no socket file (`ENOENT`) → spool | 6.1 ms | 6.7 ms | 8.8 ms | 10.0 ms | none | 0 ×100 |
| Listener up → socket | 6.0 ms | 6.4 ms | 7.7 ms | 11.3 ms | none | 0 ×100 |

- In both "not running" cases, the spool got exactly 100 lines, all decodable.
- With the listener up, it received 100 envelopes and no spool file was created.
- The spool lines were deleted afterwards.
- The 150 ms budget only matters when the peer is alive but stalled. A unit test covers this: the listener
  accepts but never reads, and a 900 KB line spools within the budget.

## Surprises

1. **Process name is the version string** (`2.1.319`). Adapters must not find the agent by the name `claude`.
   Use the first ancestor (the hook's parent) or `CLAUDE_PID`.
2. **No TTY on the hook's stdio**: solved with the controlling-terminal fallback described above.
3. **`SubagentStop` fires for Claude Code's internal helper agents** with `agent_type: ""`. They appeared 3 s
   after most `Stop` events, with `last_assistant_message` values such as `ls -la`, apparently next-prompt
   suggestions. Adapters must ignore `SubagentStop` with an empty `agent_type`, or ignore `SubagentStop` for
   session status entirely.
4. **`Stop` fires while background subagents still run.** `background_tasks` lists them with
   `status: "running"`. When the subagent finishes, Claude Code injects a synthetic `UserPromptSubmit` whose
   `prompt` starts with `<agent-message from="…">`, then a second `Stop`. A turn can therefore "end" and resume
   without user input.
5. **`SessionEnd` from `-p` has `reason: "other"`**; `/exit` gives `prompt_input_exit`.
6. **`permission_prompt` lags its dialog by about 6 s**; see the §14.4 caveat.
7. **The docs list 32 hook events** in this version (`PermissionRequest`, `PostToolUseFailure`, `StopFailure`,
   `SubagentStart`, …). SPEC's 8 are enough for the spike. `StopFailure` (error type) and `PermissionRequest`
   are candidates for `session.error` and `blocked`.
8. The common fields include `prompt_id`, `effort` and `scratchpad_dir`, which SPEC does not mention. They are
   harmless, since unknown fields are ignored.
9. Spike listener bug, fixed: a `DispatchSource` signal handler in top-level `main.swift` is inferred
   `@MainActor`. On a global queue it trapped (exit 133) and left a stale socket. The sources must use
   `queue: .main`. The Event Server must still unlink a stale socket on start, as the listener does.

## Fixtures (Story 4.6)

Raw stdin payloads, with `/Users/me` rewritten to `/Users/romain`, in
`Packages/VigieCLI/Tests/Fixtures/claude/2.1.319/`:

- `SessionStart.json` (interactive), `SessionStart.print.json` (`-p`)
- `UserPromptSubmit.json`, `UserPromptSubmit.agent_message.json` (synthetic subagent hand-back prompt)
- `PreToolUse.json`, `PreToolUse.subagent.json` (with `agent_id` and `agent_type`)
- `PostToolUse.json`
- `Notification.permission_prompt.json`, `Notification.idle_prompt.json`
- `Stop.json`, `Stop.background_tasks.json`
- `SubagentStop.json` (`general-purpose`), `SubagentStop.internal.json` (`agent_type: ""`)
- `SessionEnd.json` (`prompt_input_exit`), `SessionEnd.print.json` (`other`)

`HookCommandTests.claudeFixturesBuildValidEnvelopes` checks that every fixture wraps into a valid envelope whose
`raw` is byte-for-byte the same JSON value, and that all 8 events are present.

## Next stories need to know

- **4.1 (Event Server):** reuse `Envelope.decodeLine` and `WireError`.
  - Drop a trailing fragment without `\n` at EOF: a writer that ran out of budget mid-write leaves one, then
    spools the full line.
  - `sent_at` has millisecond precision.
  - `JSONValue` stores numbers as `Double`, so integers above 2^53 lose precision. Agent payloads only carry
    small integers.
- **4.2 (CLI):** `HookCommand` is production-shaped: injectable paths, clock and stdin; `Outcome` for tests.
  - The live entry point captures `ContinuousClock.now` as the first statement of `main.swift`.
  - The dev product still needs to be named `vigie-dev`.
  - Decide whether to whitelist `CLAUDE_PID` and `CLAUDE_PROJECT_DIR`. Never forward `CLAUDE_CODE_MESSAGING_TOKEN`.
- **4.6 (Claude adapter):** map `blocked` from `Notification` with `notification_type == "permission_prompt"`
  only. Treat `Stop` with running `background_tasks` as not-done-yet. Ignore `SubagentStop` with empty
  `agent_type`. Agent PID = first ancestor.
- **The installer (SPEC §8.3) must still offer** the `matcher` key. It is optional and `"*"` matches all, so the
  SPEC config (no matcher) is also valid.
