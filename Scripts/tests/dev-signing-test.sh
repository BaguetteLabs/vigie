#!/usr/bin/env bash
# Tests for Scripts/dev-signing.sh (keychain prompt loop fix) with a fake `security` on PATH: never reads the
# real keychain.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="$ROOT/Scripts/dev-signing.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "dev-signing-test: FAIL: $*" >&2; exit 1; }
DEV=938616608F7563FFC3033680E3AA762BBA0D4D14
SELF=0123456789ABCDEF0123456789ABCDEF01234567

mkdir -p "$TMP/bin"
cat > "$TMP/bin/security" <<'FAKE'
#!/bin/sh
[ "$1 $2 $3 $4" = "find-identity -v -p codesigning" ] || { echo "unexpected: $*" >&2; exit 9; }
cat "$FAKE_IDENTITIES"
FAKE
chmod +x "$TMP/bin/security"
run() { FAKE_IDENTITIES="$TMP/ids" PATH="$TMP/bin:$PATH" "$S" "$@"; }

# An Apple Development identity wins over the self-signed one; --print writes nothing.
cat > "$TMP/ids" <<IDS
  1) $SELF "Vigie Dev Signing"
  2) $DEV "Apple Development: Jane Doe (TEAM123456)"
     2 valid identities found
IDS
out="$(run --print --output "$TMP/local.xcconfig")"
[ ! -e "$TMP/local.xcconfig" ] || fail "--print wrote a file"
[ "$(printf '%s\n' "$out" | sed -n 2p)" = "CODE_SIGN_IDENTITY[config=Debug] = $DEV" ] || fail "dev identity: $out"
printf '%s\n' "$out" | head -1 | grep -q "Apple Development: Jane Doe (TEAM123456)" || fail "CN comment: $out"

# Without --print the file is written.
run --output "$TMP/sub/local.xcconfig" > /dev/null
[ "$(cat "$TMP/sub/local.xcconfig")" = "$out" ] || fail "written file differs from --print"

# Only the self-signed certificate.
printf '  1) %s "Vigie Dev Signing"\n     1 valid identities found\n' "$SELF" > "$TMP/ids"
run --print | grep -qx "CODE_SIGN_IDENTITY\[config=Debug\] = $SELF" || fail "self-signed identity"

# Neither: steps on stderr, exit 1, nothing written.
printf '  1) %s "Developer ID Application: Someone (X)"\n     1 valid identities found\n' "$SELF" > "$TMP/ids"
if run --output "$TMP/none.xcconfig" > /dev/null 2> "$TMP/err"; then fail "no identity should exit 1"; fi
[ ! -e "$TMP/none.xcconfig" ] || fail "no identity wrote a file"
grep -q "Certificate Assistant" "$TMP/err" && grep -q "Code Signing: Always Trust" "$TMP/err" || fail "steps"

run --bogus > /dev/null 2>&1 && fail "unknown option accepted"
echo "dev-signing-test: OK"
