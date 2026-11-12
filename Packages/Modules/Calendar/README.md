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
- **No closed-notch glance**: no left-wing item, no compact view. The Home card is Story 13.3's (below).
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
  (`reminder.open`: `focusEvent(id)` selects the event's day in the grid and its row in the upcoming list (`selectedEventID`), then the
  tab opens). Dismiss is the event's `secondaryAction` (`reminder.dismiss`). Every action resolves the alert.
- **Resolution.** The alert stays unresolved until its event ends (so `[notify] after_focus = "replay"` replays
  it after a Focus, and `drop` drops it), until an action is taken, until the occurrence disappears from the
  store, or until `reminders` is turned off or the module stops.
- **Core side.** Peek style (now accent, 26 px event-track beacon), urgency rank 2, Focus/DND withholding and
  replay, and the `[sounds] calendar_reminder` sound (off by default, listed in Settings › Sounds) are the
  Notifier's.

## Month grid

Story 13.2, DESIGN "Month grid" (`components.month-grid`), mockup `key-calendar-tab.html`. The tab shows the 300px
grid card left and the upcoming list right (Story 13.3). The setup card replaces both while access is missing.

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

## Upcoming list and Home card

Story 13.3, DESIGN "Upcoming list and event track" (UX-DR35), mockup `key-calendar-tab.html`.

- **Model.** `UpcomingList.build(events:calendars:selectedDay:now:calendar:locale:limit:)` is pure. It starts at
  `selectedDay`; when that is today it starts at *now*, so events that ended today are dropped (a running one
  stays as `NOW`). Sections by day: the start day always, then each day with a shown row or the first day of an
  all-day event. Headers `TODAY · WED 04 NOV`, `THU 05 NOV · TOMORROW`, then `FRI 06 NOV` (date from the locale,
  template `EEEddMMM`, uppercased: `MER. 04 NOV.` in French; `TODAY` / `TOMORROW` from the catalog). All-day
  events are chips on the first listed day they cover and never count as rows. At most 5 timed rows; then
  `+N LATER THIS WEEK` counts the remaining timed events that start before the end of the start day's ISO 8601
  week (no line at 0). An empty start day reads `NO EVENTS TODAY` (`NO EVENTS` for another day) and the
  following days follow.
- **Source.** The module merges `events` (today → +14 days) with the grid month's `gridEvents`, so any day picked
  in the grid has its events.
- **Hero.** Only when the list starts today: today's running or next timed event (no hero when today has none
  left; tomorrow's first event is a normal row). Big time (`numeral-big`), title, countdown in the now color
  (A `iris-1`, C `gold-text`), `15:30–16:15 ● WORK`, `JOIN CALL ↵` when it has a video link, and the event track.
  Countdown: `IN 42 MIN` under an hour, `IN 2 H 05` from an hour (minutes round up, so `IN 1 MIN` until the
  start), `NOW` from the start to the end. Only the hero (and the Home card) tick each second (`TimelineView`);
  the list rebuilds each minute.
- **Event track.** A 1px line from the window start (left) to the event start (right tick), with the now marker
  (A cyan dot, C gold diamond) at `(now − windowStart) / (start − windowStart)`, clamped to 0…1 (1 once running).
  `windowStart` = the latest end of a timed event that ends by the hero's start, or 2 h before the start,
  whichever is later (`UpcomingList.trackWindowStart(for:events:)`).
- **Rows.** time · calendar dot · title (+ `MEET` / `ZOOM` / `TEAMS` tag) · calendar · relative time (the
  countdown today, `IN 3 D` on later days). The selected row with a link shows `JOIN CALL ↵` in place of its
  relative time; rows without a link never show a Join button.
- **Keyboard.** With the list focused, ↑↓ move the selection through the rows (hero included; from nothing, ↓
  takes the first and ↑ the last); ↵ opens the selected row's link, or the hero's when nothing is selected. The
  selection is the module's `selectedEventID` (theme selection ring). `focusEvent(_:)` (occurrence id or EventKit
  id) selects the event's day in the grid and its row; `joinCall(_:)` opens the link through the module's
  `openURL` seam (`NSWorkspace.open` in the app).
- **Home card** (`homeCard()`, 222 × 138): `UPCOMING` with today's date, today's next event (time, `JOIN CALL ↵`
  when linked, title with the calendar dot, countdown, the same event track), whatever day the grid has
  selected. `NO EVENTS TODAY` when today has nothing left; without access the card stays (so Settings › Home can
  list it) and shows `CALENDAR ACCESS` / "Vigie can't read your calendars". The Home grid's button around the
  card opens the Calendar tab.
- **Privacy** (AD-24). Event titles and calendar names (rows, chips, hero, Home card) are `.sensitive()` and
  scrubbed from the VoiceOver labels; times, countdowns, headers, the track and `JOIN CALL` stay and work.
- **Accessibility.** A row reads "10:30 to 11:00, Design review, Work calendar, in 42 minutes, Join call
  available"; a chip "v0.3 release week, Work calendar, all day". The track is decorative.

