import Foundation
import SwiftUI
import Testing
import VigieUI

@testable import Calendar

/// The pure month model (Story 13.2): rows, ISO weeks, flags, dots, strings.
@Suite struct MonthGridTests {
    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Fixture.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func build(
        _ year: Int, _ month: Int, today: Date? = nil, selected: Date? = nil, events: [CalendarEvent] = [],
        calendars: [CalendarInfo] = Sample.calendars, locale: Locale = Locale(identifier: "en_GB"), maxDots: Int = 4
    ) -> MonthGrid {
        let today = today ?? date(2026, 11, 4, hour: 14)
        return MonthGrid.build(
            month: date(year, month, 15), today: today, selected: selected ?? today, events: events,
            calendars: calendars, calendar: Fixture.calendar, locale: locale, maxDots: maxDots)
    }

    static func event(
        _ id: String, calendar: String, start: Date, hours: Double = 1, allDay: Bool = false
    ) -> CalendarEvent {
        let end = allDay ? start.addingTimeInterval(86_400) : start.addingTimeInterval(hours * 3600)
        return CalendarEvent(
            id: id, eventID: id, calendarID: calendar, title: id, start: start, end: end, isAllDay: allDay)
    }

    // MARK: Rows and cells

    @Test func monthStartingMondayHasNoLeadingDays() {
        let grid = Self.build(2026, 6)
        #expect(grid.weeks.count == 6)
        #expect(grid.weeks.allSatisfy { $0.days.count == 7 })
        #expect(grid.days.first?.date == Self.date(2026, 6, 1, hour: 0))
        #expect(grid.days.first?.isCurrentMonth == true)
        #expect(grid.days.last?.date == Self.date(2026, 7, 12, hour: 0))
        #expect(grid.days.filter(\.isCurrentMonth).count == 30)
        #expect(grid.weeks.map(\.weekNumber) == [23, 24, 25, 26, 27, 28])
        #expect(grid.firstColumn == 0)
        #expect(grid.lastColumn == 1)  // Tue 30 June
        #expect(grid.lastRow == 4)
    }

    @Test func monthStartingSundayShowsSixAdjacentDays() {
        let grid = Self.build(2026, 11)
        #expect(grid.days.first?.date == Self.date(2026, 10, 26, hour: 0))
        #expect(grid.days.prefix(6).allSatisfy { !$0.isCurrentMonth })  // Oct 26–31 dimmed
        #expect(grid.days[6].day == 1 && grid.days[6].isCurrentMonth)
        #expect(grid.days.suffix(6).allSatisfy { !$0.isCurrentMonth })  // Dec 1–6 dimmed
        #expect(grid.days.suffix(6).map(\.day) == [1, 2, 3, 4, 5, 6])
        #expect(grid.weeks.map(\.weekNumber) == [44, 45, 46, 47, 48, 49])
        #expect(grid.firstColumn == 6)
        #expect(grid.lastColumn == 0)
        #expect(grid.lastRow == 5)
        #expect(
            MonthGrid.interval(month: Self.date(2026, 11, 20), calendar: Fixture.calendar)
                == DateInterval(start: Self.date(2026, 10, 26, hour: 0), end: Self.date(2026, 12, 7, hour: 0)))
    }

    @Test func februaryOfALeapYear() {
        let grid = Self.build(2028, 2)
        #expect(grid.days.filter(\.isCurrentMonth).count == 29)
        #expect(grid.days.first?.date == Self.date(2028, 1, 31, hour: 0))
        #expect(grid.weeks.count == 6)  // fixed: the card height never changes
        #expect(grid.weeks.map(\.weekNumber) == [5, 6, 7, 8, 9, 10])
        #expect(grid.lastRow == 4 && grid.lastColumn == 1)  // Tue 29 Feb
    }

    @Test func isoWeekNumbersAcrossTheYearBoundary() {
        #expect(Self.build(2026, 12).weeks.map(\.weekNumber) == [49, 50, 51, 52, 53, 1])
        let january = Self.build(2027, 1)
        #expect(january.weeks.map(\.weekNumber) == [53, 1, 2, 3, 4, 5])
        #expect(january.days.first?.date == Self.date(2026, 12, 28, hour: 0))
    }

    // MARK: Flags

    @Test func todayAndSelectedFlags() {
        let today = Self.date(2026, 11, 4, hour: 14)
        let grid = Self.build(2026, 11, today: today, selected: Self.date(2026, 11, 12, hour: 9))
        #expect(grid.days.filter(\.isToday).map(\.day) == [4])
        #expect(grid.days.filter(\.isSelected).map(\.day) == [12])
        let same = Self.build(2026, 11, today: today)
        #expect(same.days.filter { $0.isToday && $0.isSelected }.map(\.day) == [4])
        // Another month: today is not in view.
        #expect(Self.build(2027, 3, today: today).days.allSatisfy { !$0.isToday && !$0.isSelected })
    }

    // MARK: Dots

    @Test func oneDotPerCalendarOrderedByTitle() throws {
        let day = Self.date(2026, 11, 12, hour: 9)
        let events = [
            Self.event("a", calendar: "work", start: day),
            Self.event("b", calendar: "work", start: day.addingTimeInterval(7200)),
            Self.event("c", calendar: "personal", start: day),
            Self.event("d", calendar: "family", start: day),
        ]
        let grid = Self.build(2026, 11, events: events)
        let cell = try #require(grid.days.first { $0.day == 12 && $0.isCurrentMonth })
        // Family, Personal, Work: by title, not by store order, one dot each however many events.
        #expect(cell.dots.map(\.calendarID) == ["family", "personal", "work"])
        #expect(cell.dots.first?.color == Sample.family.color)
        #expect(cell.calendarCount == 3)
        #expect(grid.days.filter { !$0.dots.isEmpty }.count == 1)
    }

    @Test func dotsAreCappedWithoutOverflow() throws {
        let day = Self.date(2026, 11, 12, hour: 9)
        let calendars = (1...6).map {
            CalendarInfo(
                id: "c\($0)", title: "Cal \($0)", color: CalendarColor(sRGBRed: 0.1, green: 0.2, blue: 0.3),
                account: "iCloud")
        }
        let events = calendars.map { Self.event($0.id, calendar: $0.id, start: day) }
        let grid = Self.build(2026, 11, events: events, calendars: calendars, maxDots: 4)
        let cell = try #require(grid.days.first { $0.day == 12 && $0.isCurrentMonth })
        #expect(cell.dots.map(\.calendarID) == ["c1", "c2", "c3", "c4"])
        #expect(cell.calendarCount == 6)
    }

    @Test func allDayAndMultiDayEventsCountOnEachDayTheyCover() {
        let allDay = Self.event("holiday", calendar: "personal", start: Self.date(2026, 11, 5, hour: 0), allDay: true)
        let trip = Self.event("trip", calendar: "work", start: Self.date(2026, 11, 9, hour: 18), hours: 40)
        let instant = Self.event("deadline", calendar: "family", start: Self.date(2026, 11, 20, hour: 0), hours: 0)
        let grid = Self.build(2026, 11, events: [allDay, trip, instant])
        let busy = grid.days.filter { !$0.dots.isEmpty && $0.isCurrentMonth }.map(\.day)
        // The all-day event ends at the next midnight: 5 only. The trip runs 9 18:00 → 11 10:00.
        #expect(busy == [5, 9, 10, 11, 20])
    }

    @Test func adjacentMonthDaysCarryTheirDots() throws {
        let events = [Self.event("x", calendar: "work", start: Self.date(2026, 10, 30, hour: 10))]
        let grid = Self.build(2026, 11, events: events)
        let cell = try #require(grid.days.first { $0.date == Self.date(2026, 10, 30, hour: 0) })
        #expect(!cell.isCurrentMonth)
        #expect(cell.dots.map(\.calendarID) == ["work"])
    }

    @Test func noEventsTodayMeansNoDotOnToday() throws {
        let events = [Self.event("x", calendar: "work", start: Self.date(2026, 11, 5, hour: 10))]
        let grid = Self.build(2026, 11, events: events)
        let today = try #require(grid.days.first { $0.isToday })
        #expect(today.dots.isEmpty)
    }

    // MARK: Strings

    @Test func headerAndWeekdaysInEnglish() {
        let grid = Self.build(2026, 11, locale: Locale(identifier: "en_GB"))
        #expect(grid.title == "NOVEMBER 2026")
        #expect(grid.weekdaySymbols == ["M", "T", "W", "T", "F", "S", "S"])
    }

    @Test func headerAndWeekdaysInFrench() {
        let grid = Self.build(2026, 11, locale: Locale(identifier: "fr_FR"))
        #expect(grid.title == "NOVEMBRE 2026")
        #expect(grid.weekdaySymbols == ["L", "M", "M", "J", "V", "S", "D"])
    }

    @Test func cellAccessibilityLabel() throws {
        let day = Self.date(2026, 11, 4, hour: 9)
        let events = [
            Self.event("a", calendar: "work", start: day), Self.event("b", calendar: "personal", start: day),
        ]
        let grid = Self.build(2026, 11, events: events)
        let today = try #require(grid.days.first { $0.isToday })
        #expect(
            MonthGrid.accessibilityLabel(for: today, calendar: Fixture.calendar, locale: Locale(identifier: "en_GB"))
                == "Wednesday 4 November, 2 calendars with events, today, selected")
        let plain = try #require(grid.days.first { $0.day == 3 && $0.isCurrentMonth })
        #expect(
            MonthGrid.accessibilityLabel(for: plain, calendar: Fixture.calendar, locale: Locale(identifier: "en_GB"))
                == "Tuesday 3 November")
    }

    // MARK: Metrics

    @Test func metricsComeFromTheTheme() throws {
        let library = try ThemeLoader.loadBundled()
        let hologram = library.resolve(themeID: "chrome-hologram", look: .dark).theme
        let metrics = MonthGridMetrics(theme: hologram)
        #expect(metrics.cardWidth == 300)
        #expect(metrics.weekColumn == 22)
        #expect(metrics.cellWidth == 36)
        #expect(metrics.cellHeight == 37)
        #expect(metrics.todayRadius == 8)
        #expect(metrics.maxDots == 4)
        #expect(metrics.dotSize == 4)
        #expect(metrics.weekColumn + 7 * metrics.cellWidth + 2 * hologram.spacing(.cardPaddingX) <= metrics.cardWidth)
        let tactical = library.resolve(themeID: "twin-metal-tactical", look: .dark).theme
        #expect(MonthGridMetrics(theme: tactical).todayRadius == 0)  // C: square today outline
        // A theme file without the tokens keeps DESIGN's values.
        #expect(MonthGridMetrics(theme: .empty).cellHeight == 37)
        let columns = try #require(MonthGridMetrics.columns("22px repeat(7, 36px)"))
        #expect(columns.week == 22 && columns.cell == 36)
        #expect(MonthGridMetrics.columns("1fr") == nil)
    }
}
