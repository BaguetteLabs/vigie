import Foundation
import SwiftUI

/// An EventKit calendar color as plain sRGB components (user data, not a theme token: DESIGN "Calendar colors").
public struct CalendarColor: Hashable, Sendable, Codable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(sRGBRed red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// The SwiftUI color for a calendar dot or swatch.
    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// One calendar of the macOS calendar store (any account).
public struct CalendarInfo: Identifiable, Hashable, Sendable {
    /// EventKit `calendarIdentifier`; the value stored in `[modules.calendar] calendars`.
    public let id: String
    public let title: String
    public let color: CalendarColor
    /// The account (EventKit source) title, e.g. "iCloud", "Google", "On My Mac".
    public let account: String

    public init(id: String, title: String, color: CalendarColor, account: String) {
        self.id = id
        self.title = title
        self.color = color
        self.account = account
    }
}

/// A time-based alarm set on an event in Calendar (SPEC §7.5). Location-based alarms are not represented
/// (they never raise a reminder).
public enum AlarmInfo: Hashable, Sendable {
    /// Fires at this instant.
    case absolute(Date)
    /// Fires this many seconds from the event start (negative = before).
    case relative(TimeInterval)

    /// When the alarm fires for an event starting at `start`.
    public func fireDate(eventStart start: Date) -> Date {
        switch self {
        case .absolute(let date): date
        case .relative(let offset): start.addingTimeInterval(offset)
        }
    }
}

/// One event occurrence in the loaded window. Recurring events give one value per occurrence.
public struct CalendarEvent: Identifiable, Hashable, Sendable {
    /// Unique per occurrence: the EventKit identifier plus the occurrence start.
    public let id: String
    /// EventKit `eventIdentifier`, shared by every occurrence of a recurring event.
    public let eventID: String
    public let calendarID: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?
    public let url: URL?
    public let alarms: [AlarmInfo]
    /// The Meet, Zoom or Teams link found in `url`, `location` or `notes` (``VideoLink/extract(url:location:notes:)``).
    public let videoLink: URL?

    public init(
        id: String, eventID: String, calendarID: String, title: String, start: Date, end: Date,
        isAllDay: Bool = false, location: String? = nil, notes: String? = nil, url: URL? = nil,
        alarms: [AlarmInfo] = [], videoLink: URL? = nil
    ) {
        self.id = id
        self.eventID = eventID
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.url = url
        self.alarms = alarms
        self.videoLink = videoLink
    }

    /// The occurrence id for an EventKit event starting at `start`.
    public static func occurrenceID(eventID: String, start: Date) -> String {
        "\(eventID)@\(Int(start.timeIntervalSince1970))"
    }
}

/// Whether Vigie can read the calendar store.
public enum CalendarAccess: Hashable, Sendable {
    /// Not checked yet (the module has not started, or is starting).
    case unknown
    case granted
    /// Denied, restricted or never answered: the tab and the pane show the setup card.
    case missing
}

/// `[modules.calendar]` (SPEC §7.5, §11).
public struct CalendarOptions: Hashable, Sendable {
    /// `reminders`: peek at each event's own alarm times (Story 13.4).
    public var reminders: Bool
    /// `hide_all_day`: all-day events are left out of `events` (and so raise no reminder).
    public var hideAllDay: Bool
    /// `calendars`: the included calendar ids; empty means every calendar.
    public var includedCalendarIDs: [String]

    public init(reminders: Bool = true, hideAllDay: Bool = false, includedCalendarIDs: [String] = []) {
        self.reminders = reminders
        self.hideAllDay = hideAllDay
        self.includedCalendarIDs = includedCalendarIDs
    }

    /// Whether events of `calendarID` are shown.
    public func includes(_ calendarID: String) -> Bool {
        includedCalendarIDs.isEmpty || includedCalendarIDs.contains(calendarID)
    }
}
