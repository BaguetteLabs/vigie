#!/usr/bin/env bash
# Tests for Scripts/dev-signing.sh (keychain prompt loop fix, Story 6.1 --team) with a fake `security` on PATH:
# never reads the real keychain. Team filtering reads the OU of real throwaway certificates made with openssl.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="$ROOT/Scripts/dev-signing.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "dev-signing-test: FAIL: $*" >&2; exit 1; }
SELF=0123456789ABCDEF0123456789ABCDEF01234567

# Two Apple Development certificates of different teams (OU = team id).
cert() { # $1: file stem, $2: CN, $3: OU; prints the SHA-1
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -keyout "$TMP/$1.key" -out "$TMP/$1.pem" \
    -subj "/CN=$2/OU=$3/O=Test/C=US" > /dev/null 2>&1
  openssl x509 -in "$TMP/$1.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g'
}
NAME_A="Apple Development: Jane Doe (PERSONAAAA)" NAME_B="Apple Development: Jane Doe (PERSONBBBB)"
A="$(cert a "$NAME_A" TEAMAAAAAA)" B="$(cert b "$NAME_B" TEAMBBBBBB)"
{ for c in a b; do
  echo "SHA-256 hash: 0000"; echo "SHA-1 hash: $(openssl x509 -in "$TMP/$c.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
  cat "$TMP/$c.pem"
done; } > "$TMP/certs"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/security" <<'FAKE'
#!/bin/sh
case "$1 $2 $3 $4" in
  "find-identity -v -p codesigning") cat "$FAKE_IDENTITIES" ;;
  "find-certificate -a -Z -p") cat "$FAKE_CERTS" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
FAKE
chmod +x "$TMP/bin/security"
run() { FAKE_IDENTITIES="$TMP/ids" FAKE_CERTS="$TMP/certs" PATH="$TMP/bin:$PATH" "$S" "$@"; }

# One Apple Development identity wins over the self-signed one; --print writes nothing.
cat > "$TMP/ids" <<IDS
  1) $SELF "Vigie Dev Signing"
  2) $A "$NAME_A"
     2 valid identities found
IDS
out="$(run --print --output "$TMP/local.xcconfig")"
[ ! -e "$TMP/local.xcconfig" ] || fail "--print wrote a file"
[ "$(printf '%s\n' "$out" | sed -n 2p)" = "CODE_SIGN_IDENTITY[config=Debug] = $A" ] || fail "dev identity: $out"
printf '%s\n' "$out" | head -1 | grep -qF "$NAME_A" || fail "CN comment: $out"
printf '%s\n' "$out" | grep -q DEVELOPMENT_TEAM && fail "no --team wrote a team: $out"

# Without --print the file is written.
run --output "$TMP/sub/local.xcconfig" > /dev/null
[ "$(cat "$TMP/sub/local.xcconfig")" = "$out" ] || fail "written file differs from --print"

# Two Apple Development identities without --team: listed with their teams, exit 1, nothing written.
cat > "$TMP/ids" <<IDS
  1) $A "$NAME_A"
  2) $B "$NAME_B"
     2 valid identities found
IDS
if run --output "$TMP/two.xcconfig" > /dev/null 2> "$TMP/err"; then fail "two identities without --team should exit 1"; fi
[ ! -e "$TMP/two.xcconfig" ] || fail "two identities wrote a file"
grep -q -- "--team" "$TMP/err" || fail "no --team hint: $(cat "$TMP/err")"
grep -qF "team TEAMAAAAAA: $NAME_A ($A)" "$TMP/err" && grep -qF "team TEAMBBBBBB: $NAME_B ($B)" "$TMP/err" ||
  fail "identity list: $(cat "$TMP/err")"

# --team picks the identity whose certificate OU is the team (the second one here) and writes automatic signing.
out="$(run --team TEAMBBBBBB --print)"
expected="DEVELOPMENT_TEAM[config=Debug] = TEAMBBBBBB
CODE_SIGN_STYLE[config=Debug] = Automatic
CODE_SIGN_IDENTITY[config=Debug] = Apple Development
CODE_SIGN_ENTITLEMENTS[config=Debug] = Vigie.signed.entitlements"
[ "$(printf '%s\n' "$out" | tail -n +2)" = "$expected" ] || fail "--team TEAMBBBBBB: $out"
printf '%s\n' "$out" | head -1 | grep -qF "$NAME_B ($B)" || fail "--team comment: $out"
printf '%s\n' "$out" | grep -q "config=Release" && fail "--team touched Release: $out"
run --team TEAMAAAAAA --print | head -1 | grep -qF "$NAME_A ($A)" || fail "--team TEAMAAAAAA"
run --team TEAMBBBBBB --output "$TMP/team.xcconfig" > /dev/null
[ "$(cat "$TMP/team.xcconfig")" = "$out" ] || fail "--team written file differs from --print"

# --team with no identity of that team (the self-signed one does not count): exit 1, nothing written.
if run --team TEAMCCCCCC --output "$TMP/none.xcconfig" > /dev/null 2> "$TMP/err"; then fail "unknown team should exit 1"; fi
[ ! -e "$TMP/none.xcconfig" ] || fail "unknown team wrote a file"
grep -q "team TEAMCCCCCC" "$TMP/err" || fail "unknown team message: $(cat "$TMP/err")"
run --team bogus --print > /dev/null 2>&1 && fail "malformed team accepted"
run --team > /dev/null 2>&1 && fail "--team without a value accepted"

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
