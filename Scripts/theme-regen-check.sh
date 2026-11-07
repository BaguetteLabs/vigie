#!/usr/bin/env bash
# CI theme-regen-diff (AD-14): regenerates the built-in themes into a temp dir and fails if
# Themes/ or the VigieUI resources copy differ from the generator output.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$ROOT/Scripts/themegen.sh" "$TMP/out" "$TMP/out-resources" >/dev/null

status=0
for dest in "$ROOT/Themes" "$ROOT/Packages/VigieUI/Sources/VigieUI/Resources/Themes"; do
  # Only *.toml are generated; Themes/README.md is hand-written.
  if ! diff -r -x 'README.md' "$TMP/out" "$dest"; then
    echo "error: $dest differs from themegen output; run Scripts/themegen.sh and commit the result" >&2
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "theme-regen-check: OK"
exit "$status"
