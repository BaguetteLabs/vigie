#!/usr/bin/env bash
# Manual focus check (Story 2.5, NFR2): with Vigie Dev visible, keystrokes still reach the frontmost app.
# Launches the Debug app, opens a new TextEdit document, types a sentence through System Events and reads
# the document text back. Needs Automation permission for your terminal (TextEdit, System Events) and
# Accessibility permission for keystrokes. Not run in CI.
#
# Usage: Scripts/check-focus.sh [path/to/Vigie Dev.app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/App/.build-dd/Build/Products/Debug/Vigie Dev.app}"
[ -d "$APP" ] || { echo "error: $APP not found; build the Debug app first (see App/README.md)" >&2; exit 1; }

SENTENCE="Vigie keeps focus where it belongs $RANDOM"

open "$APP"
sleep 2

osascript <<OSA
tell application "TextEdit"
  activate
  make new document
end tell
delay 1
tell application "System Events" to keystroke "$SENTENCE"
delay 1
OSA

frontmost="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')"
text="$(osascript -e 'tell application "TextEdit" to get text of front document')"

osascript -e 'tell application "TextEdit" to close front document saving no' || true
osascript -e 'tell application id "fr.baguettelabs.vigie.dev" to quit' || true

if [ "$frontmost" != "TextEdit" ]; then
  echo "FAIL: frontmost app is '$frontmost', expected TextEdit" >&2
  exit 1
fi
if [ "$text" != "$SENTENCE" ]; then
  echo "FAIL: TextEdit received '$text', expected '$SENTENCE'" >&2
  exit 1
fi
echo "check-focus: OK (TextEdit kept key status while Vigie Dev was visible)"
