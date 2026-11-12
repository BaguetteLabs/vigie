import Foundation

/// The upcoming list's state and actions on the module (Story 13.3).
extension CalendarModule {
    /// The events the list reads: ``events`` (today → +14 days) plus the visible month's ``gridEvents``, so a day
    /// picked anywhere in the grid has its events (the grid always shows the selected day's month).
    var upcomingEvents: [CalendarEvent] {
        var seen = Set(events.map(\.id))
        var merged = events
        for event in gridEvents where seen.insert(event.id).inserted { merged.append(event) }
        return merged
    }

    /// The list from ``selectedDay`` at `now` (default: the module's clock).
    public func upcomingList(locale: Locale = .current, now date: Date? = nil) -> UpcomingList {
        UpcomingList.build(
            events: upcomingEvents, calendars: calendars, selectedDay: selectedDay, now: date ?? now(),
            calendar: calendar, locale: locale)
    }

    /// The Home card's list: always from today, whatever day the grid has selected.
    func todayUpcomingList(locale: Locale = .current, now date: Date? = nil) -> UpcomingList {
        let instant = date ?? now()
        return UpcomingList.build(
            events: events, calendars: calendars, selectedDay: instant, now: instant, calendar: calendar,
            locale: locale)
    }

    /// Selects a row of the list (a click or ↑↓); nil clears the selection.
    public func selectUpcoming(_ id: String?) {
        selectedEventID = id
    }

    /// Shows an event in the tab (a reminder's `Show`, Story 13.4): selects its day in the grid (today for an
    /// event already running) and its row in the list. False when the event is not loaded.
    @discardableResult
    public func focusEvent(_ id: String) -> Bool {
        guard let event = upcomingEvents.first(where: { $0.id == id || $0.eventID == id }) else { return false }
        let running = event.start < calendar.startOfDay(for: now()) && event.end > now()
        select(running ? now() : event.start)
        selectedEventID = event.id
        return true
    }

    /// `JOIN CALL ↵` or ↵ on a row: opens the event's video link through the `openURL` seam. False when the event
    /// has no link (no Join button is drawn then).
    @discardableResult
    public func joinCall(_ id: String) -> Bool {
        guard let url = upcomingEvents.first(where: { $0.id == id })?.videoLink else { return false }
        openURL(url)
        return true
    }

    /// Applies a key of the list (↑↓ select, ↵ join). Returns whether the key was used.
    @discardableResult
    func handleUpcomingKey(_ key: UpcomingList.Key, list: UpcomingList) -> Bool {
        switch list.keyAction(key, selected: selectedEventID) {
        case .select(let id):
            selectedEventID = id
            return true
        case .join(let id, let url):
            selectedEventID = id
            openURL(url)
            return true
        case .ignored:
            return false
        }
    }

    /// The list card's meta: `FROM TODAY`, or `FROM THU 12 NOV` for another selected day.
    nonisolated static func upcomingMeta(_ list: UpcomingList, calendar: Calendar, locale: Locale) -> String {
        guard !list.startsToday else { return CalendarText.string("calendar.upcoming.from.today") }
        return CalendarText.format(
            "calendar.upcoming.from", UpcomingList.dayText(list.startDay, calendar: calendar, locale: locale))
    }
}
