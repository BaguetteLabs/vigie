#!/usr/bin/env bash
# AD-14 lint: views read colors and durations only from the theme.
# Flags hex colors / Color(red:) / Color(hex in Swift sources, and literal durations in View files,
# outside the theme engine (Theme/), the theme generator and tests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PATHS=(
  Packages/VigieUI/Sources
  Packages/Modules
  Packages/VigieCore/Sources/VigieCore/Host
)

files=()
for p in "${PATHS[@]}"; do
  [ -d "$p" ] || continue
  while IFS= read -r f; do files+=("$f"); done < <(
    find "$p" -name '*.swift' \
      -not -path '*/Theme/*' \
      -not -path '*/Tests/*' \
      -not -path '*/ThemeGenKit/*' \
      -not -path '*/themegen/*' | sort
  )
done

status=0
if [ "${#files[@]}" -gt 0 ]; then
  if grep -HnE 'Color\(red:|Color\(hex|#[0-9A-Fa-f]{6}\b' "${files[@]}"; then
    echo "error: color literals above; read colors from the theme (AD-14)" >&2
    status=1
  fi
  view_files=()
  for f in "${files[@]}"; do
    grep -qE ':[[:space:]]*(some[[:space:]]+)?View\b|some View' "$f" && view_files+=("$f")
  done
  if [ "${#view_files[@]}" -gt 0 ] &&
    grep -HnE '\.seconds\(|\.milliseconds\(|Duration\.|(duration|delay|after):[[:space:]]*[0-9]' "${view_files[@]}"; then
    echo "error: literal durations above in view code; read motion from the theme (AD-14)" >&2
    status=1
  fi
fi
[ "$status" -eq 0 ] && echo "check-view-literals: OK"
exit "$status"
