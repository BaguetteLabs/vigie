#!/usr/bin/env bash
# Story 6.3: Sparkle signing and the stable appcast, with a throwaway Ed25519 key (never a keychain: generate_keys
# is not used; openssl makes the key, or a fixed test vector when openssl lacks Ed25519).
#   - sign-update.sh: pinned tools (version = App/project.yml), sign + verify round trip (Sparkle and openssl with
#     the public key), a tampered zip fails verification, public key derivation, check-config, dry runs.
#   - appcast.sh: well-formed XML, item fields, pre-release skipped, previous items kept, same version replaced,
#     signed feed verifies and fails once edited, dry run writes nothing.
# Needs network once to download the pinned Sparkle tools (cached in SPARKLE_TOOLS_DIR or RUNNER_TEMP/TMPDIR).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REL="$ROOT/Scripts/release"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "release-sparkle-test: FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"; }
has() { grep -qF -- "$2" <<<"$1" || fail "$3: no '$2' in output"; }
hasnt() { if grep -qF -- "$2" <<<"$1"; then fail "$3: '$2' must not appear"; fi; }
export SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-${TMPDIR:-/tmp}/vigie-sparkle-tools}"
unset GITHUB_ACTIONS SPARKLE_PRIVATE_KEY || true

# --- Pinned tools: same version as the app's package pin.
pinned="$(sed -n 's/^SPARKLE_VERSION=//p' "$REL/sign-update.sh")"
eq "$(awk '/^  Sparkle:/ { s = 1 } s && /exactVersion:/ { print $2; exit }' "$ROOT/App/project.yml")" "$pinned" "Sparkle pin in project.yml vs sign-update.sh"
BIN="$("$REL/sign-update.sh" tools)" || fail "tools download"
[ -x "$BIN/sign_update" ] || fail "sign_update missing in $BIN"

# --- Throwaway key: base64 Ed25519 seed (the `generate_keys -x` format) and its public key.
OSSL=""
for b in openssl /opt/homebrew/bin/openssl /usr/local/bin/openssl; do
  if command -v "$b" >/dev/null 2>&1 && "$b" genpkey -algorithm ed25519 >/dev/null 2>&1; then OSSL="$(command -v "$b")"; break; fi
done
if [ -n "$OSSL" ]; then
  # An xcconfig treats `//` as a comment, so a key whose base64 contains it cannot be configured; the
  # setup doc says to regenerate such a key. Do the same here so the check-config step is deterministic.
  PUB=//
  while [[ "$PUB" == *//* ]]; do
    "$OSSL" genpkey -algorithm ed25519 -out "$TMP/k.pem" 2>/dev/null
    SEED="$("$OSSL" pkey -in "$TMP/k.pem" -outform DER | tail -c 32 | base64)"
    PUB="$("$OSSL" pkey -in "$TMP/k.pem" -pubout -outform DER | tail -c 32 | base64)"
  done
  eq "$(SPARKLE_PRIVATE_KEY="$SEED" "$REL/sign-update.sh" public-key)" "$PUB" "public key derived from the seed"
else
  echo "release-sparkle-test: no openssl with Ed25519; using the fixed test vector (public-key checks skipped)"
  # Test-only key, never used for a release (RFC 8032 section 7.1 test 1).
  SEED="nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
  PUB="11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
fi
export SPARKLE_PRIVATE_KEY="$SEED"

# --- sign / verify round trip.
printf 'zip bytes' > "$TMP/Vigie-1.2.0.zip"
o="$("$REL/sign-update.sh" sign --file "$TMP/Vigie-1.2.0.zip" --out "$TMP/sig")"
[[ "$o" =~ ^sparkle:edSignature=\"[A-Za-z0-9+/]{86}==\"\ sparkle:length=\"9\"$ ]] || fail "sign output: $o"
hasnt "$o" "$SEED" "private key in output"
SIG="$(sed -n 's/^ed_signature=//p' "$TMP/sig")"
eq "$(sed -n 's/^length=//p' "$TMP/sig")" 9 "length"
"$REL/sign-update.sh" verify --file "$TMP/Vigie-1.2.0.zip" --signature "$SIG" || fail "valid signature rejected (sign_update)"
if [ -n "$OSSL" ]; then
  "$REL/sign-update.sh" verify --file "$TMP/Vigie-1.2.0.zip" --signature "$SIG" --public-key "$PUB" \
    || fail "valid signature rejected with the public key (what Info.plist carries)"
fi
# A tampered update: the signature no longer matches, which is what Sparkle checks before extracting.
cp "$TMP/Vigie-1.2.0.zip" "$TMP/tampered.zip"; printf 'x' >> "$TMP/tampered.zip"
"$REL/sign-update.sh" verify --file "$TMP/tampered.zip" --signature "$SIG" && fail "tampered zip verified (sign_update)"
if [ -n "$OSSL" ]; then
  "$REL/sign-update.sh" verify --file "$TMP/tampered.zip" --signature "$SIG" --public-key "$PUB" && fail "tampered zip verified (openssl)"
  # Another key's signature is rejected too.
  "$OSSL" genpkey -algorithm ed25519 -out "$TMP/k2.pem" 2>/dev/null
  OTHER="$("$OSSL" pkey -in "$TMP/k2.pem" -pubout -outform DER | tail -c 32 | base64)"
  "$REL/sign-update.sh" verify --file "$TMP/Vigie-1.2.0.zip" --signature "$SIG" --public-key "$OTHER" && fail "signature verified with another key"
fi
env -u SPARKLE_PRIVATE_KEY "$REL/sign-update.sh" sign --file "$TMP/Vigie-1.2.0.zip" >/dev/null 2>&1 && fail "sign without key ran"
# Dry run: no key needed, nothing written, the key never printed.
o="$(env -u SPARKLE_PRIVATE_KEY "$REL/sign-update.sh" sign --file "$TMP/none.zip" --out "$TMP/dry.sig" --dry-run)" || fail "sign dry run"
has "$o" "--ed-key-file -" "dry run shows the stdin key"
[ ! -e "$TMP/dry.sig" ] || fail "sign dry run wrote the signature file"
o="$("$REL/sign-update.sh" sign-feed --file "$TMP/none.xml" --dry-run)"; hasnt "$o" "$SEED" "key in dry-run output"

# --- check-config against App/Config/Updates.xcconfig (a copy of the repo layout).
FAKE="$TMP/root"; mkdir -p "$FAKE/App/Config" "$FAKE/Scripts"; cp -R "$REL" "$FAKE/Scripts/release"
cp "$ROOT/App/project.yml" "$FAKE/App/project.yml"
printf 'VIGIE_RELEASE_REPO = BaguetteLabs/vigie-releases\nVIGIE_SPARKLE_PUBLIC_KEY = %s\nVIGIE_SPARKLE_PUBLIC_KEY[config=Debug] =\n' "$PUB" > "$FAKE/App/Config/Updates.xcconfig"
"$FAKE/Scripts/release/sign-update.sh" check-config --repo BaguetteLabs/vigie-releases >/dev/null || fail "matching config rejected"
"$FAKE/Scripts/release/sign-update.sh" check-config --repo Other/vigie-releases >/dev/null 2>&1 && fail "other release repo accepted"
if [ -n "$OSSL" ]; then
  printf 'VIGIE_RELEASE_REPO = BaguetteLabs/vigie-releases\nVIGIE_SPARKLE_PUBLIC_KEY = %s\n' "$OTHER" > "$FAKE/App/Config/Updates.xcconfig"
  o="$("$FAKE/Scripts/release/sign-update.sh" check-config --repo BaguetteLabs/vigie-releases 2>&1)" && fail "mismatched key accepted"
  has "$o" "does not match" "key mismatch message"
fi
# The committed placeholder fails a real release, warns in a dry run.
"$REL/sign-update.sh" check-config --repo BaguetteLabs/vigie-releases >/dev/null 2>&1 && fail "placeholder config accepted for a release"
o="$("$REL/sign-update.sh" check-config --repo OWNER/vigie-releases --dry-run)" || fail "dry-run check-config failed"
has "$o" "::warning::" "dry-run check-config warns"

# --- appcast.sh in a scratch git repo (tag date, notes).
R="$TMP/repo"; git init -q -b master "$R"
g() { git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
printf '# Changelog\n\n## 1.2.0\n\n- New **thing** <b>&</b>\n- Ends with ]]> safely\n' > "$R/CHANGELOG.md"
g add CHANGELOG.md; g commit -q -m c; g tag -a v1.2.0 -m "Vigie 1.2.0"; g tag -a v1.3.0-beta.1 -m beta
cp -R "$ROOT/Scripts/release" "$R/release"; mkdir -p "$R/App" "$R/Scripts"; mv "$R/release" "$R/Scripts/release"
cp "$ROOT/App/project.yml" "$R/App/project.yml"
AC="$R/Scripts/release/appcast.sh"
DIST="$TMP/dist"; mkdir -p "$DIST"; cp "$TMP/Vigie-1.2.0.zip" "$DIST/"

# Pre-release: nothing written.
o="$("$AC" --tag v1.3.0-beta.1 --build 50 --zip "$DIST/Vigie-1.3.0-beta.1.zip" --signature "$TMP/sig" --repo BaguetteLabs/vigie-releases --dist "$DIST")"
has "$o" "pre-release" "pre-release message"
[ ! -e "$DIST/appcast.xml" ] || fail "pre-release wrote an appcast"

# Dry run: nothing written.
o="$("$AC" --tag v1.2.0 --build 42 --zip "$DIST/Vigie-1.2.0.zip" --signature "$TMP/sig" --repo BaguetteLabs/vigie-releases --dist "$TMP/dry" --dry-run)"
has "$o" "releases/latest/download/appcast.xml" "dry run names the current feed"
has "$o" "sign_update" "dry run signs the feed"
[ ! -e "$TMP/dry" ] || fail "dry run wrote files"

# A previous feed with two releases, one of them the same version (a re-run).
cat > "$TMP/previous.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Vigie</title>
    <item>
      <title>Version 1.2.0</title>
      <sparkle:version>41</sparkle:version>
      <sparkle:shortVersionString>1.2.0</sparkle:shortVersionString>
      <enclosure url="https://example.invalid/old-1.2.0.zip" length="1" type="application/octet-stream" sparkle:edSignature="old"/>
    </item>
    <item>
      <title>Version 1.1.0</title>
      <sparkle:version>30</sparkle:version>
      <sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
      <enclosure url="https://github.com/BaguetteLabs/vigie-releases/releases/download/v1.1.0/Vigie-1.1.0.zip" length="5" type="application/octet-stream" sparkle:edSignature="prev"/>
    </item>
  </channel>
</rss>
XML
(cd "$R" && "$AC" --tag v1.2.0 --build 42 --zip "$DIST/Vigie-1.2.0.zip" --signature "$TMP/sig" --repo BaguetteLabs/vigie-releases --dist "$DIST" --previous "$TMP/previous.xml" >/dev/null) || fail "appcast.sh failed"
X="$DIST/appcast.xml"
xmllint --noout "$X" || fail "appcast not well-formed"
q() { xmllint --xpath "string($1)" "$X" 2>/dev/null; }
eq "$(xmllint --xpath 'count(/rss/channel/item)' "$X")" 2 "items (new + 1.1.0, old 1.2.0 replaced)"
eq "$(q '/rss/channel/item[1]/title')" "Version 1.2.0" "title"
eq "$(q '/rss/channel/item[1]/*[local-name()="version"]')" 42 "sparkle:version = build number"
eq "$(q '/rss/channel/item[1]/*[local-name()="shortVersionString"]')" 1.2.0 "shortVersionString"
eq "$(q '/rss/channel/item[1]/*[local-name()="minimumSystemVersion"]')" 15.0 "minimumSystemVersion"
eq "$(q '/rss/channel/item[1]/enclosure/@url')" "https://github.com/BaguetteLabs/vigie-releases/releases/download/v1.2.0/Vigie-1.2.0.zip" "enclosure url"
eq "$(q '/rss/channel/item[1]/enclosure/@length')" 9 "enclosure length"
eq "$(q '/rss/channel/item[1]/enclosure/@*[local-name()="edSignature"]')" "$SIG" "edSignature"
eq "$(q '/rss/channel/item[1]/description/@*[local-name()="format"]')" markdown "notes format"
notes="$(q '/rss/channel/item[1]/description')"
has "$notes" "- New **thing** <b>&</b>" "notes from CHANGELOG"
has "$notes" "Ends with ]]> safely" "CDATA terminator escaped"
[ -n "$(q '/rss/channel/item[1]/pubDate')" ] || fail "pubDate"
eq "$(q '/rss/channel/item[2]/*[local-name()="version"]')" 30 "previous item kept"
eq "$(q '/rss/channel/item[2]/enclosure/@*[local-name()="edSignature"]')" prev "previous item verbatim"
grep -q 'old-1.2.0' "$X" && fail "same-version item not replaced"
# The feed is signed (SURequireSignedFeed) and the signature breaks when the feed is edited.
grep -q 'sparkle-signatures:' "$X" || fail "feed not signed"
"$REL/sign-update.sh" verify-feed --file "$X" || fail "signed feed does not verify"
cp "$X" "$TMP/edited.xml"; sed -i '' 's/Version 1.2.0/Version 9.9.9/' "$TMP/edited.xml"
"$REL/sign-update.sh" verify-feed --file "$TMP/edited.xml" && fail "edited feed verified"

# Next release, previous = the feed just written (signed): items accumulate, newest first.
printf 'next zip' > "$DIST/Vigie-1.2.1.zip"
"$REL/sign-update.sh" sign --file "$DIST/Vigie-1.2.1.zip" --out "$TMP/sig2" >/dev/null
g tag -a v1.2.1 -m "Vigie 1.2.1 from the tag message"
cp "$X" "$TMP/current.xml"
(cd "$R" && "$AC" --tag v1.2.1 --build 43 --zip "$DIST/Vigie-1.2.1.zip" --signature "$TMP/sig2" --repo BaguetteLabs/vigie-releases --dist "$DIST" --previous "$TMP/current.xml" >/dev/null) || fail "second appcast"
xmllint --noout "$X" || fail "second appcast not well-formed"
eq "$(xmllint --xpath 'count(/rss/channel/item)' "$X")" 3 "items accumulate"
eq "$(xmllint --xpath 'string(/rss/channel/item[1]/*[local-name()="version"])' "$X")" 43 "newest first"
has "$(xmllint --xpath 'string(/rss/channel/item[1]/description)' "$X")" "from the tag message" "tag message notes"
eq "$(grep -c 'sparkle-signatures:' "$X")" 1 "one feed signature"
"$REL/sign-update.sh" verify-feed --file "$X" || fail "second feed does not verify"

# Refusals: signature for another file, malformed previous feed, missing build.
"$AC" --tag v1.2.0 --build 42 --zip "$DIST/Vigie-1.2.1.zip" --signature "$TMP/sig" --repo a/b --dist "$TMP/x" --previous none >/dev/null 2>&1 && fail "signature of another file accepted"
printf '<rss><channel><item>' > "$TMP/bad.xml"
"$AC" --tag v1.2.0 --build 42 --zip "$DIST/Vigie-1.2.0.zip" --signature "$TMP/sig" --repo a/b --dist "$TMP/x" --previous "$TMP/bad.xml" >/dev/null 2>&1 && fail "malformed previous feed accepted"
"$AC" --tag v1.2.0 --zip "$DIST/Vigie-1.2.0.zip" --signature "$TMP/sig" --repo a/b --dist "$TMP/x" --previous none >/dev/null 2>&1 && fail "missing build accepted"
echo "release-sparkle-test: OK"
