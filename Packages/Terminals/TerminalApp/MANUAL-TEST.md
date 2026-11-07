# Terminal.app focus — manual test (Story 5.2)

Needs Automation permission for the process sending the Apple Events (Vigie, or the shell used below) to
control Terminal (System Settings › Privacy & Security › Automation).

1. Open Terminal.app with three windows × two tabs (`⌘N`, `⌘T`).
2. List each tab's tty:
   `/usr/bin/osascript -e 'tell application "Terminal" to get tty of tabs of windows'`
3. For each tty, bring another window to the front, then run the adapter's script
   (`TerminalAppAdapter.focusScript(tty:)`, printed by a test or copied from the source with the tty filled in)
   through `/usr/bin/osascript`. Expect `found`, and that window in front with that tab selected.
4. Run it with an unused tty (`/dev/ttys999`): expect `notfound` and Terminal.app activated, tab unchanged.
5. In Vigie: deny Automation for Terminal, press Focus on a Terminal.app session: Terminal.app comes to the
   front without changing tab (and, once Story 5.1 lands, `SETUP · PERMISSION` appears).
