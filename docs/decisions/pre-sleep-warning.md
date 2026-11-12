# Pre-sleep warning

Date: 2026-11-12. Story 4.14 (SPEC §14.14, Architecture Deferred, A25, AD-19, AD-20). Research only: nothing ships.

## Decision

**Feasible in part.** A user-space, non-sandboxed, Hardened Runtime app with no entitlement and no permission can:

- **Prevent idle sleep** (assertion, or a veto at `kIOMessageCanSystemSleep`): fully.
- **Learn about a forced sleep** (Apple menu, power button, hot corner, lid close, `pmset sleepnow`) only when it has already started, and **delay it by at most 30 s**. It cannot be refused.

So "warn before a lid close or manual sleep so the user can cancel it" is **not possible**. What is possible: keep the Mac awake through idle time while agents work (already shipped as `prevent_idle_sleep`, Story 4.12), and, in the gap before a forced sleep completes, use the delay window to flush state and show a peek. Section "Proposed follow-up story" scopes that.

## What can be intercepted, per cause

| Cause | `NSWorkspace.willSleepNotification` | `kIOMessageCanSystemSleep` (veto) | `kIOMessageSystemWillSleep` (delay) | `PreventUserIdleSystemSleep` assertion |
|---|---|---|---|---|
| Idle sleep | Delivered | Delivered. `IOCancelPowerChange` vetoes it | Only if nobody vetoed | Prevents it |
| Apple menu, power button, hot corner | Delivered | **Not delivered** | Delivered, cannot be refused, can be delayed up to 30 s | Does not prevent it |
| Lid close | Delivered | **Not delivered** | Same | Does not prevent it |
| `pmset sleepnow` | Delivered | **Not delivered** (same forced path) | Same | Does not prevent it |

The `pmset sleepnow` and power-button rows come from the "forced sleep" wording below plus the fact that they are not idle timeouts. They are **unverified by a run**: the Mac was in use and the brief forbids sleeping it.

### NSWorkspace

`willSleepNotification` is posted before sleep and `didWakeNotification` after wake. It is an observer notification: there is no acknowledgement, no veto and no documented way to hold sleep from the handler. Anything slow in the handler races the sleep, which proceeds on its own schedule. It carries no sleep cause and no date. Vigie already uses it (`PowerService.sleepWake`, Story 4.12). Reference: <https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification>.

### IOKit `IORegisterForSystemPower`

From the SDK header (`IOKit.framework/Headers/pwr_mgt/IOPMLib.h`, `IOMessage.h`, Xcode 26.6 SDK):

- `kIOMessageCanSystemSleep`: "the system is pondering an idle sleep, but gives apps the chance to veto that sleep attempt". The caller must answer with `IOAllowPowerChange` or `IOCancelPowerChange`. "any app that calls IOCancelPowerChange will veto the idle sleep". It is "followed up to 30 seconds later by a `kIOMessageSystemWillSleep` message or a `kIOMessageSystemWillNotSleep` message". After a veto the idle timer elapses again and the same message comes back.
- `kIOMessageSystemWillSleep`: "delivered at the point the system is initiating a non-abortable sleep". The caller must call `IOAllowPowerChange`; if not, "the sleep will continue anyway after a 30 second timeout". `IOCancelPowerChange` "has no meaning" for it (the `IOCancelPowerChange` header comment).
- `kIOMessageSystemWillNotSleep`: sent after a veto. No acknowledgement.
- `kIOMessageSystemWillPowerOn` / `kIOMessageSystemHasPoweredOn`: wake. No acknowledgement. `HasPoweredOn` arrives "1-5 or more seconds after initiating system wakeup".

Apple's Technical Q&A QA1340 states the split directly (<https://developer.apple.com/library/archive/qa/qa1340/_index.html>): for `kIOMessageCanSystemSleep`, "This message will not be sent for forced sleep"; for `kIOMessageSystemWillSleep`, "If you call IOCancelPowerChange to deny sleep it returns kIOReturnSuccess, however the system WILL still go to sleep"; and "even with I/O Kit, it is not possible to prevent forced sleep, only delay it". The I/O Kit Power Management release notes say the same ("no API allows an application to prevent forced system sleep (lid close, Apple menu, thermal)": <https://developer.apple.com/library/archive/releasenotes/Darwin/RN-IOKitPowerManagment/>). An Apple engineer on darwin-dev confirms that with lid close or Apple menu sleep the callback never receives `kIOMessageCanSystemSleep` (<https://lists.apple.com/archives/Darwin-dev/2006/Dec/msg00037.html>). Those sources are old; I found nothing that says macOS 15 or 26 changed this, and a 2024 Apple Developer Forums thread (<https://developer.apple.com/forums/thread/770517>) still describes lid close and the Apple menu as producing power notifications only.

The 30 s is a timeout from Power Management, not a promise: the system may also cut it short under thermal or critical-battery sleep (QA1340 lists those as forced). Treat the available time as "up to 30 s, often much less, not guaranteed".

### Power assertions

Each assertion is created with `IOPMAssertionCreateWithName` and released with `IOPMAssertionRelease`. Header (`IOPMLib.h`) and probe results:

| Type | Header | Prevents | Probe (this Mac) |
|---|---|---|---|
| `PreventUserIdleSystemSleep` | Current. "The system may still sleep for lid close, Apple menu, low battery, or other sleep reasons. No effect in Dark Wake." | Idle system sleep. The display may still dim and sleep | Created, listed under that name |
| `PreventUserIdleDisplaySleep` | Current. "While the display is prevented from dimming, the system cannot go into idle sleep." Display may still sleep on lid close | Display dimming and idle sleep | Created, listed |
| `NoIdleSleepAssertion` | Deprecated 10.7, use `PreventUserIdleSystemSleep` | Idle system sleep (legacy name) | Created, listed under its own name |
| `PreventSystemSleep` | Deprecated 10.9: "not supported in any OS X releases" | Documented as unsupported. `caffeinate -s` still uses it, and `man caffeinate` says it is "valid only when system is running on AC power" | Created (`kIOReturnSuccess`), listed. Effect not tested |

Visibility: `pmset -g assertions` lists each as `pid N(name): [id] hh:mm:ss <Type> named: "<reason>"`, and `pmset -g` shows `sleep prevented by <process>`. Activity Monitor shows them in the **Preventing Sleep** column (View › Columns) and `kIOPMAssertionTypeKey` is the type string. The reason string passed at creation is what users see, so it must be meaningful (`Vigie: an agent session is working`).

None of the four stops lid close or a forced sleep on a Mac on battery without an external display. `PreventSystemSleep` on AC is the only one Apple's own tool says goes further (clamshell sleep with AC), but it is deprecated and "not supported": do not build on it.

### Lid close

- Closing the lid sends the forced path: no veto, `kIOMessageSystemWillSleep` with up to 30 s of delay.
- Without root, nothing short of the **clamshell mode** conditions keeps the Mac awake: AC power plus an external display (and, usually, an external keyboard or mouse) attached. That is the OS's own behavior, not something an app turns on.
- `sudo pmset disablesleep 1` (root) sets the `SleepDisabled` flag and does keep the Mac awake with the lid shut, battery included. It is a global, persistent power setting that needs root and survives the app quitting. A non-root, sandbox-free app cannot do it, and a helper tool is out of Vigie's envelope. Not run.
- `caffeinate` and its assertions have the same limits as the table above: `-i` is idle only, `-s` is AC only and does not override an explicit sleep.

## Permissions and entitlements

None for any route.

| Route | Entitlement / permission | Hardened Runtime, no sandbox |
|---|---|---|
| `NSWorkspace` notifications | None | Works (already shipping) |
| `IORegisterForSystemPower`, `IOAllowPowerChange`, `IOCancelPowerChange` | None. No TCC prompt | Works |
| `IOPMAssertionCreateWithName` / `ProcessInfo.beginActivity` | None | Works |

Probe: a SwiftPM executable signed ad-hoc with `codesign -s - -o runtime` (flags `adhoc,runtime`, no entitlements file) registered with `IORegisterForSystemPower` (port and notifier returned non-zero), and created all four assertion types successfully. Release signing (Developer ID, notarized) is untested, as in the Story 20.1 spike, but nothing in these APIs is gated by signing. No change to AD-20 is needed. In the App Sandbox the same calls also work, so a future App Store route would not block it.

## Latency and what the user sees

- **Idle sleep:** the app learns at `kIOMessageCanSystemSleep`, which is the point where the idle timer has already elapsed. It can answer immediately (veto or allow) or up to 30 s later. The veto is silent: the user sees nothing, the Mac just stays awake, and the same question returns after the next idle period. Any visible explanation is Vigie's own UI.
- **Forced sleep:** the app learns at `kIOMessageSystemWillSleep` (and `willSleepNotification`) at the moment the sleep starts, with no lead time before the user acted. For the Apple menu, power button and hot corner the display is still on. For a lid close the user has already shut the lid, so on a laptop with no external display nobody sees a peek. The most the app can do is hold `IOAllowPowerChange` for up to 30 s (not recommended: Apple calls it "a bad user experience").
- **UI:** a delay window only has value if what happens in it is useful. A peek in the notch that never steals focus is possible for the menu, button and hot corner cases. It cannot ask the user "really sleep?" because the sleep cannot be cancelled; it can only say "n sessions will be interrupted". Because the answer cannot change the outcome, the more useful action in the window is to mark the sessions (what 4.12 does at wake) or to tell the agents nothing.
- `kIOMessageSystemWillSleep` from a lid close can also be Clamshell Sleep or Maintenance/Dark Wake: a handler must not treat every call as a user decision.

## Probe record

Probe: `/private/tmp/claude-501/-Users-me-www-vigie/03a97dc6-097f-4d60-a649-a2f93afa8536/scratchpad/pre-sleep-probe/` (Swift 6.3.3 package, Swift 5 language mode for the C callback, not in the repo), macOS 26.5.2, Apple silicon, signed ad-hoc with `-o runtime`. It registered with `IORegisterForSystemPower`, observed `NSWorkspace.willSleepNotification`, created one assertion of each of the four types, held them 6 s, and exited.

- Saw: `IORegisterForSystemPower port: 6915 notifier: 6659`; four `assert ... OK` lines; while it ran, `pmset -g assertions` listed all four under `pid N(probe)` with the types and reasons above; after exit `pmset -g assertions | grep -c vigie-probe` was `0` and `pgrep probe` found nothing.
- Not seen: any `CanSystemSleep` or `SystemWillSleep`. The Mac was not put to sleep and another process (`caffeinate`) was already holding idle sleep, so no sleep could occur. Nothing was run with `sudo`, no power setting was changed.

## Unverified

- Which message each forced cause delivers on macOS 15 and 26 (menu, power button, hot corner, `pmset sleepnow`, lid close): documented by QA1340 and the release notes, which predate macOS 15, not observed.
- How long a `kIOMessageSystemWillSleep` acknowledgement can really be held in practice on Apple silicon, on battery, and for a lid close.
- Whether `PreventSystemSleep` still works on AC on macOS 15+ (header says unsupported, `caffeinate -s` documents it).
- Behavior under a Developer ID, notarized build.

## Alternatives considered

- **Veto forced sleep with a kernel extension or a root helper.** Out of envelope (AD-20, no helper, no root). Rejected.
- **`pmset disablesleep` while agents work.** Needs root, global, persists after a crash, and keeps a closed laptop running in a bag. Rejected.
- **`PreventSystemSleep` assertion.** Deprecated, "not supported", AC-only in `caffeinate`. Rejected.
- **Hold `IOAllowPowerChange` for 30 s to give the user time.** Delays only; does not let them cancel; a bad experience per the header. Not proposed.
- **Do nothing beyond 4.12.** Valid fallback: the interruption is reported on wake and idle sleep is already opt-in preventable.

## Proposed follow-up story

For the PM to lift into `docs/epics.md`. Not added there.

### Story 4.15: Hold idle sleep and warn when a sleep will interrupt running agents

As Romain,
I want Vigie to keep the Mac awake through idle time while an agent works and tell me, before it happens, when a sleep I started is about to interrupt a run,
So that a run does not die silently because of a closed lid or a Sleep command.

**Requirements:** SPEC §7.1.2, §14.14, A25, AD-5, AD-19

**API choice:** one IOKit root-domain registration owned by `CorePowerService` (AD-19; modules never import IOKit). `IORegisterForSystemPower` on the main run loop, `kIOMessageCanSystemSleep` answered with `IOCancelPowerChange` when idle-sleep hold is on and a session is `working`, otherwise `IOAllowPowerChange`; `kIOMessageSystemWillSleep` always answered with `IOAllowPowerChange` after at most 2 s. The existing `ProcessInfo.beginActivity(.idleSystemSleepDisabled)` token stays the primary way to hold idle sleep; the veto is only the fallback for the moments the assertion is not yet in place. No `PreventSystemSleep`, no `disablesleep`, no helper. `SleepWakeEvent` gains `.willSleepWarning(cause: .idle | .forced)`. No entitlement, no TCC.

**Config sketch:**

```toml
[modules."agents.sessions"]
hold_idle_sleep = false      # opt-in; same effect as [general] prevent_idle_sleep, which it replaces
warn_before_sleep = true     # peek when a forced sleep starts while a session is working
```

**Notifier kind:** `session.sleep_warning` (new, added to the AD-13 list and SPEC §10), severity `warn`, outputs `["peek"]` by default, action `Open Agents`, `dedupe_key = "sleep_warning"`.

**Acceptance Criteria:**

**Given** `hold_idle_sleep = true` and at least one session `working`
**When** macOS sends `kIOMessageCanSystemSleep`
**Then** Vigie vetoes it with `IOCancelPowerChange` within 1 s, no peek appears, and `pmset -g assertions` lists one Vigie assertion with the reason `Vigie: an agent session is working`; with `hold_idle_sleep = false` or no working session Vigie answers `IOAllowPowerChange`

**Given** `warn_before_sleep = true` and at least one session `working`
**When** `kIOMessageSystemWillSleep` arrives (Apple menu, power button, hot corner, lid close)
**Then** Vigie posts one `session.sleep_warning` alert (`<n> sessions will be interrupted by sleep`, action Open Agents) as a peek that does not take focus, calls `IOAllowPowerChange` within 2 s whether or not the peek was shown, and the existing wake-time `host_slept` marking of Story 4.12 is unchanged

**Given** no session is `working`, or `warn_before_sleep = false`
**When** any sleep starts
**Then** Vigie posts no alert and acknowledges `kIOMessageCanSystemSleep` / `kIOMessageSystemWillSleep` immediately; the app never delays a sleep by the 30 s timeout

**Given** the power service is unit-tested with a fake root-domain port
**When** the tests run
**Then** they cover `CanSystemSleep` allow and veto, `WillSleep` acknowledged within the 2 s bound, `WillNotSleep` and wake messages not acknowledged, and a manual check on a real Mac records which message each cause produced on macOS 15 and later (closes the "Unverified" rows of this record)
