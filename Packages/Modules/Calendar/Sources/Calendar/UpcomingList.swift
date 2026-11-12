import Foundation

/// An all-day event drawn as a chip on its day header (not one of the list's rows).
public struct UpcomingChip: Hashable, Sendable, Identifiable {
    /// The occurrence id.
    public let id: String
    /// The event title (sensitive, AD-24).
    public let title: String
    /// The calendar title (sensitive, AD-24); empty when the calendar is unknown.
    public let calendarName: String
    public let color: CalendarColor?
}

/// One timed event of the upcoming list.
public struct UpcomingRow: Hashable, Sendable, Identifiable {
    /// The occurrence id (``CalendarEvent/id``).
    public let id: String
    /// The event title (sensitive, AD-24).
    public let title: String
    /// The calendar title (sensitive, AD-24); empty when the calendar is unknown.
    public let calendarName: String
    public let color: CalendarColor?
    public let start: Date
    public let end: Date
    /// `15:30` and `16:15` in the locale's hour cycle.
    public let startText: String
    public let endText: String
    /// Days from today to the row's day (0 = today; negative for a past day picked in the grid).
    public let dayOffset: Int
    /// The Meet, Zoom or Teams link: ↵ and `JOIN CALL ↵` open it. Nil = no Join button.
    public let videoLink: URL?
    /// The service of ``videoLink`` (the row's `MEET` / `ZOOM` / `TEAMS` tag).
    public let service: VideoService?
    /// The next event, drawn as the hero row (only when the list starts today).
    public let isHero: Bool

    public var canJoin: Bool { videoLink != nil }
}

/// The hero row's live parts: its event, and the start of the 1px track the now marker runs along.
public struct UpcomingHero: Hashable, Sendable {
    public let row: UpcomingRow
    /// The track runs from `windowStart` (left) to the event start (right). See
    /// ``UpcomingList/trackWindowStart(for:events:)``.
    public let windowStart: Date
}

/// One day of the list: its header, the all-day chips, the timed rows.
public struct UpcomingSection: Hashable, Sendable, Identifiable {
    /// The start of the day.
    public let day: Date
    /// `TODAY · WED 04 NOV`, `THU 05 NOV · TOMORROW`, `FRI 06 NOV`.
    public let header: String
    public let isToday: Bool
    public let chips: [UpcomingChip]
    public let rows: [UpcomingRow]
    public var id: Date { day }
    /// Nothing at all that day: the list shows `NO EVENTS TODAY` (or `NO EVENTS` for another day).
    public var isEmpty: Bool { chips.isEmpty && rows.isEmpty }
}

/// The Calendar tab's upcoming list (Story 13.3, DESIGN "Upcoming list and event track", UX-DR35): a pure model
/// built from the loaded events, the selected day and now.
///
/// - **Start.** The selected day; when it is today the list starts at *now*, so events that already ended today
///   are dropped (a running event stays, as `NOW`).
/// - **Sections.** One per day with something to show, by day: the start day always (empty: `NO EVENTS TODAY`),
///   then each day holding a shown row or the first day of an all-day event. Headers: `TODAY · WED 04 NOV`,
///   `THU 05 NOV · TOMORROW`, then `FRI 06 NOV` (date in the locale, uppercased).
/// - **All-day events** are chips on the header of the first listed day they cover; they never count as rows.
/// - **Rows.** At most `limit` (5) timed events, by start. Past the cap, `+N LATER THIS WEEK` counts the remaining
///   timed events that start before the end of the start day's ISO 8601 week (none: no line).
/// - **Hero.** When the list starts today, the first row of today (the running or next event) is the hero:
///   big time, title, countdown (`IN 42 MIN`, `IN 2 H 05`, `NOW`) and the event track. No hero when today has no
///   timed event left, or when another day is selected.
public struct UpcomingList: Hashable, Sendable {
    public static let defaultLimit = 5
    /// The track never starts more than this long before the event.
    public static let trackLead: TimeInterval = 2 * 3600

    /// The selected day's start.
    public let startDay: Date
    /// The selected day is today: the list starts now and may have a hero.
    public let startsToday: Bool
    public let sections: [UpcomingSection]
    public let hero: UpcomingHero?
    /// Timed events after the shown rows that start within the start day's ISO week.
    public let overflow: Int

    /// Every row in list order (the hero first when there is one): the order ↑↓ moves through.
    public var rows: [UpcomingRow] { sections.flatMap(\.rows) }

    /// `+4 LATER THIS WEEK`, nil when nothing is left this week.
    public var overflowText: String? {
        overflow > 0 ? CalendarText.format("calendar.upcoming.overflow", overflow) : nil
    }

    /// Builds the list.
    /// - Parameters:
    ///   - events: the loaded occurrences (already filtered by `calendars` and `hide_all_day`), any order.
    ///   - calendars: the store's calendars, for each row's calendar title and color.
    ///   - selectedDay: any instant of the day the list starts on (the module's ``CalendarModule/selectedDay``).
    ///   - now: the current instant.
    ///   - calendar: the user's calendar (days, time zone).
    ///   - locale: the header dates and times.
    ///   - limit: the most timed rows.
    public static func build(
        events: [CalendarEvent], calendars: [CalendarInfo] = [], selectedDay: Date, now: Date,
        calendar: Calendar, locale: Locale = .current, limit: Int = defaultLimit
    ) -> UpcomingList {
        let today = calendar.startOfDay(for: now)
        let startDay = calendar.startOfDay(for: selectedDay)
        let startsToday = startDay == today
        let from = startsToday ? now : startDay
        let infos = Dictionary(calendars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let formats = Formats(calendar: calendar, locale: locale)

        // Timed events still to come (or running) from `from`, by start.
        let timed = events.filter { !$0.isAllDay && isUpcoming($0, from: from) }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        let shown = Array(timed.prefix(max(0, limit)))
        let weekEnd = MonthGrid.gridCalendar(calendar).dateInterval(of: .weekOfYear, for: startDay)?.end ?? startDay
        let overflow = timed.dropFirst(shown.count).filter { $0.start < weekEnd }.count

        func dayOf(_ event: CalendarEvent) -> Date { calendar.startOfDay(for: max(event.start, from)) }
        let heroID: String? = startsToday ? shown.first.flatMap { dayOf($0) == today ? $0.id : nil } : nil

        // All-day events: each on the first listed day it covers, from the start day.
        let allDay = events.filter { $0.isAllDay && $0.end > startDay }
            .sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
        let lastShownDay = shown.count == limit ? shown.last.map(dayOf) : nil

        var days: Set<Date> = [startDay]
        for event in shown { days.insert(dayOf(event)) }
        for event in allDay {
            let first = calendar.startOfDay(for: max(event.start, startDay))
            if let lastShownDay, first > lastShownDay { continue }
            days.insert(first)
        }
        let sortedDays = days.sorted()

        var placedChips: Set<String> = []
        var sections: [UpcomingSection] = []
        for day in sortedDays {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let chips = allDay.filter { event in
                !placedChips.contains(event.id) && event.start < next && event.end > day
            }
            for chip in chips { placedChips.insert(chip.id) }
            let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
            let rows = shown.filter { dayOf($0) == day }.map { event in
                UpcomingRow(
                    id: event.id, title: event.title, calendarName: infos[event.calendarID]?.title ?? "",
                    color: infos[event.calendarID]?.color, start: event.start, end: event.end,
                    startText: formats.time(event.start), endText: formats.time(event.end), dayOffset: offset,
                    videoLink: event.videoLink, service: event.videoLink.flatMap(VideoLink.service(of:)),
                    isHero: event.id == heroID)
            }
            sections.append(
                UpcomingSection(
                    day: day, header: header(day: day, offset: offset, formats: formats), isToday: offset == 0,
                    chips: chips.map { event in
                        UpcomingChip(
                            id: event.id, title: event.title, calendarName: infos[event.calendarID]?.title ?? "",
                            color: infos[event.calendarID]?.color)
                    },
                    rows: rows))
        }

        let hero = sections.first?.rows.first { $0.isHero }.flatMap { row in
            timed.first { $0.id == row.id }.map {
                UpcomingHero(row: row, windowStart: trackWindowStart(for: $0, events: events))
            }
        }
        return UpcomingList(
            startDay: startDay, startsToday: startsToday, sections: sections, hero: hero, overflow: overflow)
    }

    /// Still to come or running at `from`. A zero-length event counts until its instant passes.
    static func isUpcoming(_ event: CalendarEvent, from: Date) -> Bool {
        event.end > from || (event.end == event.start && event.start >= from)
    }

    // MARK: Header

    static func header(day: Date, offset: Int, formats: Formats) -> String {
        let date = formats.day(day)
        switch offset {
        case 0: return CalendarText.format("calendar.upcoming.header.today", date)
        case 1: return CalendarText.format("calendar.upcoming.header.tomorrow", date)
        default: return date
        }
    }

    /// `WED 04 NOV` (`MER. 04 NOV.` in French): abbreviated weekday, two-digit day, abbreviated month.
    public static func dayText(_ day: Date, calendar: Calendar, locale: Locale) -> String {
        Formats(calendar: calendar, locale: locale).day(day)
    }

    struct Formats {
        let dayFormatter: DateFormatter
        let timeFormatter: DateFormatter
        let locale: Locale

        init(calendar: Calendar, locale: Locale) {
            self.locale = locale
            dayFormatter = DateFormatter()
            dayFormatter.calendar = calendar
            dayFormatter.timeZone = calendar.timeZone
            dayFormatter.locale = locale
            dayFormatter.setLocalizedDateFormatFromTemplate("EEEddMMM")
            timeFormatter = DateFormatter()
            timeFormatter.calendar = calendar
            timeFormatter.timeZone = calendar.timeZone
            timeFormatter.locale = locale
            timeFormatter.setLocalizedDateFormatFromTemplate("jjmm")
        }

        func day(_ date: Date) -> String { dayFormatter.string(from: date).uppercased(with: locale) }
        func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    }

    // MARK: Countdown and track

    /// `IN 42 MIN` under an hour, `IN 2 H 05` from an hour, `NOW` from the start until the end. Minutes round up,
    /// so the countdown reads `IN 1 MIN` until the start.
    public static func countdown(start: Date, now: Date) -> String {
        let minutes = minutesUntil(start, now: now)
        guard minutes > 0 else { return CalendarText.string("calendar.upcoming.now") }
        if minutes < 60 { return CalendarText.format("calendar.upcoming.in.minutes", minutes) }
        return CalendarText.format("calendar.upcoming.in.hours", minutes / 60, minutes % 60)
    }

    /// A row's relative time: the countdown today, `IN 3 D` on a later day, nothing on a past day.
    public static func relative(_ row: UpcomingRow, now: Date) -> String {
        if row.dayOffset == 0 { return countdown(start: row.start, now: now) }
        return row.dayOffset > 0 ? CalendarText.format("calendar.upcoming.in.days", row.dayOffset) : ""
    }

    /// The same, spoken: "in 42 minutes", "in 2 hours 5 minutes", "now", "in 3 days".
    public static func spokenRelative(_ row: UpcomingRow, now: Date) -> String {
        if row.dayOffset > 0 { return CalendarText.format("calendar.upcoming.a11y.in.days", row.dayOffset) }
        if row.dayOffset < 0 { return "" }
        let minutes = minutesUntil(row.start, now: now)
        guard minutes > 0 else { return CalendarText.string("calendar.upcoming.a11y.now") }
        let hours = minutes / 60
        let rest = minutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append(CalendarText.format("calendar.upcoming.a11y.hours", hours)) }
        if rest > 0 || hours == 0 { parts.append(CalendarText.format("calendar.upcoming.a11y.minutes", rest)) }
        return CalendarText.format("calendar.upcoming.a11y.in", parts.joined(separator: " "))
    }

    static func minutesUntil(_ start: Date, now: Date) -> Int {
        let seconds = start.timeIntervalSince(now)
        return seconds <= 0 ? 0 : Int((seconds / 60).rounded(.up))
    }

    /// Where the hero's track starts: the end of the latest timed event that ends by the hero's start, or
    /// ``trackLead`` (2 h) before the start, whichever is later. The now marker then moves from the left end
    /// (the previous event just ended, or two hours to go) to the right end (the event starts).
    public static func trackWindowStart(for event: CalendarEvent, events: [CalendarEvent]) -> Date {
        let lead = event.start.addingTimeInterval(-trackLead)
        let previous = events.filter { !$0.isAllDay && $0.id != event.id && $0.end <= event.start }.map(\.end).max()
        return max(lead, previous ?? lead)
    }

    /// The now marker's position on the track, 0 (window start) → 1 (event start), clamped; 1 once running.
    public static func trackFraction(now: Date, windowStart: Date, start: Date) -> Double {
        let span = start.timeIntervalSince(windowStart)
        guard span > 0 else { return now >= start ? 1 : 0 }
        return min(1, max(0, now.timeIntervalSince(windowStart) / span))
    }

    // MARK: Accessibility

    /// "10:30 to 11:00, Design review, Work calendar, in 42 minutes, Join call available".
    public static func accessibilityLabel(_ row: UpcomingRow, now: Date) -> String {
        var parts = [CalendarText.format("calendar.upcoming.a11y.range", row.startText, row.endText), row.title]
        if !row.calendarName.isEmpty {
            parts.append(CalendarText.format("calendar.upcoming.a11y.calendar", row.calendarName))
        }
        let relative = spokenRelative(row, now: now)
        if !relative.isEmpty { parts.append(relative) }
        if row.canJoin { parts.append(CalendarText.string("calendar.upcoming.a11y.join")) }
        return parts.joined(separator: CalendarText.string("calendar.grid.cell.separator"))
    }

    /// "v0.3 release week, Work calendar, all day".
    public static func accessibilityLabel(_ chip: UpcomingChip) -> String {
        var parts = [chip.title]
        if !chip.calendarName.isEmpty {
            parts.append(CalendarText.format("calendar.upcoming.a11y.calendar", chip.calendarName))
        }
        parts.append(CalendarText.string("calendar.upcoming.a11y.allDay"))
        return parts.joined(separator: CalendarText.string("calendar.grid.cell.separator"))
    }

    // MARK: Keyboard

    /// What a key does in the list: ↑↓ move the selection through ``rows`` (from nothing, ↓ picks the first
    /// row and ↑ the last); ↵ joins the selected row's call, or the hero's when nothing is selected.
    public enum KeyAction: Hashable, Sendable {
        case select(String)
        case join(id: String, url: URL)
        case ignored
    }

    public enum Key: Sendable {
        case up
        case down
        case enter
    }

    public func keyAction(_ key: Key, selected: String?) -> KeyAction {
        let rows = rows
        let index = selected.flatMap { id in rows.firstIndex { $0.id == id } }
        switch key {
        case .up, .down:
            guard !rows.isEmpty else { return .ignored }
            let next: Int
            if let index {
                next = min(rows.count - 1, max(0, index + (key == .up ? -1 : 1)))
            } else {
                next = key == .up ? rows.count - 1 : 0
            }
            return .select(rows[next].id)
        case .enter:
            let row = index.map { rows[$0] } ?? hero?.row
            guard let row, let url = row.videoLink else { return .ignored }
            return .join(id: row.id, url: url)
        }
    }
}
