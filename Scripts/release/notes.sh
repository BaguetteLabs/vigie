#!/usr/bin/env bash
# Story 6.2 (SPEC §12.3 steps 6-7): release notes of a tag, in Markdown, on stdout.
#   notes.sh --tag vX.Y.Z[-suffix] [--repo DIR]
# Source, first found:
#   1. the `## X.Y.Z` (or `## [X.Y.Z]`, `## vX.Y.Z`, with an optional ` - date` after it) section of CHANGELOG.md
#      at the tagged commit, up to the next `## ` heading;
#   2. the message of an annotated tag (a PGP/SSH signature block is dropped);
#   3. "Vigie X.Y.Z".
# publish.sh uses it for the public release; Story 6.3 reuses it for the appcast.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

tag="" repo="$RELEASE_ROOT"
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) tag="${2-}"; shift 2 ;;
    --repo) repo="${2-}"; shift 2 ;;
    *) echo "usage: notes.sh --tag vX.Y.Z[-suffix] [--repo DIR]" >&2; exit 2 ;;
  esac
done
[ -n "$tag" ] || die "--tag is required"
version="${tag#v}"

trim() { awk 'NF { started = 1 } started { lines[++n] = $0 } END { while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }'; }

changelog="$(git -C "$repo" show "refs/tags/$tag:CHANGELOG.md" 2>/dev/null || true)"
if [ -n "$changelog" ]; then
  section="$(printf '%s\n' "$changelog" | awk -v v="$version" '
    /^## / {
      if (found) exit
      h = $0; sub(/^## +/, "", h); sub(/^\[/, "", h); sub(/^v/, "", h)
      split(h, parts, /[] \t]/)
      if (parts[1] == v) { found = 1; next }
    }
    found { print }' | trim)"
  if [ -n "$section" ]; then printf '%s\n' "$section"; exit 0; fi
fi

if [ "$(git -C "$repo" cat-file -t "refs/tags/$tag" 2>/dev/null)" = tag ]; then
  message="$(git -C "$repo" for-each-ref --format='%(contents)' "refs/tags/$tag" \
    | awk '/^-----BEGIN (PGP|SSH) SIGNATURE-----/ { skip = 1 } !skip { print }' | trim)"
  if [ -n "$message" ]; then printf '%s\n' "$message"; exit 0; fi
fi

echo "Vigie $version"
