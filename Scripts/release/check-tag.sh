#!/usr/bin/env bash
# Story 6.2 (FR105, SPEC §12.2): may this tag be released? No secrets needed; release.yml job `check` runs it.
#   check-tag.sh --tag vX.Y.Z[-suffix] [--master origin/master] [--repo DIR] [--dry-run]
# Checks, in order, each stopping with a ::error:: line:
#   1. the tag is vX.Y.Z or vX.Y.Z-<pre-release> (semver, no leading zeros);
#   2. the tag exists in the repository and points at a commit;
#   3. that commit is on master (git merge-base --is-ancestor <tag> <master>);
#   4. the tag equals the project version: Scripts/version.sh (the single source, docs/versioning.md) yields
#      MARKETING_VERSION X.Y.Z for it. A pre-release tag carries the X.Y.Z of the version it precedes
#      (CFBundleShortVersionString stays a plain triple for Sparkle); the archive step checks the built
#      Info.plist against the same value.
# Prints and, when $GITHUB_OUTPUT is set, appends: tag, version (X.Y.Z[-suffix], used in file names),
# marketing_version (X.Y.Z), prerelease (true|false).
# VERSION_SH overrides the version script (tests only).
# --dry-run is accepted for symmetry with the other release scripts; the checks only read the repository.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

tag="" master="origin/master" repo="$RELEASE_ROOT"
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) tag="${2-}"; shift 2 ;;
    --master) master="${2-}"; shift 2 ;;
    --repo) repo="${2-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "usage: check-tag.sh --tag vX.Y.Z[-suffix] [--master REF] [--repo DIR] [--dry-run]" >&2; exit 2 ;;
  esac
done

semver='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$'
[[ "$tag" =~ $semver ]] || die "tag '$tag' is not vX.Y.Z or vX.Y.Z-<pre-release> (e.g. v1.2.0, v1.2.0-beta.1)"
marketing="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
suffix="${BASH_REMATCH[5]}"
version="${tag#v}"
prerelease=false
[ -z "$suffix" ] || prerelease=true

commit="$(git -C "$repo" rev-parse -q --verify "refs/tags/$tag^{commit}" 2>/dev/null)" \
  || die "tag '$tag' does not exist in $repo (fetch tags first)"
git -C "$repo" rev-parse -q --verify "$master^{commit}" >/dev/null 2>&1 \
  || die "master ref '$master' not found in $repo (checkout needs fetch-depth: 0)"
git -C "$repo" merge-base --is-ancestor "$commit" "$master" \
  || die "tag '$tag' ($commit) is not on master ($master): release only from master"

project="$("${VERSION_SH:-$RELEASE_ROOT/Scripts/version.sh}" --tag "v$marketing" --build 1 | sed -n 's/^MARKETING_VERSION = //p')" \
  || die "Scripts/version.sh rejected the version of '$tag'"
[ "$project" = "$marketing" ] \
  || die "tag '$tag' does not match the project version '$project' (Scripts/version.sh)"

out="tag=$tag
version=$version
marketing_version=$marketing
prerelease=$prerelease"
printf '%s\n' "$out"
if [ -n "${GITHUB_OUTPUT:-}" ] && [ "$DRY_RUN" != 1 ]; then printf '%s\n' "$out" >> "$GITHUB_OUTPUT"; fi
say "check-tag: $tag ($commit) is on $master, version $version, pre-release $prerelease"
