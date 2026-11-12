import Foundation
import Testing

@testable import Calendar

/// The pure upcoming list (Story 13.3): sections, headers, chips, the 5-row cap, the hero, countdowns and the track.
/// Reference instant: Wed 04 Nov 2026 14:48 UTC (the mockup's).
@Suite struct UpcomingListTests {
    static let gb = Locale(identifier: "en_GB")
    static let fr = Locale(identifier: "fr_FR")
    static let meet = URL(string: "https://meet.google.com/abc-defg-hij")!
    static let zoom = URL(string: "https://acme.zoom.us/j/123456789")!

    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Fixture.calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    static let now = at(4, 14, 48)

    static func timed(
        _ id: String, _ day: Int, _ hour: Int, _ minute: Int = 0, minutes: Int = 30, calendar: String = "work",
        link: URL? = nil
    ) -> CalendarEvent {
        let start = at(day, hour, minute)
        return CalendarEvent(
            id: id, eventID: id, calendarID: calendar, title: id, start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)), videoLink: link)
    }

    static func allDay(_ id: String, from day: Int, days: Int = 1, calendar: String = "work") -> CalendarEvent {
        CalendarEvent(
            id: id, eventID: id, calendarID: calendar, title: id, start: at(day, 0), end: at(day + days, 0),
            isAllDay: true)
    }

    /// The mockup's week: an ended standup, the 15:30 review with a Meet link (hero), two more today, two
    /// tomorrow, then Fri, Sat (this ISO week) and Mon (next week).
    static let week: [CalendarEvent] = [
        allDay("release", from: 2, days: 6),
        timed("ended", 4, 9, 30),
        timed("review", 4, 15, 30, minutes: 45, link: meet),
        timed("dentist", 4, 17, calendar: "personal"),
        timed("climbing", 4, 18, 30, minutes: 90, calendar: "personal"),
        timed("standup", 5, 9, 30, minutes: 15, link: zoom),
        timed("vendor", 5, 14),
        timed("retro", 6, 16),
        timed("saturday", 7, 11, calendar: "personal"),
        timed("monday", 9, 10),
    ]

    static func build(
        _ events: [CalendarEvent] = week, selected: Date = now, now: Date = now, locale: Locale = gb
    ) -> UpcomingList {
        UpcomingList.build(
            events: events, calendars: Sample.calendars, selectedDay: selected, now: now,
            calendar: Fixture.calendar, locale: locale)
    }

    // MARK: Sections

    @Test func sectionsHeadersChipsAndCapInEnglish() throws {
        let list = Self.build()
        #expect(list.startsToday)
        #expect(list.sections.map(\.header) == ["TODAY · WED 04 NOV", "THU 05 NOV · TOMORROW"])
        // The week-long all-day event is a chip on the first listed day only, and is not a row.
        #expect(list.sections[0].chips.map(\.id) == ["release"])
        #expect(list.sections[1].chips.isEmpty)
        // The ended standup is dropped; five rows, then +2 this week (Fri, Sat; Monday is next week).
        #expect(list.rows.map(\.id) == ["review", "dentist", "climbing", "standup", "vendor"])
        #expect(list.overflow == 2)
        #expect(list.overflowText == "+2 LATER THIS WEEK")
        let review = list.rows[0]
        #expect(review.startText == "15:30" && review.endText == "16:15")
        #expect(review.calendarName == "Work" && review.color == Sample.work.color)
        #expect(review.service == .meet && review.canJoin)
        #expect(list.rows[1].calendarName == "Personal" && !list.rows[1].canJoin)
        #expect(list.rows[3].service == .zoom)
    }

    @Test func headersInFrench() {
        let list = Self.build(locale: Self.fr)
        let expected = [
            CalendarText.format("calendar.upcoming.header.today", "MER. 04 NOV."),
            CalendarText.format("calendar.upcoming.header.tomorrow", "JEU. 05 NOV."),
        ]
        #expect(list.sections.map(\.header) == expected)
        #expect(list.rows[0].startText == "15:30")
        #expect(UpcomingList.dayText(Self.at(6, 0), calendar: Fixture.calendar, locale: Self.fr) == "VEN. 06 NOV.")
    }

    @Test func laterDaysHaveAPlainHeader() {
        let list = Self.build([Self.timed("a", 4, 16), Self.timed("b", 6, 9)])
        #expect(list.sections.map(\.header) == ["TODAY · WED 04 NOV", "FRI 06 NOV"])
        #expect(list.overflow == 0 && list.overflowText == nil)
    }

    @Test func allDayEventsAreNotCounted() {
        var events = Self.week
        events += [Self.allDay("holiday", from: 4), Self.allDay("trip", from: 5), Self.allDay("conf", from: 4)]
        let list = Self.build(events)
        #expect(list.rows.count == 5)
        #expect(list.sections[0].chips.map(\.id) == ["release", "conf", "holiday"])
        #expect(list.sections[1].chips.map(\.id) == ["trip"])
        #expect(list.overflow == 2)
    }

    @Test func overflowCountsOnlyTheRestOfTheISOWeek() {
        // Sunday 8 Nov is the last day of ISO week 45: Monday's events are not "this week".
        let sunday = (0..<7).map { Self.timed("s\($0)", 8, 9 + $0) }
        let monday = [Self.timed("m1", 9, 9), Self.timed("m2", 9, 10)]
        let list = Self.build(sunday + monday, selected: Self.at(8, 0), now: Self.at(8, 8))
        #expect(list.rows.count == 5)
        #expect(list.overflow == 2)
        #expect(list.overflowText == "+2 LATER THIS WEEK")
    }

    @Test func endedEventsTodayAreDroppedButRunningStays() {
        let running = Self.timed("running", 4, 14, 30, minutes: 60)
        let list = Self.build([Self.timed("ended", 4, 9), running, Self.timed("next", 4, 16)])
        #expect(list.rows.map(\.id) == ["running", "next"])
        #expect(list.hero?.row.id == "running")
        #expect(UpcomingList.countdown(start: running.start, now: Self.now) == "NOW")
    }

    @Test func noEventsTodayThenTheFollowingDays() {
        let list = Self.build([Self.timed("ended", 4, 9), Self.timed("tomorrow", 5, 9)])
        #expect(list.sections.count == 2)
        #expect(list.sections[0].isToday && list.sections[0].isEmpty)
        #expect(list.sections[0].header == "TODAY · WED 04 NOV")
        #expect(list.sections[1].rows.map(\.id) == ["tomorrow"])
        // Tomorrow's first event is not a hero: the hero is today's next event only.
        #expect(list.hero == nil)
        #expect(!list.rows.contains { $0.isHero })
    }

    @Test func anAllDayEventAloneIsNotEmpty() {
        let list = Self.build([Self.allDay("holiday", from: 4)])
        #expect(list.sections.count == 1)
        #expect(!list.sections[0].isEmpty)
        #expect(list.hero == nil)
    }

    // MARK: Hero

    @Test func heroIsTodaysNextEvent() throws {
        let list = Self.build()
        let hero = try #require(list.hero)
        #expect(hero.row.id == "review" && hero.row.isHero)
        #expect(list.rows.filter(\.isHero).count == 1)
        // The ended standup (10:00) is before the 2 h lead (13:30): the track starts at 13:30.
        #expect(hero.windowStart == Self.at(4, 13, 30))
        #expect(UpcomingList.countdown(start: hero.row.start, now: Self.now) == "IN 42 MIN")
    }

    @Test func futureSelectedDayHasNoHeroAndNoCountdown() throws {
        let list = Self.build(selected: Self.at(5, 0))
        #expect(!list.startsToday)
        #expect(list.hero == nil)
        #expect(list.sections.first?.header == "THU 05 NOV · TOMORROW")
        // From the day's start: the whole day, then Fri and Sat; the week is not over so nothing overflows.
        #expect(list.rows.map(\.id) == ["standup", "vendor", "retro", "saturday", "monday"])
        let first = try #require(list.rows.first)
        #expect(UpcomingList.relative(first, now: Self.now) == "IN 1 D")
        #expect(CalendarModule.upcomingMeta(list, calendar: Fixture.calendar, locale: Self.gb) == "FROM THU 05 NOV")
        #expect(CalendarModule.upcomingMeta(Self.build(), calendar: Fixture.calendar, locale: Self.gb) == "FROM TODAY")
    }

    // MARK: Countdown and track

    @Test func countdownStrings() {
        let start = Self.at(4, 16)
        #expect(UpcomingList.countdown(start: start, now: start.addingTimeInterval(-42 * 60)) == "IN 42 MIN")
        #expect(UpcomingList.countdown(start: start, now: start.addingTimeInterval(-125 * 60)) == "IN 2 H 05")
        #expect(UpcomingList.countdown(start: start, now: start.addingTimeInterval(-60 * 60)) == "IN 1 H 00")
        #expect(UpcomingList.countdown(start: start, now: start.addingTimeInterval(-30)) == "IN 1 MIN")
        #expect(UpcomingList.countdown(start: start, now: start) == "NOW")
        #expect(UpcomingList.countdown(start: start, now: start.addingTimeInterval(600)) == "NOW")
    }

    @Test func trackFraction() {
        let start = Self.at(4, 16)
        let window = Self.at(4, 14)
        #expect(UpcomingList.trackFraction(now: window, windowStart: window, start: start) == 0)
        #expect(UpcomingList.trackFraction(now: Self.at(4, 15), windowStart: window, start: start) == 0.5)
        #expect(UpcomingList.trackFraction(now: start, windowStart: window, start: start) == 1)
        #expect(UpcomingList.trackFraction(now: Self.at(4, 16, 10), windowStart: window, start: start) == 1)
        #expect(UpcomingList.trackFraction(now: Self.at(4, 12), windowStart: window, start: start) == 0)
    }

    @Test func trackWindowStartsAtThePreviousEndOrTwoHoursBefore() {
        let event = Self.timed("e", 4, 16)
        // No previous event: two hours before.
        #expect(UpcomingList.trackWindowStart(for: event, events: [event]) == Self.at(4, 14))
        // A previous event ending at 15:00 (later than 14:00) starts the track.
        let previous = Self.timed("p", 4, 14, 30)
        #expect(UpcomingList.trackWindowStart(for: event, events: [previous, event]) == Self.at(4, 15))
        // All-day events and events ending after the start do not count.
        let overlapping = Self.timed("o", 4, 15, 45, minutes: 60)
        #expect(
            UpcomingList.trackWindowStart(for: event, events: [Self.allDay("a", from: 4), overlapping, event])
                == Self.at(4, 14))
    }

    // MARK: Accessibility and keyboard

    @Test func accessibilityLabels() throws {
        let event = Self.timed("Design review", 4, 10, 30, link: Self.meet)
        let list = Self.build([event], now: Self.at(4, 9, 48))
        let row = try #require(list.rows.first)
        #expect(
            UpcomingList.accessibilityLabel(row, now: Self.at(4, 9, 48))
                == "10:30 to 11:00, Design review, Work calendar, in 42 minutes, Join call available")
        #expect(UpcomingList.spokenRelative(row, now: Self.at(4, 8, 25)) == "in 2 hours 5 minutes")
        #expect(UpcomingList.spokenRelative(row, now: Self.at(4, 9, 30)) == "in 1 hour")
        #expect(UpcomingList.spokenRelative(row, now: Self.at(4, 10, 40)) == "now")
        let chip = UpcomingChip(id: "c", title: "v0.3 release week", calendarName: "Work", color: nil)
        #expect(UpcomingList.accessibilityLabel(chip) == "v0.3 release week, Work calendar, all day")
    }

    @Test func keyboardMovesThroughTheRowsAndEnterJoins() {
        let list = Self.build()
        let ids = list.rows.map(\.id)
        #expect(list.keyAction(.down, selected: nil) == .select(ids[0]))
        #expect(list.keyAction(.up, selected: nil) == .select(ids[4]))
        #expect(list.keyAction(.down, selected: ids[0]) == .select(ids[1]))
        #expect(list.keyAction(.down, selected: ids[4]) == .select(ids[4]))
        #expect(list.keyAction(.up, selected: ids[0]) == .select(ids[0]))
        // ↵: the selected row's link, the hero's when nothing is selected; nothing on a row without a link.
        #expect(list.keyAction(.enter, selected: nil) == .join(id: "review", url: Self.meet))
        #expect(list.keyAction(.enter, selected: "standup") == .join(id: "standup", url: Self.zoom))
        #expect(list.keyAction(.enter, selected: "dentist") == .ignored)
        #expect(Self.build([]).keyAction(.down, selected: nil) == .ignored)
    }
}
