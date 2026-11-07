# Vigie

Vigie is a macOS 15+ notch companion (Swift 6 / SwiftUI) that shows AI coding agent sessions, usage and everyday tools in the notch.
Licensed under the GNU General Public License v3.0 (see `LICENSE`). Rules for contributors and agents: `CLAUDE.md`.

## Build

- Packages: `cd Packages/<Name> && swift test --build-system swiftbuild` (the native SwiftPM build system does not compile String Catalogs).
- App: `cd App && xcodegen generate && xcodebuild -scheme Vigie -configuration Debug build`
- Everything: `Scripts/test-all.sh`
