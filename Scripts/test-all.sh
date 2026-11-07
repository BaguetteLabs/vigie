#!/usr/bin/env bash
# Runs `swift test` in every package, then generates and builds the app (Debug and Release).
# Uses the swiftbuild build system: the native SwiftPM build system copies .xcstrings
# uncompiled, so String Catalog lookups (AD-15) would fail in tests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/DerivedData}"

for manifest in "$ROOT"/Packages/*/Package.swift "$ROOT"/Packages/*/*/Package.swift; do
  [ -f "$manifest" ] || continue
  pkg="$(dirname "$manifest")"
  echo "==> swift test: ${pkg#"$ROOT"/}"
  (cd "$pkg" && swift test --build-system swiftbuild)
done

echo "==> xcodegen generate"
(cd "$ROOT/App" && xcodegen generate)

for config in Debug Release; do
  case "$config" in
    Debug) expected_id="fr.baguettelabs.vigie.dev"; app_name="Vigie Dev" ;;
    Release) expected_id="fr.baguettelabs.vigie"; app_name="Vigie" ;;
  esac
  echo "==> xcodebuild $config"
  xcodebuild -project "$ROOT/App/Vigie.xcodeproj" -scheme Vigie -configuration "$config" \
    -derivedDataPath "$DERIVED_DATA" CODE_SIGN_IDENTITY=- build -quiet
  plist="$DERIVED_DATA/Build/Products/$config/$app_name.app/Contents/Info.plist"
  actual_id="$(plutil -extract CFBundleIdentifier raw -o - "$plist")"
  if [ "$actual_id" != "$expected_id" ]; then
    echo "error: $config build has CFBundleIdentifier '$actual_id', expected '$expected_id'" >&2
    exit 1
  fi
  echo "    CFBundleIdentifier = $actual_id"
done

echo "All packages tested; app built in Debug and Release."
