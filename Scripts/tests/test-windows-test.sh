#!/usr/bin/env bash
# The test-windows guard passes on a clean tree (helper exempt) and catches planted window code.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/P/Tests/PTests"
echo 'window.orderFrontRegardless()' > "$TMP/P/Tests/PTests/OffscreenHost.swift"
echo 'let w = hostOffscreen(v, size: .zero)' > "$TMP/P/Tests/PTests/T.swift"
TESTS_ROOT="$TMP" "$ROOT/Scripts/check-test-windows.sh" > /dev/null || { echo "FAIL: clean tree rejected" >&2; exit 1; }

for bad in 'w.orderFront(nil)' 'w.makeKeyAndOrderFront(nil)' 'let w = NSWindow(contentRect: r, styleMask: [], backing: .buffered, defer: false)'; do
  echo "$bad" > "$TMP/P/Tests/PTests/Bad.swift"
  if TESTS_ROOT="$TMP" "$ROOT/Scripts/check-test-windows.sh" > /dev/null 2>&1; then
    echo "FAIL: planted violation not caught: $bad" >&2
    exit 1
  fi
done
echo "test-windows-test: OK"
