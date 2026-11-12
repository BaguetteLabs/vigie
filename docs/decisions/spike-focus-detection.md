# Spike: detect macOS Focus / Do Not Disturb (Story 3.5 follow-up)

- **Story:** 3.5 follow-up (FR17, UX-DR62, A21, AD-20). Romain ruled "research another route" on 2026-11-08.
- **Date:** 2026-11-12
- **Mac:** macOS 26.5.2 (25F84), Apple silicon, Xcode 26.6 / Swift 6.3.3. Romain was using the Mac, so
  **Focus was never toggled** by this spike: every "on/off" observation below comes from the unified log of
  `donotdisturbd` (the nightly Do Not Disturb schedule, 00:00 to 08:00) or is marked *unverified*.
- **Envelope:** Vigie per AD-20: unsandboxed, Hardened Runtime, no entitlements beyond Apple Events and
  keychain groups, no app extensions. The probe matches it: ad-hoc signed with `--options runtime`
  (`flags=0x10002(adhoc,runtime)`), no entitlements, `LSUIElement`.

## Question

How can Vigie know that a Focus mode (Do Not Disturb included) is on, and when it ends, so the Notifier can
suppress peeks and sounds (Story 3.5), at what permission cost, with what latency, for which kinds of Focus
(manual, scheduled, smart, shared from the iPhone), and how stable is the route across macOS releases?

## Candidates

1. Read `~/Library/DoNotDisturb/DB/Assertions.json` (shipped today) and `ModeConfigurations.json`, with a
   folder watch for changes.
2. `defaults` / `plutil` on `com.apple.controlcenter`, `com.apple.ncprefs` and the ModeConfigurations store.
3. A Shortcuts personal automation on "Focus turns on / off" that runs `vigie event …`.
4. Public notifications (`NSWorkspace`, Darwin `notify`, distributed notifications) and public APIs
   (`INFocusStatusCenter`, App Intents `SetFocusFilterIntent`). Private APIs listed only to reject them.
5. Accessibility query of the menu bar Focus item.
6. Status of the shipped route (`SystemFocusModeMonitor`).

## Probe

A throwaway SwiftPM executable outside the repo:
`/private/tmp/claude-501/-Users-me-www-vigie/03a97dc6-097f-4d60-a649-a2f93afa8536/scratchpad/focus-probe/`
(`Sources/focus-probe/main.swift`), wrapped in `FocusProbe.app` (bundle id
`fr.baguettelabs.spike.focusprobe`). It is read-only: `stat`/`open`/`read` on the DB folder and files,
`Data(contentsOf:)` (the shipped code path), `INFocusStatusCenter.default.authorizationStatus` and
`focusStatus.isFocused` (**never** `requestAuthorization`), `AXIsProcessTrusted()` (no prompt option),
`notify_register_dispatch` on eight candidate Darwin names, a `DistributedNotificationCenter` observer for
any name containing dnd/focus/disturb/ncprefs, a `DispatchSource` (`O_EVTONLY`) on the DB folder, and a 5 s
`isFocused` poll, for 60 s.

Two runs, because TCC charges the **responsible** process:

- **Shell run** (`./FocusProbe.app/Contents/MacOS/focus-probe`, launched from Warp): Warp is responsible,
  and Warp has Full Disk Access. This is what the earlier "the shell could read it" note saw.
- **App run** (`open -g -j -n FocusProbe.app`): LaunchServices makes the probe its own responsible
  process, which is the situation of Vigie.app. Ran 60 s and exited by itself (`done`); `tccd` traffic read
  back with `log show`.

Static evidence: the `donotdisturbd` log for the last four nights, `strings`/`grep` over the dyld shared
cache for DND notification names, the macOS 26.5 SDK headers and `AppIntents.swiftinterface`.

## Results

### 1. `Assertions.json` / `ModeConfigurations.json` (shipped route)

| Run | `stat` | `open` | `Data(contentsOf:)` | `open(O_EVTONLY)` on `DB/` (folder watch) |
|---|---|---|---|---|
| Shell (Warp responsible, FDA) | ok | ok, 2140 / 4978 bytes read | ok | ok |
| **App (own responsibility)** | ok | **`errno 1 EPERM` "Operation not permitted"** on `DB/`, `Assertions.json`, `ModeConfigurations.json`, `Settings.sqlite` | **`NSCocoaErrorDomain 257`**, underlying `NSPOSIXErrorDomain 1` | **`errno 1 EPERM`** |

- **No prompt.** `tccd` logged `TCCDEvent: type=Create, service=kTCCServiceSystemPolicyAllFiles,
  identifier=fr.baguettelabs.spike.focusprobe`: the folder is gated by **Full Disk Access**, which never
  prompts; the app is silently denied (and is listed, switched off, under Full Disk Access). Permission cost
  is therefore FDA, granted only by hand in System Settings.
- **The folder watch fails too**: with `O_EVTONLY` refused, `DispatchDirectoryWatcher` gets no events, so
  only the 15 s poll would be left even with an open-ended watcher.
- **Even with FDA the file misses scheduled Focus.** The nightly schedule (Do Not Disturb, 00:00 to 08:00
  every day, `DNDModeConfigurationScheduleTrigger`) turned on at 00:00:00.07 and off at 08:00:02 on each of the
  last four nights (`State was updated: reason=scheduled`). Its assertion
  (`7E999E44…`, client `com.apple.donotdisturb.private.schedule`, lifetime "match schedule") exists only in
  the daemon: `Assertions.json` was last written on 2026-10-28 (header `version 8`), holds only
  `storeInvalidationRecords` (two manual Focus sessions in October), and no file under
  `~/Library/DoNotDisturb` contains the schedule assertion's UUID. The shipped parser reads "off" all night.
- **Format risk:** undocumented; the header `version` is 8 on macOS 26 and nothing documents or guarantees
  the shape.
- **Latency** (manual Focus, with FDA): file write by `donotdisturbd` plus watch, sub-second; not measured
  (no toggle).

**Verdict: rejected.** FDA is the heaviest grant a utility can ask for, and the data is incomplete anyway.

### 2. `defaults` / `plutil`

- `com.apple.ncprefs` `dnd_prefs` decodes to `{dndMirrored, dndDisplaySleep, dndDisplayLock,
  facetimeCanBreakDND, repeatedFacetimeCallsBreaksDND, playSoundsForForwardedNotifications}`: preferences
  only, no state (the `userPref`/enabled keys of macOS 11 are gone since 12). File last written 2026-01-19,
  through months of nightly DND.
- `com.apple.controlcenter` (and its ByHost plists) holds status item positions and visibility, Live
  Activities and Controls blobs; no Focus key. Its 08:00 mtime is a coincidence with the schedule end that
  cannot be tied to Focus without a toggle; none of its keys carries a Focus value.
- `ModeConfigurations.json` is configuration (modes, triggers, allowed apps and contacts), not state, and sits
  behind the same FDA gate as route 1.

**Verdict: rejected.** No Focus state is persisted in preferences on macOS 12+.

### 3. Shortcuts bridge

Shortcuts has a Focus trigger on macOS 26 (`WFUserFocusActivityTrigger` and its configuration view
controller ship in the shared cache). The user would create, per Focus, two personal automations:

1. Shortcuts › Automation › New › Focus › pick the Focus › "When Turning On" › Run Immediately
   (not "Ask Before Running") › action **Run Shell Script**:
   `~/.local/bin/vigie event app.focus '{"active":true}'` (the CLI symlink AD-22 keeps; `vigie-dev` for dev).
2. Same with "When Turning Off" and `'{"active":false}'`.
3. Shortcuts › Settings › Advanced › **Allow Running Scripts** must be on, or the shell action fails.

Findings and gaps:

- Permission cost: no TCC for Vigie. The Run Shell Script action may itself ask the user once; no Vigie prompt.
- Topic: `vigie event` accepts any `[a-z0-9_.-]+` topic, but no core handler would see `focus.on` today
  (`AppTopics` subscribes to `app.` and logs unknown ones). The bridge needs a core `app.focus` topic.
- Latency: *unverified* (no toggle). Expected 1 to 3 s (Shortcuts launch plus a CLI process); when Vigie is
  not running, the CLI spools and the state is replayed at launch, possibly stale.
- Failure modes: the user must build 2 automations per Focus (Do Not Disturb, Work, Personal, Sleep…);
  "Ask Before Running" posts a notification and nothing runs until tapped; "Allow Running Scripts" off; a
  missed "off" leaves Vigie silent until the next "on/off" (Vigie needs a staleness cap); Shortcuts renames or
  drops a trigger in a macOS release. Scheduled and smart Focus should fire the trigger (*unverified*).

**Verdict: workable, no AD change, but heavy setup and fragile.** Kept as a manual fallback.

### 4. Public notifications and APIs

**Darwin / distributed notifications.** `notify_register_dispatch` succeeded (status 0, state 0) for
`com.apple.donotdisturb.state.changed`, `com.apple.donotdisturb.state`, `_NSDoNotDisturbEnabledChanged`,
`com.apple.notificationcenterui.dndprefs_changed`, `com.apple.ncprefs`, `com.apple.donotdisturb`,
`com.apple.focus.status.changed`, `com.apple.DoNotDisturb.changed` (registering any name succeeds, so this
proves nothing). None fired in 60 s, and none could have: Focus did not change. Statically, none of these
names exists in the macOS 26 dyld shared cache (0 hits for `_NSDoNotDisturbEnabledChanged`,
`dndprefs_changed`, `com.apple.donotdisturb.state`). The daemon's log shows how state really travels:
`Delivering state update: pid=…` over XPC to registered clients of the private `DNDStateService`
(`registerForStateUpdates`). `NSWorkspace` has no Focus notification. **No public push signal exists.**

**`INFocusStatusCenter` (Intents, public, macOS 12+).** App run: `tccd` preflight for
`kTCCServiceFocusStatus`, `authValue=1` (unknown), `authorizationStatus=0` (not determined), no prompt;
`isFocused = false` (Focus was off, and the docs say `nil` when unauthorized, so `false` cannot be trusted as
"off"). Costs and doubts:

- A TCC prompt (`requestAuthorization`, Privacy & Security › Focus) plus `NSFocusStatusUsageDescription`.
- Reported on macOS to need the **Communication Notifications** entitlement
  (`com.apple.developer.usernotifications.communication`): without it `isFocused` stays `false` during a
  Focus even when authorized ([forum thread 856012](https://developer.apple.com/forums/thread/856012),
  [thread 682143](https://developer.apple.com/forums/thread/682143)). That entitlement is **not on the AD-20
  allowlist** (new AD needed), needs the provisioning profile, and Developer ID support is unconfirmed.
- It reports only Focus modes that "share Focus status", and offers no change notification on macOS (poll).

**`SetFocusFilterIntent` (App Intents, public, macOS 13+).** In the macOS 26.5 SDK:
`protocol SetFocusFilterIntent: AppIntent` with `static var current: Self { get async throws }` and
`SetFocusFilterIntentError.notFound`. The user adds "Vigie" under System Settings › Focus › *mode* › Focus
Filters; the system then runs the intent's `perform()` in the app when that Focus turns on, and again with
default parameter values when it turns off. No TCC, no entitlement, no extension target (the intent lives in
the app). Push, so latency should be the daemon's (it switched state in 73 ms at 00:00:00 here). Covers any
Focus the user attaches it to, including scheduled and smart ones, since the filter follows the Focus
whatever turned it on. Not exercised by the probe: an intent needs the App Intents metadata step of an
Xcode app build, and Focus could not be toggled. Same route the developer in thread 856012 switched to.

**Private APIs, rejected:** `DoNotDisturb.framework` (`DNDStateService`, `DNDModeAssertionService`),
`DNDModeState`, Biome streams, `Settings.sqlite`. Repo rules: no private framework (unstable symbols,
notarization risk, AD-20 envelope). Listed only to explain where the state actually lives.

### 5. Accessibility query of the menu bar Focus item

`AXIsProcessTrusted() = false`. `tccd` logged a `kTCCServiceAccessibility` **preflight** (`authValue=1`, no
prompt) and `universalAccessAuthWarn` wrote the probe into the Accessibility list (`TCCDEvent: type=Modify`),
switched off. Reading the item would need Accessibility granted, then a poll of ControlCenter's menu extras
for a Focus element whose label is localized. The item is shown "When Active" by default and can be hidden
(no `NSStatusItem Visible FocusModes` key here; nobody saw it this morning), so a hidden item reads as "off".
**Rejected:** a heavy grant for a brittle, localized, poll-only signal.

### 6. Shipped route

`SystemFocusModeMonitor` (`Packages/VigieCore/Sources/VigieCore/Alerts/FocusModeMonitor.swift`, wired in
`App/Sources/AppDelegate.swift:423`) reads `Assertions.json` (on while `data[0].storeAssertionRecords` is
non-empty), watches the folder and polls every 15 s; unreadable means "off", logged once. On first run
(PROGRESS, integration pass 4) the app logged "Focus assertions unreadable; treating Focus as off". This spike
confirms why (EPERM from FDA, folder watch refused too) and adds that the file would still miss the nightly
schedule with FDA. **Focus suppression does not work in Vigie today.** The `FocusModeMonitor` protocol and
`ManualFocusModeMonitor` are fine; only the system implementation must change.

## Results summary

| Route | Permission | Start / end latency | Manual | Scheduled | Smart / iPhone-shared | Robustness | Verdict |
|---|---|---|---|---|---|---|---|
| `Assertions.json` | Full Disk Access | ≤ 15 s poll (watch refused without FDA) | Yes with FDA | **No (measured)** | Unknown | Undocumented, versioned format | Rejected |
| `defaults` / `plutil` | None (prefs) / FDA (DB) | n/a | No state | No state | No state | n/a | Rejected |
| Shortcuts bridge | None for Vigie; user enables script running | ~1–3 s (*unverified*) | Yes | Likely (*unverified*) | Likely (*unverified*) | User-built, 2 automations per Focus | Fallback |
| Darwin / NSWorkspace | None | n/a | No public name exists | | | | Rejected |
| `INFocusStatusCenter` | Focus TCC prompt **and** an entitlement outside AD-20 | Poll | Reported broken without entitlement | Only Focus that share status | | Public but shaky on macOS | Not now |
| `SetFocusFilterIntent` | **None** (user adds the filter) | Push (*unverified*) | Yes | Yes (*unverified*) | *Unverified* | Public, macOS 13+ | **Primary** |
| Menu bar item via AX | Accessibility | Poll | Only if item visible | | | Localized, hideable | Rejected |

## Decision

1. **Primary: a Vigie Focus Filter (`SetFocusFilterIntent`).** The App ships one filter, "Silence Vigie"
   (one Boolean parameter `silence`, default `false`, suggested `true`). `perform()` forwards the value to a new
   `FocusFilterMonitor: FocusModeMonitor`; at launch the monitor reads `SetFocusFilterIntent.current`
   (`notFound` or `silence == false` means off) so a Focus that started while Vigie was not running is seen.
   No TCC permission, no entitlement, no extension, nothing undocumented. The cost is a one-time user step per
   Focus that should silence Vigie, which also matches macOS semantics (the user chooses per Focus).
2. **Fallback: the Shortcuts bridge** on a new core topic `app.focus` (`{"active": Bool}`), for users who prefer
   automations or if the filter turns out not to fire for some Focus kind. It reuses the same monitor, with a
   cap (an "on" older than 12 h without a later message is treated as off).
3. **How Vigie asks (Story 2.12 pattern, never a blocking prompt):** there is no permission to request. Settings
   › Alerts shows a "Focus" row in a **needs-setup** state until the filter has run at least once (recorded in
   `local.toml`), with "Open Focus settings" (deep link to System Settings › Focus) and a short how-to; the
   Alerts tab shows the same setup card. Nothing is shown at launch or as a modal. `INFocusStatusCenter` is
   not used (it would need a new AD for the Communication Notifications entitlement and a TCC prompt, and is
   reported not to work without it). `SystemFocusModeMonitor`'s `Assertions.json` reading is removed.

## Unverified (re-run checklist)

1. Focus Filter end to end in a Vigie build (needs an Xcode app build for App Intents metadata): add the filter
   to Do Not Disturb, toggle DND from Control Center; `perform()` called on and off, timestamps vs the
   `donotdisturbd` "State was updated" line. Repeat with the nightly schedule, a smart Focus, and DND turned on
   from the iPhone with "Share across devices".
2. `SetFocusFilterIntent.current` at launch with a Focus already on, and with none (`notFound`?).
3. Whether the system launches Vigie to run `perform()` when it is not running (AD-21 single instance holds).
4. Whether a filter declared in a Swift package (AppIntentsPackage) is picked up, or the intent must sit in
   the App target (CLAUDE.md: `App/` holds only assembly; a thin intent there forwarding to VigieCore is
   assembly).
5. Shortcuts bridge latency and whether the Focus trigger runs "immediately" on macOS 26 without a
   confirmation; whether scheduled Focus fires the trigger.
6. macOS 15 behavior of all of the above (no macOS 15 Mac available).
7. Developer ID + notarized build: FDA denial and the filter behave the same (Story 6.1).

**Probe residue for Romain:** the probe now appears, switched off, under Privacy & Security › Full Disk Access
and › Accessibility (no prompt was shown, nothing was granted). Remove with
`tccutil reset All fr.baguettelabs.spike.focusprobe` if wanted; this spike did not touch TCC settings.

## Proposed follow-up story

For the PM to lift into `docs/epics.md`. Not added there.

### Story 3.10: Detect Focus through a Vigie Focus Filter

As a user who turns on Do Not Disturb or another Focus,
I want Vigie to go quiet for the Focus modes I choose, without granting Full Disk Access,
So that Story 3.5's suppression actually works in the shipped app.

**Requirements:** FR17, UX-DR62, UX-DR55, A21, AD-19, AD-20 (no new entitlement or permission), Story 3.5,
`docs/decisions/spike-focus-detection.md`

**Acceptance Criteria:**

**Given** the App target
**When** it is built
**Then** it declares one `SetFocusFilterIntent` ("Silence Vigie", parameter `silence: Bool`, default `false`,
suggested `true`, strings from the String Catalog) whose `perform()` only forwards `silence` to the core
`FocusFilterMonitor` and returns
**And** no entitlement, `Permission` case, usage string or extension target is added

**Given** a Focus with Vigie's filter set to silence
**When** that Focus turns on (manually, by schedule, smart activation or from another device)
**Then** `FocusFilterMonitor.isActive` becomes `true` and Story 3.5 suppression applies; when it turns off,
`isActive` becomes `false` and `[notify] after_focus` applies

**Given** Vigie launches while a filtered Focus is already on
**When** the monitor starts
**Then** it reads `SetFocusFilterIntent.current` and starts active; `notFound` or `silence == false` reads as off

**Given** the user has never added the filter
**When** they open Settings › Alerts or the Alerts tab
**Then** a "Focus" row shows a needs-setup state with "Open Focus settings" and a three-step how-to; nothing
is shown at launch and no modal appears; the state clears once `perform()` has run once (recorded in
`local.toml`)

**Given** a user who prefers Shortcuts
**When** `vigie event app.focus '{"active":true}'` (or `false`) arrives
**Then** the core feeds the same monitor; an "on" with no later message for 12 h is treated as off
**And** Settings › Alerts links to the two-automation recipe from the spike

**Given** the old route
**When** this story lands
**Then** `SystemFocusModeMonitor` no longer reads `~/Library/DoNotDisturb/DB/Assertions.json`; the App wires
`FocusFilterMonitor`; `FocusModeMonitor` and `ManualFocusModeMonitor` keep their API and tests

**Given** tests
**When** `swift test --build-system swiftbuild` runs
**Then** the monitor is covered with a fake filter source (on, off, launch-time `current` on / off / not
found, Shortcuts topic, 12 h cap) and the 3.5 Focus tests pass unchanged
**And** the spike's checklist items 1 to 3 are run by hand on the first build and their results recorded in
the spike file
