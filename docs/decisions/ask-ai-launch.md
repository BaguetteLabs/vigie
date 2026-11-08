# Research 9.5: Ask AI launch per agent CLI and per terminal

- **Story:** 9.5 (FR40 research, SPEC §7.1 "Drop zone Ask AI", §14.16, Architecture Deferred "Ask AI syntax", A23)
- **Date:** 2026-11-08
- **Mac:** macOS 26.5. Installed: Claude Code `2.1.319` (`/Users/me/.local/bin/claude`), Terminal.app, Warp
  (`dev.warp.Warp-Stable`). **Not installed:** Codex CLI, Gemini CLI, iTerm2, Ghostty. Nothing was installed for
  this research; the rows for those come from their public docs and are marked *unverified*.
- **Method:** `claude --help`, reading the mention parser in the installed Claude Code binary, the terminals'
  AppleScript dictionaries and URL schemes (`Info.plist`, strings in the Warp binary). No terminal tab was opened
  and no Apple Event was sent (opening tabs unattended would trigger Automation prompts on the Mac).

## Decision

1. **Best launch = start the agent bare in the folder, then type the file mentions into its prompt without
   Return** (an unsent prompt the user completes). No agent CLI has a "prefill but don't send" flag, so the
   typing has to come from the terminal; only iTerm2 can type text without a newline over AppleScript.
2. **Where the terminal can run a command but cannot type** (Terminal.app): start the agent with the mentions
   as its **initial prompt** (`claude '@/a.swift @/b.swift '`). The prompt is sent at once, but the files are
   attached, which SPEC §7.1 allows ("the files are attached, or their paths prefilled in an unsent prompt").
3. **Where the terminal cannot run a command at all** (Warp, the generic fallback): open what can be opened
   (Warp: a new tab in the folder through its URL scheme; generic: activate the terminal), copy the full command
   line (point 2's form, with `cd`) to the clipboard and show the readout `COMMAND COPIED`; the user pastes it
   with ⌘V and presses Return.
4. **An agent without an initial-prompt argument on a terminal that cannot type:** the agent starts bare and the
   mentions go to the clipboard, readout `PATHS COPIED` (the SPEC "paste the paths" fallback). No shipped
   adapter needs it today.

The resulting shapes (AgentKit, append-only):

```swift
public struct LaunchCommand {
    let executable: String            // bare name, resolved through ExecutableResolver (or the adapter's own setting)
    let arguments: [String]           // the bare interactive launch: Claude []
    let environment: [String: String] // prefixed as `/usr/bin/env K=V …` by the caller
    let typedText: String?            // typed into the new tab with no Return: Claude "@/a.swift @/b.swift "
    let promptArguments: [String]?    // replace `arguments` when the terminal cannot type: Claude ["@/a.swift @/b.swift "]
}

protocol TerminalAdapter {
    var supportsTypedText: Bool { get }  // default false; iTerm2 true
    func openTab(argv: [String], cwd: URL?, typedText: String?, context: any AdapterContext) async throws
        -> OpenTabOutcome            // .running | .commandNotRun (caller copies the command line)
}
```

`argv[0]` is always an absolute path. The `cwd` is chosen by `agents.sessions` (`ask_cwd`, `ask_alt_cwd` with ⌥).

## Agent CLIs

| CLI | Interactive start in a folder | Attach files | Unsent prompt | Initial prompt (sent) | Non-interactive (not wanted) | Status |
|---|---|---|---|---|---|---|
| **Claude Code** 2.1.319 | `cd <dir> && claude` (no `--cwd` flag; `--add-dir <dirs…>` only widens tool access) | `@<path>` mention in the prompt, resolved when the turn is sent. Absolute paths work. | **No flag.** Only by typing into the TUI. | `claude "<prompt>"` (one positional argument) | `-p/--print` | **Verified** (`--help`, binary) |
| **Codex CLI** | `codex --cd <dir>` (`-C`), or `cd <dir> && codex` | `-i/--image <file>` attaches images to the first prompt; other files: put the paths in the prompt (the agent reads them with its tools); `@` in the composer opens a file search | **No flag** | `codex "<prompt>"` | `codex exec` | *Unverified* (docs; not installed) |
| **Gemini CLI** | `cd <dir> && gemini` (`--include-directories` widens access) | `@<path>` in the prompt (contents read with `read_many_files`) | **No flag** | `gemini -i "<prompt>"` / `--prompt-interactive` (runs the prompt, stays interactive) | `gemini -p` | *Unverified* (docs; not installed) |

### Quoting rules

- **Shell (every `argv` element, the `cd` folder, the copied command line):** POSIX single quotes, `'` written as
  `'\''` (`AgentKit.ShellQuote`). Spaces, `"`, `$`, `` ` ``, `!`, `*` are then literal in sh, bash and zsh.
  fish reads `'\''` the same way; it differs only for a backslash inside single quotes (rare in paths; accepted).
  The command line is `cd '<cwd>' && '<argv0>' '<arg>' …`.
- **Claude Code `@` mentions (inside the prompt, not the shell).** The installed parser accepts two forms:
  `@"<path>"` (regex `(^|\s)@"([^"]+)"`) and an unquoted `@<non-whitespace>` token. So:
  - path with no whitespace → `@/abs/path` (a `"` inside is fine unquoted);
  - path with whitespace and no `"` → `@"/abs/my file.swift"`;
  - path with whitespace **and** `"` → cannot be mentioned; the bare path is typed instead (Claude can still read
    it when asked).
  - Mentions are joined by one space, with a trailing space so the user types right after them.
- **Gemini `@` mentions** (*unverified*): docs say spaces in `@` paths are escaped with a backslash
  (`@My\ Documents/file.txt`).
- **Codex** (*unverified*): no mention syntax at launch; paths are plain text in the prompt, quoted with `"` when
  they contain spaces.
- **AppleScript:** every string handed to a script goes through `AppleScriptText.literal` (`\` and `"` escaped).

### Risks recorded (manual check pending)

- Typing ahead: the mentions are written to the tab ~1.5 s after the command. If the agent is not reading yet the
  bytes wait in the tty input queue (Node's raw-mode switch drains, it does not flush), so they still land in the
  prompt. A slow shell start (heavy `.zshrc`, instant-prompt themes) could still eat them.
- Claude Code's **workspace trust dialog** (first run in a folder) comes before the prompt; typed characters
  reach the dialog instead. Nothing is submitted (no Return), but the mentions are lost in that case.

## Terminals: `openTab(argv:cwd:)`

| Terminal | How a command runs in a folder | Can type without Return | Permission | Decision | Status |
|---|---|---|---|---|---|
| **Terminal.app** | `tell application id "com.apple.Terminal" to do script "<cd && argv>"`. Without `in`, `do script` opens a **new window** (Terminal.app's dictionary has no "new tab"; a tab needs System Events `keystroke "t" using command down`, which needs Accessibility and is fragile). When Terminal.app was not running, `activate` opens its default window, so the script runs `in window 1` to avoid a second, empty window. Then `activate`. | **No** (`do script` always presses Return; typing needs System Events + Accessibility) | Automation for Terminal.app (-1743 → `SETUP · PERMISSION`) | New window, command = `promptArguments` form (files attached, sent) | AppleScript from the dictionary; *not run* |
| **iTerm2** | `create window with default profile` (none open) or `tell current window to create tab with default profile`, then `tell current session of current window to write text "<cd && argv>"` | **Yes**: `write text "<text>" newline no` after `delay 1.5` | Automation for iTerm2 | New tab, bare `claude`, mentions typed unsent | *Unverified* (iTerm2 not installed; documented AppleScript API) |
| **Warp** | No AppleScript dictionary. The registered `warp` scheme has `warp://action/new_tab?path=<dir>` (and `new_window`), seen in Warp's docs and as `new_tab` / `path` strings in the binary. A command can only run through a Launch Configuration YAML (`~/.warp/launch_configurations/`, opened with `warp://launch/<name>`), which would mean writing into Warp's own config folder: rejected (AD-17 paths, side effects). Typing = clipboard + `keystroke "v"` (Accessibility): rejected. | No | None (a URL open) | Open the new tab in `cwd`, activate Warp, copy the command line → `COMMAND COPIED` | URL scheme registration verified; the tab opening is *unverified* |
| **Ghostty** | `open -na Ghostty --args --working-directory=<dir> -e <cmd>` or the `ghostty` CLI with the same flags (new window, not a tab). Starting Ghostty with arguments means spawning a process, which terminal adapters may not do (`check-process-launch.sh`); a future adapter would go through an AD-19 service. | No | None | No adapter yet: the `terminal = "ghostty"` setting falls to the generic adapter | *Unverified* (docs; not installed) |
| **Generic fallback** | `open -b <bundle id>` cannot pass a command. | No | None | Activate the first running known terminal app, copy the command line → `COMMAND COPIED` | Verified by unit tests only |

Everything runs only from the drop (a user action, AD-23). A missing Automation permission on Terminal.app or
iTerm2 throws `TerminalFocusError.permissionRequired`, which `agents.sessions` turns into `SETUP · PERMISSION`
(the Story 5.1 alert) and the copied-command fallback.

## Follow-ups

- Manual check on an unlocked Mac: Terminal.app new window, iTerm2 tab + typed mentions (with the trust dialog
  case), Warp `new_tab?path=`.
- Codex and Gemini adapters (later epics) fill `launchCommand` per the rows above, after testing the installed
  CLIs.
