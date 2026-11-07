---
review-of: ../ARCHITECTURE-SPINE.md
lens: good-spine rubric
date: 2026-11-05
sources-checked: [SPEC.md v0.4 §2–14, EXPERIENCE.md, DESIGN.md (frontmatter), .memlog.md]
---

# Rubric review — Architecture Spine, Vigie

## Verdict

The spine is solid and terse. Package isolation, state ownership, session-status authority, the wire format, config/secret writers and dev isolation are the right seams, and most Rules can be enforced. It is not ready to hand to parallel agents yet, for four reasons:

1. The layer table contradicts itself: adapters can't reach the services the Rules require them to use.
2. AD-6, the durability rule, has a race that loses exactly the events it exists to protect.
3. The macOS operational envelope is mostly silent: entitlements and hardened runtime, TCC, launch at login, activation policy, single instance, and CLI install/PATH.
4. The dependency allowlist leaves out parsers that script modules and notes cannot be built without.

Counts: 0 critical · 6 high · 11 medium · 6 low.

---

## High

### H1 — Layer table: adapters can't reach the core services the Rules require them to use
- **Location:** Design Paradigm layer table; AD-1, AD-9, AD-16; SPEC §8.3
- **Problem:** Adapters may depend only on `AgentKit`, and `AgentKit` only on `Wire`. But:
  - SPEC's `AgentAdapter.settings: [SettingDescriptor]` uses a type that lives in `ModuleKit`.
  - Plan-limit usage providers need Keychain credentials, which AD-9 says go only through `SecretStore`.
  - Adapters also need logging, settings values and network access.
  - Nothing gives adapters an injected context.

  Each adapter will either break the layer table or roll its own Keychain, settings and log access. That is the divergence AD-1 and AD-9 exist to prevent. `ModuleContext` (SPEC §4.5) has the same gap: `secrets`, `permissions`, `dropZones` and power/sleep are not on it. Modules can't import VigieCore, so these must be on the context, or every module invents its own path.
- **Fix:**
  - Move `SettingDescriptor`, `Permission` and `ConfigDiff` into a contracts-only home: either `ModuleKit`, with the table changed to "AgentKit → ModuleKit, Wire", or a new `Packages/Contracts`.
  - Add to AD-1: *"Modules see the system only through `ModuleContext`, which exposes settings, storage, secrets, scheduler, hotkeys, notifier, events, host, permissions, dropZones, power, log. Adapters see it only through an injected `AdapterContext` (settings, secrets, log, http) built by App assembly. Neither imports VigieCore, Security, or opens Keychain/files outside these services."*

### H2 — AD-6: replay-then-truncate race loses spooled events
- **Location:** AD-6
- **Problem:** The Rule says the Event Server replays the spool, then truncates it, *before* accepting socket traffic. While replay runs, the socket isn't bound, so concurrent `vigie hook` calls append to the spool. The truncate then deletes those lines unreplayed.

  Concurrent CLI appends also have no stated atomicity. Several hooks fire in parallel, for example PreToolUse from two sessions.
- **Fix:** Replace the replay sentence with: *"On launch the Event Server binds the socket first and queues incoming lines. It then atomically renames `spool.jsonl` → `spool.replaying.jsonl`, replays that file in order, deletes it, and then drains the socket queue. The CLI appends each line with a single `write(2)` under `O_APPEND` while holding `flock(LOCK_EX)` on the spool. Lines over 4 KiB are rejected, not split."*

### H3 — Entitlements, hardened runtime and TCC are undecided
- **Location:** missing AD; Stack; Conventions → Permissions
- **Problem:** The spine never says:
  - that the app is unsandboxed with hardened runtime on;
  - which entitlements are allowed;
  - which Info.plist usage strings exist.

  The likely real divergence: AppleScript focus for Terminal.app and iTerm works in a debug build but fails silently in the hardened, notarized release unless `com.apple.security.automation.apple-events` and `NSAppleEventsUsageDescription` are present.

  Other gaps:
  - Automation consent is per target app, and the `Permission` set lists no automation case.
  - EventKit on macOS 15 needs `NSCalendarsFullAccessUsageDescription`.
  - TCC folder prompts (Desktop/Documents/Downloads, iCloud Drive) hit shelf references, the notes folder, the Ask AI cwd and child scripts, which inherit Vigie's TCC identity.
  - Ad-hoc-signed dev builds lose their Accessibility grant on every rebuild.
- **Fix:** New AD, "Runtime envelope": *"Vigie.app is unsandboxed, Hardened Runtime on, Developer ID signed. Allowed entitlements: `com.apple.security.automation.apple-events` (plus keychain-access-groups per H4). Nothing else without a new AD. Info.plist carries `NSAppleEventsUsageDescription` and `NSCalendarsFullAccessUsageDescription`. `Permission` has cases `.accessibility, .automation(bundleID), .calendar, .notifications`, and folder access is treated as on-demand TCC. Dev builds sign with a stable Apple Development identity, never ad-hoc. CI runs one smoke test of AppleScript focus against a hardened build."*

### H4 — Synchronizable notes key needs a provisioning profile, and the release pipeline doesn't account for it
- **Location:** AD-9; SPEC §12.3; Deferred → bundle ID
- **Problem:**
  - A synchronizable iCloud Keychain item requires the data-protection keychain. That requires a `keychain-access-groups` entitlement, and a Developer ID app needs a provisioning profile for it, embedded at export.
  - `release.yml` (SPEC §12.3) imports only the certificate.
  - The access group also ties to the bundle ID and team ID. Those are deferred, yet v0.1 already ships signed releases via Sparkle.
  - Changing the bundle ID after the first release orphans Keychain items and TCC grants.
- **Fix:**
  - Add to AD-9: *"All SecretStore items use the data-protection keychain (`kSecUseDataProtectionKeychain`) in access group `<TeamID>.<bundle id>`. The release export embeds a Developer ID provisioning profile with Keychain Sharing, stored as a `release`-environment secret."*
  - Change the Deferred "Bundle ID" row to: *"Must be fixed before the first tagged release (v0.1); never changed after."*

### H5 — The dependency allowlist leaves out parsers that script modules and notes need
- **Location:** AD-16; Stack; AD-18
- **Problem:**
  - Script modules have YAML front matter (SPEC §9.1), and no YAML parser is allowed.
  - AD-18 requires validation against a JSON Schema, and no validator is allowed.
  - Notes are Markdown with custom secret syntax (SPEC §7.6), and no Markdown parser is listed. Foundation's `AttributedString(markdown:)` cannot parse `||…||` or fenced `secret` blocks.

  Each agent working on v0.3/v0.4 will either add a dependency (breaking AD-16) or hand-roll one differently.
- **Fix:** Decide now and add to Stack, for example:
  - `Yams` (exact pin) for front matter;
  - `swift-markdown` (Apple, exact pin) for notes and script docs;
  - for JSON Schema: *"No JSON Schema validator dependency: `schemas/script-module.schema.json` is the published contract; the runner validates with Codable types generated from/kept in sync with the schema, and CI checks the examples against the schema with a dev-only tool."*

### H6 — Process model, launch at login, activation policy and single instance are silent
- **Location:** missing AD (operational envelope)
- **Problem:** Nothing decides:
  - launch at login (`SMAppService.mainApp`, default on or off, and where the toggle lives);
  - Dock and menu-bar presence (`LSUIElement` / accessory activation policy), which interacts with "never steal focus" and the Settings window;
  - single instance. Two copies of the release build, for example `/Applications` plus a DMG mount, will both try to own `vigie.sock`, and the second will unlink the live socket.

  The memlog rejected a helper process, but the spine doesn't state the resulting process model. These choices span the App target, VigieCore host and Settings, so separately built units will diverge.
- **Fix:** New AD, "Process model":
  - *One GUI process (accessory activation policy, `LSUIElement = YES`; switches to `.regular` only while the Settings window is open) plus short-lived `vigie` CLI processes and script child processes.*
  - *No XPC services, LaunchAgents or login items other than `SMAppService.mainApp`. Launch at login is offered in onboarding, default on, stored in the local machine file.*
  - *Single instance per `AppEnvironment`: the Event Server takes `flock` on `<support>/vigie.lock` before touching the socket. If the lock is held, the new instance tells the running one to expand, then quits. A stale socket file is unlinked only while holding the lock.*

---

## Medium

### M1 — The CLI install location and hook command path are undecided
- **Location:** AD-17; SPEC §3, §8.2, §12.3 (Homebrew)
- **Problem:** SPEC says "symlinked into `PATH`", but none of these is decided:
  - who creates the link;
  - where (`/usr/local/bin` needs admin, `~/.local/bin` may not be on PATH);
  - how the cask's `binary` stanza and the in-app installer coexist;
  - whether hook installers write a bare `vigie` or an absolute path.

  A bare name that isn't on the hook's PATH makes the shell exit 127, which breaks "exits 0 in every case". Separate adapter installers will each choose differently.
- **Fix:** Add to AD-17, or a new CLI AD: *"The app ensures a symlink `~/.local/bin/vigie` (dev: `vigie-dev`) → `Vigie.app/Contents/MacOS/vigie` at every launch, repairing it if the app moved. Hook installers always write the absolute symlink path, never a bare name. The Homebrew cask declares the same `binary`. One core `CLIInstaller` owns this."*

### M2 — The CLI can't reach `AppEnvironment`
- **Location:** AD-17 and the layer table
- **Problem:** "All paths derive from one `AppEnvironment` value", but `VigieCLI` may depend only on `Wire`, and the Rule doesn't say where `AppEnvironment` lives. The CLI will hard-code `~/Library/Application Support/Vigie/vigie.sock`, and a dev CLI will then write to the release spool.
- **Fix:** *"`AppEnvironment` (bundle id, support dir, socket, spool, lock, CLI name) lives in `Wire` and is selected by a compile-time flag shared by the app and CLI targets."*

### M3 — The wire envelope has no capture timestamp, so replayed events skew status timing
- **Location:** AD-7, AD-5
- **Problem:** Spooled events can be replayed minutes or hours later. Without a timestamp taken when the CLI captures the event, `SessionStore` will compute `done_to_idle`, T+, `stale_after` and host-slept against replay time. Ordering between the spool and live traffic is also undefined.
- **Fix:** Change the AD-7 envelope to `{ "v", "topic", "ts", "payload" }`, where `ts` is set by the CLI at capture (ISO 8601 UTC). Add to AD-5: *"SessionStore uses `ts`, never arrival time; events older than the session's last applied `ts` are ignored."*

### M4 — The CLI never says how long it may block
- **Location:** AD-6
- **Problem:** "Exits 0 with no output" holds, but nothing caps how long the CLI waits. If the app is alive but its accept loop is stalled, every agent tool call waits on `connect`/`write`.
- **Fix:** Add: *"The CLI uses a non-blocking connect and write with a 150 ms total budget. When the budget runs out it spools and exits."*

### M5 — Agent-config edits (`integrationPlan`) have no single applier
- **Location:** AD-5/AD-8 neighbourhood; SPEC §8.3
- **Problem:** Adapters return a `ConfigDiff`, but no Rule says who:
  - shows the diff;
  - backs up the file;
  - writes it atomically;
  - preserves JSON or TOML formatting in `~/.claude/settings.json` and `~/.codex/config.toml`;
  - records that the integration is installed.

  Three adapters will produce three install paths.
- **Fix:** *"Adapters only produce `ConfigDiff`s and never write files. One core `IntegrationInstaller` shows the diff, writes a timestamped backup next to the target, applies the change atomically (temp + rename), and records the result in the local machine file."*

### M6 — Settings window, onboarding and expanded view are missing from the Capability map, and their placement is blocked by the layer table
- **Location:** Capability → Architecture Map; layer table
- **Problem:** SPEC §10 (expanded view, Home, tab bar) and §10.1 (Settings window generated from `SettingDescriptor`, onboarding with the hook-installer diff, Accessibility step) have no row. Onboarding needs adapters' `integrationPlan`, but VigieCore may not depend on AgentKit.
- **Fix:**
  - Add the row: *"Expanded view, Home, Settings window, onboarding (SPEC §10, §10.1) | VigieCore (host, generated settings UI), App assembly (onboarding composition) | AD-4, AD-8, AD-13".*
  - Add to AD-4: *"Onboarding steps that need adapters are composed in App assembly; modules may contribute onboarding steps via ModuleKit."*

### M7 — Script modules register as several dynamic modules with no contract
- **Location:** AD-1, AD-18; SPEC §7.4, §5
- **Problem:** "Each script appears as its own module in arbitration, settings, and tabs", yet Integrations is one package that can't touch the Registry, and the Registry API for runtime-discovered modules is not stated. The core-template widget renderer has no fixed home either.
- **Fix:** Add to AD-18: *"Integrations registers one `NotchModule` per confirmed script via `context.host.registerDynamicModule(manifest:)` and unregisters it on removal or decline. Script widgets are rendered only by VigieUI templates."*

### M8 — No forward/backward compatibility rule for synced config and theme files
- **Location:** AD-8, AD-12, AD-14; Conventions
- **Problem:** `config.toml` and custom themes sync between Macs that may run different Vigie versions. A renamed key, a repurposed key, or a ConfigStore that drops unknown keys will corrupt the older Mac's config. The JSON-state versioning convention doesn't cover TOML.
- **Fix:** Add to Conventions: *"Config and theme TOML: keys are never renamed or repurposed. Deprecated keys keep being read. Unknown keys and tables are preserved byte-for-byte and ignored. Theme files carry `schema = <int>`; a newer schema falls back to the base theme with a setup-problem alert."*

### M9 — The `[sync] icloud` toggle has no defined mechanism
- **Location:** AD-12; SPEC §11 `[sync] icloud`
- **Problem:** Sync is "the user places the folder", but SPEC has an `icloud = false` setting and a Sync pane. Nothing says what the toggle does or who moves the folders, so the Settings pane and ConfigStore will diverge.
- **Fix:** Add to AD-12: *"`sync.icloud = true` makes ConfigStore move the config and notes folders to `~/Library/Mobile Documents/com~apple~CloudDocs/Vigie/{config,notes}` and record the new locations in the local machine file. `false` moves them back. No other code moves these folders."* Also move `icloud` out of the synced file, since it is machine-specific.

### M10 — Runtime PATH resolution for scripts and agent CLIs
- **Location:** AD-18; adapter version detection
- **Problem:** A GUI app launched at login gets a minimal PATH. `runtime: python3`, `node`, and the `claude --version` check (SPEC §14.5) will resolve differently or not at all, and each adapter and the runner will invent its own fix.
- **Fix:** *"Core resolves executables via one `ExecutableResolver`: the user's login-shell PATH is captured once per launch (`$SHELL -l -c 'printf %s "$PATH"'`, 2 s timeout), and a per-runtime override can be set in the local machine file. Scripts and adapters never call `Process` with bare names."* Also add to AD-18: *"On timeout the runner kills the process group."*

### M11 — Unsupported CLI versions have no enforcing rule
- **Location:** AD-5; SPEC §14.5
- **Problem:** The fixture directories are keyed by CLI version, but no Rule makes adapters gate on version. One adapter may guess while another refuses.
- **Fix:** Add to AD-5: *"Each adapter detects the installed CLI version at start. Outside its fixture-tested range it emits no normalized events and reports `unsupported(version)`, which agents.sessions raises as a setup-problem alert."*

---

## Low

### L1 — Session persistence frequency and atomicity (AD-6)
**Problem:** "Persists on every change" includes tool.start/tool.end heartbeats, which means main-actor disk writes on every tool call.

**Fix:** *"Persist on status or membership change only (not heartbeats), atomically (temp + rename), off the main actor."*

### L2 — Swift 6 sendability of shared adapters (AD-3/AD-4)
**Problem:** The same adapter instances go to two modules.

**Fix:** *"`AgentAdapter`, `TerminalAdapter` and `UsageProvider` conform to `Sendable`; any mutable state is actor-isolated."*

### L3 — Strings in package bundles (AD-15)
**Problem:** In SwiftPM targets, `String(localized:)` defaults to `Bundle.main`, so lookups miss the package catalog.

**Fix:** *"…`String(localized: …, bundle: .module)`; SwiftUI `Text` with `bundle: .module`."*

### L4 — Theme generation ownership (AD-14 / Deferred "Theme TOML schema")
**Problem:** The DESIGN.md → TOML generator and VigieUI's loader can drift apart.

**Fix:** *"The generator is a Swift executable in the VigieUI package that uses the same Codable token types. CI regenerates the themes and fails on any diff; never hand-edit `Themes/`."*

### L5 — Deferred rows with the wrong containment, and missing Deferred rows
**Problems and fixes:**
- "Arbitration when blocked/failed outnumber slots … inside Notch Host" is only partly true. Glyph selection and `+X` live in `agents.sessions.compactView`, and script side-slot competition involves Integrations. Restate as: *"Host owns slot counts; each module owns which items fill its slots."*
- The "Ask AI launch syntax" row is not fully contained in `launchCommand`. Opening a new tab, and the paste fallback, need a `TerminalAdapter.openTab(command:cwd:)` that SPEC §7.1.1 doesn't define. Add it to the contract or to this row.
- Add these Deferred rows:
  - DND/Focus detection technique, contained in Notifier;
  - DND replay vs drop (SPEC §14.20);
  - coexistence with other notch apps (SPEC §14.8);
  - touch input (SPEC §14.12).

### L6 — The §12 mapping and the CI floor
**Problem:** The map row "Build, release, updates" says it is governed by AD-16 and AD-17, but neither governs release. The CI floor decided in the memlog doesn't appear in the spine.

**Fix:**
- Change the row to *"SPEC §12 is binding (release only from `v*.*.*` tags on master, secrets only in the `release` environment, CI never signs)"*.
- Add to Conventions → Tests: *"CI floor: SessionStore transitions, arbitration, ConfigStore round-trip, spool/replay, usage ingest, adapter fixtures."*

---

## Checklist summary

| Criterion | Result |
| --- | --- |
| Fixes the real divergence points | Mostly. Gaps: adapter context (H1), integration installer (M5), dynamic script modules (M7), CLI install (M1) |
| Every Rule enforceable and preventing its divergence | AD-6 does not (H2, M4). AD-1/AD-9 cannot be followed by adapters as layered (H1). AD-17 cannot be followed by the CLI (M2) |
| Nothing Deferred lets units diverge | Bundle ID (H4), theme schema (L4), arbitration overflow and Ask AI containment (L5) |
| Covers SPEC §3–12 | Missing: §10/§10.1 (M6), §8.3 integrationPlan application (M5), §14.5 version gating (M11). §12 is mapped to the wrong ADs (L6) |
| Owned dimensions decided, deferred, or open | Silent: entitlements/hardened runtime/TCC (H3), launch at login/process model/single instance (H6), CLI distribution (M1), cross-version config compatibility (M8). i18n is decided (L3 nit). Accessibility API use is only implied |
| Terse, records decisions | Yes |
