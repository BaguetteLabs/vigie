import ModuleKit
import SwiftUI
import VigieUI

/// What the Calendar tab shows (Story 13.1, 13.2). Story 13.3 replaces the list placeholder with the upcoming
/// list.
public enum CalendarTabContent: Hashable, Sendable {
    /// Before the first access check.
    case checking
    /// Access missing: the setup card (mockup `key-calendar-tab.html` 03).
    case setup
    /// Access granted: the month grid, and the list placeholder with today's event count (`NO EVENTS TODAY`
    /// when there is none) until Story 13.3's upcoming list.
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
            case .grid(let count):
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
                    listPlaceholder(count)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await module.recheckAccess() }
    }

    @ViewBuilder private func listPlaceholder(_ count: Int) -> some View {
        if count == 0 {
            EmptyStateBlock(VigieCopy.noEventsToday)
        } else {
            EmptyStateBlock(
                label: LocalizedStringResource(
                    "calendar.tab.today", defaultValue: "\(count) EVENTS TODAY", bundle: CalendarModule.bundle))
        }
    }
}
