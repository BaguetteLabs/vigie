#!/usr/bin/env bash
# Story 6.2: Scripts/release/check-tag.sh against a throwaway git repository. Tags on and off master, bad tag
# formats, pre-release detection, a project version that disagrees with the tag, and the GITHUB_OUTPUT lines.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
C="$ROOT/Scripts/release/check-tag.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "release-check-tag-test: FAIL: $*" >&2; exit 1; }

R="$TMP/repo"
git init -q -b master "$R"
g() { git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
g commit -q --allow-empty -m one
g tag -a v1.0.0 -m "Vigie 1.0.0"
g commit -q --allow-empty -m two
g tag v1.1.0-beta.1
g checkout -q -b side
g commit -q --allow-empty -m side
g tag -a v2.0.0 -m "not on master"
g checkout -q master
g tag v1.2 HEAD
g tag v01.0.0 HEAD

ok() { # ok <tag> <expected output line>...
  local tag="$1" out; shift
  out="$("$C" --repo "$R" --master master --tag "$tag" 2>&1)" || fail "$tag rejected: $out"
  for want in "$@"; do grep -qx "$want" <<<"$out" || fail "$tag: no line '$want' in: $out"; done
}
ko() { # ko <tag> <message fragment> [env...]
  local tag="$1" frag="$2" out; shift 2
  if out="$(env "$@" "$C" --repo "$R" --master master --tag "$tag" 2>&1)"; then fail "$tag accepted"; fi
  grep -q "^::error::.*$frag" <<<"$out" || fail "$tag: expected ::error:: with '$frag', got: $out"
}

ok v1.0.0 "version=1.0.0" "marketing_version=1.0.0" "prerelease=false"
ok v1.1.0-beta.1 "version=1.1.0-beta.1" "marketing_version=1.1.0" "prerelease=true"
ko v2.0.0 "is not on master"
ko v9.9.9 "does not exist"
ko v1.2 "is not vX.Y.Z"
ko v01.0.0 "is not vX.Y.Z"
ko 1.0.0 "is not vX.Y.Z"
ko "v1.0.0-" "is not vX.Y.Z"
"$C" --repo "$R" --master origin/master --tag v1.0.0 >/dev/null 2>&1 && fail "missing master ref accepted"

# The project version (Scripts/version.sh) disagrees with the tag, or rejects it.
cat > "$TMP/version-other.sh" <<'SH'
#!/usr/bin/env bash
printf 'MARKETING_VERSION = 9.9.9\nCURRENT_PROJECT_VERSION = 1\n'
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/version-reject.sh"
chmod +x "$TMP/version-other.sh" "$TMP/version-reject.sh"
ko v1.0.0 "does not match the project version '9.9.9'" VERSION_SH="$TMP/version-other.sh"
ko v1.0.0 "rejected the version" VERSION_SH="$TMP/version-reject.sh"

# Outputs for later jobs.
GITHUB_OUTPUT="$TMP/out" "$C" --repo "$R" --master master --tag v1.1.0-beta.1 >/dev/null
[ "$(cat "$TMP/out")" = $'tag=v1.1.0-beta.1\nversion=1.1.0-beta.1\nmarketing_version=1.1.0\nprerelease=true' ] \
  || fail "GITHUB_OUTPUT: $(cat "$TMP/out")"
: > "$TMP/out2"
GITHUB_OUTPUT="$TMP/out2" "$C" --repo "$R" --master master --tag v1.0.0 --dry-run >/dev/null
[ ! -s "$TMP/out2" ] || fail "dry run wrote GITHUB_OUTPUT"
echo "release-check-tag-test: OK"
