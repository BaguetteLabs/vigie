#!/usr/bin/env bash
# Local dry run of .github/workflows/ci.yml: lint, package tests, theme regen diff, view literals,
# xcodegen + xcodebuild, locale check.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> lint (swift format)"
xcrun swift format lint --strict --recursive Packages App/Sources

for manifest in Packages/*/Package.swift Packages/*/*/Package.swift; do
  [ -f "$manifest" ] || continue
  pkg="$(dirname "$manifest")"
  echo "==> swift test: $pkg"
  (cd "$pkg" && swift test --build-system swiftbuild)
done

echo "==> theme regen diff"
Scripts/theme-regen-check.sh

echo "==> view literals"
Scripts/check-view-literals.sh

echo "==> spi-host guard"
Scripts/check-spi-host.sh

echo "==> process-launch guard"
Scripts/check-process-launch.sh

echo "==> package-deps guard"
Scripts/check-package-deps.sh

echo "==> config corpus"
Scripts/config-corpus.sh

echo "==> xcodegen generate"
(cd App && xcodegen generate)

echo "==> xcodebuild build"
xcodebuild -project App/Vigie.xcodeproj -scheme Vigie -configuration Debug build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO -derivedDataPath App/DerivedData -quiet

echo "==> locale check"
APP="$(find App/DerivedData/Build/Products/Debug -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP" ] || { echo "error: no .app found" >&2; exit 1; }
Scripts/check-locales.sh "$APP"

echo "ci-local: OK"
