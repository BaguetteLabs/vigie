#!/usr/bin/env bash
# The module-away guard passes on a clean tree and catches each planted presence read.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/Modules/Mod/Sources/Mod" "$TMP/Modules/Mod/Tests/ModTests" "$TMP/Adapters/Ad/Sources/Ad"
echo 'let x = context.away.presence' > "$TMP/Modules/Mod/Sources/Mod/A.swift"
echo 'let y = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)' \
  > "$TMP/Modules/Mod/Tests/ModTests/T.swift"
echo 'let z = 1' > "$TMP/Adapters/Ad/Sources/Ad/A.swift"
run() { MODULES_DIR="$TMP/Modules" ADAPTERS_DIR="$TMP/Adapters" "$ROOT/Scripts/check-module-away.sh"; }
run > /dev/null || { echo "FAIL: clean tree rejected" >&2; exit 1; }

for planted in \
  'let s = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)' \
  'let n = Notification.Name("com.apple.screenIsLocked")' \
  'let n = Notification.Name("com.apple.screensaver.didstart")' \
  'let n = NSWorkspace.screensDidSleepNotification' \
  'let n = NSWorkspace.sessionDidResignActiveNotification'; do
  for target in "$TMP/Modules/Mod/Sources/Mod/B.swift" "$TMP/Adapters/Ad/Sources/Ad/B.swift"; do
    echo "$planted" > "$target"
    if run > /dev/null 2>&1; then
      echo "FAIL: planted read not caught in $target: $planted" >&2
      exit 1
    fi
    rm "$target"
  done
done
echo "module-away-test: OK"
