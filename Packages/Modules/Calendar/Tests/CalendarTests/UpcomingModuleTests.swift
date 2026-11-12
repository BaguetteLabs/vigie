import Foundation
import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import Calendar

/// The module's upcoming list, Join call, `focusEvent` and the Home card (Story 13.3). Now: Fri 06 Nov 2026 14:43 UTC.
@MainActor @Suite struct UpcomingModuleTests {
    static let gb = Locale(identifier: "en_GB")
    static let meet = URL(string: "https://meet.google.com/abc-defg-hij")!

    /// Sample's events plus a 15:30 call with a Meet link today.
    static var events: [CalendarEvent] {
        let start = Sample.at(day: 6, hour: 15, minute: 30)
        let call = CalendarEvent(
            id: "call@1", eventID: "call", calendarID: "work", title: "Design review", start: start,
            end: start.addingTimeInterval(1800), videoLink: meet)
        return Sample.events + [call]
    }

    static func granted(_ events: [CalendarEvent] = events) async throws -> Harness {
        let h = Harness(access: .granted, source: FakeCalendarSource(events: events))
        try await h.start()
        #expect(await eventually { h.module.gridInterval != nil })
        return h
    }

    @Test func listStartsTodayWithTheHero() async throws {
        let h = try await Self.granted()
        let list = h.module.upcomingList(locale: Self.gb)
        #expect(list.sections.first?.header == "TODAY · FRI 06 NOV")
        #expect(list.sections.first?.chips.map(\.title) == ["holiday"])
        #expect(list.hero?.row.title == "Design review")
        // `later` (25 Nov) is outside the 14-day window but in the grid month.
        #expect(list.rows.map(\.title) == ["Design review", "standup", "dinner", "review", "later"])
        await h.module.stop()
    }

    @Test func selectedDayMovesTheListStart() async throws {
        let h = try await Self.granted()
        h.module.select(Sample.at(day: 20, hour: 0))
        var list = h.module.upcomingList(locale: Self.gb)
        #expect(!list.startsToday && list.hero == nil)
        #expect(list.sections.first?.header == "FRI 20 NOV")
        #expect(list.rows.map(\.title) == ["review", "later"])  // `later` comes from the grid's month
        // A day of another month: its events come from that month's grid load.
        h.module.select(Sample.at(day: 25, hour: 0))
        #expect(await eventually { h.module.upcomingList().rows.first?.title == "later" })
        h.module.returnToToday()
        list = h.module.upcomingList(locale: Self.gb)
        #expect(list.startsToday && list.hero != nil)
        await h.module.stop()
    }

    @Test func focusEventSelectsItsDayAndRow() async throws {
        let h = try await Self.granted()
        let dinner = Sample.dinner
        #expect(h.module.focusEvent(dinner.id))
        #expect(h.module.selectedDay == Sample.at(day: 7, hour: 0))
        #expect(h.module.selectedEventID == dinner.id)
        #expect(h.module.upcomingList().rows.first?.id == dinner.id)
        // By EventKit identifier too; unknown ids change nothing.
        #expect(h.module.focusEvent("standup"))
        #expect(h.module.selectedDay == Sample.at(day: 6, hour: 0))
        #expect(h.module.selectedEventID == Sample.standup.id)
        #expect(!h.module.focusEvent("nope"))
        #expect(h.module.selectedEventID == Sample.standup.id)
        await h.module.stop()
    }

    @Test func joinCallOpensTheLinkOnlyWhenThereIsOne() async throws {
        let h = try await Self.granted()
        #expect(!h.module.joinCall(Sample.standup.id))
        #expect(h.opened.urls.isEmpty)
        #expect(h.module.joinCall("call@1"))
        #expect(h.opened.urls == [Self.meet])
        await h.module.stop()
    }

    @Test func keysSelectInOrderAndEnterJoins() async throws {
        let h = try await Self.granted()
        let list = h.module.upcomingList()
        var visited: [String] = []
        for _ in list.rows {
            #expect(h.module.handleUpcomingKey(.down, list: list))
            visited.append(h.module.selectedEventID ?? "")
        }
        #expect(visited == list.rows.map(\.id))
        // On `later` (no link) ↵ does nothing; back up to the hero and ↵ joins.
        #expect(!h.module.handleUpcomingKey(.enter, list: list))
        #expect(h.opened.urls.isEmpty)
        for _ in list.rows { h.module.handleUpcomingKey(.up, list: list) }
        #expect(h.module.selectedEventID == "call@1")
        #expect(h.module.handleUpcomingKey(.enter, list: list))
        #expect(h.opened.urls == [Self.meet])
        await h.module.stop()
    }

    // MARK: Home card

    @Test func homeCardStates() async throws {
        let missing = Harness(access: .denied, answer: .denied)
        try await missing.start()
        #expect(missing.module.homeCardContent() == .setup)
        #expect(missing.module.homeCard() != nil)
        await missing.module.stop()

        let h = try await Self.granted()
        guard case .next(let hero) = h.module.homeCardContent(locale: Self.gb) else {
            Issue.record("expected the next event")
            return
        }
        #expect(hero.row.title == "Design review" && hero.row.canJoin)
        #expect(UpcomingList.countdown(start: hero.row.start, now: Fixture.start) == "IN 47 MIN")
        // Another selected day does not change the Home card.
        h.module.select(Sample.at(day: 20, hour: 0))
        #expect(h.module.homeCardContent(locale: Self.gb) == .next(hero))
        await h.module.stop()

        let empty = try await Self.granted([Sample.yesterday, Sample.dinner])
        #expect(empty.module.homeCardContent() == .noEventsToday)
        await empty.module.stop()
    }

    // MARK: Views

    @Test(arguments: [false, true])
    func viewsRenderInBothPrivacyStatesAndLooks(privacy: Bool) async throws {
        let h = try await Self.granted()
        h.module.selectUpcoming("call@1")
        let library = try ThemeLoader.loadBundled()
        for variant in ["chrome-hologram", "twin-metal-tactical"] {
            for look in [Look.dark, .light] {
                let theme = library.resolve(themeID: variant, look: look).theme
                let tab = CalendarTabView(module: h.module, now: Fixture.start)
                    .frame(width: 760, height: 340)
                    .vigieTheme(theme)
                    .privacyActive(privacy)
                    .environment(\.locale, Self.gb)
                #expect(ImageRenderer(content: tab).cgImage != nil, "tab \(variant) \(look)")
                let card = CalendarHomeCardView(module: h.module, now: Fixture.start)
                    .frame(width: 222, height: 138)
                    .vigieTheme(theme)
                    .privacyActive(privacy)
                    .environment(\.locale, Self.gb)
                #expect(ImageRenderer(content: card).cgImage != nil, "card \(variant) \(look)")
            }
        }
        await h.module.stop()
    }

    @Test func privacyScrubsTitlesAndCalendarsFromLabels() throws {
        let row = try #require(
            UpcomingList.build(
                events: Self.events, calendars: Sample.calendars, selectedDay: Fixture.start, now: Fixture.start,
                calendar: Fixture.calendar, locale: Self.gb
            ).hero?.row)
        let open = upcomingLabel(row, now: Fixture.start, privacy: false)
        let hidden = upcomingLabel(row, now: Fixture.start, privacy: true)
        #expect(open.contains("Design review") && open.contains("Work calendar"))
        #expect(!hidden.contains("Design review") && !hidden.contains("Work"))
        #expect(hidden.contains("15:30 to 16:00") && hidden.contains("in 47 minutes"))
        #expect(hidden.contains("Join call available"))
    }
}
