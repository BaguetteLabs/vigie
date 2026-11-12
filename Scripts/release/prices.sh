#!/usr/bin/env bash
# Story 6.5 (AD-16, SPEC §11 `[updates] prices`): the signed price table on the public release host.
#   prices.sh sign --dist DIR [--source FILE] [--dry-run]
#       check FILE (default prices/prices.json: schema 2, integer version, a providers map, the bundled copy in
#       AgentsUsage identical), copy it to DIR/prices.json and EdDSA-sign it with the Sparkle key
#       (sign-update.sh sign: sign_update, the key on stdin) into DIR/prices.json.sig, one line holding the base64
#       Ed25519 signature of the file's bytes. publish.sh then uploads both with the release.
#   prices.sh publish-latest --repo OWNER/NAME --dist DIR [--dry-run]
#       upload DIR/prices.json and DIR/prices.json.sig to the latest release of OWNER/NAME, replacing the old ones
#       (prices.yml: the prices/ folder changed on master between releases).
# The app fetches https://github.com/<RELEASE_REPO>/releases/latest/download/prices.json and .sig, verifies the
# signature with SUPublicEDKey and keeps a table only when its version is above the one in use.
# SPARKLE_PRIVATE_KEY (sign) and GH_TOKEN = RELEASE_REPO_TOKEN (publish-latest) are release secrets.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  echo "usage: prices.sh sign --dist DIR [--source FILE] [--dry-run] | publish-latest --repo OWNER/NAME --dist DIR [--dry-run]" >&2
  exit 2
}

cmd="${1-}"; shift || true
dist="" source="$RELEASE_ROOT/prices/prices.json" repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dist) dist="${2-}"; shift 2 ;;
    --source) source="${2-}"; shift 2 ;;
    --repo) repo="${2-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$dist" ] || usage
redact "${SPARKLE_PRIVATE_KEY:-}" "${GH_TOKEN:-}"
BUNDLED="$RELEASE_ROOT/Packages/Modules/AgentsUsage/Sources/AgentsUsage/Resources/prices.json"

# check_table FILE: the shape the app decodes (PriceTable, schema 2). Prints the version.
check_table() {
  /usr/bin/python3 -I - "$1" <<'PY' || die "$1 is not a schema 2 price table"
import json, re, sys
t = json.load(open(sys.argv[1]))
assert t.get("schema") == 2, "schema"
assert isinstance(t.get("version"), int) and not isinstance(t["version"], bool) and t["version"] > 0, "version"
providers = t.get("providers")
assert isinstance(providers, dict) and providers, "providers"
for pid, p in providers.items():
    assert re.fullmatch(r"[a-z][a-z0-9-]*", pid), pid
    for k in ("currency", "unit", "updated"):
        assert isinstance(p.get(k), str), pid + "." + k
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", p["updated"]), pid + ".updated"
    for mid, m in p.get("models", {}).items():
        for k in ("input", "output", "cache_write", "cache_read"):
            assert isinstance(m.get(k), (int, float)) and not isinstance(m[k], bool), pid + "/" + mid + "." + k
print(t["version"])
PY
}

case "$cmd" in
  sign)
    [ -f "$source" ] || die "$source not found"
    version="$(check_table "$source")"
    if [ "$source" = "$RELEASE_ROOT/prices/prices.json" ] && [ -f "$BUNDLED" ]; then
      cmp -s "$source" "$BUNDLED" || die "prices/prices.json and the bundled copy in AgentsUsage differ: copy it"
    fi
    say "== price table version $version"
    run mkdir -p "$dist"
    run cp "$source" "$dist/prices.json"
    if [ "$DRY_RUN" = 1 ]; then
      "$(dirname "${BASH_SOURCE[0]}")/sign-update.sh" sign --file "$dist/prices.json" --dry-run
      say "+ write the base64 signature to $dist/prices.json.sig"
      exit 0
    fi
    out="$("$(dirname "${BASH_SOURCE[0]}")/sign-update.sh" sign --file "$dist/prices.json")" || die "signing failed"
    sig="$(printf '%s' "$out" | sed -n 's/^sparkle:edSignature="\([A-Za-z0-9+/=]*\)".*/\1/p')"
    [[ "$sig" =~ ^[A-Za-z0-9+/]{86}==$ ]] || die "unexpected signature output"
    printf '%s\n' "$sig" > "$dist/prices.json.sig"
    say "prices: signed $dist/prices.json (version $version)"
    ;;
  publish-latest)
    [[ "$repo" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] \
      || die "release repository '$repo' is not OWNER/NAME (set the RELEASE_REPO variable, docs/release-setup.md)"
    [ "$DRY_RUN" = 1 ] || [ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is not set (release secret RELEASE_REPO_TOKEN)"
    [ "$DRY_RUN" = 1 ] || { [ -f "$dist/prices.json" ] && [ -f "$dist/prices.json.sig" ]; } || die "run prices.sh sign first"
    if [ "$DRY_RUN" = 1 ]; then
      tag="<latest>"
      say "+ gh release view --repo $repo --json tagName --jq .tagName"
    else
      tag="$(gh release view --repo "$repo" --json tagName --jq .tagName)" || die "$repo has no latest release yet"
    fi
    run gh release upload "$tag" --repo "$repo" --clobber "$dist/prices.json" "$dist/prices.json.sig"
    say "prices: https://github.com/$repo/releases/latest/download/prices.json"
    ;;
  *) usage ;;
esac
