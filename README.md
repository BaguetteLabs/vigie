# Vigie

Vigie is a macOS 15+ notch companion (Swift 6 / SwiftUI) that shows AI coding agent sessions, usage and everyday tools in the notch.
Licensed under the GNU General Public License, version 3 only (`GPL-3.0-only`, see `LICENSE`). Rules for contributors and agents: `CLAUDE.md`.

## Build

- Packages: `cd Packages/<Name> && swift test --build-system swiftbuild` (the native SwiftPM build system does not compile String Catalogs).
- App: `cd App && xcodegen generate && xcodebuild -scheme Vigie -configuration Debug build`
- Everything: `Scripts/test-all.sh`
- CI: `.github/workflows/ci.yml` (macOS 26 runner, Xcode from `.xcode-version`) runs swift-format lint, `swift test` per package, the app build and a locale check on every PR and push to `master`. No secrets, no signing. Dry run locally: `Scripts/ci-local.sh`
