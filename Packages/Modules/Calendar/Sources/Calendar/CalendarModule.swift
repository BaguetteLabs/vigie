import AppKit
import Foundation
import ModuleKit
import Observation
import SwiftUI
import VigieUI
import os

/// `calendar` (SPEC §7.5, Story 13.1): reads every account of the macOS calendar store once the user allows it.
///
/// Off by default (SPEC §11): the Registry never starts it, so calendar access is never asked. When it starts
/// enabled it asks once through `context.permissions` (`.calendar`); the manifest sets `startsWithoutPermissions`
/// so the module runs without access and its tab and Settings pane show the setup card (UX-DR23). Access is
/// checked again when Vigie becomes active, when the tab or the pane appears and when the store reports a change;
/// there is no polling.
///
/// With access, ``events`` holds the occurrences from the start of today through the next 14 days of the
/// included calendars (`calendars`, empty = all), without all-day events when `hide_all_day` is on. It reloads on
/// each store change, each settings change and every hour. Stories 13.3–13.4 read ``events``, ``calendars`` and
/// ``options``.
///
/// The month grid (Story 13.2) has its own state: ``visibleMonth`` (`‹ ›`), ``selectedDay`` (a day click; Story
/// 13.3's list starts there) and ``gridEvents``, the visible month's 42 cells loaded per month, cached until the
/// next reload, never widening ``events``.
///
/// No closed-notch glance (amended 2026-11-07): no left-wing item, no compact view, no Home card yet. The state
/// stays `hidden` (Story 13.4 sets `alert` while a reminder is unresolved).
@MainActor @Observable
public final class CalendarModule: NotchModule {
    nonisolated static let bundle = CalendarText.bundle

    /// The Settings pane id (the module id).
    public nonisolated static let settingsPane = "calendar"
    /// How many days after today are loaded.
    public nonisolated static let daysAhead = 14
    /// The periodic reload, so the window moves with the day.
    public nonisolated static let reloadInterval: Duration = .seconds(3600)
    /// System Settings › Privacy & Security › Calendars (the same deep link Settings uses for `.calendar`).
    public nonisolated static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    public nonisolated static let staticManifest = ModuleManifest(
        id: "calendar",
        name: LocalizedStringResource("calendar.module.name", bundle: bundle),
        icon: "calendar",
        permissions: [.calendar],
        settings: [
            SettingDescriptor(
                key: "reminders",
                label: LocalizedStringResource("calendar.setting.reminders", bundle: bundle),
                kind: .bool(default: true),
                help: LocalizedStringResource("calendar.setting.reminders.help", bundle: bundle)),
            SettingDescriptor(
                key: "hide_all_day",
                label: LocalizedStringResource("calendar.setting.hideAllDay", bundle: bundle),
                kind: .bool(default: false),
                help: LocalizedStringResource("calendar.setting.hideAllDay.help", bundle: bundle)),
            SettingDescriptor(
                key: "calendars",
                label: LocalizedStringResource("calendar.setting.calendars", bundle: bundle),
                kind: .list(of: .string, default: []),
                help: LocalizedStringResource("calendar.setting.calendars.help", bundle: bundle),
                customControl: true),
        ],
        defaultEnabled: false,
        startsWithoutPermissions: true
    )

    public let manifest = CalendarModule.staticManifest
    public private(set) var state: ModuleState = .hidden
    public private(set) var access: CalendarAccess = .unknown
    /// Every calendar of the store (for Settings), sorted by account then title.
    public private(set) var calendars: [CalendarInfo] = []
    /// The loaded occurrences, filtered by `calendars` and `hide_all_day`, sorted by start.
    public private(set) var events: [CalendarEvent] = []
    /// The loaded window, nil before the first load.
    public private(set) var window: DateInterval?
    public private(set) var options = CalendarOptions()
    public private(set) var isRunning = false
    /// The month grid's events (Story 13.2): the occurrences of ``gridInterval`` (the visible month's 42 cells),
    /// filtered like ``events``. Loaded per month and kept in a per-month cache that every reload empties.
    public private(set) var gridEvents: [CalendarEvent] = []
    /// The interval ``gridEvents`` covers, nil before the first grid load.
    public private(set) var gridInterval: DateInterval?
    /// The month the grid shows when the user moved away from today's month; nil follows today.
    private var monthOverride: Date?
    /// The day the user selected when it is not today; nil follows today.
    private var selectionOverride: Date?

    @ObservationIgnored let source: any CalendarSource
    @ObservationIgnored let openSettings: (@MainActor @Sendable (String) -> Void)?
    @ObservationIgnored let openURL: @MainActor @Sendable (URL) -> Void
    @ObservationIgnored private let activations: @Sendable () -> AsyncStream<Void>
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private var context: (any ModuleContext)?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var reloadJob: RegistrationToken?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var gridGeneration = 0
    @ObservationIgnored private var gridCache: [Date: [CalendarEvent]] = [:]
    @ObservationIgnored private var gridTask: Task<Void, Never>?

    /// - Parameters:
    ///   - source: the calendar store; EventKit in the app.
    ///   - openSettings: opens a Settings pane by id (the setup card's `Calendar settings`).
    ///   - openURL: opens System Settings (the setup card's `Open System Settings`).
    ///   - activations: yields each time Vigie becomes active; defaults to AppKit's notification.
    public init(
        source: any CalendarSource = EventKitCalendarSource(),
        openSettings: (@MainActor @Sendable (String) -> Void)? = nil,
        openURL: @escaping @MainActor @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) },
        activations: (@Sendable () -> AsyncStream<Void>)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.source = source
        self.openSettings = openSettings
        self.openURL = openURL
        self.activations = activations ?? Self.appActivations
        self.now = now
        self.calendar = calendar
    }

    // MARK: Lifecycle

    public func start(context: any ModuleContext) async throws {
        self.context = context
        options = Self.resolvedOptions(context.settings)
        isRunning = true
        for key in ["reminders", "hide_all_day", "calendars"] {
            let changes = context.settings.observe(key)
            tasks.append(
                Task { @MainActor [weak self] in
                    for await _ in changes {
                        guard let self, !Task.isCancelled, let settings = self.context?.settings else { return }
                        self.applyOptions(Self.resolvedOptions(settings))
                    }
                })
        }
        let activations = activations()
        tasks.append(
            Task { @MainActor [weak self] in
                for await _ in activations {
                    guard !Task.isCancelled else { return }
                    await self?.recheckAccess()
                }
            })
        reloadJob = context.scheduler.every(Self.reloadInterval) { [weak self] in
            await self?.reload()
        }
        // Enabled: the one moment calendar access is asked (SPEC §4.3).
        await checkAccess(requesting: true)
    }

    public func stop() async {
        for task in tasks { task.cancel() }
        tasks = []
        changeTask?.cancel()
        changeTask = nil
        gridTask?.cancel()
        gridTask = nil
        reloadJob?.cancel()
        reloadJob = nil
        isRunning = false
        generation += 1
        gridGeneration += 1
    }

    // MARK: Access

    /// Reads the access status again (app activation, tab or pane shown, store change). Never asks macOS.
    public func recheckAccess() async {
        await checkAccess(requesting: false)
    }

    private func checkAccess(requesting: Bool) async {
        guard isRunning, let permissions = context?.permissions else { return }
        var status = await permissions.status(of: .calendar)
        if requesting, status == .notDetermined {
            status = await permissions.request(.calendar)
        }
        guard isRunning else { return }
        let granted = status == .granted
        if granted, access != .granted {
            access = .granted
            await source.accessDidChange()
            startObservingChanges()
            await reload()
        } else if !granted, access != .missing {
            access = .missing
            changeTask?.cancel()
            changeTask = nil
            generation += 1
            calendars = []
            events = []
            window = nil
            gridGeneration += 1
            gridCache = [:]
            gridEvents = []
            gridInterval = nil
        }
    }

    private func startObservingChanges() {
        changeTask?.cancel()
        let changes = source.changes()
        changeTask = Task { @MainActor [weak self] in
            for await _ in changes {
                guard let self, !Task.isCancelled else { return }
                // A store change may also be an access change made in System Settings.
                await self.recheckAccess()
                await self.reload()
            }
        }
    }

    // MARK: Loading

    /// Loads the calendars and the window's events again (no-op without access).
    public func reload() async {
        guard isRunning, access == .granted else { return }
        generation += 1
        let current = generation
        let interval = loadInterval()
        let options = options
        let ids = options.includedCalendarIDs.isEmpty ? nil : Set(options.includedCalendarIDs)
        let all = await source.calendars()
        let loaded = await source.events(in: interval, calendars: ids)
        guard current == generation, isRunning, access == .granted else { return }
        calendars = all.sorted { ($0.account, $0.title) < ($1.account, $1.title) }
        events = Self.filter(loaded, options: options)
        window = interval
        // The store or the settings changed: every cached month is stale.
        gridCache = [:]
        await loadGrid()
    }

    /// From the start of today through the end of the 14th day after it.
    func loadInterval() -> DateInterval {
        let start = calendar.startOfDay(for: now())
        let end = calendar.date(byAdding: .day, value: Self.daysAhead + 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// The included calendars' events, without all-day events when they are hidden.
    nonisolated static func filter(_ events: [CalendarEvent], options: CalendarOptions) -> [CalendarEvent] {
        events.filter { event in
            options.includes(event.calendarID) && !(options.hideAllDay && event.isAllDay)
        }
    }

    /// Events that start or run today (the placeholder tab's count).
    public var todayEvents: [CalendarEvent] {
        let today = calendar.dateInterval(of: .day, for: now()) ?? DateInterval(start: now(), duration: 86_400)
        return events.filter { $0.start < today.end && $0.end > today.start }
    }

    // MARK: Month grid (Story 13.2)

    /// The first day of the month the grid shows (today's month unless the user moved with `‹ ›`).
    public var visibleMonth: Date {
        monthOverride ?? MonthGrid.monthStart(of: now(), calendar: gridCalendar)
    }

    /// The start of the selected day (today unless the user clicked another day). Story 13.3's upcoming list
    /// starts there.
    public var selectedDay: Date {
        selectionOverride ?? calendar.startOfDay(for: now())
    }

    /// The header dot is lit: another month is shown or another day is selected, so clicking it jumps back.
    public var canReturnToToday: Bool {
        visibleMonth != MonthGrid.monthStart(of: now(), calendar: gridCalendar)
            || selectedDay != calendar.startOfDay(for: now())
    }

    /// The grid for the visible month, today and the selected day. The visible month's dots appear once its
    /// events are loaded (until then, or for another month still loading, no dots).
    public func monthGrid(locale: Locale = .current, maxDots: Int = MonthGrid.defaultMaxDots) -> MonthGrid {
        let month = visibleMonth
        let loaded = gridInterval == MonthGrid.interval(month: month, calendar: calendar)
        return MonthGrid.build(
            month: month, today: now(), selected: selectedDay, events: loaded ? gridEvents : [],
            calendars: calendars, calendar: calendar, locale: locale, maxDots: maxDots)
    }

    /// `‹`: the previous month (the selection does not change).
    public func showPreviousMonth() { showMonth(offset: -1) }

    /// `›`: the next month (the selection does not change).
    public func showNextMonth() { showMonth(offset: 1) }

    private func showMonth(offset: Int) {
        let next = gridCalendar.date(byAdding: .month, value: offset, to: visibleMonth) ?? visibleMonth
        setVisibleMonth(next)
    }

    /// A day click (or an arrow key): selects that day. A day of an adjacent month also moves the grid there.
    public func select(_ day: Date) {
        let start = calendar.startOfDay(for: day)
        selectionOverride = start == calendar.startOfDay(for: now()) ? nil : start
        let month = MonthGrid.monthStart(of: start, calendar: gridCalendar)
        if month != visibleMonth { setVisibleMonth(month) }
    }

    /// Arrow keys: moves the selection by `days` (±1 day, ±7 for a week).
    public func moveSelection(byDays days: Int) {
        select(calendar.date(byAdding: .day, value: days, to: selectedDay) ?? selectedDay)
    }

    /// The lit header dot: back to today's month with today selected.
    public func returnToToday() {
        selectionOverride = nil
        setVisibleMonth(MonthGrid.monthStart(of: now(), calendar: gridCalendar))
    }

    private func setVisibleMonth(_ month: Date) {
        let start = MonthGrid.monthStart(of: month, calendar: gridCalendar)
        monthOverride = start == MonthGrid.monthStart(of: now(), calendar: gridCalendar) ? nil : start
        gridTask?.cancel()
        gridTask = Task { @MainActor [weak self] in await self?.loadGrid() }
    }

    /// Loads the visible month's grid interval (from the cache when this month was loaded since the last reload).
    func loadGrid() async {
        guard isRunning, access == .granted else { return }
        let interval = MonthGrid.interval(month: visibleMonth, calendar: calendar)
        if let cached = gridCache[interval.start] {
            gridEvents = cached
            gridInterval = interval
            return
        }
        gridGeneration += 1
        let current = gridGeneration
        let options = options
        let ids = options.includedCalendarIDs.isEmpty ? nil : Set(options.includedCalendarIDs)
        let loaded = await source.events(in: interval, calendars: ids)
        guard current == gridGeneration, isRunning, access == .granted else { return }
        let filtered = Self.filter(loaded, options: options)
        gridCache[interval.start] = filtered
        // The user may have moved on while this month loaded: cache it, show only the visible one.
        guard interval == MonthGrid.interval(month: visibleMonth, calendar: calendar) else { return }
        gridEvents = filtered
        gridInterval = interval
    }

    private var gridCalendar: Calendar { MonthGrid.gridCalendar(calendar) }

    // MARK: Settings

    private func applyOptions(_ new: CalendarOptions) {
        guard new != options else { return }
        options = new
        Task { @MainActor [weak self] in await self?.reload() }
    }

    nonisolated static func resolvedOptions(_ settings: any ModuleSettings) -> CalendarOptions {
        CalendarOptions(
            reminders: settings.value("reminders", as: Bool.self) ?? true,
            hideAllDay: settings.value("hide_all_day", as: Bool.self) ?? false,
            includedCalendarIDs: settings.value("calendars", as: [String].self) ?? [])
    }

    /// Whether the Settings checkbox of `calendarID` is on.
    public func isIncluded(_ calendarID: String) -> Bool {
        options.includes(calendarID)
    }

    /// Turns one calendar on or off and writes `[modules.calendar] calendars` (empty when every calendar is on).
    public func setIncluded(_ calendarID: String, _ included: Bool) async throws {
        guard let settings = context?.settings else { return }
        let next = Self.includedList(
            current: options.includedCalendarIDs, all: calendars.map(\.id), toggling: calendarID, on: included)
        var updated = options
        updated.includedCalendarIDs = next
        applyOptions(updated)
        try await settings.set(next, for: "calendars")
    }

    /// The `calendars` value after turning `id` on or off: listed explicitly, in the store's order, unless every
    /// known calendar is on (then empty, which also includes calendars added later). The last checked calendar
    /// cannot be turned off, since an empty list means every calendar.
    nonisolated static func includedList(current: [String], all: [String], toggling id: String, on: Bool) -> [String] {
        var included = current.isEmpty ? all : current
        if on {
            if !included.contains(id) { included.append(id) }
        } else {
            included.removeAll { $0 == id }
            if included.isEmpty { return current }
        }
        if !all.isEmpty, Set(all).isSubset(of: Set(included)) { return [] }
        let order = Dictionary(all.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return included.sorted { (order[$0] ?? Int.max) < (order[$1] ?? Int.max) }
    }

    // MARK: Actions

    /// The setup card's `Open System Settings`: Privacy & Security › Calendars.
    public func openSystemSettings() {
        openURL(Self.systemSettingsURL)
    }

    /// The setup card's `Calendar settings`: this module's Settings pane.
    public func openCalendarSettings() {
        openSettings?(Self.settingsPane)
    }

    private nonisolated static func appActivations() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let token = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { _ in continuation.yield() }
        nonisolated(unsafe) let observer = token
        continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer) }
        return stream
    }
}
