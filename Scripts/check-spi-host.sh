#!/usr/bin/env bash
# AD-13 guard: only VigieCore mints UserIntent. `@_spi(Host)` (the SPI that exposes UserIntent.init) may
# appear only in Packages/VigieCore/ and in package test targets (Packages/*/Tests/).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

hits="$(grep -rn --include='*.swift' '@_spi(Host)' Packages App 2>/dev/null \
  | grep -v '^Packages/VigieCore/' \
  | grep -vE '^Packages/([^/]+/)+Tests/' \
  | grep -v '^Packages/ModuleKit/Sources/ModuleKit/' || true)"

if [ -n "$hits" ]; then
  echo "error: @_spi(Host) used outside VigieCore and tests (AD-13):" >&2
  echo "$hits" >&2
  exit 1
fi
echo "spi-host guard: OK"
