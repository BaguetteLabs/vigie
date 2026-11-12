import ModuleKit
import SwiftUI
import VigieUI

/// What the Home calendar card shows (Story 13.3).
public enum CalendarHomeCardContent: Hashable, Sendable {
    /// Before the first access check: an empty card.
    case checking
    /// Access missing: `CALENDAR ACCESS` with "Vigie can't read your calendars"; a click opens the tab, whose
    /// setup card has the buttons.
    case setup
    /// No timed event left today: `NO EVENTS TODAY`.
    case noEventsToday
    /// Today's running or next event, with its track.
    case next(UpcomingHero)
}

extension CalendarModule {
    /// The Home calendar card (Story 13.3, DESIGN "Upcoming list and event track": "the same track serves the Home
    /// calendar card"): today's next event with its time, title, countdown, the event track and `JOIN CALL ↵`
    /// when it has a link. The card is offered whatever the access, so Settings › Home can list it; without
    /// access it shows the setup copy. The Home grid's button around the card opens the Calendar tab.
    public func homeCard() -> AnyView? {
        AnyView(CalendarHomeCardView(module: self))
    }

    /// The card's content at `now` (default: the module's clock). Always from today, whatever day the grid has
    /// selected.
    public func homeCardContent(locale: Locale = .current, now date: Date? = nil) -> CalendarHomeCardContent {
        switch access {
        case .unknown: return .checking
        case .missing: return .setup
        case .granted:
            guard let hero = todayUpcomingList(locale: locale, now: date).hero else { return .noEventsToday }
            return .next(hero)
        }
    }
}

/// The Home calendar card in the 222 × 138 cell: `UPCOMING` with today's date as meta, then the next event's
/// time (time-value type) and `JOIN CALL ↵`, its title (sensitive) with the calendar dot, the countdown in the
/// now color, and the event track. The countdown and track tick each second.
struct CalendarHomeCardView: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.privacyActive) private var privacyActive
    let module: CalendarModule
    /// Fixed instant for tests; nil runs the 1 s clock.
    var now: Date?

    var body: some View {
        if let now {
            card(now)
        } else {
            TimelineView(.periodic(from: .now, by: UpcomingMetrics.tick)) { context in card(context.date) }
        }
    }

    private func card(_ date: Date) -> some View {
        WidgetCard(
            title: Text(CalendarText.resource("calendar.upcoming.title")),
            meta: Text(verbatim: UpcomingList.dayText(date, calendar: module.calendar, locale: locale))
        ) {
            switch module.homeCardContent(locale: locale, now: date) {
            case .checking:
                Color.clear
            case .setup:
                EmptyStateBlock(label: VigieCopy.calendarAccess.topic, sentence: VigieCopy.calendarAccess.title)
            case .noEventsToday:
                EmptyStateBlock(VigieCopy.noEventsToday)
            case .next(let hero):
                next(hero, now: date)
            }
        }
    }

    private func next(_ hero: UpcomingHero, now: Date) -> some View {
        let row = hero.row
        let nowColor = UpcomingNowColor(theme: theme)
        return VStack(alignment: .leading, spacing: theme.spacing(.glyphGap) / 2) {
            HStack(alignment: .center, spacing: theme.spacing(.glyphGap)) {
                Text(verbatim: row.startText)
                    .font(theme.font(.timeValue))
                    .monospacedDigit()
                    .foregroundStyle(theme.color(.ink1))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if row.canJoin {
                    UpcomingJoinButton { module.joinCall(row.id) }
                }
            }
            HStack(spacing: theme.spacing(.glyphGap)) {
                Circle().fill(row.color?.color ?? theme.color(.ink3))
                    .frame(width: UpcomingMetrics.dot, height: UpcomingMetrics.dot)
                Text(verbatim: row.title)
                    .font(theme.font(.rowPrimary))
                    .foregroundStyle(theme.color(.ink1))
                    .lineLimit(1)
                    .sensitive()
            }
            Text(verbatim: UpcomingList.countdown(start: row.start, now: now))
                .font(theme.font(.kicker))
                .tracking(theme.tracking(.kicker))
                .foregroundStyle(nowColor.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            EventTrack(fraction: UpcomingList.trackFraction(now: now, windowStart: hero.windowStart, start: row.start))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: upcomingLabel(row, now: now, privacy: privacyActive)))
    }
}
