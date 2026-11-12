# Calendar

`calendar` module (SPEC §7.5, Epic 13). Reads every account of the macOS calendar store through EventKit.

- **Off by default.** Disabled, the Registry never starts it and calendar access is never asked.
- **Access.** The manifest declares `.calendar` with `startsWithoutPermissions`, so the module runs without
  access: at `start` it asks once through `context.permissions` (only when undetermined), and while access is
  missing the tab shows the setup card `Vigie can't read your calendars` (`Open System Settings`,
  `Calendar settings`) and the Settings pane shows the same copy. Access is read again when Vigie becomes
  active, when the tab or pane appears and on each store change. No polling.
- **Events.** `CalendarSource` (`EventKitCalendarSource` in the app, an actor) gives `calendars()`,
  `events(in:calendars:)`, `changes()` and `accessDidChange()`. The module keeps `calendars` (all, for Settings),
  `events` (today through the next 14 days, filtered by `calendars` and `hide_all_day`), `options` and `window`,
  reloaded on store changes, settings changes and every hour. `CalendarEvent` carries its `alarms`
  (`AlarmInfo.absolute` / `.relative`, location alarms dropped) and `videoLink` (Meet, Zoom or Teams, found by
  the pure `VideoLink.extract(url:location:notes:)`).
- **Settings** (`[modules.calendar]`): `reminders` (default true, used by Story 13.4), `hide_all_day` (default
  false), `calendars` (included calendar ids, empty = all; drawn by the module's own pane view as checkboxes
  grouped by account with the calendar color, `customControl`). The last checked calendar cannot be unchecked.
- **No closed-notch glance**: no left-wing item, no compact view, no Home card (Story 13.3 adds the card).
  The state stays `hidden`, reminders included.

## Reminders (Story 13.4)

`CalendarReminders` posts `calendar.reminder` (declared in the manifest) through `context.notifier` at each
alarm of `events` (so `calendars` and `hide_all_day` apply; location alarms never reach the module), while
`[modules.calendar] reminders` is on.

- **Planning.** One `context.scheduler.at` job at the next instant that matters: the next alarm, or the end of an
  event whose reminder is open. It is re-planned when `events` reload (store change, hourly, settings), when
  `reminders` changes, on wake (`context.power.sleepWake`) and on `NSSystemClockDidChange`. Each pass raises the
  alarms whose fire date lies after the previous pass and at or before now, if their event has not ended. So an
  alarm missed while the Mac slept is raised once on wake (only the latest one of an event), an alarm already
  past at launch or added in the past is not, and one past its event's end never is.
- **Dedupe.** Each alarm posts once: dedupe key `calendar:<occurrence id>:<fire date epoch>`, kept in memory for
  the alarms still planned. A newer alarm of the same occurrence replaces the open alert.
- **Peek.** Kicker category `in 10 min` (minutes to the start, rounded; `in 1h30` from an hour, `in 2 d` from a
  day, `now` at or after the start), shown by the core as `CALENDAR · IN 10 MIN`. Title = event title; detail
  `16:00–17:00 · Work`, the day first when not today, `All day` for all-day events, the video service last
  (`· Zoom`). Both are `Sensitive` (dots in Privacy mode; macOS notifications carry only `CALENDAR`). Primary:
  `Join call` (`reminder.join`, opens the link) when the event has a video link, else `Open calendar`
  (`reminder.open`: `focusEvent(id)` selects the event's day in the grid and sets `focusedEventID`, then the
  tab opens). Dismiss is the event's `secondaryAction` (`reminder.dismiss`). Every action resolves the alert.
- **Resolution.** The alert stays unresolved until its event ends (so `[notify] after_focus = "replay"` replays
  it after a Focus, and `drop` drops it), until an action is taken, until the occurrence disappears from the
  store, or until `reminders` is turned off or the module stops.
- **Core side.** Peek style (now accent, 26 px event-track beacon), urgency rank 2, Focus/DND withholding and
  replay, and the `[sounds] calendar_reminder` sound (off by default, listed in Settings › Sounds) are the
  Notifier's.

## Month grid

Story 13.2, DESIGN "Month grid" (`components.month-grid`), mockup `key-calendar-tab.html`. The tab shows the 300px
grid card left and the list area right (Story 13.3's upcoming list; until then `NO EVENTS TODAY` or
`N EVENTS TODAY`). The setup card replaces both while access is missing.

- **Model.** `MonthGrid.build(month:today:selected:events:calendars:calendar:locale:maxDots:)` is pure: always six
  rows of seven days (the card height never changes), Monday first with ISO 8601 week numbers (an `.iso8601`
  calendar in the user's time zone), each `MonthGridDay` with `isCurrentMonth` (adjacent-month days are dimmed but
  keep their dots), `isToday`, `isSelected` and `dots`. Header `NOVEMBER 2026` and the weekday initials come from
  the locale (`LLLLyyyy`, `veryShortStandaloneWeekdaySymbols` rotated to Monday), uppercased.
- **Dots.** One per calendar with at least one event that day (timed, all-day, multi-day on each day it covers, a
  zero-length event on its day), in the EventKit color (UX-DR79), ordered by calendar title, at most `max-dots`
  (4) with no overflow mark. `hide_all_day` and `calendars` apply, as for `events`.
- **Data window.** `events` keeps today → +14 days (13.1, used by 13.3/13.4). The grid loads its own interval,
  `MonthGrid.interval(month:calendar:)` (first cell → end of the 42nd), into `gridEvents` / `gridInterval`,
  through the source off the main actor, one month at a time, cached per month; every reload (store change,
  settings change, hourly) empties the cache and loads the visible month again.
- **State.** `visibleMonth` (today's month unless `‹ ›` moved it), `selectedDay` (today unless a day was
  clicked), `canReturnToToday` (the header dot is lit in the now color). `‹ ›` change only the month; a click
  selects the day (and moves the grid when the day belongs to an adjacent month); the dot returns to today and
  the current month.
- **Look.** Every length comes from `components.month-grid` (`card-width`, `columns`, `cell-height`,
  `a-today-radius`, `header-height`, `nav-size`, `weekday-height`, `dot-size`, `dot-gap`, `max-dots`). Today: 1px
  outline in the now color (A `iris-1`, rounded 8px; C `gold`, square, number in `gold-text`). Selected: `ink-1`
  tint with a hairline. A 1px line at 28% traces the month's days. The legend lists the calendars with events
  this month; their titles are `.sensitive()` (Privacy mode), the dots are not.
- **Keyboard.** With the grid focused, ←/→ move the selection by a day and ↑/↓ by a week. EXPERIENCE names no
  month shortcut, so `‹ ›` are pointer and VoiceOver controls only.
- **Accessibility.** Each cell reads `Wednesday 4 November, 2 calendars with events, today, selected`; the
  buttons read `Previous month`, `Back to today`, `Next month`.
