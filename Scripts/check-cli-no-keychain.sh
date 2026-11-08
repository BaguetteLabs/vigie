#!/usr/bin/env bash
# AD-9 / Story 7.2: only the main app touches the Keychain; the `vigie` CLI never does. Fails if the CLI's
# sources, or Wire (which the CLI links), import Security or mention SecItem, kSec or Keychain.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

dirs=(Packages/VigieCLI/Sources Packages/Wire/Sources)
for dir in "${dirs[@]}"; do
  [ -d "$dir" ] || { echo "error: $dir is missing" >&2; exit 1; }
done

hits="$(grep -rHnE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+(Security|LocalAuthentication)\b|SecItem|\bkSec|[Kk]eychain' \
  --include='*.swift' "${dirs[@]}" || true)"
if [ -n "$hits" ]; then
  echo "error: Keychain access in the CLI or Wire (AD-9: only the app process touches the Keychain):" >&2
  echo "$hits" >&2
  exit 1
fi
echo "cli-no-keychain guard: OK"
