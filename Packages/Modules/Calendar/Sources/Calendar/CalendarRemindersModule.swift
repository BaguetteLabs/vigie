import Foundation
import ModuleKit

/// The module's side of calendar reminders (Story 13.4): feeds ``CalendarReminders`` and routes the peek's
/// actions (``AlertActionHandler``).
extension CalendarModule: AlertActionHandler {
    /// `calendar.reminder` (AD-13 amended 2026-11-07).
    public nonisolated static let reminderKind = CalendarReminders.kind

    /// Hands the current events, calendar names and `reminders` setting to the scheduler.
    func remindersDidChange() {
        guard isRunning else { return }
        let names = Dictionary(calendars.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        reminders.update(events: events, calendarNames: names, enabled: options.reminders)
    }

    /// The peek's Join call, Open calendar and Dismiss (and a click on the macOS notification, the primary).
    /// Each one ends the reminder.
    public func handleAlertAction(_ actionID: String, payload: Data, intent: UserIntent?) {
        let id = String(decoding: payload, as: UTF8.self)
        switch actionID {
        case CalendarReminders.joinAction:
            if let link = reminders.event(id)?.videoLink { openURL(link) }
        case CalendarReminders.openAction:
            focusEvent(id)
            context?.host.openOwnTab(focus: intent)
        case CalendarReminders.dismissAction:
            break
        default:
            return
        }
        reminders.resolve(id)
    }

}
