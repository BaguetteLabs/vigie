#!/usr/bin/env bash
# Story 6.2 (SPEC §12.3 step 5): the downloadable files of a release, in DIST.
#   package.sh zip       --app Vigie.app --version V --dist DIR [--dry-run]   -> Vigie-V.zip (ditto, for Sparkle)
#   package.sh dmg       --app Vigie.app --version V --dist DIR [--dry-run]   -> Vigie-V.dmg (UDZO, /Applications
#                        link, signed with the Developer ID Application identity; notarize.sh notarizes it next)
#   package.sh checksums --dist DIR [--dry-run]                               -> SHA256SUMS.txt
# V is the tag without its `v` (1.2.0, 1.2.0-beta.1). Run zip and dmg on the notarized, stapled app, so the
# ticket travels in both. SHA256SUMS.txt is `shasum -a 256` output ("<64 hex>  <file name>" per line, sorted by
# name) for every Vigie-* file in DIST, checkable with `shasum -a 256 -c SHA256SUMS.txt`. Story 6.3 adds the
# Sparkle signature and appcast.xml to DIST between these steps and publish.sh.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cmd="${1-}"; shift || true
app="" version="" dist=""
while [ $# -gt 0 ]; do
  case "$1" in
    --app) app="${2-}"; shift 2 ;;
    --version) version="${2-}"; shift 2 ;;
    --dist) dist="${2-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "usage: package.sh zip|dmg|checksums [--app PATH] [--version V] --dist DIR [--dry-run]" >&2; exit 2 ;;
  esac
done
[ -n "$dist" ] || die "--dist is required"
CHECKSUMS=SHA256SUMS.txt

need_app() {
  [ -n "$app" ] && [ -n "$version" ] || die "$cmd needs --app and --version"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "invalid version '$version'"
  [ "$DRY_RUN" = 1 ] || [ -d "$app" ] || die "$app not found"
  run mkdir -p "$dist"
}

case "$cmd" in
  zip)
    need_app
    out="$dist/Vigie-$version.zip"
    run rm -f "$out"
    # Same flags as Xcode's "Compress": keeps the bundle, symlinks, extended attributes and the stapled ticket.
    run ditto -c -k --sequesterRsrc --keepParent "$app" "$out"
    say "package: $out"
    ;;
  dmg)
    need_app
    out="$dist/Vigie-$version.dmg"
    staging="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"; staging="${staging%/}/vigie-dmg-$$"
    run rm -rf "$staging" "$out"
    run mkdir -p "$staging"
    run ditto "$app" "$staging/$(basename "$app")"
    run ln -s /Applications "$staging/Applications"
    run hdiutil create -volname Vigie -srcfolder "$staging" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$out"
    run rm -rf "$staging"
    identity="$(release_identity): "
    run codesign --force --sign "$(release_identity)" --timestamp "$out"
    if [ "$DRY_RUN" != 1 ]; then
      codesign -dv --verbose=2 "$out" 2>&1 | grep -q "^Authority=$identity.*($(release_team))$" \
        || die "$out is not signed by $(release_identity) ($(release_team))"
    fi
    say "package: $out"
    ;;
  checksums)
    if [ "$DRY_RUN" = 1 ]; then
      say "+ (cd $dist && shasum -a 256 Vigie-* > $CHECKSUMS)"
      exit 0
    fi
    [ -d "$dist" ] || die "$dist not found"
    files=()
    while IFS= read -r f; do files+=("$f"); done < <(cd "$dist" && find . -maxdepth 1 -type f -name 'Vigie-*' | sed 's|^\./||' | LC_ALL=C sort)
    [ "${#files[@]}" -gt 0 ] || die "no Vigie-* file in $dist"
    (cd "$dist" && shasum -a 256 "${files[@]}" > "$CHECKSUMS")
    cat "$dist/$CHECKSUMS"
    ;;
  *) echo "usage: package.sh zip|dmg|checksums [--app PATH] [--version V] --dist DIR [--dry-run]" >&2; exit 2 ;;
esac
