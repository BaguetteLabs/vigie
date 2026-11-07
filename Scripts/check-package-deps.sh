#!/usr/bin/env bash
# AD-1 guard: every local package dependency (`.package(path:)`) in Packages/**/Package.swift follows the
# dependency direction:
#   VigieCore -> ModuleKit, VigieUI, Wire     AgentKit -> ModuleKit, Wire     VigieUI -> ModuleKit
#   VigieCLI -> Wire                           ModuleKit, Wire -> (none)
#   Modules/* -> ModuleKit, VigieUI, AgentKit, Wire (AgentKit and Wire for agent modules only)
#   Adapters/*, Terminals/* -> AgentKit
# A package outside this matrix fails until its rule is added here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

allowed_for() {
  case "$1" in
    ModuleKit | Wire) echo "" ;;
    VigieCore) echo "ModuleKit VigieUI Wire" ;;
    AgentKit) echo "ModuleKit Wire" ;;
    VigieUI) echo "ModuleKit" ;;
    VigieCLI) echo "Wire" ;;
    Modules/*) echo "ModuleKit VigieUI AgentKit Wire" ;;
    Adapters/* | Terminals/*) echo "AgentKit" ;;
    *) return 1 ;;
  esac
}

# Normalizes "<pkg dir>/<relative path>" to a path under Packages/ (resolving `..`).
normalize() {
  local IFS=/ part
  local -a out=()
  for part in $1; do
    case "$part" in
      '' | .) ;;
      ..) [ "${#out[@]}" -gt 0 ] && unset 'out[${#out[@]}-1]' ;;
      *) out+=("$part") ;;
    esac
  done
  echo "${out[*]}"
}

status=0
count=0
while IFS= read -r manifest; do
  pkg_dir="$(dirname "$manifest")"
  pkg="${pkg_dir#Packages/}"
  count=$((count + 1))
  if ! allowed="$(allowed_for "$pkg")"; then
    echo "error: $manifest: package '$pkg' has no AD-1 rule in Scripts/check-package-deps.sh" >&2
    status=1
    continue
  fi
  deps="$(sed -nE 's/.*\.package\( *path: *"([^"]+)".*/\1/p' "$manifest")"
  for dep_path in $deps; do
    target="$(normalize "$pkg_dir/$dep_path")"
    dep="${target#Packages/}"
    if [ "$target" = "$dep" ]; then
      echo "error: $manifest: dependency '$dep_path' is outside Packages/" >&2
      status=1
      continue
    fi
    case " $allowed " in
      *" $dep "*) ;;
      *)
        echo "error: $manifest: '$pkg' may not depend on '$dep' (AD-1 allows: ${allowed:-nothing})" >&2
        status=1
        ;;
    esac
  done
done < <(find Packages -type d \( -name '.build' -o -name '.build*' -o -name '.swiftpm' \) -prune -o \
  -type f -name Package.swift -print | sort)

[ "$status" -eq 0 ] && echo "package-deps guard: OK ($count packages)"
exit "$status"
