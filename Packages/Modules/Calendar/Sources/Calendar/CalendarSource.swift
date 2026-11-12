import Foundation

/// Where the module reads calendars and events (Story 13.1). ``EventKitCalendarSource`` in the app; a fake in
/// tests. Calls run off the main actor. The module calls it only while calendar access is granted.
public protocol CalendarSource: Sendable {
    /// Every calendar of the store that holds events, all accounts.
    func calendars() async -> [CalendarInfo]
    /// Event occurrences overlapping `interval`, sorted by start; `calendars` nil = every calendar.
    func events(in interval: DateInterval, calendars: Set<String>?) async -> [CalendarEvent]
    /// Yields when the store changes (events, calendars, or access edited outside Vigie). Each call returns a new
    /// stream; it ends when the caller stops iterating.
    func changes() -> AsyncStream<Void>
    /// Called when access became granted, so a store created before the grant starts over.
    func accessDidChange() async
}
