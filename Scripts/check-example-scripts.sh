#!/usr/bin/env bash
# Story 12.7 (A85, PRD FR-41): the example scripts the app bundles validate against
# schemas/script-module.schema.json: front matter, exactly one code block, and a committed sample of the
# script's stdout (<name>.sample.json). The Swift side (ExamplesTests) parses the same files with ScriptMarkdown
# and runs the dependency-free example for real.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 -I Scripts/check-example-scripts.py "$@"
