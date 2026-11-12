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

The tab is a placeholder (today's event count) until Stories 13.2 (month grid) and 13.3 (upcoming list).
