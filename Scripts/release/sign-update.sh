#!/usr/bin/env bash
# Story 6.3 (SPEC §12.3 step 6, §12.4): Sparkle EdDSA signing with the release key, reusable by Story 6.5 (the
# signed price table uses the same key and the same commands).
#   sign-update.sh tools                               print the folder of Sparkle's command-line tools, downloading
#                                                      the pinned release once (version and SHA-256 below)
#   sign-update.sh sign --file F [--out SIG] [--dry-run]
#                                                      EdDSA-sign a file (update zip, prices.json): prints
#                                                      `sparkle:edSignature="…" sparkle:length="…"`, and writes
#                                                      `ed_signature=…` / `length=…` lines to SIG when given
#   sign-update.sh sign-feed --file appcast.xml [--dry-run]
#                                                      embed the feed signature in an appcast (SURequireSignedFeed)
#   sign-update.sh verify --file F --signature S [--public-key K]
#                                                      exit 0 when S is a valid signature of F: with K (base64
#                                                      public key) through openssl, independently of Sparkle;
#                                                      otherwise with sign_update --verify and the private key
#   sign-update.sh verify-feed --file appcast.xml      check an appcast's embedded signature (private key)
#   sign-update.sh public-key                          the base64 public key of SPARKLE_PRIVATE_KEY (openssl)
#   sign-update.sh check-config --repo OWNER/NAME      App/Config/Updates.xcconfig names that release repository
#                                                      and a public key, and that key matches SPARKLE_PRIVATE_KEY
# SPARKLE_PRIVATE_KEY (release secret) is the base64 Ed25519 seed exported by `generate_keys -x`. It reaches
# sign_update only on stdin (`--ed-key-file -`), never on a command line, in a file or in the log.
# The private key never touches a keychain here: generate_keys is not used.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Same release as App/project.yml (`exactVersion`); the checksum is the one of Sparkle's Package.swift for that tag.
SPARKLE_VERSION=2.10.1
SPARKLE_SHA256=4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-for-Swift-Package-Manager.zip"
UPDATES_XCCONFIG="$RELEASE_ROOT/App/Config/Updates.xcconfig"

usage() {
  echo "usage: sign-update.sh tools | sign --file F [--out SIG] | sign-feed --file XML | verify --file F --signature S [--public-key K] | verify-feed --file XML | public-key | check-config --repo OWNER/NAME [--dry-run]" >&2
  exit 2
}

cmd="${1-}"; shift || true
file="" out="" signature="" public_key="" repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file) file="${2-}"; shift 2 ;;
    --out) out="${2-}"; shift 2 ;;
    --signature) signature="${2-}"; shift 2 ;;
    --public-key) public_key="${2-}"; shift 2 ;;
    --repo) repo="${2-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) usage ;;
  esac
done
redact "${SPARKLE_PRIVATE_KEY:-}"

# tools_dir: Sparkle's bin/ (sign_update, generate_keys, generate_appcast), downloaded once and checked.
tools_dir() {
  local cache="${SPARKLE_TOOLS_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
  cache="${cache%/}/sparkle-$SPARKLE_VERSION"
  if [ ! -x "$cache/bin/sign_update" ]; then
    local zip="$cache.download.zip" sum
    mkdir -p "$(dirname "$cache")"
    curl -fsSL --retry 3 -o "$zip" "$SPARKLE_URL" >&2 || die "download of Sparkle $SPARKLE_VERSION failed"
    sum="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
    [ "$sum" = "$SPARKLE_SHA256" ] || { rm -f "$zip"; die "Sparkle $SPARKLE_VERSION checksum mismatch: $sum"; }
    rm -rf "$cache.tmp" && mkdir -p "$cache.tmp"
    unzip -q "$zip" 'bin/*' -d "$cache.tmp"
    rm -rf "$cache" && mv "$cache.tmp" "$cache" && rm -f "$zip"
  fi
  printf '%s\n' "$cache/bin"
}

need_key() {
  [ -n "${SPARKLE_PRIVATE_KEY:-}" ] || die "SPARKLE_PRIVATE_KEY is not set (release secret, docs/release-setup.md step 6)"
}

need_file() {
  [ -n "$file" ] || die "$cmd needs --file"
  [ "$DRY_RUN" = 1 ] || [ -f "$file" ] || die "$file not found"
}

# sign_update with the private key on stdin.
sparkle_sign() { printf '%s' "$SPARKLE_PRIVATE_KEY" | "$(tools_dir)/sign_update" --ed-key-file - "$@"; }

# DER prefixes of an Ed25519 PKCS#8 private key (seed follows) and SubjectPublicKeyInfo (key follows).
ED25519_PRIVATE_DER=302e020100300506032b657004220420
ED25519_PUBLIC_DER=302a300506032b6570032100

openssl_ed25519() {
  local bin
  for bin in "${OPENSSL:-}" openssl /opt/homebrew/bin/openssl /usr/local/bin/openssl; do
    if [ -z "$bin" ] || ! command -v "$bin" >/dev/null 2>&1; then continue; fi
    if "$bin" genpkey -algorithm ed25519 >/dev/null 2>&1; then command -v "$bin"; return 0; fi
  done
  return 1
}

# public_key_of <base64 seed>: base64 public key, or nothing when the key is not a 32-byte seed / no openssl.
public_key_of() {
  local ossl seed_hex
  ossl="$(openssl_ed25519)" || return 0
  seed_hex="$(printf '%s' "$1" | base64 -D 2>/dev/null | xxd -p | tr -d '\n')" || return 0
  [ "${#seed_hex}" = 64 ] || return 0
  printf '%s%s' "$ED25519_PRIVATE_DER" "$seed_hex" | xxd -r -p \
    | "$ossl" pkey -inform DER -pubout -outform DER 2>/dev/null | tail -c 32 | base64
}

xcconfig_key() { xcconfig_value VIGIE_SPARKLE_PUBLIC_KEY "$UPDATES_XCCONFIG"; }

case "$cmd" in
  tools)
    tools_dir
    ;;
  sign)
    need_file
    if [ "$DRY_RUN" = 1 ]; then
      say "+ sign_update --ed-key-file - $file   (SPARKLE_PRIVATE_KEY on stdin)"
      [ -z "$out" ] || say "+ write ed_signature / length to $out"
      exit 0
    fi
    need_key
    sig="$(sparkle_sign -p "$file")" || die "sign_update failed for $file"
    [[ "$sig" =~ ^[A-Za-z0-9+/]{86}==$ ]] || die "unexpected sign_update output"
    length="$(stat -f %z "$file")"
    printf 'sparkle:edSignature="%s" sparkle:length="%s"\n' "$sig" "$length"
    if [ -n "$out" ]; then printf 'ed_signature=%s\nlength=%s\n' "$sig" "$length" > "$out"; fi
    ;;
  sign-feed)
    need_file
    if [ "$DRY_RUN" = 1 ]; then say "+ sign_update --ed-key-file - $file   (embeds the feed signature)"; exit 0; fi
    need_key
    sparkle_sign "$file" >/dev/null || die "sign_update failed for $file"
    grep -q 'sparkle-signatures:' "$file" || die "no signature embedded in $file"
    say "sign-update: signed feed $file"
    ;;
  verify)
    need_file
    [ -n "$signature" ] || die "verify needs --signature"
    if [ -n "$public_key" ]; then
      ossl="$(openssl_ed25519)" || die "no openssl with Ed25519 support to verify with a public key"
      tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
      key_hex="$(printf '%s' "$public_key" | base64 -D 2>/dev/null | xxd -p | tr -d '\n')"
      [ "${#key_hex}" = 64 ] || die "public key is not a base64 32-byte Ed25519 key"
      printf '%s%s' "$ED25519_PUBLIC_DER" "$key_hex" | xxd -r -p > "$tmp/pub.der"
      printf '%s' "$signature" | base64 -D > "$tmp/sig" 2>/dev/null || die "signature is not base64"
      "$ossl" pkeyutl -verify -pubin -keyform DER -inkey "$tmp/pub.der" -rawin -in "$file" -sigfile "$tmp/sig" >/dev/null 2>&1
    else
      need_key
      sparkle_sign --verify "$file" "$signature" >/dev/null 2>&1
    fi
    ;;
  verify-feed)
    need_file
    need_key
    sparkle_sign --verify "$file" >/dev/null 2>&1
    ;;
  public-key)
    need_key
    key="$(public_key_of "$SPARKLE_PRIVATE_KEY")"
    [ -n "$key" ] || die "cannot derive the public key (needs openssl with Ed25519 and a 32-byte seed; else use generate_keys -p)"
    printf '%s\n' "$key"
    ;;
  check-config)
    [[ "$repo" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || die "--repo '$repo' is not OWNER/NAME"
    # A dry run reports the problems as warnings: rehearsals work before A49 and the keys are settled.
    problem() { if [ "$DRY_RUN" = 1 ]; then say "::warning::$*"; else die "$*"; fi; }
    configured="$(xcconfig_value VIGIE_RELEASE_REPO "$UPDATES_XCCONFIG")"
    [ "$configured" = "$repo" ] \
      || problem "App/Config/Updates.xcconfig VIGIE_RELEASE_REPO is '$configured', the release goes to '$repo': the app would read another feed"
    key="$(xcconfig_key)"
    [ "$(printf '%s' "$key" | base64 -D 2>/dev/null | wc -c | tr -d ' ')" = 32 ] \
      || problem "App/Config/Updates.xcconfig VIGIE_SPARKLE_PUBLIC_KEY is not set: the release could never update itself"
    if [ "$DRY_RUN" = 1 ] || [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
      say "sign-update: config names $repo and a public key (private key not compared)"
      exit 0
    fi
    derived="$(public_key_of "$SPARKLE_PRIVATE_KEY")"
    if [ -z "$derived" ]; then
      say "::warning::cannot derive the public key of SPARKLE_PRIVATE_KEY here (openssl Ed25519 / key format); not compared"
    elif [ "$derived" != "$key" ]; then
      die "SPARKLE_PRIVATE_KEY does not match VIGIE_SPARKLE_PUBLIC_KEY: installed apps would reject this update"
    fi
    say "sign-update: config OK ($repo, public key matches)"
    ;;
  *) usage ;;
esac
