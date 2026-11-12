#!/usr/bin/env bash
# Story 6.2: every release script in --dry-run prints its commands and changes nothing (no file in HOME,
# RUNNER_TEMP or the output folders, no GITHUB_ENV line), secrets never appear in the output, the publish
# step marks suffixed tags as pre-releases, and notes.sh picks CHANGELOG section > tag message > fallback.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REL="$ROOT/Scripts/release"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "release-dry-run-test: FAIL: $*" >&2; exit 1; }
has() { grep -qF -- "$2" <<<"$1" || fail "$3: no '$2' in output"; }
hasnt() { if grep -qF -- "$2" <<<"$1"; then fail "$3: '$2' must not appear"; fi; }

mkdir -p "$TMP/home" "$TMP/runner"
export HOME="$TMP/home" RUNNER_TEMP="$TMP/runner" GITHUB_ENV="$TMP/github_env" GITHUB_OUTPUT="$TMP/github_output"
unset GITHUB_ACTIONS || true
export DEVELOPER_ID_P12="UDEyLXNlY3JldA==" DEVELOPER_ID_P12_PASSWORD='p12 pa$$w"rd' DEVELOPER_ID_PROFILE="cHJvZmlsZQ=="
export ASC_KEY_ID=KEYID123 ASC_ISSUER_ID=issuer-6f1c-secret ASC_KEY_P8="-----BEGIN PRIVATE KEY-----p8secret"
OUT="$TMP/out" DIST="$TMP/dist"
version_xcconfig="$ROOT/App/Config/Version.xcconfig"
before="$(cat "$version_xcconfig" 2>/dev/null || echo absent)"

all=""
step() { local o; o="$("$@" 2>&1)" || fail "dry run failed: $* -> $o"; all+="$o"$'\n'; printf '%s' "$o"; }

o="$(step "$REL/import-signing.sh" import --dry-run)"
has "$o" "+ security create-keychain -p ***" "keychain"
has "$o" "security set-key-partition-list -S apple-tool:\\,apple:\\,codesign: -s -k ***" "partition list"
has "$o" "-P *** -T /usr/bin/codesign" "p12 import"
has "$o" "Library/Developer/Xcode/UserData/Provisioning\\ Profiles" "Xcode profile folder"
has "$o" "Library/MobileDevice/Provisioning\\ Profiles" "legacy profile folder"

o="$(step "$REL/archive-export.sh" --marketing-version 1.2.0 --build 42 --out "$OUT" --dry-run)"
has "$o" "Scripts/version.sh --tag v1.2.0 --build 42 --xcconfig" "version"
has "$o" "+ xcodegen generate" "xcodegen"
has "$o" "-configuration Release" "Release archive"
has "$o" " archive" "archive"
has "$o" "-exportArchive" "export"
has "$o" "Scripts/release/ExportOptions.plist" "export options"
"$REL/archive-export.sh" --marketing-version 1.2.0-beta.1 --build 42 --dry-run >/dev/null 2>&1 && fail "suffixed marketing version accepted"
"$REL/archive-export.sh" --marketing-version 1.2.0 --build 0 --dry-run >/dev/null 2>&1 && fail "build 0 accepted"

o="$(step "$REL/notarize.sh" --file "$OUT/export/Vigie.app" --dry-run)"
has "$o" "+ ditto -c -k --sequesterRsrc --keepParent" "app zipped for upload"
has "$o" "xcrun notarytool submit" "submit"
has "$o" "--wait" "wait"
has "$o" "--key-id KEYID123 --issuer ***" "API key auth"
has "$o" "+ xcrun stapler staple $OUT/export/Vigie.app" "staple app"
o="$(step "$REL/notarize.sh" --file "$DIST/Vigie-1.2.0.dmg" --dry-run)"
hasnt "$o" "ditto" "dmg uploaded as is"
has "$o" "+ xcrun stapler staple $DIST/Vigie-1.2.0.dmg" "staple dmg"
has "$o" "--type open --context context:primary-signature" "dmg assessment"
"$REL/notarize.sh" --file "$DIST/Vigie.zip" --dry-run >/dev/null 2>&1 && fail "notarize accepted a zip"

o="$(step "$REL/package.sh" zip --app "$OUT/export/Vigie.app" --version 1.2.0 --dist "$DIST" --dry-run)"
has "$o" "$DIST/Vigie-1.2.0.zip" "zip name"
o="$(step "$REL/package.sh" dmg --app "$OUT/export/Vigie.app" --version 1.2.0 --dist "$DIST" --dry-run)"
has "$o" "+ hdiutil create -volname Vigie" "hdiutil"
has "$o" "+ ln -s /Applications" "Applications link"
has "$o" "+ codesign --force --sign Developer\\ ID\\ Application --timestamp $DIST/Vigie-1.2.0.dmg" "dmg signed"
o="$(step "$REL/package.sh" checksums --dist "$DIST" --dry-run)"
has "$o" "shasum -a 256" "checksums"

o="$(step "$REL/publish.sh" --tag v1.2.0 --repo BaguetteLabs/vigie-releases --dist "$DIST" --dry-run)"
has "$o" "+ gh release create v1.2.0 --repo BaguetteLabs/vigie-releases --draft" "create draft on the release repo"
has "$o" "--latest" "stable is latest"
hasnt "$o" "--prerelease" "stable is not a pre-release"
has "$o" "+ gh release upload v1.2.0 --repo BaguetteLabs/vigie-releases --clobber" "upload"
has "$o" "+ gh release edit v1.2.0 --repo BaguetteLabs/vigie-releases --draft=false" "publish draft"
o="$(step "$REL/publish.sh" --tag v1.2.0-beta.1 --repo BaguetteLabs/vigie-releases --dist "$DIST" --dry-run)"
has "$o" "--prerelease --latest=false" "suffixed tag is a pre-release, never latest"
o="$(step "$REL/publish.sh" --tag v1.2.0 --repo BaguetteLabs/vigie-releases --dist "$DIST" --prerelease true --dry-run)"
has "$o" "--prerelease" "explicit pre-release"
"$REL/publish.sh" --tag v1.2.0 --repo "" --dist "$DIST" --dry-run >/dev/null 2>&1 && fail "empty release repo accepted"
"$REL/publish.sh" --tag v1.2.0 --repo "not a repo" --dist "$DIST" --dry-run >/dev/null 2>&1 && fail "bad release repo accepted"

o="$(step "$REL/import-signing.sh" cleanup --dry-run)"

# Nothing changed, nothing leaked.
[ -z "$(find "$TMP/home" "$TMP/runner" -mindepth 1 -print -quit)" ] || fail "dry run wrote: $(find "$TMP/home" "$TMP/runner" -mindepth 1)"
[ ! -e "$OUT" ] && [ ! -e "$DIST" ] || fail "dry run created output folders"
[ ! -e "$GITHUB_ENV" ] && [ ! -e "$GITHUB_OUTPUT" ] || fail "dry run wrote GITHUB_ENV/OUTPUT"
[ "$(cat "$version_xcconfig" 2>/dev/null || echo absent)" = "$before" ] || fail "dry run changed Version.xcconfig"
for secret in "$DEVELOPER_ID_P12" "$DEVELOPER_ID_P12_PASSWORD" 'pa$$w' "$DEVELOPER_ID_PROFILE" "$ASC_ISSUER_ID" p8secret; do
  hasnt "$all" "$secret" "secret in dry-run output"
done

# Dry runs work before the secrets exist.
env -u DEVELOPER_ID_P12 -u DEVELOPER_ID_P12_PASSWORD -u DEVELOPER_ID_PROFILE "$REL/import-signing.sh" import --dry-run >/dev/null \
  || fail "import dry run needs secrets"
env -u ASC_KEY_ID -u ASC_ISSUER_ID -u ASC_KEY_P8 "$REL/notarize.sh" --file x.dmg --dry-run >/dev/null || fail "notarize dry run needs secrets"
# Real runs refuse to start without them.
env -u DEVELOPER_ID_P12 "$REL/import-signing.sh" import >/dev/null 2>&1 && fail "import without DEVELOPER_ID_P12 ran"
touch "$TMP/x.dmg"
o="$(env -u ASC_KEY_ID "$REL/notarize.sh" --file "$TMP/x.dmg" 2>&1)" && fail "notarize without key ran"
has "$o" "ASC_KEY_ID is not set" "notarize without key"
rm -f "$TMP/x.dmg"
GH_TOKEN="" "$REL/publish.sh" --tag v1.2.0 --repo a/b --dist "$TMP" >/dev/null 2>&1 && fail "publish without GH_TOKEN ran"

# --- notes.sh
R="$TMP/repo"
git init -q -b master "$R"
g() { git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
g commit -q --allow-empty -m "commit message, never the notes"
g tag v0.1.0
g tag -a v0.2.0 -m $'Vigie 0.2.0\n\n- First tag message line'
printf '# Changelog\n\n## [1.0.0] - 2026-12-01\n\n- Stable thing\n\n## 0.9.0-beta.1\n- Beta thing\n\n## 0.8.0\n- Old\n' > "$R/CHANGELOG.md"
g add CHANGELOG.md; g commit -q -m changelog
g tag -a v1.0.0 -m "tag message loses to CHANGELOG"
g tag -a v0.9.0-beta.1 -m "beta tag"
g tag -a v0.9.1 -m "Not in the changelog"
eq() { [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"; }
eq "$("$REL/notes.sh" --repo "$R" --tag v1.0.0)" "- Stable thing" "CHANGELOG section with brackets and date"
eq "$("$REL/notes.sh" --repo "$R" --tag v0.9.0-beta.1)" "- Beta thing" "CHANGELOG pre-release section"
eq "$("$REL/notes.sh" --repo "$R" --tag v0.9.1)" "Not in the changelog" "tag message when no section"
eq "$("$REL/notes.sh" --repo "$R" --tag v0.2.0)" $'Vigie 0.2.0\n\n- First tag message line' "annotated tag message"
eq "$("$REL/notes.sh" --repo "$R" --tag v0.1.0)" "Vigie 0.1.0" "lightweight tag fallback"
echo "release-dry-run-test: OK"
