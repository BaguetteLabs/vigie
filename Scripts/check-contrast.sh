#!/usr/bin/env bash
# Story 2.15 / UX-DR94: WCAG contrast check of the DESIGN contrast and further-surfaces pairs on the
# repository themes (Themes/*.toml). Fails when a Chrome Hologram pair is below 4.5:1 (text) or 3:1
# (non-text meaning); Twin Metal Tactical is reported only until Story 18.1. Pass --quiet to list only
# failures and exceptions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/Packages/VigieUI"
swift run --build-system swiftbuild contrastcheck --themes "$ROOT/Themes" "$@"
