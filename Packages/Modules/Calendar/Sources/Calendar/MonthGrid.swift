import Foundation

/// One calendar dot under a day number: a calendar with at least one event that day, in its EventKit color.
public struct MonthGridDot: Hashable, Sendable, Identifiable {
    public let calendarID: String
    public let color: CalendarColor
    public var id: String { calendarID }

    public init(calendarID: String, color: CalendarColor) {
        self.calendarID = calendarID
        self.color = color
    }
}

/// One day cell of the month grid.
public struct MonthGridDay: Hashable, Sendable, Identifiable {
    /// The start of the day.
    public let date: Date
    /// The day of the month (`1`…`31`).
    public let day: Int
    /// False for the leading and trailing days of the adjacent months (drawn dimmed).
    public let isCurrentMonth: Bool
    public let isToday: Bool
    public let isSelected: Bool
    /// The calendars with events that day, ordered by calendar title, at most `maxDots`.
    public let dots: [MonthGridDot]
    /// How many calendars have events that day, before the cap (for the accessibility label).
    public let calendarCount: Int
    public var id: Date { date }
}

/// One row of the grid: its ISO 8601 week number and seven days, Monday first.
public struct MonthGridWeek: Hashable, Sendable, Identifiable {
    public let weekNumber: Int
    public let days: [MonthGridDay]
    public var id: Date { days.first?.date ?? .distantPast }
}

/// The Calendar tab's month grid (Story 13.2, DESIGN `components.month-grid`, UX-DR34): a pure model built from
/// the visible month, today, the selected day and the loaded events.
///
/// Always six rows of seven days, Monday first (ISO 8601: weeks start on Monday and week 1 holds the year's first
/// Thursday), so the card keeps one height from month to month, as in the mockup's December (Jan 4–10 shown).
/// Days of the adjacent months fill the first and last rows and carry their own dots.
public struct MonthGrid: Hashable, Sendable {
    /// Rows in every month (fixed: the card height never changes).
    public static let rowCount = 6
    /// Dots per day when the theme has no `components.month-grid.max-dots`.
    public static let defaultMaxDots = 4

    /// The first day of the visible month.
    public let month: Date
    /// `NOVEMBER 2026`: the month and year in the locale, uppercased.
    public let title: String
    /// Seven very short standalone weekday symbols in the locale, Monday first, uppercased (`M T W T F S S`).
    public let weekdaySymbols: [String]
    public let weeks: [MonthGridWeek]
    /// The column (0 = Monday) of the month's first and last days, and the row of its last day: the 1px outline
    /// that traces the month's days.
    public let firstColumn: Int
    public let lastColumn: Int
    public let lastRow: Int

    /// Every day cell, row by row.
    public var days: [MonthGridDay] { weeks.flatMap(\.days) }

    /// The grid's calendar: ISO 8601 (Monday first, ISO week numbers) in `base`'s time zone.
    public static func gridCalendar(_ base: Calendar, locale: Locale = .current) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = base.timeZone
        calendar.locale = locale
        return calendar
    }

    /// The first day of the month that holds `date`.
    public static func monthStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// From the first cell's start (the Monday on or before the 1st) through the end of the 42nd cell: what the
    /// module loads for the grid.
    public static func interval(month: Date, calendar base: Calendar) -> DateInterval {
        let calendar = gridCalendar(base)
        let first = firstCell(month: monthStart(of: month, calendar: calendar), calendar: calendar)
        let end = calendar.date(byAdding: .day, value: rowCount * 7, to: first) ?? first
        return DateInterval(start: first, end: end)
    }

    private static func firstCell(month: Date, calendar: Calendar) -> Date {
        // Monday = 2 in Foundation's weekday numbering; the column is 0 for Monday … 6 for Sunday.
        let column = (calendar.component(.weekday, from: month) + 5) % 7
        return calendar.date(byAdding: .day, value: -column, to: month) ?? month
    }

    /// Builds the grid.
    /// - Parameters:
    ///   - month: any instant of the month to show.
    ///   - today: now; the cell of that day is outlined.
    ///   - selected: the selected day (any instant of it).
    ///   - events: the occurrences overlapping the grid's interval, already filtered by the module
    ///     (`calendars`, `hide_all_day`). All-day and timed events both count.
    ///   - calendars: the store's calendars, for the dot colors and their order (by title).
    ///   - calendar: the user's calendar (its time zone is kept; the grid itself is ISO 8601).
    ///   - locale: the header and weekday strings.
    ///   - maxDots: the most dots per day; extra calendars are dropped without an overflow mark.
    public static func build(
        month: Date, today: Date, selected: Date, events: [CalendarEvent], calendars: [CalendarInfo],
        calendar base: Calendar, locale: Locale = .current, maxDots: Int = defaultMaxDots
    ) -> MonthGrid {
        let calendar = gridCalendar(base, locale: locale)
        let monthStart = monthStart(of: month, calendar: calendar)
        let first = firstCell(month: monthStart, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        let selectedStart = calendar.startOfDay(for: selected)
        let monthIndex = calendar.component(.month, from: monthStart)
        let order = calendars.sorted { lhs, rhs in
            let byTitle = lhs.title.localizedStandardCompare(rhs.title)
            return byTitle == .orderedSame ? lhs.id < rhs.id : byTitle == .orderedAscending
        }

        var weeks: [MonthGridWeek] = []
        var firstColumn = 0
        var lastColumn = 6
        var lastRow = rowCount - 1
        var seenMonth = false
        for row in 0..<rowCount {
            var days: [MonthGridDay] = []
            for column in 0..<7 {
                let start = calendar.date(byAdding: .day, value: row * 7 + column, to: first) ?? first
                let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
                let inMonth = calendar.component(.month, from: start) == monthIndex
                if inMonth {
                    if !seenMonth {
                        firstColumn = column
                        seenMonth = true
                    }
                    lastColumn = column
                    lastRow = row
                }
                let busy = Set(events.filter { occurs($0, from: start, to: end) }.map(\.calendarID))
                let present = order.filter { busy.contains($0.id) }
                days.append(
                    MonthGridDay(
                        date: start, day: calendar.component(.day, from: start), isCurrentMonth: inMonth,
                        isToday: start == todayStart, isSelected: start == selectedStart,
                        dots: present.prefix(max(0, maxDots)).map { MonthGridDot(calendarID: $0.id, color: $0.color) },
                        calendarCount: present.count))
            }
            let week = days.first.map { calendar.component(.weekOfYear, from: $0.date) } ?? 0
            weeks.append(MonthGridWeek(weekNumber: week, days: days))
        }
        return MonthGrid(
            month: monthStart, title: title(month: monthStart, calendar: calendar, locale: locale),
            weekdaySymbols: weekdaySymbols(locale: locale), weeks: weeks, firstColumn: firstColumn,
            lastColumn: lastColumn, lastRow: lastRow)
    }

    /// Whether `event` runs during the day `[start, end)`. A zero-length event counts on the day it starts.
    static func occurs(_ event: CalendarEvent, from start: Date, to end: Date) -> Bool {
        event.start < end && (event.end > start || (event.end == event.start && event.start >= start))
    }

    /// `NOVEMBER 2026` in `locale` (`NOVEMBRE 2026` in French).
    public static func title(month: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        return formatter.string(from: month).uppercased(with: locale)
    }

    /// The weekday initials, Monday first (`M T W T F S S`; `L M M J V S D` in French).
    public static func weekdaySymbols(locale: Locale) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        // Foundation lists Sunday first.
        return (symbols[1...] + symbols[..<1]).map { $0.uppercased(with: locale) }
    }

    /// `Wednesday 4 November, 2 calendars with events, today, selected` (VoiceOver label of a day cell).
    public static func accessibilityLabel(
        for day: MonthGridDay, calendar base: Calendar, locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = gridCalendar(base, locale: locale)
        formatter.timeZone = base.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(day.isCurrentMonth ? "EEEEdMMMM" : "EEEEdMMMMyyyy")
        var parts = [formatter.string(from: day.date)]
        if day.calendarCount > 0 {
            parts.append(CalendarText.format("calendar.grid.cell.calendars", day.calendarCount))
        }
        if day.isToday { parts.append(CalendarText.string("calendar.grid.cell.today")) }
        if day.isSelected { parts.append(CalendarText.string("calendar.grid.cell.selected")) }
        return parts.joined(separator: CalendarText.string("calendar.grid.cell.separator"))
    }
}
