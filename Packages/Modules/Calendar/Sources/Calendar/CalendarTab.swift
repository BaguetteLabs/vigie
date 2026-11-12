import ModuleKit
import SwiftUI
import VigieUI

/// What the Calendar tab shows (Stories 13.1–13.3).
public enum CalendarTabContent: Hashable, Sendable {
    /// Before the first access check.
    case checking
    /// Access missing: the setup card (mockup `key-calendar-tab.html` 03).
    case setup
    /// Access granted: the month grid and the upcoming list (Story 13.3). `todayCount` counts the events that
    /// start or run today.
    case grid(todayCount: Int)
}

extension CalendarModule {
    public func expandedView() -> AnyView? {
        AnyView(CalendarTabView(module: self))
    }

    public func settingsView() -> AnyView? {
        AnyView(CalendarSettingsView(module: self))
    }

    /// The tab's content for the current access and events.
    public var tabContent: CalendarTabContent {
        switch access {
        case .unknown: .checking
        case .missing: .setup
        case .granted: .grid(todayCount: todayEvents.count)
        }
    }

    /// The calendars with events in the visible month, by title (the legend under the grid).
    var gridLegend: [CalendarInfo] {
        let month = visibleMonth
        let end = calendar.date(byAdding: .month, value: 1, to: month) ?? month
        let ids = Set(gridEvents.filter { $0.start < end && $0.end > month }.map(\.calendarID))
        return calendars.filter { ids.contains($0.id) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// `3 EVENTS TODAY` (the list placeholder label); `NO EVENTS TODAY` comes from VigieCopy.
    nonisolated static func todayLabel(count: Int) -> String {
        CalendarText.format("calendar.tab.today", count)
    }
}

struct CalendarTabView: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.locale) private var locale
    let module: CalendarModule
    /// Fixed instant for tests; nil follows the clock (the list each minute, the hero each second).
    var now: Date?

    var body: some View {
        Group {
            switch module.tabContent {
            case .checking:
                Color.clear
            case .setup:
                SetupCard(
                    VigieCopy.calendarAccess,
                    primaryAction: { module.openSystemSettings() },
                    secondaryAction: { module.openCalendarSettings() })
            case .grid:
                // Mockup `key-calendar-tab.html`: the 300px grid card left, the upcoming list right
                // (EXPERIENCE "Calendar": "Month grid left, upcoming list right").
                HStack(alignment: .top, spacing: theme.spacing(.gridGap)) {
                    MonthGridCard(
                        grid: module.monthGrid(locale: locale, maxDots: MonthGridMetrics(theme: theme).maxDots),
                        canReturnToToday: module.canReturnToToday,
                        legend: module.gridLegend,
                        calendar: module.calendar,
                        locale: locale,
                        actions: MonthGridActions(
                            previous: { module.showPreviousMonth() },
                            next: { module.showNextMonth() },
                            today: { module.returnToToday() },
                            select: { module.select($0) },
                            move: { module.moveSelection(byDays: $0) }))
                    upcoming
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await module.recheckAccess() }
    }

    /// The upcoming list (Story 13.3), rebuilt each minute so ended events drop off and relative times move.
    @ViewBuilder private var upcoming: some View {
        if let now {
            upcomingList(at: now, fixed: now)
        } else {
            TimelineView(.everyMinute) { context in upcomingList(at: context.date, fixed: nil) }
        }
    }

    private func upcomingList(at date: Date, fixed: Date?) -> some View {
        let list = module.upcomingList(locale: locale, now: date)
        return UpcomingListView(
            list: list, selectedID: module.selectedEventID, now: fixed, builtAt: date,
            meta: CalendarModule.upcomingMeta(list, calendar: module.calendar, locale: locale),
            actions: UpcomingActions(
                select: { module.selectUpcoming($0) },
                join: { module.joinCall($0) },
                key: { module.handleUpcomingKey($0, list: module.upcomingList(locale: locale)) }))
    }
}
