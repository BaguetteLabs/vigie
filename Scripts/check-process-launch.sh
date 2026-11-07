#!/usr/bin/env bash
# Conventions "External executables" (AD-19): no code launches a process by a bare executable name. Programs are
# resolved through `context.executables` / `AdapterContext.executables` (ExecutableResolver) to an absolute path.
# Heuristic over Swift sources in Packages/ (build folders skipped):
#   - any `launchPath` (the old API took a bare or relative path);
#   - `executableURL = URL(fileURLWithPath: "...")` / `URL(filePath: "...")` and `Process.run(URL(...: "..."), ...)`
#     whose string literal does not start with `/`;
#   - `/usr/bin/env` as the executable (it looks the real program up by name in PATH).
# A non-literal path (a variable) cannot be checked here; VigieCore/Executables validates `$SHELL` in code.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

sources() {
  find Packages -type d \( -name '.build' -o -name '.build*' -o -name '.swiftpm' \) -prune -o \
    -type f -name '*.swift' -print
}

status=0
report() {
  echo "error: $1 (Conventions: External executables):" >&2
  echo "$2" >&2
  status=1
}

files="$(sources)"
[ -n "$files" ] || { echo "process-launch guard: no sources"; exit 0; }

# shellcheck disable=SC2086
hits="$(grep -HnE '\blaunchPath\b' $files || true)"
[ -z "$hits" ] || report "launchPath is not allowed; set executableURL to a resolved absolute URL" "$hits"

url_literal='URL\((fileURLWithPath|filePath): *"'
# shellcheck disable=SC2086
hits="$(grep -HnE "(executableURL *= *|Process\.run\( *)${url_literal}" $files \
  | grep -vE "(executableURL *= *|Process\.run\( *)${url_literal}/" || true)"
[ -z "$hits" ] || report "process executable built from a relative or bare path literal" "$hits"

# shellcheck disable=SC2086
hits="$(grep -HnE "(executableURL *= *|Process\.run\( *)${url_literal}/usr/bin/env\"" $files || true)"
[ -z "$hits" ] || report "/usr/bin/env resolves the program by name; resolve it with ExecutableResolver" "$hits"

[ "$status" -eq 0 ] && echo "process-launch guard: OK"
exit "$status"
