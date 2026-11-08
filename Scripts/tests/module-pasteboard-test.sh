#!/usr/bin/env bash
# The module-pasteboard guard passes on a clean tree and catches a planted clipboard read.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/Mod/Sources/Mod" "$TMP/Mod/Tests/ModTests"
echo 'let x = context.clipboard' > "$TMP/Mod/Sources/Mod/A.swift"
echo 'let y = NSPasteboard.general.string(forType: .string)' > "$TMP/Mod/Tests/ModTests/T.swift"
MODULES_DIR="$TMP" "$ROOT/Scripts/check-module-pasteboard.sh" > /dev/null || { echo "FAIL: clean tree rejected" >&2; exit 1; }

echo 'let s = NSPasteboard.general.string(forType: .string)' > "$TMP/Mod/Sources/Mod/B.swift"
if MODULES_DIR="$TMP" "$ROOT/Scripts/check-module-pasteboard.sh" > /dev/null 2>&1; then
  echo "FAIL: planted NSPasteboard.general read not caught" >&2
  exit 1
fi
echo "module-pasteboard-test: OK"
