#!/usr/bin/env bash
# Test hygiene: tests never create or front real windows (they steal focus from the developer). Windows come from
# the per-target OffscreenHost.swift helper (hostOffscreen), which parks them far off every screen. Fails if any
# Tests/**/*.swift outside a file named OffscreenHost.swift fronts a window, makes one key, or builds one directly.
# Set TESTS_ROOT to check another tree (Scripts/tests/test-windows-test.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

root="${TESTS_ROOT:-Packages}"
[ -d "$root" ] || { echo "error: $root is missing" >&2; exit 1; }

hits="$(find "$root" -type d -name .build -prune -o -type f -path '*/Tests/*' -name '*.swift' ! -name OffscreenHost.swift -print0 \
  | xargs -0 grep -HnE 'orderFront|makeKey(AndOrderFront)?[[:space:]]*\(|NSWindow[[:space:]]*\([[:space:]]*contentRect|NSPanel[[:space:]]*\([[:space:]]*contentRect' 2>/dev/null \
  | grep -vE 'func makeKey' || true)"
if [ -n "$hits" ]; then
  echo "error: test creates or fronts a real window (use hostOffscreen from OffscreenHost.swift):" >&2
  echo "$hits" >&2
  exit 1
fi
echo "test-windows guard: OK"
