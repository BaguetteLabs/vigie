---
review: currency
target: ../ARCHITECTURE-SPINE.md
date: 2026-11-05
lens: Were the committed decisions checked against current reality (versions, existence and fit, platform APIs) or asserted from memory?
---

# Currency review: Vigie Architecture Spine

## Verdict

**The spine needs revision before scaffold.** Most named technologies exist, are maintained, and fit a macOS 15 target. Three decisions rest on assumptions that do not hold as of 2026-11-05:

1. One Stack row pins a superseded major version (KeyboardShortcuts).
2. One Stack row cannot provide the behavior an AD requires (swift-toml vs AD-8).
3. One AD depends on a platform requirement the spine never states (AD-9: provisioning profile and entitlement for iCloud Keychain).

The toolchain row is outdated and loosely worded but not wrong.

## Findings

### F1 — HIGH — KeyboardShortcuts pinned to a superseded major (2.4.x)

- **Spine says:** Stack: `KeyboardShortcuts | 2.4.x`.
- **Found:** The latest release is **3.1.0** (11 Sep 2026), which notes "Improve macOS 27 compatibility". **3.0.0** (14 Jun 2026) moved the package to Swift 6 (`defaultIsolation(MainActor)`, `NonisolatedNonsendingByDefault`). It also made a breaking rename, `default:` → `initial:`. **3.0.1** fixes a release-build crash with the Swift 6.3 compiler, which is the spine's own toolchain floor. 2.4.0 dates from Sep 2025 and predates all of this. The package uses swift-tools 6.2 and supports macOS 10.15+, so a macOS 15 target is fine.
  - https://github.com/sindresorhus/KeyboardShortcuts/releases
  - https://raw.githubusercontent.com/sindresorhus/KeyboardShortcuts/main/Package.swift
- **Fit for LSUIElement and a non-activating NSPanel:** Global hotkeys register through Carbon `RegisterEventHotKey` and do not depend on app activation, so they work in an agent app. The Recorder view needs key focus, so it belongs in the (activating) Settings window, not in a peek. I found no reported bug for this combination. This is inferred, not confirmed.
- **Also note:** Option-only shortcuts are blocked by the OS on macOS 15.0 and 15.1 and work again from 15.2. This matters because the deployment target is 15.0.
- **Fix (Stack row):** `KeyboardShortcuts | 3.1.x (≥ 3.1.0; Swift 6, macOS 27 fixes)`.
- **Fix (add to the Hotkeys convention):** "The shortcut Recorder appears only in the Settings window. Default shortcuts avoid Option-only modifiers (blocked on macOS 15.0–15.1)."

### F2 — HIGH — swift-toml cannot do the comment-preserving writes that AD-8 requires

- **Spine says:** AD-8: "Writes patch only the changed keys and preserve comments, order and formatting." Stack: `swift-toml (mattt) | 2.0.0`. Deferred: "TOML comment-preserving editor implementation: internal to ConfigStore."
- **Found:** The package exists as described: "spec-compliant … powered by toml++", TOML v1.0.0, passes 100% of toml-test, MIT, macOS 10.15+, Swift 6.0+. Since 2.0.0 it no longer needs C++ interop mode.
  - Its API is only `TOMLDecoder` / `TOMLEncoder` over `Codable`. It exposes no document or tree model.
  - The encoder writes from Codable values, so comments, ordering and formatting cannot survive a round trip. toml++ itself does not keep comments in its node tree either.
  - A newer tag, **2.1.0**, was cut on 27 Oct 2026. The repo publishes no GitHub Releases, only tags.
  - I found no Swift TOML library that preserves comments (nothing equivalent to Rust `toml_edit` or Python `tomlkit`).
  - https://github.com/mattt/swift-toml
  - https://github.com/mattt/swift-toml/tags
- **Impact:** The Stack row reads as if it covers AD-8, but it covers only the read path. The writer would be new code that someone has to build. Leaving it as a deferred item hides the largest piece of work in ConfigStore.
- **Fix (Stack row):** `swift-toml (mattt) | 2.1.x — decode only (config, themes); never used to write config.toml`.
- **Fix (AD-8 rule, append):** "Writes are done by ConfigStore's own line-level TOML patcher, which replaces or inserts single `key = value` lines inside the target table and leaves every other line byte-identical. After each patch, the result is re-parsed with swift-toml, and the write is aborted if the parse fails or the decoded value differs from the intended one."
- **Fix (Deferred):** Remove "TOML comment-preserving editor implementation" from Deferred, or turn it into a named spike with an acceptance test (round-trip corpus with comments, inline tables, arrays of tables).

### F3 — HIGH — AD-9 iCloud Keychain item needs a provisioning profile and keychain-access-groups entitlement, which the spine never states

- **Spine says:** AD-9: the notes key "is a synchronizable iCloud Keychain item". The Stack lists only "Security (Keychain)". No entitlement or provisioning requirement appears anywhere. Bundle ID is Deferred.
- **Found:**
  - A synchronizable item lives in the data protection keychain. Apple's `kSecAttrSynchronizable` documentation says the keychain-access-groups entitlement must be enabled and a common access group specified.
  - Apple DTS (Quinn) confirms three things:
    - "the data protection keychain *is* available to directly distributed programs that use Developer ID signing", so Developer ID is not blocked.
    - "that access must be authorised by a provisioning profile".
    - Access groups must be prefixed by the Team ID.
    - https://developer.apple.com/forums/thread/826107
    - https://developer.apple.com/documentation/security/ksecattrsynchronizable
  - A standalone command-line tool needs the extra steps in "Signing a daemon with a restricted entitlement". The app bundle's embedded profile does not cover helper executables.
  - If the entitlement is missing at runtime, keychain calls fail with `errSecMissingEntitlement` (-34018).
- **Impact:** AD-9 is feasible for Developer ID distribution, but it has setup work the spine does not mention:
  - a registered explicit App ID;
  - a Developer ID provisioning profile embedded in the app;
  - entitlements `com.apple.application-identifier`, `com.apple.developer.team-identifier` and `keychain-access-groups`;
  - a profile installed in the release CI;
  - a second App ID and profile for the `.dev` bundle (AD-17).
  The Deferred row "Bundle ID … AD-17 only needs it to exist" is wrong, because AD-9 needs a registered App ID before the notes key can be created.
  The rule should also make clear that local-only items still go to the data protection keychain, so all items share one access model.
- **Fix (Stack row, add):** `Signing | Developer ID + Developer ID provisioning profile (explicit App ID, Keychain Sharing capability) for Vigie and Vigie Dev`.
- **Fix (AD-9 rule, append):** "All items use the data protection keychain (`kSecUseDataProtectionKeychain = true`) in access group `<TeamID>.<bundle id>`. The app target carries `keychain-access-groups`, signed with an embedded Developer ID provisioning profile. Only the main app process touches the keychain; the `vigie` CLI never does. If iCloud Keychain is off, the notes key stays local and the recovery-key path is the only cross-Mac route."
- **Fix (Deferred row):** Change "Bundle ID and org prefix" to say it blocks AD-9 and release signing, and must be decided before the notes module.

### F4 — MEDIUM — Toolchain row is one major behind and not pinned

- **Spine says:** `Swift | 6 language mode, toolchain ≥ 6.3 (Xcode ≥ 26.4)`.
- **Found:**
  - **Xcode 27** (27A266a) shipped on 14 Sep 2026, and **Xcode 27.1** (27A9275) on 15 Oct 2026. Both bundle **Swift 6.4**, which was announced 15 Sep 2026.
  - Xcode 27 requires a macOS Tahoe 26.6+ host on **Apple silicon only**.
  - Its minimum macOS deployment target is **12**, so a macOS 15 target builds fine. This is why Sparkle 2.10 raised its own minimum to macOS 12.
  - Breaking changes: ld64 is removed (`-ld_classic` is ignored); there are `@State` initializer and SE-0508 source breaks; Clang module names must be unique.
  - In Swift 6.4, **SwiftPM defaults to Swift Build**. That changes how `swift build` / `swift test` (AD-2) handle resources compared with 6.3.
  - The GitHub runner-images releases I could check (Jul–Sep 2026) show Xcode 27 as a preview, with 26.6 as the default on macos-26. I could not confirm that Xcode 27 GA is now on the hosted runners.
  - Sources:
    - https://developer.apple.com/news/releases/?id=09142026h
    - https://blakecrosley.com/blog/xcode-27-release
    - https://www.infoworld.com/article/4225734/apple-touts-simpler-and-clearer-code-with-swift-6-4.html
    - https://github.com/actions/runner-images/releases
- **Fix (Stack row):** `Swift | 6 language mode; toolchain Swift 6.4 (Xcode 27.1), pinned in CI via xcode-select / .xcode-version; floor 6.3 (Xcode 26.4) for local builds`.
- **Fix (CI row):** `GitHub Actions macOS runners (macos-26 arm64, Xcode 27.x selected explicitly)`.

### F5 — MEDIUM — String Catalogs in SwiftPM: `swift build` / `swift test` support is unconfirmed

- **Spine says:** AD-15: "Every user-facing string comes from a String Catalog in its package." AD-2 and the Tests convention rely on `swift test`.
- **Found:**
  - Under Xcode or `xcodebuild`, `.xcstrings` in a package target (with `defaultLocalization` and `.process`) compiles correctly, including symbol generation.
  - Under the older native SwiftPM build system, `.xcstrings` were copied verbatim and not compiled to `.lproj`. The bundle reported only `en`, and symbols were not generated. The workaround was a plugin that runs `xcrun xcstringstool`.
  - Library code must pass `bundle: .module`. A plain `Text("key")` or `String(localized:)` looks in the main bundle.
  - Generated symbols are `internal`, so VigieUI cannot export status-label symbols to other packages.
  - Swift 6.4's switch to Swift Build may fix the compilation gap, but I could not confirm it.
  - Sources:
    - https://elegantchaos.com/2026/02/12/string-catalogues.html
    - https://github.com/Periicles/Notchapp/pull/26
- **Fix (AD-15 rule, append):** "Package code looks up strings with `bundle: .module`. Shared labels are exposed by VigieUI as public functions or properties, not as generated catalog symbols. CI runs the app's tests through `xcodebuild test` so catalogs compile, and adds one check that the built bundle contains every shipped locale."

### F6 — MEDIUM — iCloud Drive dataless files: AD-12 names the problem but not the mechanism

- **Spine says:** AD-12: "tolerate … iCloud placeholder files not yet downloaded."
- **Found:**
  - Since macOS Sonoma, evicted iCloud Drive files are **dataless files at their real path**. The old `.name.icloud` stubs are gone, and `brctl download/evict` was removed.
  - Opening a dataless file triggers a synchronous download, which can block the caller. A partly downloaded file never appears; the placeholder is replaced only when the download completes.
  - The supported calls are `URLResourceValues.ubiquitousItemDownloadingStatus`, `FileManager.startDownloadingUbiquitousItem(at:)`, and `NSFileCoordinator` for coordinated reads. A non-sandboxed app needs no entitlement to read a user-chosen folder.
  - iCloud replaces files atomically, so a vnode watcher on `config.toml` itself loses track. Watch the directory, or use `NSFilePresenter`.
  - Sources:
    - https://eclecticlight.co/2023/08/06/last-week-on-my-mac-are-we-ready-for-dataless-files/
    - https://mjtsai.com/blog/2023/10/27/icloud-drive-switches-to-dataless-files/
    - https://fatbobman.com/en/posts/advanced-icloud-documents/
  - No Apple primary source was found for whether non-sandboxed apps behave differently. That is unconfirmed.
- **Fix (AD-12 rule, append):** "Reads of synced folders happen off the main actor through `NSFileCoordinator`. Before reading, check `ubiquitousItemDownloadingStatus`. If the file is not current, call `startDownloadingUbiquitousItem` and treat the file as pending (keep the last good value). Watchers observe the containing directory (or use `NSFilePresenter`), never a single file's inode."

### F7 — LOW — Sparkle: confirmed; pin the current tag and note the macOS 12 floor

- **Spine says:** `Sparkle | 2.x (pin latest tag at scaffold)`.
- **Found:** The latest release is **2.10.1** (25 Oct 2026), and the project is actively maintained (default branch updated days ago). It is distributed through SwiftPM and listed on Swift Package Index for Swift 6.1–6.4. 2.10 requires macOS 12+, which fits a macOS 15 target, and removed CocoaPods support.
  - https://github.com/sparkle-project/Sparkle/releases
  - https://swiftpackageindex.com/sparkle-project/Sparkle
- **Fix (Stack row):** `Sparkle | 2.10.x (≥ 2.10.1), SwiftPM`.

### F8 — LOW — GRDB.swift 7.12.0: confirmed current

- **Found:** **v7.12.0** (1 Nov 2026) is the latest release. It uses swift-tools 6.1 and supports macOS 10.15+. Since 7.9.0 it requires Swift 6.1+ and Xcode 16.3+. GRDB 7 targets Swift 6 concurrency (Sendable database access, async reads and writes).
  - https://github.com/groue/GRDB.swift/releases
  - https://raw.githubusercontent.com/groue/GRDB.swift/master/Package.swift
- **Fix (optional):** `GRDB.swift | 7.12.x (≥ 7.12.0)`, so patch releases can be taken.

### F9 — LOW — IOKit power assertions: still the right API, but name the assertion type

- **Spine says:** "IOKit (power assertions)".
- **Found:** `IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleSystemSleep` is still the current API. The older `kIOPMAssertionTypeNoIdleSleep` is deprecated. The higher-level `ProcessInfo.beginActivity(options: .idleSystemSleepDisabled, …)` is equivalent and works in Swift without bridging. Neither prevents lid-close or forced sleep, which matters for SPEC §14.14–15 host-slept detection. Detecting sleep needs `NSWorkspace.willSleepNotification` / `didWakeNotification` (or IOKit `IORegisterForSystemPower`).
  - https://developer.apple.com/documentation/foundation/processinfo/activityoptions/idlesystemsleepdisabled
  - The IOKit header deprecation is cited through third-party bindings; I did not fetch the Apple IOKit page directly.
- **Fix (Stack row):** `IOKit power assertions (PreventUserIdleSystemSleep) or ProcessInfo.beginActivity(.idleSystemSleepDisabled) | system`.

## Could not confirm

- Whether Xcode 27 GA is installed or default on GitHub-hosted macos-26 runners as of Nov 2026. The latest notes I could check, from Sep 2026, show it as a preview.
- Whether Swift 6.4's Swift Build backend compiles `.xcstrings` under plain `swift build` / `swift test`.
- The exact per-capability Developer ID checkmarks on Apple's "Supported capabilities (macOS)" table, which did not render as text. Keychain Sharing ✓ for Developer ID is asserted by Apple DTS in thread 826107.
- That KeyboardShortcuts global hotkeys work with nothing extra in an LSUIElement app with a non-activating panel. This is inferred from its `RegisterEventHotKey` design; no issue or test was found either way.
- Apple primary documentation on dataless-file behavior for non-sandboxed apps. Only secondary sources were found.
- TN3137 (On Mac keychain APIs) body text, which did not render; relied on the DTS forum answer instead.
