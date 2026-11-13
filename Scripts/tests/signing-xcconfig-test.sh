#!/usr/bin/env bash
# Story 6.1 (AD-17, AD-20): the committed signing envelope, checked without xcodebuild. App/Config/Signing.xcconfig
# holds the expected key per configuration, project.yml sets no signing key on the target (it would win), the
# entitlements files carry only the allowed keys, and Info.plist has LSUIElement and both usage descriptions,
# localised in the InfoPlist String Catalog.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/App"
X="$APP/Config/Signing.xcconfig"
fail() { echo "signing-xcconfig-test: FAIL: $*" >&2; exit 1; }

# value <key with optional [config=…]>: the last assignment in Signing.xcconfig, comments stripped, trimmed.
value() {
  awk -v want="$1" '
    { line = $0; sub(/\/\/.*/, "", line) }
    match(line, /^[ \t]*[A-Za-z0-9_]+(\[[^]]*\])?[ \t]*=/) {
      key = substr(line, 1, RLENGTH - 1); val = substr(line, RLENGTH + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", val)
      if (key == want) { found = 1; last = val }
    }
    END { if (found) print last; else print "<unset>" }' "$X"
}
expect() { [ "$(value "$1")" = "$2" ] || fail "$1 = '$(value "$1")', expected '$2'"; }

# Default (= Debug on a Mac without Signing.local.xcconfig, and CI): ad-hoc, no team, no keychain entitlement.
expect CODE_SIGN_STYLE Manual
expect CODE_SIGN_IDENTITY -
expect DEVELOPMENT_TEAM ""
expect CODE_SIGN_ENTITLEMENTS Vigie.entitlements
expect ENABLE_HARDENED_RUNTIME YES
for key in CODE_SIGN_STYLE CODE_SIGN_IDENTITY DEVELOPMENT_TEAM CODE_SIGN_ENTITLEMENTS PROVISIONING_PROFILE_SPECIFIER; do
  expect "$key[config=Debug]" "<unset>" # Debug overrides belong in the gitignored Signing.local.xcconfig only
done
expect PROVISIONING_PROFILE_SPECIFIER "<unset>"

# Release: Developer ID, Baguette Labs, manual, named profile, keychain entitlement, timestamp, no get-task-allow.
expect "CODE_SIGN_STYLE[config=Release]" Manual
expect "DEVELOPMENT_TEAM[config=Release]" BWMPMACCYZ
expect "CODE_SIGN_IDENTITY[config=Release]" "Developer ID Application"
expect "PROVISIONING_PROFILE_SPECIFIER[config=Release]" "Vigie Developer ID"
expect "CODE_SIGN_ENTITLEMENTS[config=Release]" Vigie.signed.entitlements
expect "OTHER_CODE_SIGN_FLAGS[config=Release]" --timestamp
expect "CODE_SIGN_INJECT_BASE_ENTITLEMENTS[config=Release]" NO
expect "ENABLE_HARDENED_RUNTIME[config=Release]" "<unset>" # inherits YES

# Includes: Version.xcconfig first, the optional local file last (so it can override Debug).
grep -qx '#include "Version.xcconfig"' "$X" || fail "Version.xcconfig include"
[ "$(grep -v '^[[:space:]]*$' "$X" | tail -1)" = '#include? "Signing.local.xcconfig"' ] ||
  fail "Signing.local.xcconfig must be the last include"
grep -qx '/App/Config/Signing.local.xcconfig' "$ROOT/.gitignore" || fail "Signing.local.xcconfig not gitignored"

# project.yml: no signing key on the target or project (target settings win over the project's xcconfig).
grep -En '^[[:space:]]+(CODE_SIGN_[A-Z_]+|DEVELOPMENT_TEAM|PROVISIONING_PROFILE[A-Z_]*|ENABLE_HARDENED_RUNTIME|OTHER_CODE_SIGN_FLAGS):' \
  "$APP/project.yml" && fail "project.yml sets a signing key"
grep -q 'Release: Config/Signing.xcconfig' "$APP/project.yml" && grep -q 'Debug: Config/Signing.xcconfig' "$APP/project.yml" ||
  fail "project.yml configFiles"
# The embedded CLI: Hardened Runtime, no entitlements, a secure timestamp for a signed Release.
grep -q -- '--options runtime' "$APP/project.yml" || fail "CLI not signed with Hardened Runtime"
grep -q -- '--entitlements' "$APP/project.yml" && fail "CLI must be signed without entitlements"
grep -q 'TIMESTAMP=--timestamp; fi' "$APP/project.yml" || fail "CLI release timestamp"

# Entitlements: only the AD-20 keys; never the App Sandbox.
keys() { plutil -convert json -o - "$1" | /usr/bin/python3 -c 'import json,sys; print(" ".join(sorted(json.load(sys.stdin))))'; }
[ "$(keys "$APP/Vigie.entitlements")" = "com.apple.security.automation.apple-events" ] || fail "Vigie.entitlements keys"
[ "$(keys "$APP/Vigie.signed.entitlements")" = "com.apple.security.automation.apple-events keychain-access-groups" ] ||
  fail "Vigie.signed.entitlements keys"
[ "$(plutil -extract keychain-access-groups.0 raw -o - "$APP/Vigie.signed.entitlements")" = \
  '$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)' ] || fail "keychain access group"
# The notes key group (AD-9): shared by Vigie and Vigie Dev, named after the release bundle id.
[ "$(plutil -extract keychain-access-groups.1 raw -o - "$APP/Vigie.signed.entitlements")" = \
  '$(AppIdentifierPrefix)fr.baguettelabs.vigie.notes' ] || fail "notes access group"
[ "$(plutil -extract keychain-access-groups raw -o - "$APP/Vigie.signed.entitlements")" = 2 ] || fail "two access groups"

# Info.plist and its String Catalog.
[ "$(plutil -extract LSUIElement raw -o - "$APP/Info.plist")" = true ] || fail "LSUIElement"
for key in NSAppleEventsUsageDescription NSCalendarsFullAccessUsageDescription; do
  plist="$(plutil -extract "$key" raw -o - "$APP/Info.plist" 2> /dev/null)" || fail "Info.plist has no $key"
  catalog="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["strings"][sys.argv[2]]["localizations"]["en"]["stringUnit"]["value"])' \
    "$APP/Resources/InfoPlist.xcstrings" "$key" 2> /dev/null)" || fail "InfoPlist.xcstrings has no $key"
  [ "$plist" = "$catalog" ] || fail "$key differs between Info.plist and the catalog"
done
echo "signing-xcconfig-test: OK"
