#!/usr/bin/env bash
# Gives Debug builds a stable code-signing identity on this Mac (keychain prompt loop fix, 2026-11-08). Release
# stays ad-hoc until Developer ID signing (Story 6.1).
#
# Ad-hoc signatures have no stable designated requirement, so macOS forgets "Always Allow" on Keychain prompts
# at every rebuild. This writes App/Config/Signing.local.xcconfig (gitignored, included by Signing.xcconfig)
# with the SHA-1 of this Mac's first "Apple Development:" identity, else of a self-signed "Vigie Dev Signing"
# code-signing certificate. With neither, it prints how to create the self-signed one and exits 1.
#   --print          show what would be written, write nothing
#   --output <path>  write there instead of App/Config/Signing.local.xcconfig
# `security` is looked up on PATH (the tests put a fake one first).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF_SIGNED="Vigie Dev Signing"
print=0 output="$ROOT/App/Config/Signing.local.xcconfig"
while [ $# -gt 0 ]; do
  case "$1" in
    --print) print=1; shift ;;
    --output) output="${2-}"; shift 2 ;;
    *) echo "usage: dev-signing.sh [--print] [--output PATH]" >&2; exit 2 ;;
  esac
done

# Lines look like:   1) 938616608F7563FFC3033680E3AA762BBA0D4D14 "Apple Development: Jane Doe (TEAMID)"
identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
pick() { # $1: awk test on the name; prints "<sha1> <name>" of the first match
  printf '%s\n' "$identities" | awk -v want="$1" '
    match($0, /^ *[0-9]+\) [0-9A-F]{40} "/) {
      hash = $2; name = substr($0, RSTART + RLENGTH); sub(/"[^"]*$/, "", name)
      if ((want == "dev" && index(name, "Apple Development: ") == 1) || (want != "dev" && name == want)) {
        print hash " " name; exit
      }
    }'
}
found="$(pick dev)"
[ -n "$found" ] || found="$(pick "$SELF_SIGNED")"

if [ -z "$found" ]; then
  cat >&2 <<STEPS
dev-signing: no "Apple Development:" or "$SELF_SIGNED" code-signing identity on this Mac.
Create a self-signed one (once per Mac):
  1. Open Keychain Access › Certificate Assistant › Create a Certificate…
  2. Name: $SELF_SIGNED · Identity Type: Self-Signed Root · Certificate Type: Code Signing › Create.
     Keep it in the login keychain.
  3. Double-click the certificate › Trust › Code Signing: Always Trust, close and confirm with your password.
  4. Run Scripts/dev-signing.sh again.
STEPS
  exit 1
fi

hash="${found%% *}" name="${found#* }"
content="// Written by Scripts/dev-signing.sh for this Mac (gitignored). Identity: $name
CODE_SIGN_IDENTITY[config=Debug] = $hash"
if [ "$print" = 1 ]; then
  printf '%s\n' "$content"
else
  mkdir -p "$(dirname "$output")"
  printf '%s\n' "$content" > "$output"
  echo "dev-signing: Debug builds now sign with \"$name\" ($output)"
fi
