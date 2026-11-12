import Foundation
import ModuleKit

/// One alarm of one event occurrence: when it fires and the dedupe key of the alert it raises.
struct ReminderAlarm: Hashable, Sendable {
    let event: CalendarEvent
    let fireDate: Date

    /// `calendar:<occurrence id>:<fire date epoch>`: one alert per alarm, whatever re-plans happen.
    var key: String { ReminderAlarm.key(occurrenceID: event.id, fireDate: fireDate) }

    static func key(occurrenceID: String, fireDate: Date) -> String {
        "calendar:\(occurrenceID):\(Int(fireDate.timeIntervalSince1970))"
    }

    /// Every time-based alarm of `events` (location alarms are already dropped by the source), by fire date.
    static func all(in events: [CalendarEvent]) -> [ReminderAlarm] {
        events.flatMap { event in
            Set(event.alarms.map { $0.fireDate(eventStart: event.start) })
                .map { ReminderAlarm(event: event, fireDate: $0) }
        }
        .sorted { ($0.fireDate, $0.event.id) < ($1.fireDate, $1.event.id) }
    }
}

/// Calendar reminder alerts (SPEC §7.5, Story 13.4): at each alarm time of an event of ``CalendarModule/events``
/// (already filtered by `calendars` and `hide_all_day`, so a hidden all-day event never reminds), posts
/// `calendar.reminder` through the Notifier, once per alarm.
///
/// Planning: one scheduler job at the next instant that matters, the next alarm or the end of an event whose
/// reminder is open. Each pass raises the alarms whose fire date lies after the last pass (the `checkedUntil`
/// watermark) and at or before now, when their event has not ended. So an alarm missed while the Mac slept (or
/// skipped by a clock change) is raised once on wake if its event is still on, an alarm added in the past never
/// is, and several missed alarms of one event raise only the latest. Dedupe keys (``ReminderAlarm/key``) keep
/// re-plans (store changes, settings, wake) from posting twice.
///
/// An open reminder stays unresolved until its event ends (so `[notify] after_focus = "replay"` replays it after
/// a Focus), until the user takes an action (Join call, Open calendar, Dismiss), until the event disappears, or
/// until `reminders` is turned off. The module's state stays `hidden`: nothing shows on the closed notch.
@MainActor
final class CalendarReminders {
    /// The alert kind (AD-13 amended 2026-11-07).
    nonisolated static let kind = "calendar.reminder"
    nonisolated static let joinAction = "reminder.join"
    nonisolated static let openAction = "reminder.open"
    nonisolated static let dismissAction = "reminder.dismiss"

    /// An alert posted and not resolved yet.
    struct OpenReminder {
        let handle: AlertHandle
        let key: String
        var end: Date
    }

    private let moduleID: ModuleID
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let clockChanges: @Sendable () -> AsyncStream<Void>

    private var context: (any ModuleContext)?
    private(set) var enabled = false
    private(set) var events: [CalendarEvent] = []
    private var calendarNames: [String: String] = [:]
    /// Alarms at or before this instant have been handled.
    private(set) var checkedUntil: Date?
    /// Dedupe keys already posted (pruned to the alarms still planned).
    private(set) var posted: Set<String> = []
    /// Open alerts by occurrence id.
    private(set) var open: [String: OpenReminder] = [:]
    private var job: RegistrationToken?
    /// When the job fires, for tests.
    private(set) var nextWake: Date?
    private var tasks: [Task<Void, Never>] = []

    init(
        moduleID: ModuleID, now: @escaping @Sendable () -> Date, calendar: Calendar,
        clockChanges: (@Sendable () -> AsyncStream<Void>)? = nil
    ) {
        self.moduleID = moduleID
        self.now = now
        self.calendar = calendar
        self.clockChanges = clockChanges ?? Self.systemClockChanges
    }

    // MARK: Lifecycle

    /// Subscribes to sleep/wake (`context.power`) and clock changes; plans with `events`.
    func start(context: any ModuleContext) {
        self.context = context
        checkedUntil = now()
        let wakes = context.power.sleepWake
        tasks.append(
            Task { @MainActor [weak self] in
                for await event in wakes {
                    guard !Task.isCancelled else { return }
                    if event == .didWake { self?.pass() }
                }
            })
        let changes = clockChanges()
        tasks.append(
            Task { @MainActor [weak self] in
                for await _ in changes {
                    guard !Task.isCancelled else { return }
                    self?.pass()
                }
            })
    }

    /// Cancels the job and the subscriptions and resolves every open reminder.
    func stop() {
        for task in tasks { task.cancel() }
        tasks = []
        cancelJob()
        resolveAll()
        context = nil
    }

    /// New events, calendar names or `reminders` setting: re-plans (and resolves what no longer applies).
    func update(events: [CalendarEvent], calendarNames: [String: String], enabled: Bool) {
        if enabled, !self.enabled { checkedUntil = now() }  // turned on: nothing from the past
        self.events = events
        self.calendarNames = calendarNames
        self.enabled = enabled
        pass()
    }

    // MARK: Planning

    /// Resolves what ended, raises what is due, schedules the next job.
    func pass() {
        guard context != nil else { return }
        let date = now()
        guard enabled else {
            resolveAll()
            cancelJob()
            checkedUntil = date
            return
        }
        // Ended or vanished events end their reminder.
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, reminder) in open {
            if let event = byID[id], date < event.end {
                open[id]?.end = event.end
            } else {
                reminder.handle.resolve()
                open[id] = nil
            }
        }
        let alarms = ReminderAlarm.all(in: events)
        let since = checkedUntil ?? date
        var due: [String: ReminderAlarm] = [:]
        for alarm in alarms where alarm.fireDate > since && alarm.fireDate <= date && !posted.contains(alarm.key) {
            posted.insert(alarm.key)
            guard date < alarm.event.end else { continue }
            // Several alarms of one event in the window (a sleep): only the latest is raised.
            if let current = due[alarm.event.id], current.fireDate >= alarm.fireDate { continue }
            due[alarm.event.id] = alarm
        }
        for alarm in due.values.sorted(by: { $0.fireDate < $1.fireDate }) { raise(alarm, at: date) }
        checkedUntil = max(since, date)
        posted.formIntersection(alarms.map(\.key))
        schedule(alarms: alarms, after: checkedUntil ?? date)
    }

    private func schedule(alarms: [ReminderAlarm], after date: Date) {
        cancelJob()
        let nextAlarm = alarms.first { $0.fireDate > date && $0.fireDate < $0.event.end && !posted.contains($0.key) }
        let nextEnd = open.values.map(\.end).min()
        let candidates = [nextAlarm?.fireDate, nextEnd].compactMap { $0 }
        guard let next = candidates.min(), let context else { return }
        nextWake = next
        job = context.scheduler.at(next) { [weak self] in
            await MainActor.run { self?.pass() }
        }
    }

    private func cancelJob() {
        job?.cancel()
        job = nil
        nextWake = nil
    }

    // MARK: Alerts

    private func raise(_ alarm: ReminderAlarm, at date: Date) {
        guard let context else { return }
        open.removeValue(forKey: alarm.event.id)?.handle.resolve()
        let event = alarm.event
        let payload = Data(event.id.utf8)
        let primary =
            event.videoLink == nil
            ? AlertAction.module(id: moduleID, actionID: Self.openAction, payload: payload)
            : AlertAction.module(id: moduleID, actionID: Self.joinAction, payload: payload)
        let notifierEvent = NotifierEvent(
            kind: Self.kind, severity: .info,
            title: ReminderText.title(event),
            body: ReminderText.detail(
                event, calendarName: calendarNames[event.calendarID], now: date, calendar: calendar),
            action: primary,
            dedupeKey: alarm.key,
            category: ReminderText.category(start: event.start, now: date),
            secondaryAction: .module(id: moduleID, actionID: Self.dismissAction, payload: payload),
            primaryLabel: event.videoLink == nil ? nil : CalendarText.string("calendar.reminder.joinCall"))
        let handle = context.notifier.post(notifierEvent)
        open[event.id] = OpenReminder(handle: handle, key: alarm.key, end: event.end)
    }

    /// Resolves the open reminder of `occurrenceID` (an action was taken on it).
    func resolve(_ occurrenceID: String) {
        open.removeValue(forKey: occurrenceID)?.handle.resolve()
        guard context != nil else { return }
        schedule(alarms: ReminderAlarm.all(in: events), after: checkedUntil ?? now())
    }

    private func resolveAll() {
        for reminder in open.values { reminder.handle.resolve() }
        open = [:]
    }

    func event(_ occurrenceID: String) -> CalendarEvent? {
        events.first { $0.id == occurrenceID }
    }

    // MARK: Clock

    /// `NSSystemClockDidChange`: the user (or NTP) set the clock.
    private nonisolated static func systemClockChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let token = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: nil
        ) { _ in continuation.yield() }
        nonisolated(unsafe) let observer = token
        continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer) }
        return stream
    }
}

/// The reminder peek's copy (DESIGN "Peek alert panel → Calendar reminder"), from the Calendar String Catalog.
enum ReminderText {
    /// The event title, or `Untitled event`.
    static func title(_ event: CalendarEvent) -> String {
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? CalendarText.string("calendar.reminder.untitled") : title
    }

    /// The kicker's category after `CALENDAR · `: `in 10 min` (minutes to the start, rounded), `in 1h30` from an
    /// hour, `in 2 d` from a day, `now` at or after the start. The peek shows it uppercase.
    static func category(start: Date, now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded())
        guard minutes > 0 else { return CalendarText.string("calendar.reminder.now") }
        if minutes < 60 { return CalendarText.format("calendar.reminder.inMinutes", minutes) }
        if minutes < 24 * 60 {
            return CalendarText.format("calendar.reminder.inHours", minutes / 60, minutes % 60)
        }
        return CalendarText.format("calendar.reminder.inDays", Int((Double(minutes) / 1440).rounded()))
    }

    /// `14:00–14:30 · Work`, with the day first when the event is not today (`Tue 10 Nov 14:00–14:30 · Work`),
    /// `All day · Work` for an all-day event, and the video service last when the event has a link
    /// (`… · Zoom`).
    static func detail(_ event: CalendarEvent, calendarName: String?, now: Date, calendar: Calendar) -> String {
        var when: String
        if event.isAllDay {
            when = CalendarText.string("calendar.reminder.allDay")
        } else {
            let time = formatter(CalendarText.string("calendar.reminder.timeFormat"), calendar: calendar)
            when = CalendarText.format(
                "calendar.reminder.timeRange", time.string(from: event.start), time.string(from: event.end))
        }
        if !calendar.isDate(event.start, inSameDayAs: now), !(event.isAllDay && event.start <= now) {
            let day = formatter(CalendarText.string("calendar.reminder.dayFormat"), calendar: calendar)
            when = CalendarText.format("calendar.reminder.dayAndTime", day.string(from: event.start), when)
        }
        var parts = [when]
        if let calendarName, !calendarName.isEmpty { parts.append(calendarName) }
        if let link = event.videoLink, let service = VideoLink.service(of: link) {
            parts.append(CalendarText.string("calendar.reminder.service.\(service.rawValue)"))
        }
        return parts.joined(separator: CalendarText.string("calendar.reminder.separator"))
    }

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = CalendarText.catalogLocale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
