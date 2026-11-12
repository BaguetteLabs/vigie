import Foundation

@testable import Calendar

/// A calendar store in memory: filters by interval and calendar ids like EventKit, records every query, and
/// yields a change when the test calls `sendChange()`. No EventKit.
final class FakeCalendarSource: CalendarSource, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalendars: [CalendarInfo]
    private var storedEvents: [CalendarEvent]
    private var queries: [(interval: DateInterval, calendars: Set<String>?)] = []
    private var calendarReads = 0
    private var resets = 0
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    init(calendars: [CalendarInfo] = Sample.calendars, events: [CalendarEvent] = Sample.events) {
        storedCalendars = calendars
        storedEvents = events
    }

    var eventQueries: [(interval: DateInterval, calendars: Set<String>?)] { lock.withLock { queries } }
    var calendarsRead: Int { lock.withLock { calendarReads } }
    var accessResets: Int { lock.withLock { resets } }
    var subscribers: Int { lock.withLock { continuations.count } }
    var totalCalls: Int { lock.withLock { queries.count + calendarReads + resets } }

    func setEvents(_ events: [CalendarEvent]) { lock.withLock { storedEvents = events } }

    func calendars() async -> [CalendarInfo] {
        lock.withLock {
            calendarReads += 1
            return storedCalendars
        }
    }

    func events(in interval: DateInterval, calendars ids: Set<String>?) async -> [CalendarEvent] {
        lock.withLock {
            queries.append((interval, ids))
            return storedEvents.filter { event in
                event.start < interval.end && event.end > interval.start
                    && (ids.map { $0.contains(event.calendarID) } ?? true)
            }
            .sorted { $0.start < $1.start }
        }
    }

    func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let id = UUID()
        lock.withLock { continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    func accessDidChange() async { lock.withLock { resets += 1 } }

    func sendChange() {
        for continuation in lock.withLock({ Array(continuations.values) }) { continuation.yield() }
    }
}

/// Two accounts, three calendars; events around the reference instant (Fri 06 Nov 2026 14:43 UTC).
enum Sample {
    static let work = CalendarInfo(
        id: "work", title: "Work", color: CalendarColor(sRGBRed: 0.2, green: 0.4, blue: 0.9), account: "Google")
    static let personal = CalendarInfo(
        id: "personal", title: "Personal", color: CalendarColor(sRGBRed: 0.9, green: 0.3, blue: 0.2), account: "iCloud")
    static let family = CalendarInfo(
        id: "family", title: "Family", color: CalendarColor(sRGBRed: 0.3, green: 0.8, blue: 0.4), account: "iCloud")
    static let calendars = [personal, work, family]

    static func at(day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = day
        components.hour = hour
        components.minute = minute
        return Fixture.calendar.date(from: components)!
    }

    static func event(
        _ id: String, calendar: String, day: Int, hour: Int, hours: Int = 1, allDay: Bool = false,
        alarms: [AlarmInfo] = []
    ) -> CalendarEvent {
        let start = allDay ? at(day: day, hour: 0) : at(day: day, hour: hour)
        let end = allDay ? at(day: day + 1, hour: 0) : start.addingTimeInterval(TimeInterval(hours * 3600))
        return CalendarEvent(
            id: CalendarEvent.occurrenceID(eventID: id, start: start), eventID: id, calendarID: calendar,
            title: id, start: start, end: end, isAllDay: allDay, alarms: alarms)
    }

    static let standup = event("standup", calendar: "work", day: 6, hour: 16, alarms: [.relative(-600)])
    static let holiday = event("holiday", calendar: "personal", day: 6, hour: 0, allDay: true)
    static let dinner = event("dinner", calendar: "family", day: 7, hour: 19)
    static let review = event("review", calendar: "work", day: 20, hour: 10)
    /// Outside today → +14 days.
    static let later = event("later", calendar: "work", day: 25, hour: 10)
    /// Ended yesterday: outside the window.
    static let yesterday = event("yesterday", calendar: "work", day: 5, hour: 9)
    static let events = [yesterday, holiday, standup, dinner, review, later]
}
