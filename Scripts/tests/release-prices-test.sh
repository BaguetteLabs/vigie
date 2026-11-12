#!/usr/bin/env bash
# Story 6.5: Scripts/release/prices.sh with a throwaway Ed25519 key (openssl, or the RFC 8032 test vector; never a
# keychain). Dry runs write nothing and need no key; sign writes prices.json (the repository file, byte for byte)
# and prices.json.sig (one base64 Ed25519 signature line) that verifies with the public key and fails for an
# edited table; malformed tables and a stale bundled copy are refused; publish-latest targets the latest release.
# Needs network once to download the pinned Sparkle tools (cached like release-sparkle-test.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REL="$ROOT/Scripts/release"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "release-prices-test: FAIL: $*" >&2; exit 1; }
has() { grep -qF -- "$2" <<<"$1" || fail "$3: no '$2' in output"; }
hasnt() { if grep -qF -- "$2" <<<"$1"; then fail "$3: '$2' must not appear"; fi; }
export SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-${TMPDIR:-/tmp}/vigie-sparkle-tools}"
unset GITHUB_ACTIONS SPARKLE_PRIVATE_KEY GH_TOKEN || true

# --- The repository table is valid and the bundled copy is identical (also a Swift test).
cmp -s "$ROOT/prices/prices.json" "$ROOT/Packages/Modules/AgentsUsage/Sources/AgentsUsage/Resources/prices.json" \
  || fail "bundled prices.json differs from prices/prices.json"

# --- Dry runs: no key, nothing written.
o="$("$REL/prices.sh" sign --dist "$TMP/dry" --dry-run)" || fail "sign dry run"
has "$o" "--ed-key-file -" "dry run signs with the key on stdin"
has "$o" "prices.json.sig" "dry run names the signature file"
[ ! -e "$TMP/dry" ] || fail "sign dry run wrote files"
o="$("$REL/prices.sh" publish-latest --repo BaguetteLabs/vigie-releases --dist "$TMP/dry" --dry-run)" || fail "publish dry run"
has "$o" "gh release upload" "publish uploads"
has "$o" "--clobber" "publish replaces the previous files"
has "$o" "prices.json.sig" "publish uploads the signature"
"$REL/prices.sh" publish-latest --repo OWNER --dist "$TMP/dry" --dry-run >/dev/null 2>&1 && fail "malformed repo accepted"
"$REL/prices.sh" publish-latest --repo a/b --dist "$TMP/dry" >/dev/null 2>&1 && fail "publish without GH_TOKEN ran"

# --- Refusals: malformed tables, and a canonical table whose bundled copy is stale.
printf '{"schema": 1, "version": 3, "models": {}}' > "$TMP/v1.json"
"$REL/prices.sh" sign --dist "$TMP/x" --source "$TMP/v1.json" --dry-run >/dev/null 2>&1 && fail "schema 1 table accepted"
printf '{"schema": 2, "version": "3", "providers": {"claude": {}}}' > "$TMP/bad.json"
"$REL/prices.sh" sign --dist "$TMP/x" --source "$TMP/bad.json" --dry-run >/dev/null 2>&1 && fail "malformed table accepted"
FAKE="$TMP/root"; mkdir -p "$FAKE/Scripts" "$FAKE/prices" "$FAKE/Packages/Modules/AgentsUsage/Sources/AgentsUsage/Resources"
cp -R "$REL" "$FAKE/Scripts/release"
cp "$ROOT/prices/prices.json" "$FAKE/prices/prices.json"
sed 's/"version": [0-9]*/"version": 999/' "$ROOT/prices/prices.json" > "$FAKE/Packages/Modules/AgentsUsage/Sources/AgentsUsage/Resources/prices.json"
o="$("$FAKE/Scripts/release/prices.sh" sign --dist "$TMP/x" --dry-run 2>&1)" && fail "stale bundled copy accepted"
has "$o" "differ" "stale copy message"

# --- Throwaway key.
OSSL=""
for b in openssl /opt/homebrew/bin/openssl /usr/local/bin/openssl; do
  if command -v "$b" >/dev/null 2>&1 && "$b" genpkey -algorithm ed25519 >/dev/null 2>&1; then OSSL="$(command -v "$b")"; break; fi
done
if [ -n "$OSSL" ]; then
  "$OSSL" genpkey -algorithm ed25519 -out "$TMP/k.pem" 2>/dev/null
  SEED="$("$OSSL" pkey -in "$TMP/k.pem" -outform DER | tail -c 32 | base64)"
  PUB="$("$OSSL" pkey -in "$TMP/k.pem" -pubout -outform DER | tail -c 32 | base64)"
else
  echo "release-prices-test: no openssl with Ed25519; using the fixed test vector (public-key checks skipped)"
  SEED="nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
  PUB="11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
fi
export SPARKLE_PRIVATE_KEY="$SEED"

# --- Sign / verify round trip.
DIST="$TMP/dist"
o="$("$REL/prices.sh" sign --dist "$DIST")" || fail "sign"
hasnt "$o" "$SEED" "private key in output"
cmp -s "$DIST/prices.json" "$ROOT/prices/prices.json" || fail "published table differs from the repository file"
SIG="$(cat "$DIST/prices.json.sig")"
[[ "$SIG" =~ ^[A-Za-z0-9+/]{86}==$ ]] || fail "signature file is not one base64 Ed25519 signature: $SIG"
[ "$(wc -l < "$DIST/prices.json.sig" | tr -d ' ')" = 1 ] || fail "signature file is not one line"
"$REL/sign-update.sh" verify --file "$DIST/prices.json" --signature "$SIG" || fail "signature rejected (sign_update)"
if [ -n "$OSSL" ]; then
  "$REL/sign-update.sh" verify --file "$DIST/prices.json" --signature "$SIG" --public-key "$PUB" \
    || fail "signature rejected with the public key (what the app checks)"
  sed 's/"input": 4,/"input": 0.4,/' "$DIST/prices.json" > "$TMP/edited.json"
  cmp -s "$TMP/edited.json" "$DIST/prices.json" && fail "edit did not change the table"
  "$REL/sign-update.sh" verify --file "$TMP/edited.json" --signature "$SIG" --public-key "$PUB" && fail "edited table verified"
fi
env -u SPARKLE_PRIVATE_KEY "$REL/prices.sh" sign --dist "$TMP/nokey" >/dev/null 2>&1 && fail "sign without key ran"
echo "release-prices-test: OK"
