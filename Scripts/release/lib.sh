#!/usr/bin/env bash
# Shared helpers for Scripts/release/*.sh (Story 6.2). Sourced, not run.
#   DRY_RUN=1  run() prints each command ("+ cmd") instead of running it, and nothing on disk changes.
#   redact <value>...  values replaced by *** wherever run() or say() prints them (secrets never reach the log).

RELEASE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRY_RUN="${DRY_RUN:-0}"
_REDACT=()

redact() {
  local v
  for v in "$@"; do
    [ -n "$v" ] || continue
    # run() prints arguments shell-quoted, so redact the quoted form too.
    _REDACT+=("$v" "$(printf '%q' "$v")")
    # On GitHub Actions, also mask the value in every later log line.
    if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::add-mask::$v"; fi
  done
}

_scrub() {
  local s="$1" v
  for v in ${_REDACT[@]+"${_REDACT[@]}"}; do s="${s//"$v"/***}"; done
  printf '%s' "$s"
}

say() { printf '%s\n' "$(_scrub "$*")"; }

# error <message>: GitHub annotation + stderr, then exit 1.
die() { printf '::error::%s\n' "$(_scrub "$*")" >&2; exit 1; }

# run <cmd> [args...]: execute, or print in dry-run mode. Arguments are shown shell-quoted.
run() {
  local line
  line="$(printf '%q ' "$@")"
  say "+ ${line% }"
  if [ "$DRY_RUN" = 1 ]; then return 0; fi
  "$@"
}

# xcconfig_value <key[config=…]> [file]: last assignment of a key in an xcconfig, comments stripped.
xcconfig_value() {
  awk -v want="$1" '
    { line = $0; sub(/\/\/.*/, "", line) }
    match(line, /^[ \t]*[A-Za-z0-9_]+(\[[^]]*\])?[ \t]*=/) {
      key = substr(line, 1, RLENGTH - 1); val = substr(line, RLENGTH + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", val)
      if (key == want) { found = 1; last = val }
    }
    END { if (found) print last }' "${2:-$RELEASE_ROOT/App/Config/Signing.xcconfig}"
}

# The release envelope of Story 6.1, read from the committed xcconfig so the scripts never drift from it.
release_team() { xcconfig_value 'DEVELOPMENT_TEAM[config=Release]'; }
release_profile_name() { xcconfig_value 'PROVISIONING_PROFILE_SPECIFIER[config=Release]'; }
release_identity() { xcconfig_value 'CODE_SIGN_IDENTITY[config=Release]'; }
release_bundle_id() {
  awk '/^[ \t]*Release:[ \t]*$/ { r = 1 } r && /PRODUCT_BUNDLE_IDENTIFIER:/ { print $2; exit }' "$RELEASE_ROOT/App/project.yml"
}
