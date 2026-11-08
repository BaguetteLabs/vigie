#!/usr/bin/env bash
# AD-19 / Story 9.10: modules never read the clipboard. `⌘V` and Services go through the host (VigieCore's
# PasteboardReader); `context.clipboard` is copy-only. Fails if a module's sources touch the general pasteboard
# (or any named one). Set MODULES_DIR to check another tree (Scripts/tests/module-pasteboard-test.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

dir="${MODULES_DIR:-Packages/Modules}"
[ -d "$dir" ] || { echo "error: $dir is missing" >&2; exit 1; }

hits="$(grep -rHnE 'NSPasteboard[[:space:]]*\.[[:space:]]*general|NSPasteboard[[:space:]]*\([[:space:]]*name|\.generalPasteboard|UIPasteboard' \
  --include='*.swift' "$dir" | grep -v '/Tests/' | grep -v '/\.build/' || true)"
if [ -n "$hits" ]; then
  echo "error: pasteboard access in a module (AD-19: the host reads the clipboard; context.clipboard is copy-only):" >&2
  echo "$hits" >&2
  exit 1
fi
echo "module-pasteboard guard: OK"
