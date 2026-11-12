import ModuleKit
import SwiftUI
import VigieUI

/// What the Calendar tab shows (Story 13.1). Stories 13.2 and 13.3 replace `.placeholder` with the month grid and
/// the upcoming list.
public enum CalendarTabContent: Hashable, Sendable {
    /// Before the first access check.
    case checking
    /// Access missing: the setup card (mockup `key-calendar-tab.html` 03).
    case setup
    /// Access granted: today's event count until the grid and list arrive.
    case placeholder(todayCount: Int)
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
        case .granted: .placeholder(todayCount: todayEvents.count)
        }
    }

    /// `3 EVENTS TODAY` (the placeholder label); `NO EVENTS TODAY` comes from VigieCopy.
    nonisolated static func todayLabel(count: Int) -> String {
        CalendarText.format("calendar.tab.today", count)
    }
}

struct CalendarTabView: View {
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
            case .placeholder(let count):
                if count == 0 {
                    EmptyStateBlock(VigieCopy.noEventsToday)
                } else {
                    EmptyStateBlock(
                        label: LocalizedStringResource(
                            "calendar.tab.today", defaultValue: "\(count) EVENTS TODAY", bundle: CalendarModule.bundle))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await module.recheckAccess() }
    }
}
