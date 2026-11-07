# Host-slept detection

Date: 2026-11-08. Story 4.12 (FR45, FR46, AD-5, AD-19, SPEC §14.15, A20, A24 ruled 2026-11-06).

## Decision

A session is **interrupted by sleep** when it was `working` as the Mac went to sleep and is still `working`,
with no event since, when the Mac wakes. It is then marked `failed` with reason `host_slept`.

## Technique

1. **Signals.** `context.power.sleepWake` (`CorePowerService`) turns `NSWorkspace.willSleepNotification` into
   `.willSleep` and `NSWorkspace.didWakeNotification` into `.didWake`. These cover lid close, the Sleep menu
   item and idle sleep alike. Neither event carries a date, so the wake time is the moment `agents.sessions`
   receives `.didWake`.
2. **At sleep.** `agents.sessions` records a snapshot: the sleep time and every session whose stored status is
   `working`, with its last action. Liveness passes are paused from now on.
3. **At wake.** For each session in the snapshot that is still `working` and whose `lastEventAt` is not after the
   sleep time, `SessionReducer.markHostSlept(keys:at:in:)` sets `failed`, `failureReason = host_slept` and
   `statusSince = wake time`, so `T+` counts from wake. `lastAction` stays the interrupted action. `lastEventAt`
   is not changed. The table is persisted. One alert is posted for the wake (A20): the usual `session.failed`
   alert (kicker `FAILED · HOST SLEPT`, `Run interrupted during <action>`, Focus) for one session, or a single
   summary `session.failed` (`<n> sessions interrupted by sleep`, Open Agents) for several.
4. **Then liveness resumes** with an immediate pass. Liveness never removes a failed session for a dead process
   (AD-5), so a session whose process died during sleep stays listed as failed until it is dismissed or 24 h
   pass.

`SessionStore` stays the only writer of statuses. The snapshot is only a list of keys: the decision to fail is
made against the table at wake time.

## Known false positives and limits

- **A process that survived sleep is still marked failed** (accepted in A24). Most agent CLIs survive sleep:
  their network calls fail or retry. The session shows `FAILED · HOST SLEPT` until its next event. Any in-order
  event (`tool.start`, `prompt.submit`, `turn.end`…) applies normally: the reducer moves the session to that
  event's status and clears `failureReason`, so a run that carries on returns to `working` on its next hook.
  A run that finished during a dark wake, with its `turn.end` already spooled, converges the same way once the
  spool replays.
- **Long tool calls.** A session that sits in one long tool call for the whole sleep and then finishes quietly
  stays failed until its `turn.end`.
- **Missed `.willSleep`.** If Vigie was not running, or the notification was not delivered, there is no snapshot
  and nothing is marked on wake. Sessions then go stale (`stale_after`) as usual.
- **Events during a dark wake (Power Nap).** An event stamped after the sleep time shows the session is alive, so
  it is not marked. An event that arrives late but is stamped before the sleep does not save it.
- **Stale sessions** count as working for the snapshot (their stored status is `working`), so a hung session can
  also be marked host-slept on wake. That is harmless: it was already showing a warning state.

## Alternatives considered

- **Probe the process after wake** and keep the session `working` when its pid and start time are alive (the
  A24 alternative). Rejected for v1. A live process does not mean the run went on: the agent may be waiting on a
  dead connection. The probe would also hide every interruption whose process survived, and those are the
  common case.
- **Compare `lastEventAt` with the wake time** (gap larger than the sleep length). This needs no snapshot, but
  it cannot tell sleep apart from a long quiet tool call, and the gap is already what `stale` reports.
- **IOKit `IORegisterForSystemPower`** (`kIOMessageSystemWillSleep` / `kIOMessageSystemHasPoweredOn`). Same
  information with more plumbing. It can delay sleep, which we do not need. The `NSWorkspace` notifications are
  enough.
- **Mark on `.willSleep`.** Rejected: it would show failed for runs that later resume after a short sleep or
  a cancelled sleep, and the user cannot see it before waking anyway.

## Keep-awake (related)

With `[general] prevent_idle_sleep = true`, `agents.sessions` holds one `context.power.preventIdleSleep` token
while any session shows `working` (stale sessions do not count). `CorePowerService` turns that into one
`ProcessInfo.beginActivity(options: [.idleSystemSleepDisabled])`. It prevents **idle** sleep only. Closing the
lid or choosing Sleep still sleeps the Mac (PRD FR-19), and those runs are caught by the detection above. With
the setting off, requests are accepted but take no assertion.
