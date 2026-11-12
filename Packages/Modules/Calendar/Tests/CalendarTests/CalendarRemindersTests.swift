import Foundation
import ModuleKit
import Testing

@testable import Calendar

/// A started, granted module on a clock the test moves; scheduler, notifier, power and clock changes are fakes.
@MainActor
struct ReminderHarness {
    let clock = TestClock(Fixture.start)
    let source: FakeCalendarSource
    let context: FakeModuleContext
    let module: CalendarModule
    let clockChanges: AsyncStream<Void>.Continuation
    let opened = Harness.Recorder()

    init(events: [CalendarEvent], settings: [String: any SettingValue] = [:]) {
        source = FakeCalendarSource(events: events)
        context = FakeModuleContext(settings: settings, calendarAccess: .granted)
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        clockChanges = continuation
        nonisolated(unsafe) let changes = stream
        let clock = clock
        let opened = opened
        module = CalendarModule(
            source: source, openURL: { opened.urls.append($0) }, activations: { AsyncStream { _ in } },
            now: { clock.now }, calendar: Fixture.calendar, clockChanges: { changes })
    }

    func start() async throws { try await module.start(context: context) }

    var posted: [NotifierEvent] { context.fakeNotifier.posted }
    var unresolved: [NotifierEvent] { context.fakeNotifier.unresolved }
    var nextWake: Date? { module.reminders.nextWake }

    /// Moves the clock to `date` and runs the job due by then, as the real scheduler would.
    func run(until date: Date) async {
        clock.advance(date.timeIntervalSince(clock.now))
        while let job = context.fakeScheduler.liveOneShots.min(by: { $0.date! < $1.date! }), job.date! <= date {
            await context.fakeScheduler.fireNext()
        }
    }

    /// Moves the clock without running any job (the Mac slept).
    func sleep(until date: Date) { clock.advance(date.timeIntervalSince(clock.now)) }

    /// Replaces the store's events and lets the module reload.
    func change(_ events: [CalendarEvent]) async {
        let reads = source.eventQueries.count
        source.setEvents(events)
        source.sendChange()
        _ = await eventually { source.eventQueries.count > reads && module.events.map(\.id) == events.map(\.id) }
    }
}

func event(
    _ id: String, start: Date, minutes: Int = 60, calendar: String = "work", allDay: Bool = false,
    alarms: [AlarmInfo], videoLink: URL? = nil
) -> CalendarEvent {
    CalendarEvent(
        id: CalendarEvent.occurrenceID(eventID: id, start: start), eventID: id, calendarID: calendar, title: id,
        start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: allDay, alarms: alarms,
        videoLink: videoLink)
}

@MainActor @Suite struct CalendarRemindersTests {
    static let sixteen = Sample.at(day: 6, hour: 16)
    static let standup = event("standup", start: sixteen, alarms: [.relative(-600)])
    static let zoom = URL(string: "https://acme.zoom.us/j/123456789")!

    // MARK: Firing

    @Test func manifestDeclaresTheReminderKind() {
        #expect(CalendarModule.staticManifest.alertKinds == ["calendar.reminder"])
        #expect(CalendarModule.reminderKind == "calendar.reminder")
    }

    @Test func relativeAlarmFiresOnceAtItsTime() async throws {
        let h = ReminderHarness(events: [Self.standup])
        try await h.start()
        let fire = Self.sixteen.addingTimeInterval(-600)
        #expect(h.nextWake == fire)
        await h.run(until: fire.addingTimeInterval(-1))
        #expect(h.posted.isEmpty)
        await h.run(until: fire)
        #expect(h.posted.count == 1)
        let alert = try #require(h.posted.first)
        #expect(alert.kind == "calendar.reminder")
        #expect(alert.severity == .info)
        #expect(alert.title == "standup")
        #expect(alert.body == "16:00–17:00 · Work")
        #expect(alert.category == "in 10 min")
        #expect(alert.dedupeKey == "calendar:\(Self.standup.id):\(Int(fire.timeIntervalSince1970))")
        // Re-plans (store change, wake, clock change) never post it again.
        await h.change([Self.standup])
        h.context.fakePower.send(.didWake)
        h.clockChanges.yield()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.posted.count == 1)
        #expect(h.nextWake == Self.standup.end, "next: the event's end resolves it")
    }

    @Test func absoluteAlarmFiresAtItsDate() async throws {
        let at = Sample.at(day: 6, hour: 15)
        let h = ReminderHarness(events: [event("review", start: Self.sixteen, alarms: [.absolute(at)])])
        try await h.start()
        #expect(h.nextWake == at)
        await h.run(until: at)
        #expect(h.posted.map(\.category) == ["in 1h00"])
    }

    @Test func multipleAlarmsOnOneEventEachFireAndReplaceTheOpenOne() async throws {
        let h = ReminderHarness(events: [
            event("plan", start: Self.sixteen, alarms: [.relative(-1800), .relative(-300)])
        ])
        try await h.start()
        await h.run(until: Self.sixteen.addingTimeInterval(-1800))
        await h.run(until: Self.sixteen.addingTimeInterval(-300))
        #expect(h.posted.map(\.category) == ["in 30 min", "in 5 min"])
        #expect(h.unresolved.map(\.category) == ["in 5 min"])
    }

    @Test func eventWithoutAlarmRaisesNothing() async throws {
        let h = ReminderHarness(events: [event("quiet", start: Self.sixteen, alarms: [])])
        try await h.start()
        #expect(h.nextWake == nil)
        await h.run(until: Self.sixteen.addingTimeInterval(7200))
        #expect(h.posted.isEmpty)
    }

    @Test func remindersOffRaisesNothing() async throws {
        let h = ReminderHarness(events: [Self.standup], settings: ["reminders": false])
        try await h.start()
        #expect(h.nextWake == nil)
        await h.run(until: Self.sixteen)
        #expect(h.posted.isEmpty)
    }

    @Test func turningRemindersOffResolvesTheOpenAlert() async throws {
        let h = ReminderHarness(events: [Self.standup])
        try await h.start()
        await h.run(until: Self.sixteen.addingTimeInterval(-600))
        #expect(h.unresolved.count == 1)
        try await h.context.fakeSettings.set(false, for: "reminders")
        #expect(await eventually { h.unresolved.isEmpty })
        #expect(h.nextWake == nil)
        // Back on: an alarm already past is not raised.
        try await h.context.fakeSettings.set(true, for: "reminders")
        #expect(await eventually { h.module.options.reminders })
        #expect(h.posted.count == 1)
    }

    @Test func hiddenAllDayEventRaisesNothing() async throws {
        let day = Sample.at(day: 7, hour: 0)
        let allDay = event("holiday", start: day, minutes: 1440, allDay: true, alarms: [.relative(-3600)])
        let hidden = ReminderHarness(events: [allDay], settings: ["hide_all_day": true])
        try await hidden.start()
        #expect(hidden.nextWake == nil)
        await hidden.run(until: day)
        #expect(hidden.posted.isEmpty)
        // Shown: it reminds.
        let shown = ReminderHarness(events: [allDay])
        try await shown.start()
        await shown.run(until: day.addingTimeInterval(-3600))
        #expect(shown.posted.map(\.body) == ["Sat 07 Nov All day · Work"])
    }

    @Test func movedEventMovesItsAlarm() async throws {
        let h = ReminderHarness(events: [Self.standup])
        try await h.start()
        let later = event("standup", start: Sample.at(day: 6, hour: 17), alarms: [.relative(-600)])
        await h.change([later])
        #expect(h.nextWake == Sample.at(day: 6, hour: 16, minute: 50))
        await h.run(until: Sample.at(day: 6, hour: 15, minute: 50))
        #expect(h.posted.isEmpty)
        await h.run(until: Sample.at(day: 6, hour: 16, minute: 50))
        #expect(h.posted.count == 1)
    }

    @Test func deletedEventCancelsItsAlarmAndResolvesItsAlert() async throws {
        let other = event("other", start: Sample.at(day: 6, hour: 18), alarms: [.relative(-600)])
        let h = ReminderHarness(events: [Self.standup, other])
        try await h.start()
        await h.change([other])
        #expect(h.nextWake == Sample.at(day: 6, hour: 17, minute: 50))
        await h.run(until: Sample.at(day: 6, hour: 17, minute: 50))
        #expect(h.posted.map(\.title) == ["other"])
        await h.change([])
        #expect(h.unresolved.isEmpty)
        #expect(h.nextWake == nil)
    }

    // MARK: Copy

    @Test func kickerCountsMinutesThenNow() {
        let start = Self.sixteen
        #expect(ReminderText.category(start: start, now: start.addingTimeInterval(-600)) == "in 10 min")
        #expect(ReminderText.category(start: start, now: start.addingTimeInterval(-580)) == "in 10 min", "rounded")
        #expect(ReminderText.category(start: start, now: start.addingTimeInterval(-5400)) == "in 1h30")
        #expect(ReminderText.category(start: start, now: start.addingTimeInterval(-2 * 86_400)) == "in 2 d")
        #expect(ReminderText.category(start: start, now: start) == "now")
        #expect(ReminderText.category(start: start, now: start.addingTimeInterval(20)) == "now")
    }

    @Test func alarmAtTheStartSaysNow() async throws {
        let h = ReminderHarness(events: [event("now", start: Self.sixteen, alarms: [.relative(0)])])
        try await h.start()
        await h.run(until: Self.sixteen)
        #expect(h.posted.map(\.category) == ["now"])
    }

    @Test func detailNamesTheDayWhenNotTodayAndTheVideoService() {
        let tomorrow = event("t", start: Sample.at(day: 7, hour: 9), alarms: [], videoLink: Self.zoom)
        #expect(
            ReminderText.detail(tomorrow, calendarName: "Work", now: Fixture.start, calendar: Fixture.calendar)
                == "Sat 07 Nov 09:00–10:00 · Work · Zoom")
        let untitled = CalendarEvent(
            id: "x", eventID: "x", calendarID: "work", title: "  ", start: Self.sixteen, end: Self.sixteen)
        #expect(ReminderText.title(untitled) == "Untitled event")
    }

    @Test func everyReminderStringIsInTheCatalog() {
        let keys =
            [
                "calendar.reminder.now", "calendar.reminder.inMinutes", "calendar.reminder.inHours",
                "calendar.reminder.inDays", "calendar.reminder.joinCall", "calendar.reminder.untitled",
                "calendar.reminder.allDay", "calendar.reminder.timeFormat", "calendar.reminder.dayFormat",
                "calendar.reminder.timeRange", "calendar.reminder.dayAndTime", "calendar.reminder.separator",
            ] + VideoService.allCases.map { "calendar.reminder.service.\($0.rawValue)" }
        for key in keys { #expect(CalendarText.string(key) != key, "\(key)") }
    }

    // MARK: Actions

    @Test func joinCallOnlyWithAVideoLinkAndItOpensTheLink() async throws {
        let call = event("call", start: Self.sixteen, alarms: [.relative(-600)], videoLink: Self.zoom)
        let plain = event("plain", start: Self.sixteen, calendar: "personal", alarms: [.relative(-600)])
        let h = ReminderHarness(events: [call, plain])
        try await h.start()
        await h.run(until: Self.sixteen.addingTimeInterval(-600))
        let byTitle = Dictionary(uniqueKeysWithValues: h.posted.map { ($0.title, $0) })
        let joined = try #require(byTitle["call"])
        #expect(joined.primaryLabel == "Join call")
        #expect(joined.action == .module(id: "calendar", actionID: "reminder.join", payload: Data(call.id.utf8)))
        #expect(
            joined.secondaryAction == .module(id: "calendar", actionID: "reminder.dismiss", payload: Data(call.id.utf8))
        )
        let opened = try #require(byTitle["plain"])
        #expect(opened.primaryLabel == nil, "the core labels it Open calendar")
        #expect(opened.action == .module(id: "calendar", actionID: "reminder.open", payload: Data(plain.id.utf8)))

        h.module.handleAlertAction("reminder.join", payload: Data(call.id.utf8), intent: nil)
        #expect(h.opened.urls == [Self.zoom])
        #expect(h.unresolved.map(\.title) == ["plain"])
    }

    @Test func openCalendarFocusesTheEventOnTheTab() async throws {
        let soon = event(
            "tomorrow", start: Sample.at(day: 7, hour: 9), alarms: [.absolute(Sample.at(day: 6, hour: 16))])
        let h = ReminderHarness(events: [soon])
        try await h.start()
        await h.run(until: Sample.at(day: 6, hour: 16))
        #expect(h.posted.count == 1)
        h.module.handleAlertAction("reminder.open", payload: Data(soon.id.utf8), intent: nil)
        #expect(h.module.selectedEventID == soon.id)
        #expect(h.module.selectedDay == Sample.at(day: 7, hour: 0))
        #expect(h.context.fakeHost.openedOwnTab.count == 1)
        #expect(h.unresolved.isEmpty)
    }

    @Test func dismissResolves() async throws {
        let h = ReminderHarness(events: [Self.standup])
        try await h.start()
        await h.run(until: Self.sixteen.addingTimeInterval(-600))
        h.module.handleAlertAction("reminder.dismiss", payload: Data(Self.standup.id.utf8), intent: nil)
        #expect(h.unresolved.isEmpty)
        #expect(h.opened.urls.isEmpty)
        #expect(h.context.fakeHost.openedOwnTab.isEmpty)
        #expect(h.nextWake == nil)
    }

    @Test func alertStaysOpenUntilTheEventEndsThenResolves() async throws {
        let h = ReminderHarness(events: [Self.standup])
        try await h.start()
        await h.run(until: Self.sixteen.addingTimeInterval(-600))
        await h.run(until: Self.standup.end.addingTimeInterval(-1))
        #expect(h.unresolved.count == 1, "open through the event, so after_focus replay can show it")
        await h.run(until: Self.standup.end)
        #expect(h.unresolved.isEmpty)
    }

    // MARK: Sleep, wake and clock

    @Test func alarmMissedAsleepIsRaisedOnceOnWakeWhileTheEventIsOn() async throws {
        let h = ReminderHarness(events: [
            event("plan", start: Self.sixteen, alarms: [.relative(-1800), .relative(-600)])
        ])
        try await h.start()
        h.sleep(until: Self.sixteen.addingTimeInterval(300))
        h.context.fakePower.send(.didWake)
        #expect(await eventually { h.posted.count == 1 })
        #expect(h.posted.first?.category == "now", "only the latest missed alarm, once")
        await h.run(until: Self.sixteen.addingTimeInterval(301))
        h.context.fakePower.send(.didWake)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.posted.count == 1)
    }

    @Test func alarmMissedAsleepIsNeverRaisedOnceTheEventEnded() async throws {
        let h = ReminderHarness(events: [Self.standup])
        try await h.start()
        h.sleep(until: Self.standup.end.addingTimeInterval(60))
        h.context.fakePower.send(.didWake)
        try? await Task.sleep(for: .milliseconds(50))
        await h.run(until: Self.standup.end.addingTimeInterval(61))
        #expect(h.posted.isEmpty)
        #expect(h.nextWake == nil)
    }

    @Test func clockChangeReplans() async throws {
        let h = ReminderHarness(events: [Self.standup])
        try await h.start()
        h.sleep(until: Self.sixteen.addingTimeInterval(-300))
        h.clockChanges.yield()
        #expect(await eventually { h.posted.count == 1 })
        #expect(h.posted.first?.category == "in 5 min")
    }

    @Test func alarmBeforeLaunchIsNotRaised() async throws {
        let h = ReminderHarness(events: [
            event("early", start: Self.sixteen, alarms: [.absolute(Sample.at(day: 6, hour: 14))])
        ])
        try await h.start()
        #expect(h.nextWake == nil)
        #expect(h.posted.isEmpty)
    }

    // MARK: Privacy and closed notch

    @Test func titleAndDetailAreSensitive() async throws {
        let h = ReminderHarness(events: [Self.standup])
        try await h.start()
        await h.run(until: Self.sixteen.addingTimeInterval(-600))
        let alert = try #require(h.posted.first)
        #expect(alert.$title.value(privacyActive: true) == PrivacyMask.text)
        #expect(alert.$body.masked != alert.body)
        #expect(alert.category == "in 10 min", "the kicker is core-style copy and stays")
    }

    @Test func closedNotchStaysEmptyWhileAReminderIsOpen() async throws {
        let h = ReminderHarness(events: [Self.standup])
        try await h.start()
        await h.run(until: Self.sixteen.addingTimeInterval(-600))
        #expect(h.unresolved.count == 1)
        #expect(h.module.state == .hidden)
        #expect(h.module.leftWingItems().isEmpty)
        for size in CompactSize.allCases { #expect(h.module.compactView(size: size) == nil) }
    }

    @Test func stopResolvesAndCancels() async throws {
        let h = ReminderHarness(events: [Self.standup])
        try await h.start()
        await h.run(until: Self.sixteen.addingTimeInterval(-600))
        await h.module.stop()
        #expect(h.unresolved.isEmpty)
        #expect(h.context.fakeScheduler.liveOneShots.isEmpty)
    }
}
