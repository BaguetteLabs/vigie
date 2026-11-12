#!/usr/bin/env bash
# Story 6.2 (SPEC §12.3 step 7, AD-20 release hosting, A86): publish DIST as a GitHub Release of the public
# releases-only repository. The private code repository gets nothing.
#   publish.sh --tag vX.Y.Z[-suffix] --repo OWNER/NAME --dist DIR [--prerelease true|false] [--dry-run]
# GH_TOKEN (release secret RELEASE_REPO_TOKEN) must be allowed to write releases of OWNER/NAME only.
# Every regular file of DIST is attached (DMG, zip, SHA256SUMS.txt; appcast.xml from Story 6.3).
# Notes come from notes.sh. A pre-release (tag with a suffix) is marked --prerelease and never "latest", so the
# releases/latest/download/appcast.xml URL of SPEC §12.4 keeps serving the newest stable release.
# Re-runs: the release is created as a draft, the assets uploaded (--clobber), then published. A draft left by a
# failed run is reused; an already published release stops the script (delete it on the host first).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

tag="" repo="" dist="" prerelease=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) tag="${2-}"; shift 2 ;;
    --repo) repo="${2-}"; shift 2 ;;
    --dist) dist="${2-}"; shift 2 ;;
    --prerelease) prerelease="${2-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "usage: publish.sh --tag vX.Y.Z --repo OWNER/NAME --dist DIR [--prerelease true|false] [--dry-run]" >&2; exit 2 ;;
  esac
done
[ -n "$tag" ] && [ -n "$dist" ] || die "--tag and --dist are required"
[[ "$repo" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] \
  || die "release repository '$repo' is not OWNER/NAME (set the RELEASE_REPO variable, docs/release-setup.md)"
if [ -z "$prerelease" ]; then
  if [[ "$tag" == *-* ]]; then prerelease=true; else prerelease=false; fi
fi
[ "$prerelease" = true ] || [ "$prerelease" = false ] || die "--prerelease must be true or false"
[ "$DRY_RUN" = 1 ] || [ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is not set (release secret RELEASE_REPO_TOKEN)"
[ "$DRY_RUN" = 1 ] || [ -d "$dist" ] || die "$dist not found"

version="${tag#v}"
files=()
if [ -d "$dist" ]; then
  while IFS= read -r f; do files+=("$dist/$f"); done < <(cd "$dist" && find . -maxdepth 1 -type f ! -name '.*' | sed 's|^\./||' | LC_ALL=C sort)
fi
if [ "${#files[@]}" -eq 0 ]; then
  [ "$DRY_RUN" = 1 ] || die "nothing to publish in $dist"
  files=("$dist/Vigie-$version.dmg" "$dist/Vigie-$version.zip" "$dist/SHA256SUMS.txt")
fi

notes="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"; notes="${notes%/}/vigie-release-notes.md"
if [ "$DRY_RUN" = 1 ]; then
  say "notes ($notes):"; "$(dirname "${BASH_SOURCE[0]}")/notes.sh" --tag "$tag" | sed 's/^/  | /'
else
  "$(dirname "${BASH_SOURCE[0]}")/notes.sh" --tag "$tag" > "$notes"
fi

flags=(--title "Vigie $version" --notes-file "$notes")
if [ "$prerelease" = true ]; then flags+=(--prerelease --latest=false); else flags+=(--latest); fi

say "== publish $tag to $repo (pre-release: $prerelease)"
state=missing
if [ "$DRY_RUN" != 1 ]; then
  if draft="$(gh release view "$tag" --repo "$repo" --json isDraft --jq .isDraft 2>/dev/null)"; then
    if [ "$draft" = true ]; then state=draft; else state=published; fi
  fi
fi
case "$state" in
  published) die "$repo already has a published release $tag; delete it there to publish again" ;;
  draft) say "reusing the draft left by an earlier run"; run gh release edit "$tag" --repo "$repo" "${flags[@]}" ;;
  missing) run gh release create "$tag" --repo "$repo" --draft "${flags[@]}" ;;
esac
run gh release upload "$tag" --repo "$repo" --clobber "${files[@]}"
run gh release edit "$tag" --repo "$repo" --draft=false
[ "$DRY_RUN" = 1 ] || rm -f "$notes"
say "publish: https://github.com/$repo/releases/tag/$tag"
