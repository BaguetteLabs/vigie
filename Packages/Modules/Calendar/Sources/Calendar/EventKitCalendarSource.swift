import CoreGraphics
import EventKit
import Foundation

/// ``CalendarSource`` over the macOS calendar store (EventKit), every account (SPEC §7.5).
///
/// An actor, so EventKit queries run off the main actor. It never asks for access: the module does that through
/// `context.permissions` (AD-19, AD-20). Until access is granted the store returns nothing.
public actor EventKitCalendarSource: CalendarSource {
    private var store: EKEventStore?

    public init() {}

    private var eventStore: EKEventStore {
        if let store { return store }
        let made = EKEventStore()
        store = made
        return made
    }

    public func calendars() async -> [CalendarInfo] {
        eventStore.calendars(for: .event).map(Self.info)
    }

    public func events(in interval: DateInterval, calendars ids: Set<String>?) async -> [CalendarEvent] {
        let store = eventStore
        var selected: [EKCalendar]?
        if let ids {
            selected = store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
            if selected?.isEmpty == true { return [] }
        }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: selected)
        return store.events(matching: predicate)
            .map(Self.event)
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    public nonisolated func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        // Any store's change notification: the actor may replace its store after an access change.
        let token = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: nil
        ) { _ in continuation.yield() }
        nonisolated(unsafe) let observer = token
        continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer) }
        return stream
    }

    public func accessDidChange() async {
        store = nil
    }

    // MARK: - Mapping

    static func info(_ calendar: EKCalendar) -> CalendarInfo {
        CalendarInfo(
            id: calendar.calendarIdentifier, title: calendar.title, color: color(calendar.cgColor),
            account: calendar.source?.title ?? "")
    }

    static func event(_ event: EKEvent) -> CalendarEvent {
        let eventID = event.eventIdentifier ?? event.calendarItemIdentifier
        let alarms: [AlarmInfo] = (event.alarms ?? []).compactMap { alarm in
            if alarm.structuredLocation != nil || alarm.proximity != .none { return nil }  // location-based
            if let date = alarm.absoluteDate { return .absolute(date) }
            return .relative(alarm.relativeOffset)
        }
        return CalendarEvent(
            id: CalendarEvent.occurrenceID(eventID: eventID, start: event.startDate),
            eventID: eventID,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            url: event.url,
            alarms: alarms,
            videoLink: VideoLink.extract(url: event.url, location: event.location, notes: event.notes))
    }

    static func color(_ cgColor: CGColor?) -> CalendarColor {
        guard let cgColor, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
            let parts = converted.components, parts.count >= 3
        else { return CalendarColor(sRGBRed: 0.5, green: 0.5, blue: 0.5) }
        return CalendarColor(
            sRGBRed: Double(parts[0]), green: Double(parts[1]), blue: Double(parts[2]),
            alpha: Double(parts.count > 3 ? parts[3] : 1))
    }
}
