#!/usr/bin/env bash
# AD-25 / Story 20.3: only the Away service in VigieCore reads input idle time or the lock, screensaver,
# display-sleep and session notifications; modules and adapters read `context.away`. Fails if a module or adapter
# source names one of those APIs. Set MODULES_DIR (and ADAPTERS_DIR) to check another tree
# (Scripts/tests/module-away-test.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

dirs=("${MODULES_DIR:-Packages/Modules}")
adapters="${ADAPTERS_DIR:-Packages/Adapters}"
[ -d "${dirs[0]}" ] || { echo "error: ${dirs[0]} is missing" >&2; exit 1; }
[ -d "$adapters" ] && dirs+=("$adapters")

pattern='CGEventSource|secondsSinceLastEventType|com\.apple\.screenIsLocked|com\.apple\.screenIsUnlocked|[Ss]creensaver|screensDidSleep|screensDidWake|sessionDidResignActive|sessionDidBecomeActive|CGSessionCopyCurrentDictionary'
hits="$(grep -rHnE "$pattern" --include='*.swift' "${dirs[@]}" | grep -v '/Tests/' | grep -v '/\.build/' || true)"
if [ -n "$hits" ]; then
  echo "error: a module or adapter reads presence signals itself (AD-25: use context.away):" >&2
  echo "$hits" >&2
  exit 1
fi
echo "module-away guard: OK"
