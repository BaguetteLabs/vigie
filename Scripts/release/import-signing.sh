#!/usr/bin/env bash
# Story 6.2 (SPEC §12.3 step 2, AD-20): put the Developer ID identity and the "Vigie Developer ID" profile where
# xcodebuild finds them, on a throwaway CI runner, and remove them afterwards.
#
#   import-signing.sh import  [--dry-run]   reads from the environment (release-environment secrets):
#       DEVELOPER_ID_P12           base64 of the Developer ID Application .p12
#       DEVELOPER_ID_P12_PASSWORD  its export password
#       DEVELOPER_ID_PROFILE       base64 of the "Vigie Developer ID" .provisionprofile
#     Creates a temporary keychain with a random password (unique name under $RUNNER_TEMP), imports the
#     identity, allows codesign to use it without a prompt (set-key-partition-list), puts the keychain first in
#     the user search list, and installs the profile as <UUID>.provisionprofile in both profile folders (Xcode 16+
#     and the legacy MobileDevice one). Writes VIGIE_KEYCHAIN and VIGIE_PROFILE_UUID to $GITHUB_ENV when set.
#   import-signing.sh cleanup [--dry-run]   deletes that keychain and the installed profile (release.yml runs it
#     in an always() step, so a failed build leaves nothing behind).
#   import-signing.sh profile-info FILE     prints UUID, Name, TeamIdentifier, application-identifier of a
#     .provisionprofile (signed CMS) and checks them against App/Config/Signing.xcconfig.
#
# Secrets are read from the environment only, never echoed; they are masked with ::add-mask:: and redacted from
# the dry-run listing.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cmd="${1-}"; shift || true
file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    *) if [ -z "$file" ]; then file="$1"; shift; else echo "usage: import-signing.sh import|cleanup|profile-info FILE [--dry-run]" >&2; exit 2; fi ;;
  esac
done

work="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
work="${work%/}"
state="$work/vigie-signing.state"
profile_dirs=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)

# plist_value <decoded plist> <key path>: one value with plutil (raw), empty when missing.
plist_value() { plutil -extract "$2" raw -o - "$1" 2>/dev/null || true; }

profile_info() {
  local profile="$1" decoded
  [ -f "$profile" ] || die "profile '$profile' not found"
  decoded="$(mktemp "$work/vigie-profile.XXXXXX")"
  security cms -D -i "$profile" > "$decoded" 2>/dev/null || { rm -f "$decoded"; die "'$profile' is not a signed provisioning profile"; }
  local uuid name team appid want_name want_team want_appid
  uuid="$(plist_value "$decoded" UUID)"
  name="$(plist_value "$decoded" Name)"
  team="$(plist_value "$decoded" TeamIdentifier.0)"
  appid="$(plist_value "$decoded" Entitlements.com\\.apple\\.application-identifier)"
  rm -f "$decoded"
  want_name="$(release_profile_name)"; want_team="$(release_team)"; want_appid="$want_team.$(release_bundle_id)"
  printf 'uuid=%s\nname=%s\nteam=%s\napplication_identifier=%s\n' "$uuid" "$name" "$team" "$appid"
  [[ "$uuid" =~ ^[0-9A-Fa-f-]{36}$ ]] || die "profile has no UUID"
  [ "$name" = "$want_name" ] || die "profile name '$name', expected '$want_name' (PROVISIONING_PROFILE_SPECIFIER in Signing.xcconfig)"
  [ "$team" = "$want_team" ] || die "profile team '$team', expected '$want_team'"
  [ "$appid" = "$want_appid" ] || die "profile App ID '$appid', expected '$want_appid'"
}

require_env() {
  local name
  for name in "$@"; do
    [ -n "${!name:-}" ] && continue
    # A dry run works before the secrets exist (release.yml dry_run input): placeholders stand in.
    if [ "$DRY_RUN" = 1 ]; then say "warning: $name is not set (dry run)"; printf -v "$name" '%s' "<$name>"; continue; fi
    die "$name is not set (release environment secret, docs/release-setup.md step 8)"
  done
}

do_import() {
  require_env DEVELOPER_ID_P12 DEVELOPER_ID_P12_PASSWORD DEVELOPER_ID_PROFILE
  redact "$DEVELOPER_ID_P12_PASSWORD"
  local kc_pw keychain p12 profile uuid="<UUID>"
  kc_pw="$(openssl rand -hex 24)"
  redact "$kc_pw"
  keychain="$work/vigie-signing-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-$RANDOM$RANDOM.keychain-db"
  p12="$work/vigie-developer-id.p12"
  profile="$work/vigie-developer-id.provisionprofile"

  say "== decode the certificate and the profile"
  if [ "$DRY_RUN" = 1 ]; then
    say "+ base64 --decode <DEVELOPER_ID_P12> > $p12"
    say "+ base64 --decode <DEVELOPER_ID_PROFILE> > $profile"
  else
    umask 077
    printf '%s' "$DEVELOPER_ID_P12" | base64 --decode > "$p12"
    printf '%s' "$DEVELOPER_ID_PROFILE" | base64 --decode > "$profile"
    printf 'keychain=%s\np12=%s\nprofile=%s\n' "$keychain" "$p12" "$profile" > "$state"
    uuid="$(profile_info "$profile" | sed -n 's/^uuid=//p')"
    printf 'uuid=%s\n' "$uuid" >> "$state"
  fi

  say "== temporary keychain"
  run security create-keychain -p "$kc_pw" "$keychain"
  run security set-keychain-settings -lut 21600 "$keychain"
  run security unlock-keychain -p "$kc_pw" "$keychain"
  run security import "$p12" -k "$keychain" -f pkcs12 -P "$DEVELOPER_ID_P12_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild
  run security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$kc_pw" "$keychain"
  local existing=()
  if [ "$DRY_RUN" != 1 ]; then
    while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"; line="${line#\"}"; line="${line%\"}"
      [ -n "$line" ] && existing+=("$line")
    done < <(security list-keychains -d user)
  fi
  run security list-keychains -d user -s "$keychain" ${existing[@]+"${existing[@]}"}
  if [ "$DRY_RUN" != 1 ]; then
    local identity
    identity="$(release_identity)"
    security find-identity -v -p codesigning "$keychain" | grep -q "\"$identity: .*($(release_team))\"" \
      || die "no valid '$identity: … ($(release_team))' identity in the imported .p12"
    rm -f "$p12"
  fi

  say "== provisioning profile"
  local dir
  for dir in "${profile_dirs[@]}"; do
    run mkdir -p "$dir"
    run cp "$profile" "$dir/$uuid.provisionprofile"
  done
  [ "$DRY_RUN" = 1 ] || rm -f "$profile"

  if [ -n "${GITHUB_ENV:-}" ] && [ "$DRY_RUN" != 1 ]; then
    printf 'VIGIE_KEYCHAIN=%s\nVIGIE_PROFILE_UUID=%s\n' "$keychain" "$uuid" >> "$GITHUB_ENV"
  fi
  say "import-signing: identity in $keychain, profile $uuid installed"
}

do_cleanup() {
  local keychain="${VIGIE_KEYCHAIN:-}" uuid="${VIGIE_PROFILE_UUID:-}" p12="" profile=""
  if [ -f "$state" ]; then
    keychain="${keychain:-$(sed -n 's/^keychain=//p' "$state")}"
    uuid="${uuid:-$(sed -n 's/^uuid=//p' "$state")}"
    p12="$(sed -n 's/^p12=//p' "$state")"
    profile="$(sed -n 's/^profile=//p' "$state")"
  fi
  if [ -n "$keychain" ]; then run security delete-keychain "$keychain" || true; fi
  if [ -n "$uuid" ]; then
    local dir
    for dir in "${profile_dirs[@]}"; do run rm -f "$dir/$uuid.provisionprofile"; done
  fi
  for f in "$p12" "$profile" "$work/vigie-asc-key.p8"; do
    if [ -n "$f" ]; then run rm -f "$f"; fi
  done
  run rm -f "$state"
  say "import-signing: cleaned up"
}

case "$cmd" in
  import) do_import ;;
  cleanup) do_cleanup ;;
  profile-info) [ -n "$file" ] || die "profile-info needs a file"; profile_info "$file" ;;
  *) echo "usage: import-signing.sh import|cleanup|profile-info FILE [--dry-run]" >&2; exit 2 ;;
esac
