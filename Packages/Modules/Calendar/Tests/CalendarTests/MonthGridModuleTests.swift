import Foundation
import SwiftUI
import Testing
import VigieUI

@testable import Calendar

/// The module's month grid state (Story 13.2): visible month, selection, the header dot, the per-month events.
@MainActor @Suite struct MonthGridModuleTests {
    static func day(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        Fixture.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func gridLoadsTheWholeVisibleMonth() async throws {
        let h = Harness(access: .granted)
        try await h.start()
        #expect(h.module.visibleMonth == Self.day(11, 1))
        #expect(h.module.selectedDay == Self.day(11, 6))
        #expect(!h.module.canReturnToToday)
        #expect(await eventually { h.module.gridInterval != nil })
        #expect(h.module.gridInterval == DateInterval(start: Self.day(10, 26), end: Self.day(12, 7)))
        // The grid sees the whole month; the 13.1 window keeps today → +14 days.
        #expect(h.module.gridEvents.map(\.eventID) == ["yesterday", "holiday", "standup", "dinner", "review", "later"])
        #expect(h.module.events.map(\.eventID) == ["holiday", "standup", "dinner", "review"])
        let grid = h.module.monthGrid(locale: Locale(identifier: "en_GB"))
        #expect(grid.title == "NOVEMBER 2026")
        let today = try #require(grid.days.first { $0.isToday })
        #expect(today.day == 6 && today.isSelected)
        #expect(today.dots.map(\.calendarID) == ["personal", "work"])  // by title: Personal, Work
        #expect(grid.days.first { $0.day == 25 && $0.isCurrentMonth }?.dots.map(\.calendarID) == ["work"])
        #expect(h.module.gridLegend.map(\.id) == ["family", "personal", "work"])
        await h.module.stop()
    }

    @Test func arrowsChangeOnlyTheMonthAndTheDotReturnsToToday() async throws {
        let h = Harness(access: .granted)
        try await h.start()
        #expect(await eventually { h.module.gridInterval != nil })
        h.module.showNextMonth()
        #expect(h.module.visibleMonth == Self.day(12, 1))
        #expect(h.module.selectedDay == Self.day(11, 6))  // selection unchanged
        #expect(h.module.canReturnToToday)  // header dot lit
        #expect(await eventually { h.module.gridInterval?.start == Self.day(11, 30) })
        #expect(
            h.source.eventQueries.last?.interval
                == DateInterval(start: Self.day(11, 30), end: Self.day(1, 11, year: 2027)))
        // Back to November: cached, no new query.
        let queries = h.source.eventQueries.count
        h.module.showPreviousMonth()
        #expect(await eventually { h.module.gridInterval?.start == Self.day(10, 26) })
        #expect(h.source.eventQueries.count == queries)
        #expect(!h.module.canReturnToToday)
        h.module.showPreviousMonth()
        h.module.showPreviousMonth()
        #expect(h.module.visibleMonth == Self.day(9, 1))
        h.module.returnToToday()
        #expect(h.module.visibleMonth == Self.day(11, 1))
        #expect(!h.module.canReturnToToday)
        #expect(await eventually { h.module.gridInterval?.start == Self.day(10, 26) })
        await h.module.stop()
    }

    @Test func selectingADay() async throws {
        let h = Harness(access: .granted)
        try await h.start()
        h.module.select(Self.day(11, 12).addingTimeInterval(3600 * 9))
        #expect(h.module.selectedDay == Self.day(11, 12))
        #expect(h.module.visibleMonth == Self.day(11, 1))
        #expect(h.module.canReturnToToday)
        let grid = h.module.monthGrid()
        #expect(grid.days.filter(\.isSelected).map(\.day) == [12])
        #expect(grid.days.filter(\.isToday).map(\.day) == [6])  // today keeps its outline
        // Arrow keys: a week down, a day left.
        h.module.moveSelection(byDays: 7)
        h.module.moveSelection(byDays: -1)
        #expect(h.module.selectedDay == Self.day(11, 18))
        // An adjacent-month day moves the grid to its month.
        h.module.select(Self.day(12, 2))
        #expect(h.module.visibleMonth == Self.day(12, 1))
        #expect(await eventually { h.module.gridInterval?.start == Self.day(11, 30) })
        h.module.returnToToday()
        #expect(h.module.selectedDay == Self.day(11, 6))
        #expect(h.module.visibleMonth == Self.day(11, 1))
        // Clicking today is the same as no selection.
        h.module.select(Self.day(11, 6))
        #expect(!h.module.canReturnToToday)
        await h.module.stop()
    }

    @Test func storeChangeReloadsTheGridMonthAndEmptiesTheCache() async throws {
        let h = Harness(access: .granted)
        try await h.start()
        #expect(await eventually { h.source.subscribers == 1 && h.module.gridInterval != nil })
        h.module.showNextMonth()
        #expect(await eventually { h.module.gridInterval?.start == Self.day(11, 30) })
        let added = Sample.event("added", calendar: "family", day: 40, hour: 10)  // 10 Dec
        h.source.setEvents(Sample.events + [added])
        h.source.sendChange()
        #expect(await eventually { h.module.gridEvents.contains { $0.eventID == "added" } })
        let queries = h.source.eventQueries.count
        h.module.showPreviousMonth()  // November was cached before the change: loaded again
        #expect(await eventually { h.source.eventQueries.count == queries + 1 })
        await h.module.stop()
    }

    @Test func hiddenAllDayEventsLeaveNoDot() async throws {
        let h = Harness(settings: ["hide_all_day": true], access: .granted)
        try await h.start()
        #expect(await eventually { h.module.gridInterval != nil })
        #expect(!h.module.gridEvents.contains { $0.isAllDay })
        let today = try #require(h.module.monthGrid().days.first { $0.isToday })
        #expect(today.dots.map(\.calendarID) == ["work"])
        await h.module.stop()
    }

    @Test func noEventsTodayLeavesTodayWithoutADot() async throws {
        let source = FakeCalendarSource(events: [Sample.dinner, Sample.review])
        let h = Harness(access: .granted, source: source)
        try await h.start()
        #expect(await eventually { h.module.gridInterval != nil })
        #expect(h.module.tabContent == .grid(todayCount: 0))
        let today = try #require(h.module.monthGrid().days.first { $0.isToday })
        #expect(today.dots.isEmpty)
        #expect(h.module.monthGrid().days.first { $0.day == 7 && $0.isCurrentMonth }?.dots.count == 1)
        await h.module.stop()
    }

    @Test func accessLostClearsTheGrid() async throws {
        let h = Harness(access: .granted)
        try await h.start()
        #expect(await eventually { h.module.gridInterval != nil })
        h.context.fakePermissions.set(.denied)
        await h.module.recheckAccess()
        #expect(h.module.gridEvents.isEmpty)
        #expect(h.module.gridInterval == nil)
        #expect(h.module.tabContent == .setup)
        await h.module.stop()
    }

    // MARK: View

    @Test(arguments: [false, true])
    func tabRendersInBothPrivacyStates(privacy: Bool) async throws {
        let h = Harness(access: .granted)
        try await h.start()
        #expect(await eventually { h.module.gridInterval != nil })
        let library = try ThemeLoader.loadBundled()
        for variant in ["chrome-hologram", "twin-metal-tactical"] {
            for look in [Look.dark, .light] {
                let theme = library.resolve(themeID: variant, look: look).theme
                let view = CalendarTabView(module: h.module)
                    .frame(width: 760, height: 340)
                    .vigieTheme(theme)
                    .privacyActive(privacy)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                let renderer = ImageRenderer(content: view)
                #expect(renderer.cgImage != nil, "\(variant) \(look)")
            }
        }
        await h.module.stop()
    }

    @Test func cardIsTheThemeWidth() throws {
        let theme = try ThemeLoader.loadBundled().resolve(themeID: "chrome-hologram", look: .dark).theme
        let grid = MonthGridTests.build(2026, 11)
        let card = MonthGridCard(
            grid: grid, canReturnToToday: true, legend: Sample.calendars, calendar: Fixture.calendar,
            locale: Locale(identifier: "en_GB"),
            actions: MonthGridActions(previous: {}, next: {}, today: {}, select: { _ in }, move: { _ in })
        )
        .fixedSize()
        .vigieTheme(theme)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 300)
        // Header, weekday row and six 37px rows fit the expanded panel's tab area.
        #expect(image.height > 16 + 6 * 37)
        #expect(image.height < 340)
    }
}
