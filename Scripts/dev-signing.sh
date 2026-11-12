#!/usr/bin/env bash
# Gives Debug builds of this Mac a stable code-signing identity, and with a team the `.dev` provisioning profile
# and the keychain entitlement (keychain prompt loop fix 2026-11-08, Story 6.1, AD-17). Release signing is
# committed in App/Config/Signing.xcconfig and never touched here.
#
# Writes App/Config/Signing.local.xcconfig (gitignored, included last by Signing.xcconfig):
#   --team <TeamID>  Automatic signing for that team: the Apple Development identity whose certificate OU is the
#                    team, DEVELOPMENT_TEAM, and Vigie.signed.entitlements (keychain-access-groups). Xcode registers
#                    the explicit App ID fr.baguettelabs.vigie.dev with Keychain Sharing and creates the
#                    Development profile on the first `xcodebuild -allowProvisioningUpdates
#                    -allowProvisioningDeviceRegistration` (or a build in Xcode; the Mac must be a registered device).
#                    Exits 1 if no Apple Development identity of that team is in the keychain.
#   (no --team)      Identity only (no profile, no keychain entitlement, SecretStore stays unavailable): the only
#                    Apple Development identity, else a self-signed "Vigie Dev Signing" one. With several Apple
#                    Development identities it lists them with their team and exits 1 instead of guessing.
#   --print          show what would be written, write nothing
#   --output <path>  write there instead of App/Config/Signing.local.xcconfig
# `security` and `openssl` are looked up on PATH (the tests put fakes first).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF_SIGNED="Vigie Dev Signing"
print=0 team="" output="$ROOT/App/Config/Signing.local.xcconfig"
usage() { echo "usage: dev-signing.sh [--team TEAMID] [--print] [--output PATH]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --print) print=1; shift ;;
    --output) [ $# -ge 2 ] || usage; output="$2"; shift 2 ;;
    --team) [ $# -ge 2 ] || usage; team="$2"; shift 2 ;;
    *) usage ;;
  esac
done
if [ -n "$team" ] && ! printf '%s' "$team" | grep -Eq '^[A-Z0-9]{10}$'; then
  echo "dev-signing: \"$team\" is not a team id (10 capital letters or digits, e.g. BWMPMACCYZ)" >&2
  exit 2
fi

# Lines look like:   1) 938616608F7563FFC3033680E3AA762BBA0D4D14 "Apple Development: Jane Doe (ABCDE12345)"
# (the parenthesised id is the person's, not the team's: the team is the certificate's OU).
identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
list() { # $1: "dev" for every Apple Development identity, else an exact name; prints "<sha1> <name>" lines
  printf '%s\n' "$identities" | awk -v want="$1" '
    match($0, /^ *[0-9]+\) [0-9A-F]{40} "/) {
      hash = $2; name = substr($0, RSTART + RLENGTH); sub(/"[^"]*$/, "", name)
      if ((want == "dev" && index(name, "Apple Development: ") == 1) || (want != "dev" && name == want)) {
        print hash " " name
      }
    }'
}
team_of() { # $1: sha1, $2: name; prints the certificate's OU (the team id), or nothing
  security find-certificate -a -Z -p -c "$2" 2>/dev/null | awk -v want="$1" '
    /^SHA-1 hash: / { take = ($3 == want) }
    take && /-----BEGIN CERTIFICATE-----/ { pem = 1 }
    take && pem { print }
    take && /-----END CERTIFICATE-----/ { exit }' |
    openssl x509 -noout -subject -nameopt multiline 2>/dev/null |
    awk -F' = ' '/^ *organizationalUnitName / { print $2; exit }'
}

dev="$(list dev)"
found=""
if [ -n "$team" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$(team_of "${line%% *}" "${line#* }")" = "$team" ]; then found="$line"; break; fi
  done <<< "$dev"
  if [ -z "$found" ]; then
    {
      echo "dev-signing: no \"Apple Development:\" identity of team $team in the keychain."
      echo "Sign in to that team in Xcode › Settings › Accounts › Manage Certificates › + Apple Development, then run this again."
    } >&2
    exit 1
  fi
else
  count="$(printf '%s\n' "$dev" | grep -c . || true)"
  if [ "$count" -gt 1 ]; then
    {
      echo "dev-signing: several Apple Development identities; pick a team with --team <TeamID>:"
      while IFS= read -r line; do
        echo "  team $(team_of "${line%% *}" "${line#* }" || true): ${line#* } (${line%% *})"
      done <<< "$dev"
    } >&2
    exit 1
  fi
  found="$dev"
  [ -n "$found" ] || found="$(list "$SELF_SIGNED" | head -1)"
fi

if [ -z "$found" ]; then
  cat >&2 <<STEPS
dev-signing: no "Apple Development:" or "$SELF_SIGNED" code-signing identity on this Mac.
With an Apple Developer team, add an Apple Development certificate in Xcode › Settings › Accounts and run
  Scripts/dev-signing.sh --team <TeamID>
Otherwise create a self-signed one (once per Mac; SecretStore stays unavailable with it):
  1. Open Keychain Access › Certificate Assistant › Create a Certificate…
  2. Name: $SELF_SIGNED · Identity Type: Self-Signed Root · Certificate Type: Code Signing › Create.
     Keep it in the login keychain.
  3. Double-click the certificate › Trust › Code Signing: Always Trust, close and confirm with your password.
  4. Run Scripts/dev-signing.sh again.
STEPS
  exit 1
fi

hash="${found%% *}" name="${found#* }"
if [ -n "$team" ]; then
  # Automatic style: Xcode registers the App ID (Keychain Sharing comes from the entitlements file) and manages the
  # Development profile. Automatic signing refuses a pinned identity (SHA-1), so it names the certificate kind
  # and DEVELOPMENT_TEAM picks the team's one.
  content="// Written by Scripts/dev-signing.sh --team $team for this Mac (gitignored). Identity: $name ($hash)
DEVELOPMENT_TEAM[config=Debug] = $team
CODE_SIGN_STYLE[config=Debug] = Automatic
CODE_SIGN_IDENTITY[config=Debug] = Apple Development
CODE_SIGN_ENTITLEMENTS[config=Debug] = Vigie.signed.entitlements"
else
  content="// Written by Scripts/dev-signing.sh for this Mac (gitignored). Identity: $name
CODE_SIGN_IDENTITY[config=Debug] = $hash"
fi
if [ "$print" = 1 ]; then
  printf '%s\n' "$content"
else
  mkdir -p "$(dirname "$output")"
  printf '%s\n' "$content" > "$output"
  echo "dev-signing: Debug builds now sign with \"$name\" ($output)"
  [ -z "$team" ] || echo "dev-signing: build once with \`xcodebuild … -allowProvisioningUpdates -allowProvisioningDeviceRegistration\` (or in Xcode) to register this Mac and create the .dev profile"
fi
