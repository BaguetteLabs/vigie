#!/usr/bin/env bash
# Story 12.1 AC 2 (AD-16, AD-18): schemas/script-module.schema.json and the Swift Codable types in
# Packages/Modules/Integrations/Sources/Integrations/Schema agree, without a JSON Schema library.
# Both sides read the same sample documents in
# Packages/Modules/Integrations/Tests/IntegrationsTests/Fixtures/script-schema/{valid,invalid}:
#   - this script validates them against the schema with Scripts/script-schema-check.py (stdlib-only Python,
#     the subset of JSON Schema the file uses) and fails if a valid sample is rejected, an invalid one is
#     accepted or rejected elsewhere than at its named key, or a property, enum value or oneOf branch has no
#     valid sample;
#   - ScriptSchemaFixtureTests and ScriptSchemaTypesTests (`swift test` in the Integrations package) decode
#     them with the Swift types and compare the schema's enums, keys and defaults with the types.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 -I Scripts/script-schema-check.py "$@"
