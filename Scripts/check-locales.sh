#!/usr/bin/env bash
# Usage: check-locales.sh <path/to/Vigie.app>
# Fails if a shipped locale has no <locale>.lproj in the app bundle or in any embedded
# package resource bundle (Contents/Resources/*.bundle). English only for now (AD-15).
set -euo pipefail

SHIPPED_LOCALES=(en)

APP="${1:?usage: check-locales.sh <app bundle path>}"
[ -d "$APP/Contents/Resources" ] || { echo "error: $APP is not an app bundle" >&2; exit 2; }

status=0
check() {
  local dir="$1"
  echo "==> ${dir#"$APP"/}: $(cd "$dir" && ls -d ./*.lproj 2>/dev/null | sed 's|^\./||;s|\.lproj$||' | tr '\n' ' ')"
  for loc in "${SHIPPED_LOCALES[@]}"; do
    if [ ! -d "$dir/$loc.lproj" ]; then
      echo "error: locale '$loc' missing from ${dir#"$APP"/}" >&2
      status=1
    fi
  done
}

check "$APP/Contents/Resources"
shopt -s nullglob
for bundle in "$APP"/Contents/Resources/*.bundle; do
  # Resource bundles hold either Contents/Resources (macOS layout) or a flat layout.
  if [ -d "$bundle/Contents/Resources" ]; then check "$bundle/Contents/Resources"; else check "$bundle"; fi
done
exit $status
