#!/usr/bin/env bash
# Computes the app version for a build (Story 6.4, FR107). See docs/versioning.md.
#   --tag vX.Y.Z      release tag -> CFBundleShortVersionString X.Y.Z (default for dev builds: 0.0.0)
#   --build <n>       CFBundleVersion (CI passes $GITHUB_RUN_NUMBER; default: git rev-list --count HEAD)
#   --xcconfig <path> write MARKETING_VERSION / CURRENT_PROJECT_VERSION to that file instead of printing
set -euo pipefail

tag="" build="" xcconfig=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) tag="${2-}"; shift 2 ;;
    --build) build="${2-}"; shift 2 ;;
    --xcconfig) xcconfig="${2-}"; shift 2 ;;
    *) echo "usage: version.sh [--tag vX.Y.Z] [--build N] [--xcconfig PATH]" >&2; exit 2 ;;
  esac
done

version="0.0.0"
if [ -n "$tag" ]; then
  # Strict X.Y.Z, no leading zeros, no pre-release suffix: Sparkle and CFBundleShortVersionString need plain triples.
  if ! [[ "$tag" =~ ^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "version.sh: invalid tag '$tag' (expected vX.Y.Z)" >&2
    exit 1
  fi
  version="${tag#v}"
fi

if [ -z "$build" ]; then
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  build="$(git -C "$root" rev-list --count HEAD 2>/dev/null || echo 1)"
fi
if ! [[ "$build" =~ ^[1-9][0-9]*$ ]]; then
  echo "version.sh: invalid build number '$build' (expected a positive integer)" >&2
  exit 1
fi

out="MARKETING_VERSION = $version
CURRENT_PROJECT_VERSION = $build"
if [ -n "$xcconfig" ]; then
  mkdir -p "$(dirname "$xcconfig")"
  printf '%s\n' "$out" > "$xcconfig"
else
  printf '%s\n' "$out"
fi
