#!/usr/bin/env bash
# Story 6.2: release packaging pieces that run without a certificate. The Sparkle zip of an app bundle, the
# SHA256SUMS.txt format, ExportOptions.plist against the Release envelope of Signing.xcconfig and project.yml,
# and the provisioning-profile checks of import-signing.sh (on a profile signed by a throwaway key).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REL="$ROOT/Scripts/release"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "release-package-test: FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"; }
export RUNNER_TEMP="$TMP/runner"; mkdir -p "$RUNNER_TEMP"
. "$REL/lib.sh"

# --- zip: ditto keeps the bundle with its parent folder name.
APP="$TMP/Vigie.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
printf 'bin' > "$APP/Contents/MacOS/Vigie"; printf 'cli' > "$APP/Contents/Helpers/vigie"
ln -s MacOS/Vigie "$APP/Contents/link"
DIST="$TMP/dist"
"$REL/package.sh" zip --app "$APP" --version 1.2.0-beta.1 --dist "$DIST" >/dev/null
[ -f "$DIST/Vigie-1.2.0-beta.1.zip" ] || fail "zip not written"
mkdir "$TMP/unzip"; ditto -x -k "$DIST/Vigie-1.2.0-beta.1.zip" "$TMP/unzip"
eq "$(cat "$TMP/unzip/Vigie.app/Contents/Helpers/vigie")" cli "zip content"
[ -L "$TMP/unzip/Vigie.app/Contents/link" ] || fail "zip lost a symlink"
"$REL/package.sh" zip --app "$APP" --version 1.2 --dist "$DIST" >/dev/null 2>&1 && fail "bad version accepted"
"$REL/package.sh" zip --version 1.2.0 --dist "$DIST" >/dev/null 2>&1 && fail "missing --app accepted"

# --- checksums: "<64 hex>  <name>" per Vigie-* file, sorted, verifiable with shasum -c.
printf 'dmg' > "$DIST/Vigie-1.2.0-beta.1.dmg"
printf 'x' > "$DIST/.hidden"; printf 'y' > "$DIST/other.txt"
"$REL/package.sh" checksums --dist "$DIST" >/dev/null
SUMS="$DIST/SHA256SUMS.txt"
eq "$(wc -l < "$SUMS" | tr -d ' ')" 2 "checksum lines"
grep -Evq '^[0-9a-f]{64}  Vigie-1\.2\.0-beta\.1\.(dmg|zip)$' "$SUMS" && fail "checksum format: $(cat "$SUMS")"
eq "$(awk '{print $2}' "$SUMS" | tr '\n' ' ')" "Vigie-1.2.0-beta.1.dmg Vigie-1.2.0-beta.1.zip " "checksum order"
eq "$(sed -n 1p "$SUMS" | cut -c1-64)" "$(shasum -a 256 "$DIST/Vigie-1.2.0-beta.1.dmg" | cut -c1-64)" "dmg digest"
(cd "$DIST" && shasum -a 256 -c SHA256SUMS.txt >/dev/null) || fail "shasum -c"
"$REL/package.sh" checksums --dist "$TMP/empty-nope" >/dev/null 2>&1 && fail "checksums of a missing dist accepted"

# --- ExportOptions.plist: Developer ID export with the Release envelope of Story 6.1.
EO="$REL/ExportOptions.plist"
plutil -lint -s "$EO" || fail "ExportOptions.plist does not parse"
opt() { plutil -extract "$1" raw -o - "$EO"; }
eq "$(opt method)" developer-id "method"
eq "$(opt destination)" export "destination"
eq "$(opt signingStyle)" manual "signingStyle"
eq "$(opt teamID)" "$(release_team)" "teamID vs Signing.xcconfig"
eq "$(release_team)" BWMPMACCYZ "team"
eq "$(opt signingCertificate)" "$(release_identity)" "signingCertificate vs Signing.xcconfig"
eq "$(release_bundle_id)" fr.baguettelabs.vigie "Release bundle id in project.yml"
eq "$(plutil -extract provisioningProfiles."fr\.baguettelabs\.vigie" raw -o - "$EO")" "$(release_profile_name)" "profile vs Signing.xcconfig"
eq "$(plutil -extract provisioningProfiles raw -o - "$EO")" fr.baguettelabs.vigie "exactly one provisioning profile"

# --- profile-info: decodes a CMS-signed profile and checks name, team and App ID.
profile() { # profile <out> <name> <team> <app id>
  cat > "$TMP/p.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Name</key><string>$2</string>
<key>UUID</key><string>12345678-ABCD-4ABC-8ABC-1234567890AB</string>
<key>TeamIdentifier</key><array><string>$3</string></array>
<key>Entitlements</key><dict><key>com.apple.application-identifier</key><string>$4</string></dict>
</dict></plist>
PL
  openssl smime -sign -nodetach -binary -outform DER -in "$TMP/p.plist" -signer "$TMP/c.pem" -inkey "$TMP/k.pem" -out "$1"
}
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/k.pem" -out "$TMP/c.pem" -subj "/CN=vigie-test" -days 1 >/dev/null 2>&1
profile "$TMP/good.provisionprofile" "Vigie Developer ID" BWMPMACCYZ BWMPMACCYZ.fr.baguettelabs.vigie
out="$("$REL/import-signing.sh" profile-info "$TMP/good.provisionprofile")" || fail "good profile rejected: $out"
grep -qx "uuid=12345678-ABCD-4ABC-8ABC-1234567890AB" <<<"$out" || fail "profile uuid: $out"
profile "$TMP/name.provisionprofile" "Vigie Dev" BWMPMACCYZ BWMPMACCYZ.fr.baguettelabs.vigie
"$REL/import-signing.sh" profile-info "$TMP/name.provisionprofile" >/dev/null 2>&1 && fail "wrong profile name accepted"
profile "$TMP/team.provisionprofile" "Vigie Developer ID" SL52497QTV SL52497QTV.fr.baguettelabs.vigie
"$REL/import-signing.sh" profile-info "$TMP/team.provisionprofile" >/dev/null 2>&1 && fail "wrong team accepted"
profile "$TMP/app.provisionprofile" "Vigie Developer ID" BWMPMACCYZ BWMPMACCYZ.fr.baguettelabs.vigie.dev
"$REL/import-signing.sh" profile-info "$TMP/app.provisionprofile" >/dev/null 2>&1 && fail "wrong App ID accepted"
cp "$TMP/p.plist" "$TMP/unsigned.provisionprofile"
"$REL/import-signing.sh" profile-info "$TMP/unsigned.provisionprofile" >/dev/null 2>&1 && fail "unsigned profile accepted"
echo "release-package-test: OK"
