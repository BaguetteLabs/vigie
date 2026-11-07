#!/usr/bin/env bash
# CI spool floor (AD-6, Story 4.2): 1,000 events written by concurrent real `vigie event` processes (socket
# absent, so every event spools) while the Event Server goes through restart cycles; asserts no event is lost
# or duplicated. Builds the CLI in debug (dev AppEnvironment) and hands its path to SpoolFloorTests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT/Packages/VigieCLI"
swift build --build-system swiftbuild --product vigie
VIGIE_CLI_BIN="$(swift build --build-system swiftbuild --show-bin-path)/vigie"
[ -x "$VIGIE_CLI_BIN" ] || { echo "error: $VIGIE_CLI_BIN not built" >&2; exit 1; }
export VIGIE_CLI_BIN

cd "$ROOT/Packages/VigieCore"
start=$SECONDS
swift test --build-system swiftbuild --filter SpoolFloorTests
echo "spool-floor: OK ($((SECONDS - start)) s)"
