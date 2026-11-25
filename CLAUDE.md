# Vigie — rules for agents working in this repo

Vigie is a GPLv3-licensed macOS 15+ notch companion in Swift 6 / SwiftUI. Read `PROGRESS.md` for state. These documents are binding, in this order of authority for their domain:

1. `docs/architecture/architecture-vigie-2026-11-05/ARCHITECTURE-SPINE.md` — build rules AD-1..AD-26, package layout (Structural Seed), stack allowlist, conventions. Never violate an AD; if one must change, stop and report.
2. `docs/ux-designs/ux-vigie-2026-11-04/DESIGN.md` and `EXPERIENCE.md` — look and behavior. They win over SPEC on UX.
3. `docs/SPEC.md` (v0.10) and `docs/prds/prd-vigie-2026-11-06/prd.md` — what and why.
4. `docs/epics.md` — the story you are implementing, with acceptance criteria. Implement the story as written; do not widen scope.

## Hard rules

- SwiftPM-first: all code in `Packages/*`; `App/` holds only assembly, Info.plist, entitlements, assets, `project.yml` (XcodeGen). The `.xcodeproj` is generated and not committed.
- Swift 6 language mode and complete concurrency checking in every target. `@MainActor @Observable` for UI state; I/O off the main actor; boundary types `Sendable`. No singletons, no TCA.
- Package dependency direction (AD-1): Core → ModuleKit, VigieUI, Wire · AgentKit → ModuleKit, Wire · VigieUI → ModuleKit · VigieCLI → Wire only · Modules → ModuleKit, VigieUI (+ AgentKit, Wire for agent modules) · Adapters/Terminals → AgentKit. Modules never import VigieCore or another module.
- Third-party dependencies only from the AD-16 allowlist (Sparkle, GRDB, KeyboardShortcuts, swift-toml, Yams, swift-markdown). Nothing else without a new AD.
- Every user-facing string goes through a String Catalog in its package (`bundle: .module`). No hard-coded English in views.
- Views read colors, metrics, motion and fonts only from the theme (AD-14). No hex literals or durations in view code.
- All paths come from `AppEnvironment` in `Wire` (AD-17). No `Application Support` literals elsewhere.
- Config is read and written only by `ConfigStore`; secrets only by `SecretStore`; alerts only through `Notifier`.
- Tests: `swift test --build-system swiftbuild` per package must pass (the default SwiftPM build system does not compile `.xcstrings` on Swift 6.3, so catalog lookups fail under it). `Scripts/test-all.sh` runs everything. Add tests for every behavior the story's acceptance criteria name.
- Commit messages: conventional (`feat(scope): …`, `test:`, `chore:`), one story per commit, body lists the story id. End with the attribution lines given by the harness.

## Local toolchain

Xcode 26.6 / Swift 6.3.3 on macOS 26.5. Build the app with `xcodegen generate` in `App/` then `xcodebuild`. Dev builds are **ad-hoc signed for now** (keychain-access-groups features deferred).
