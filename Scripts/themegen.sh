#!/usr/bin/env bash
# Regenerates the built-in theme files from DESIGN.md frontmatter (AD-14):
# Themes/*.toml and the identical copy bundled as VigieUI resources.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/Themes}"
RESOURCES="${2:-$ROOT/Packages/VigieUI/Sources/VigieUI/Resources/Themes}"

cd "$ROOT/Packages/VigieUI"
swift run --build-system swiftbuild themegen \
  --design "$ROOT/docs/ux-designs/ux-vigie-2026-11-04/DESIGN.md" \
  --out "$OUT" \
  --resources "$RESOURCES"
