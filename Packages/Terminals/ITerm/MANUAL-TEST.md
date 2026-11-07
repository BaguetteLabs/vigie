# iTerm2 focus — manual test (Story 5.3)

Not run yet: iTerm2 is not installed on the dev Mac. Run this once it is.

Needs Automation permission for the process sending the Apple Events (Vigie, or the shell used below) to
control iTerm2 (System Settings › Privacy & Security › Automation). The script only compiles where iTerm2 is
installed (its AppleScript dictionary supplies `sessions` and `unique ID`).

1. In iTerm2 open three windows; give one window two tabs and split one tab vertically (`⌘D`).
2. In each pane run `echo $ITERM_SESSION_ID; tty` and note the UUID after `:`.
3. Bring another window to the front, then run `ITermAdapter.focusScript(.sessionID("<UUID>"))` (copy from the
   source with the UUID filled in) through `/usr/bin/osascript`. Expect `found`, and that window in front with
   that tab and that split pane selected. Repeat for every pane.
4. Close one pane and run the script with its UUID: expect `notfound` and iTerm2 activated (fallback).
5. Quit iTerm2 and run it again: expect `notrunning` and iTerm2 not launched by the script.
6. In Vigie, start a Claude Code session in an iTerm2 pane, then Focus it from the peek (`⌥⌘↵`) and from the
   Agents tab: the exact pane comes forward. Deny Automation for iTerm2 and Focus again: iTerm2 comes to the
   front without changing pane (and, once Story 5.1 lands, `SETUP · PERMISSION` appears).
7. Check `select` behaviour if a pane is not focused: if `tell s to select` does not move keyboard focus to the
   split pane, note the iTerm2 version and file it against Story 5.3.
