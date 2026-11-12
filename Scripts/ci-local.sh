#!/usr/bin/env bash
# Local dry run of .github/workflows/ci.yml: lint, package tests, theme regen diff, view literals, contrast,
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

echo "==> contrast check"
Scripts/check-contrast.sh --quiet

echo "==> spi-host guard"
Scripts/check-spi-host.sh

echo "==> process-launch guard"
Scripts/check-process-launch.sh

echo "==> package-deps guard"
Scripts/check-package-deps.sh

echo "==> cli-no-keychain guard"
Scripts/check-cli-no-keychain.sh

echo "==> module-pasteboard guard"
Scripts/check-module-pasteboard.sh
Scripts/tests/module-pasteboard-test.sh

echo "==> test-windows guard"
Scripts/check-test-windows.sh
Scripts/tests/test-windows-test.sh

echo "==> module-away guard"
Scripts/check-module-away.sh
Scripts/tests/module-away-test.sh

echo "==> script schema"
Scripts/check-script-schema.sh
echo "==> example scripts"
Scripts/check-example-scripts.sh

echo "==> services plist"
Scripts/check-services-plist.sh

echo "==> config corpus"
Scripts/config-corpus.sh

echo "==> spool floor"
Scripts/spool-floor-test.sh

echo "==> version script test"
Scripts/tests/version-test.sh

echo "==> dev signing script test"
Scripts/tests/dev-signing-test.sh

echo "==> signing xcconfig test"
Scripts/tests/signing-xcconfig-test.sh

echo "==> release script tests"
Scripts/tests/release-check-tag-test.sh
Scripts/tests/release-package-test.sh
Scripts/tests/release-dry-run-test.sh
Scripts/tests/release-sparkle-test.sh
Scripts/tests/release-prices-test.sh

echo "==> xcodegen generate"
Scripts/version.sh --xcconfig App/Config/Version.xcconfig
(cd App && xcodegen generate)

echo "==> xcodebuild build"
xcodebuild -project App/Vigie.xcodeproj -scheme Vigie -configuration Debug build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO -derivedDataPath App/DerivedData -quiet

echo "==> locale check"
APP="$(find App/DerivedData/Build/Products/Debug -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP" ] || { echo "error: no .app found" >&2; exit 1; }
Scripts/check-locales.sh "$APP"

echo "ci-local: OK"
