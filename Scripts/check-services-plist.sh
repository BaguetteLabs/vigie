#!/usr/bin/env bash
# AD-20 / Story 9.10: App/Info.plist declares exactly one NSServices entry, `Stash in Vigie`, whose message is
# the provider's selector (`StashServiceProvider.stashInVigie:userData:error:`) and which sends file URLs and text.
# AD-20 / Story 12.9: it registers one URL scheme, `$(VIGIE_URL_SCHEME)`, which App/project.yml sets to `vigie`
# (Release) and `vigie-dev` (Debug), matching Wire's AppEnvironment.urlScheme (AD-17).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="${PLIST:-$ROOT/App/Info.plist}"

value() { plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null || true; }
fail() { echo "error: $PLIST: $1" >&2; exit 1; }

[ "$(value NSServices)" = "1" ] || fail "NSServices must hold exactly one entry"
[ "$(value NSServices.0.NSMenuItem.default)" = "Stash in Vigie" ] || fail "menu item must be 'Stash in Vigie'"
[ "$(value NSServices.0.NSMessage)" = "stashInVigie" ] || fail "NSMessage must be stashInVigie"
[ -n "$(value NSServices.0.NSPortName)" ] || fail "NSPortName missing"
types="$(plutil -extract NSServices.0.NSSendTypes json -o - "$PLIST" 2>/dev/null || true)"
for t in public.file-url public.utf8-plain-text; do
  echo "$types" | grep -q "\"$t\"" || fail "NSSendTypes must include $t"
done
[ "$(value CFBundleURLTypes)" = "1" ] || fail "CFBundleURLTypes must hold exactly one entry"
[ "$(value CFBundleURLTypes.0.CFBundleURLSchemes.0)" = '$(VIGIE_URL_SCHEME)' ] ||
  fail "the URL scheme must be \$(VIGIE_URL_SCHEME)"
PROJECT="${PROJECT:-$ROOT/App/project.yml}"
grep -q '^ *VIGIE_URL_SCHEME: vigie-dev$' "$PROJECT" || fail "project.yml: Debug VIGIE_URL_SCHEME must be vigie-dev"
grep -q '^ *VIGIE_URL_SCHEME: vigie$' "$PROJECT" || fail "project.yml: Release VIGIE_URL_SCHEME must be vigie"
echo "services-plist check: OK"
