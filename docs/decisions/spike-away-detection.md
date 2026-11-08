# Spike 20.1: input idle time, Away signals and permission

- **Story:** 20.1 (PRD FR-49, addendum §1, AD-20, AD-25)
- **Date:** 2026-11-08
- **Mac:** macOS 26.5.2 (25F84), Apple silicon, Xcode 26.6 / Swift 6.3.3. The screen was **locked** for the
  whole spike (`CGSSessionScreenIsLocked = 1`) and nobody was at the Mac, so no input, unlock, screensaver or
  session switch could be produced. A `caffeinate` process held `PreventUserIdleSystemSleep` and
  `PreventUserIdleDisplaySleep` for the whole run (13 h+).
- **Not testable here:** a build **signed like the release** (Developer ID, Hardened Runtime, notarized). Dev
  builds are ad-hoc signed (PROGRESS, Story 1.1/6.1) and no Developer ID identity is installed, so every
  release-signing row below is *unverified* and must be re-run once Story 6.1 wires a real identity.
- **No macOS 15 machine was available.** macOS 15 rows come from Apple's documentation and are *unverified*.
- **Method:** a prototype in VigieCore (`Packages/VigieCore/Sources/VigieCore/Away/AwaySignals.swift`:
  `IdleTimeReading` + `CGEventSourceIdleReader`, `LockStateObserving` + `SystemLockStateObserver`,
  `ScreenAvailability`, `IdleThreshold`), unit tests on fakes, and a probe run on this Mac:
  `VIGIE_AWAY_PROBE=1 swift test --build-system swiftbuild --filter AwaySignalsTests/probe` (debug, ad-hoc,
  launched from Warp), plus two throwaway binaries (ad-hoc, `swiftc`) with `log stream --predicate
  'process == "tccd"'` running alongside.

## Decision

| Signal | API | Permission | Observed here |
|---|---|---|---|
| Input idle time | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: kCGAnyInputEventType)` (`CGEventType(rawValue: ~0)`) | **None granted, no prompt.** A silent *preflight* Input Monitoring check is logged (below) | Yes: grows 1 s per s, never reset |
| Screen locked / unlocked | `DistributedNotificationCenter` `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` | None | Not observed (locked before and after) |
| Locked at launch | `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` | None (no `tccd` traffic) | Yes: `1` |
| Screensaver | `DistributedNotificationCenter` `com.apple.screensaver.didstart` / `didstop` | None | Not observed |
| Display sleep / wake | `NSWorkspace.screensDidSleepNotification` / `screensDidWakeNotification` | None | Not observed: `pmset displaysleepnow` while locked posted nothing |
| Session switch | `NSWorkspace.sessionDidResignActiveNotification` / `sessionDidBecomeActiveNotification` | None | Not observed |
| System sleep / wake | `NSWorkspace.willSleepNotification` / `didWakeNotification` (already `PowerService.sleepWake`, Story 4.12) | None | Not observed (no sleep during the spike) |

1. **Signals for 20.3:** Away = `idle >= breaks.away_after` (default 90 s) **or** `!ScreenAvailability.isAvailable`
   (locked, screensaver, displays asleep, session inactive, system asleep). `Away(since:)` is the earlier of
   "last input" (`now - idle`) and the screen signal's receipt time. The initial lock state comes from
   `CGSessionCopyCurrentDictionary`, so a launch on a locked screen starts Away.
2. **Polling:** **5 s while break reminders (or a Pomodoro, 20.5) need presence, nothing otherwise.** The
   screen notifications are push and cost nothing; idle time has no push form. 5 s keeps a 90 s threshold
   within 5 % and costs 0.2 ms CPU per minute (below). 1 s buys nothing for a minutes-scale feature.
3. **Permission cost: none to ask for.** No prompt appeared; the idle value was correct with Input
   Monitoring *not* granted (`authValue=0`). AD-20 and AD-25 stand as written; no `Permission` case and no
   usage string are needed. Re-check on the first Developer ID / Hardened Runtime build (see "Unverified").
4. **Start/stop (PRD FR-4):** 20.3's `CoreAwayService` starts polling and subscribing only while at least
   one consumer asks for presence (break reminders on, or a Pomodoro work phase running), i.e. on the first
   subscription to `context.away.changes`, and stops when the last stream ends. With `time` disabled or
   breaks off, nothing polls. There is no permission to request, so nothing is asked when the feature turns on.
5. **Weak spots** (documented, not fixed, PRD FR-49): passive reading, watching a video or a long call with
   no input looks Away after 90 s, so a break reminder may come late, never early. A video player's
   display-sleep assertion keeps the display on but does **not** reset input idle (measured: idle grew through
   13 h of `PreventUserIdleDisplaySleep`). Synthetic input (remote desktop, a mouse jiggler, `cliclick`)
   resets idle and looks Present. Distributed lock notifications are undocumented names (stable since 10.x,
   used widely); if one is missed, input idle still makes the user Away after 90 s.

## Measurements

From the probe (`AwaySignalsTests/probe`, 60 s per loop) and the throwaway binaries:

| Measure | Result |
|---|---|
| Idle, any input, combined session state | 48 661.6 s at start (≈ 13.5 h since the last input before the lock) |
| Same, `hidSystemState` | 48 661.6 s (identical) |
| Per type (combined): `keyDown` / `mouseMoved` / `leftMouseDown` / `scrollWheel` | 48 661.8 / 48 669.3 / 48 671.8 / 48 695.4 s |
| **`eventType: .null` (0)** | **942 610.5 s combined** (≈ 11 days, meaningless) vs 48 696 s HID. Do not use `.null`; use `kCGAnyInputEventType` (`~0`) |
| 1 s polling for 60 s | 48 662.7 → 48 724.1 s, 0 resets; process CPU 0.0116 s (0.019 %) |
| 5 s polling for 60 s, holding `ProcessInfo.beginActivity(.idleSystemSleepDisabled)` | 48 729.1 → 48 785.3 s, 0 resets; process CPU 0.0024 s (0.004 %) |
| Cost of one call | 10 000 calls in 1.3 ms wall; ≈ 0.2 µs CPU per call |
| Keep-awake assertion vs idle | Not reset by our activity (above) nor by `caffeinate`'s system and display assertions held for 13 h |
| `tccd` during the first idle query | One `TCCAccessRequest` from the process, `service=kTCCServiceListenEvent, preflight=yes`, `authValue=0`, plus a WindowServer check for the same service on the process's behalf, also `preflight=yes, authValue=0`. No prompt, no `kTCCServiceAccessibility`. Later calls in the same process: no further `tccd` traffic |
| `tccd` during `CGSessionCopyCurrentDictionary` | None |

Notes on the TCC lines: the check was attributed to Warp (the responsible process of a binary launched from
a terminal); in Vigie.app the app itself is responsible. `preflight=yes` means "ask whether allowed, never
prompt". The query returned correct, growing values with the check denied, so the window server only uses
it to decide something else (most likely whether to expose per-event detail); the counter itself is not
gated. Whether input **resets** the counter while the check is denied could not be seen (nobody at the Mac):
it is the first thing to confirm on an unlocked Mac (`VIGIE_AWAY_PROBE=1 VIGIE_AWAY_PROBE_SECONDS=30`, move
the mouse in the middle: the 1 s loop must report a reset).

## Unverified (re-run checklist)

1. Release signing: run the probe logic inside a Developer ID, Hardened Runtime, notarized build (Story 6.1);
   expect the same: no prompt, preflight `ListenEvent` only, correct values. Apple documents no entitlement for
   `CGEventSourceSecondsSinceLastEventType`; it is not in the Hardened Runtime exceptions list.
2. macOS 15: same probe on a macOS 15 Mac.
3. Input resets idle with Input Monitoring not granted (unlocked Mac, move the mouse during the probe).
4. Lock / unlock (⌃⌘Q, then Touch ID): `com.apple.screenIsLocked` then `screenIsUnlocked`, with timing.
5. Screensaver (hot corner): `didstart` / `didstop`.
6. Display sleep / wake on an unlocked Mac (`pmset displaysleepnow`, then a key): `screensDidSleep` /
   `screensDidWake`; check whether `screenIsLocked` follows when "require password immediately" is set.
7. Fast user switch: `sessionDidResignActive` / `sessionDidBecomeActive`.

The observer prototype was exercised by unit tests (every notification name maps to its `ScreenSignal`)
and run live (with the main run loop running) for 40 s while `pmset displaysleepnow` was issued on the
locked screen: nothing was delivered, consistent with the displays already being off behind the lock.

## Prototype API for 20.3

- `IdleTimeReading.secondsSinceLastInput()`; `CGEventSourceIdleReader()` (any input, combined state).
- `LockStateObserving.signals: AsyncStream<ScreenSignalEvent>` and `isScreenLockedNow()`;
  `SystemLockStateObserver` (distributed + workspace centers injectable for tests).
- `ScreenAvailability` folds signals (each condition is cleared only by its own end; a system wake also clears
  display sleep). `IdleThreshold(threshold:)` gives idle and last-input time.
- 20.3 builds `CoreAwayService: AwayService` from these (5 s `Task.sleep` loop while subscribed), wires it into
  `ModuleContext.away`, and keeps everything else (Present/Away thresholds from `[modules.time.breaks]
  away_after`) in the service.
