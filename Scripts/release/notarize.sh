#!/usr/bin/env bash
# Story 6.2 (SPEC §12.3 steps 4-5): notarize and staple an exported .app or a .dmg.
#   notarize.sh --file PATH(.app|.dmg) [--dry-run]
# Reads the App Store Connect API key from the environment (release-environment secrets):
#   ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_P8 (the .p8 contents; written to a 0600 file under $RUNNER_TEMP that
#   import-signing.sh cleanup removes) or ASC_KEY_PATH (an existing .p8 file, for a local run).
# An .app is zipped (ditto --keepParent) for upload, a .dmg is uploaded as is; `notarytool submit --wait` blocks
# until Apple answers. On anything but Accepted, the notarization log is printed and the script fails. Then
# `stapler staple` + `stapler validate`, and a Gatekeeper assessment (spctl) of the stapled file.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file) file="${2-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "usage: notarize.sh --file PATH.app|PATH.dmg [--dry-run]" >&2; exit 2 ;;
  esac
done
case "$file" in
  *.app|*.dmg) ;;
  *) die "--file must be a .app or a .dmg (got '$file')" ;;
esac
[ "$DRY_RUN" = 1 ] || [ -e "$file" ] || die "$file not found"

for name in ASC_KEY_ID ASC_ISSUER_ID; do
  [ -n "${!name:-}" ] && continue
  # A dry run works before the secrets exist (release.yml dry_run input): placeholders stand in.
  if [ "$DRY_RUN" = 1 ]; then say "warning: $name is not set (dry run)"; printf -v "$name" '%s' "<$name>"; continue; fi
  die "$name is not set (release environment secret, docs/release-setup.md step 8)"
done
work="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"; work="${work%/}"
key="${ASC_KEY_PATH:-}"
if [ -z "$key" ]; then
  [ -n "${ASC_KEY_P8:-}" ] || [ "$DRY_RUN" = 1 ] || die "ASC_KEY_P8 (or ASC_KEY_PATH) is not set (release environment secret)"
  key="$work/vigie-asc-key.p8"
  if [ "$DRY_RUN" = 1 ]; then
    say "+ write <ASC_KEY_P8> > $key (mode 0600)"
  else
    (umask 077; printf '%s\n' "$ASC_KEY_P8" > "$key")
  fi
fi
redact "$ASC_ISSUER_ID"
auth=(--key "$key" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")

upload="$file"
if [[ "$file" == *.app ]]; then
  upload="$work/$(basename "$file" .app)-notarize.zip"
  run ditto -c -k --sequesterRsrc --keepParent "$file" "$upload"
fi

say "== notarize $(basename "$file")"
result="$work/vigie-notarize-result.json"
if [ "$DRY_RUN" = 1 ]; then
  run xcrun notarytool submit "$upload" "${auth[@]}" --wait --timeout 2h --output-format json
else
  set +e
  xcrun notarytool submit "$upload" "${auth[@]}" --wait --timeout 2h --output-format json > "$result"
  rc=$?
  set -e
  cat "$result"
  id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
  status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
  if [ "$rc" != 0 ] || [ "$status" != Accepted ]; then
    if [ -n "$id" ]; then xcrun notarytool log "$id" "${auth[@]}" || true; fi
    die "notarization of $(basename "$file") ended with status '${status:-unknown}' (submission ${id:-none})"
  fi
fi
[[ "$file" != *.app ]] || run rm -f "$upload"

say "== staple"
run xcrun stapler staple "$file"
run xcrun stapler validate "$file"
if [[ "$file" == *.app ]]; then
  run spctl --assess --type execute --verbose=2 "$file"
else
  run spctl --assess --type open --context context:primary-signature --verbose=2 "$file"
fi
say "notarize: $(basename "$file") notarized and stapled"
