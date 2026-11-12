#!/usr/bin/env bash
# Story 6.2 (SPEC §12.3 step 3, Story 6.4): archive the Release configuration and export it for Developer ID.
#   archive-export.sh --marketing-version X.Y.Z --build N [--out DIR] [--dry-run]
# 1. Scripts/version.sh writes App/Config/Version.xcconfig (MARKETING_VERSION X.Y.Z, CURRENT_PROJECT_VERSION N).
# 2. xcodegen generate, xcodebuild archive (scheme Vigie, Release: the signing envelope of
#    App/Config/Signing.xcconfig, unchanged), xcodebuild -exportArchive with Scripts/release/ExportOptions.plist.
# 3. Verifies the exported DIR/export/Vigie.app: strict deep signature, Developer ID authority of the team,
#    Hardened Runtime on app and bundled CLI, and Info.plist versions equal to the tag's (the second half of the
#    "tag equals the project version" check of check-tag.sh).
# Needs the identity and profile installed by import-signing.sh.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

marketing="" build="" out="$RELEASE_ROOT/build/release"
while [ $# -gt 0 ]; do
  case "$1" in
    --marketing-version) marketing="${2-}"; shift 2 ;;
    --build) build="${2-}"; shift 2 ;;
    --out) out="${2-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "usage: archive-export.sh --marketing-version X.Y.Z --build N [--out DIR] [--dry-run]" >&2; exit 2 ;;
  esac
done
[ -n "$marketing" ] && [ -n "$build" ] || die "--marketing-version and --build are required"
# Validates both values before anything runs (dry-run included).
"$RELEASE_ROOT/Scripts/version.sh" --tag "v$marketing" --build "$build" >/dev/null || die "invalid version or build"

archive="$out/Vigie.xcarchive"
export_dir="$out/export"
app="$export_dir/Vigie.app"
options="$RELEASE_ROOT/Scripts/release/ExportOptions.plist"

say "== version"
run "$RELEASE_ROOT/Scripts/version.sh" --tag "v$marketing" --build "$build" --xcconfig "$RELEASE_ROOT/App/Config/Version.xcconfig"

say "== generate project"
(cd "$RELEASE_ROOT/App" && run xcodegen generate)

say "== archive"
run rm -rf "$archive" "$export_dir"
run xcodebuild -project "$RELEASE_ROOT/App/Vigie.xcodeproj" -scheme Vigie -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$archive" -derivedDataPath "$out/DerivedData" archive

say "== export (Developer ID)"
run xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" -exportOptionsPlist "$options"

say "== verify"
team="$(release_team)"
run codesign --verify --deep --strict --verbose=2 "$app"
if [ "$DRY_RUN" = 1 ]; then
  say "+ check authority 'Developer ID Application: … ($team)', runtime flag and versions of $app"
  say "archive-export: dry run, nothing built"
  exit 0
fi
for code in "$app" "$app/Contents/Helpers/vigie"; do
  [ -e "$code" ] || die "missing $code in the export"
  details="$(codesign -dv --verbose=2 "$code" 2>&1)"
  grep -q "^Authority=Developer ID Application: .*($team)$" <<<"$details" || die "$code is not signed by Developer ID Application ($team)"
  grep -q '^CodeDirectory .*flags=.*(runtime)' <<<"$details" || die "$code has no Hardened Runtime"
  grep -q '^Timestamp=' <<<"$details" || die "$code has no secure timestamp"
done
short="$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")"
bundle="$(plutil -extract CFBundleVersion raw -o - "$app/Contents/Info.plist")"
[ "$short" = "$marketing" ] || die "built CFBundleShortVersionString '$short' does not match the tag version '$marketing'"
[ "$bundle" = "$build" ] || die "built CFBundleVersion '$bundle', expected '$build'"
say "archive-export: $app ($short build $bundle)"
