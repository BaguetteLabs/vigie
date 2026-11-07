#!/usr/bin/env bash
# CI config-corpus (AD-8): golden-file round trip of the ConfigStore TOML patcher over
# Packages/VigieCore/Tests/ConfigCorpus/ (each case: input.toml + op.json -> expected.toml, byte for byte).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/Packages/VigieCore"
swift test --build-system swiftbuild --filter ConfigCorpusTests
echo "config-corpus: OK"
