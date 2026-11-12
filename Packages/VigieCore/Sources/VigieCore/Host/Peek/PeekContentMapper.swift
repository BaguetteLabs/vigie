import Foundation
import ModuleKit
import VigieUI

/// Builds what a peek shows from an alert (SPEC §5.2, DESIGN "Peek alert panel", EXPERIENCE "Peek alert
/// panel"): the kind picks the beacon, hue, kicker and primary action label; the module supplies the title
/// and the detail. Copy comes from the VigieCore String Catalog (AD-15).
public enum PeekContentMapper {
    /// The peek kind for an alert kind (canonical kinds, AD-13). Unknown kinds peek as ``PeekKind/generic``.
    public static func kind(for alertKind: String) -> PeekKind {
        switch alertKind {
        case "session.blocked": .blocked
        case "session.failed": .failed
        case "session.done": .done
        case "usage.quota_warning": .quotaWarning
        case "setup.problem": .setupProblem
        case "time.timer_end": .timerEnd
        case "time.break_reminder": .breakDue
        case "calendar.reminder": .calendarReminder
        default: .generic
        }
    }

    /// The panel content for `alert`. `theme` gives the variant's "now" accent for Time and calendar peeks.
    public static func content(for alert: ActiveAlert, theme: Theme) -> PeekContent {
        let kind = kind(for: alert.kind)
        // A module may name its primary action (the calendar reminder's `Join call`, Story 13.4); the label comes
        // already localized from its catalog.
        let label = alert.event.primaryLabel.map { LocalizedStringResource(stringLiteral: $0) } ?? primaryLabel(kind)
        let primary =
            alert.event.action == nil
            ? nil : PeekAction(label: label, shortcut: PeekAction.primaryShortcut)
        let secondary = PeekAction(
            label: resource(kind == .breakDue ? "peek.action.skip" : "peek.action.dismiss"),
            shortcut: PeekAction.secondaryShortcut)
        // DESIGN "Break": the one three-action peek, Snooze 5m (`⌥⌘Z`) beside Skip; only the break kind draws it.
        let tertiary =
            kind == .breakDue && alert.event.tertiaryAction != nil
            ? PeekAction(label: resource("peek.action.snooze"), shortcut: PeekAction.tertiaryShortcut) : nil
        return PeekContent(
            kind: kind,
            kicker: alert.event.kicker ?? kicker(kind, category: alert.event.category),
            title: alert.event.title,
            body: alert.event.body,
            primary: primary,
            secondary: secondary,
            accentRole: accentRole(kind, theme: theme),
            tertiary: tertiary)
    }

    /// The VoiceOver announcement (UX-DR93): kicker, title and the primary shortcut with its action, e.g.
    /// "Blocked, api-refactor, Option Command Return, Focus terminal".
    public static func announcement(for content: PeekContent) -> String {
        guard let primary = content.primary else {
            return format("peek.announcement.noAction", content.kicker, content.title)
        }
        return format("peek.announcement", content.kicker, content.title, String(localized: primary.label))
    }

    // MARK: Copy

    /// The kicker, with the event's category when it has one (`SETUP · CONFIG`, Story 3.4). A Timer end's
    /// category is its end time, written after the kicker without a separator (`TIMER · ENDED 14:48`, Story 20.2).
    static func kicker(_ kind: PeekKind, category: String?) -> String {
        let base = string(kickerKey(kind))
        guard let category, !category.isEmpty else { return base }
        return format(kind == .timerEnd ? "peek.kicker.withTime" : "peek.kicker.withCategory", base, category)
    }

    static func kickerKey(_ kind: PeekKind) -> String {
        switch kind {
        case .blocked: "peek.kicker.blocked"
        case .failed: "peek.kicker.failed"
        case .done: "peek.kicker.done"
        case .sleepSummary: "peek.kicker.sleepSummary"
        case .quotaWarning: "peek.kicker.quotaWarning"
        case .setupProblem: "peek.kicker.setup"
        case .timerEnd: "peek.kicker.timerEnd"
        case .breakDue: "peek.kicker.breakDue"
        case .calendarReminder: "peek.kicker.calendar"
        case .generic: "peek.kicker.generic"
        }
    }

    static func primaryLabel(_ kind: PeekKind) -> LocalizedStringResource {
        switch kind {
        case .blocked, .failed, .done: resource("peek.action.focusTerminal")
        case .sleepSummary: resource("peek.action.openAgents")
        case .quotaWarning: resource("peek.action.openUsage")
        case .setupProblem: resource("peek.action.openSettings")
        case .timerEnd: resource("peek.action.openTime")
        case .breakDue: resource("peek.action.startBreak")
        case .calendarReminder: resource("peek.action.openCalendar")
        case .generic: resource("peek.action.open")
        }
    }

    static func accentRole(_ kind: PeekKind, theme: Theme) -> ColorRole {
        switch kind {
        case .blocked: .statusBlocked
        case .failed, .sleepSummary: .statusFailed
        case .done: .statusDone
        case .quotaWarning: .quotaWarning
        case .setupProblem: .ink2
        // The variant's "now" accent, never a status hue (DESIGN "Time accent"): A iris, C gold.
        case .timerEnd, .breakDue, .calendarReminder: theme.defines(.structure) ? .gold : .iris1
        case .generic: .ink1
        }
    }

    static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(Bundle.module.bundleURL))
    }

    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        let locale = Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en")
        return String(format: string(key), locale: locale, arguments: arguments)
    }
}
