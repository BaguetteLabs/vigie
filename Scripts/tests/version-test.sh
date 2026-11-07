#!/usr/bin/env bash
# Tests for Scripts/version.sh (Story 6.4).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
V="$ROOT/Scripts/version.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "version-test: FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"; }

eq "$("$V" --tag v1.2.3 --build 42)" $'MARKETING_VERSION = 1.2.3\nCURRENT_PROJECT_VERSION = 42' "tag with v"
eq "$("$V" --tag 10.0.1 --build 7 | head -1)" "MARKETING_VERSION = 10.0.1" "tag without v"
eq "$("$V" --build 5 | head -1)" "MARKETING_VERSION = 0.0.0" "dev version"
for bad in v1.2 v1.2.3-beta 1.02.3 vx.y.z "v1.2.3 " ""; do
  if "$V" --tag "$bad" --build 1 >/dev/null 2>&1; then
    [ -z "$bad" ] && continue
    fail "tag '$bad' should be rejected"
  fi
done
for bad in 0 abc -3 1.5; do
  "$V" --build "$bad" >/dev/null 2>&1 && fail "build '$bad' should be rejected"
done
fallback="$("$V" | sed -n 2p)"
[[ "$fallback" =~ ^CURRENT_PROJECT_VERSION\ =\ [1-9][0-9]*$ ]] || fail "build fallback: '$fallback'"
"$V" --tag v2.0.0 --build 9 --xcconfig "$TMP/sub/Version.xcconfig"
eq "$(cat "$TMP/sub/Version.xcconfig")" $'MARKETING_VERSION = 2.0.0\nCURRENT_PROJECT_VERSION = 9' "xcconfig"
echo "version-test: OK"
