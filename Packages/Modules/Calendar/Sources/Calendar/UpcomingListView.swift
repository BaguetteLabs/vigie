import ModuleKit
import SwiftUI
import VigieUI

/// The upcoming list's lengths and proportions, as the mockup `key-calendar-tab.html` draws them (`.dh`, `.er`,
/// `.hero`, `.etrack`, `.chipd`). DESIGN has no `components` token for the list; colors and fonts still come
/// from the theme (AD-14).
enum UpcomingMetrics {
    /// The live countdown's tick (hero and Home card only), in seconds.
    static let tick: TimeInterval = 1
    static let headerHeight: CGFloat = 22
    static let rowHeight: CGFloat = 26
    static let rowGap: CGFloat = 9
    static let timeColumn: CGFloat = 42
    static let calendarColumn: CGFloat = 60
    static let relativeColumn: CGFloat = 58
    static let dot: CGFloat = 6
    static let chipDot: CGFloat = 5
    static let chipHeight: CGFloat = 18
    static let heroGap: CGFloat = 14
    static let heroPaddingX: CGFloat = 12
    static let heroPaddingTop: CGFloat = 10
    static let heroPaddingBottom: CGFloat = 18
    static let heroTrackBottom: CGFloat = 8
    static let marker: CGFloat = 5
    static let endTick: CGFloat = 7
    /// The hero's now-color wash and its hairline (dark / light looks).
    static func heroTint(_ look: Look) -> Double { look == .dark ? 0.08 : 0.07 }
    static func heroHairline(_ look: Look) -> Double { look == .dark ? 0.18 : 0.24 }
    /// The 1px track: `ink-1` at 8% (16% in light looks).
    static func track(_ look: Look) -> Double { look == .dark ? 0.08 : 0.16 }
    /// The all-day chip's faint fill and hairline.
    static let chipFill = 0.04
    static let chipHairline = 0.12
}

/// The now color (DESIGN "Upcoming list and event track"): A `iris-1` (cyan) for the countdown and the marker;
/// C `gold-text` for the countdown, `gold` for the marker.
struct UpcomingNowColor {
    let theme: Theme
    private var tactical: Bool { theme.defines(.structure) }
    var text: Color { theme.color(tactical ? .goldText : .iris1) }
    var mark: Color { theme.color(tactical ? .gold : .iris1) }
    /// Twin Metal Tactical draws the now marker as a diamond, Chrome Hologram as a dot.
    var diamond: Bool { tactical }
}

/// What the list's controls do.
struct UpcomingActions {
    var select: @MainActor (String) -> Void
    var join: @MainActor (String) -> Void
    var key: @MainActor (UpcomingList.Key) -> Bool
}

/// The Calendar tab's right card (Story 13.3, UX-DR35): `UPCOMING` with `FROM TODAY` (or the selected day), the
/// day headers with their all-day chips, the hero row for the next event, the other rows, then
/// `+N LATER THIS WEEK`.
///
/// Keyboard (when the list has focus): ↑↓ move the selection through the rows, ↵ opens the selected row's video
/// link (the hero's when nothing is selected). The selection ring is the theme's (`keyboardSelectionRing`).
/// Event titles and calendar names are `.sensitive()` (AD-24); times, countdowns, headers, the track and
/// `JOIN CALL` stay.
struct UpcomingListView: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    let list: UpcomingList
    let selectedID: String?
    /// Fixed instant for tests and previews; nil runs the hero's 1 s clock.
    var now: Date?
    /// The instant the list was built at (rows' relative times).
    let builtAt: Date
    let meta: String
    let actions: UpcomingActions

    var body: some View {
        WidgetCard(
            title: Text(CalendarText.resource("calendar.upcoming.title")), meta: Text(verbatim: meta)
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(list.sections) { section in
                    UpcomingDayHeader(section: section)
                    if section.isEmpty {
                        emptyLine(section)
                    }
                    ForEach(section.rows) { row in
                        if row.isHero, let hero = list.hero {
                            timed { date in
                                UpcomingHeroRow(
                                    hero: hero, now: date, isSelected: selectedID == row.id, actions: actions)
                            }
                        } else {
                            UpcomingRowView(
                                row: row, now: builtAt, isSelected: selectedID == row.id, actions: actions)
                        }
                    }
                }
                Spacer(minLength: 0)
                if let overflow = list.overflowText {
                    Text(verbatim: overflow)
                        .font(theme.font(.kicker))
                        .tracking(theme.tracking(.kicker))
                        .foregroundStyle(theme.color(.ink3))
                        .lineLimit(1)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in
            let key: UpcomingList.Key =
                switch press.key {
                case .upArrow: .up
                case .downArrow: .down
                default: .enter
                }
            return actions.key(key) ? .handled : .ignored
        }
    }

    @ViewBuilder private func timed(@ViewBuilder _ content: @escaping (Date) -> some View) -> some View {
        if let now {
            content(now)
        } else {
            TimelineView(.periodic(from: .now, by: UpcomingMetrics.tick)) { context in content(context.date) }
        }
    }

    @ViewBuilder private func emptyLine(_ section: UpcomingSection) -> some View {
        Group {
            if section.isToday {
                Text(VigieCopy.noEventsToday.label)
            } else {
                Text(CalendarText.resource("calendar.upcoming.noEvents"))
            }
        }
        .font(theme.font(.kicker))
        .tracking(theme.tracking(.kicker))
        .textCase(.uppercase)
        .foregroundStyle(theme.color(.ink3))
        .frame(height: UpcomingMetrics.rowHeight)
    }
}

/// `TODAY · WED 04 NOV` with the all-day chips on the right.
struct UpcomingDayHeader: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    let section: UpcomingSection

    var body: some View {
        HStack(spacing: theme.spacing(.glyphGap)) {
            Text(verbatim: section.header)
                .font(theme.font(.kicker))
                .tracking(theme.tracking(.kicker))
                .foregroundStyle(theme.color(section.isToday ? .ink2 : .ink3))
                .lineLimit(1)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: theme.spacing(.glyphGap))
            ForEach(section.chips) { chip in
                UpcomingAllDayChip(chip: chip)
            }
        }
        .frame(height: UpcomingMetrics.headerHeight)
    }
}

/// An all-day event: a capsule with its calendar dot, title (sensitive) and `ALL DAY`.
struct UpcomingAllDayChip: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    let chip: UpcomingChip

    var body: some View {
        let shape = Capsule(style: .continuous)
        HStack(spacing: theme.spacing(.glyphGap)) {
            Circle().fill(chip.color?.color ?? theme.color(.ink3))
                .frame(width: UpcomingMetrics.chipDot, height: UpcomingMetrics.chipDot)
            Text(verbatim: chip.title)
                .font(theme.font(.rowStatus))
                .foregroundStyle(theme.color(.ink1))
                .lineLimit(1)
                .sensitive()
            Text(CalendarText.resource("calendar.upcoming.allDay"))
                .font(theme.font(.readoutLabel))
                .tracking(theme.tracking(.readoutLabel))
                .textCase(.uppercase)
                .foregroundStyle(theme.color(.ink3))
                .lineLimit(1)
        }
        .padding(.horizontal, theme.spacing(.glyphGap))
        .frame(height: UpcomingMetrics.chipHeight)
        .background(theme.color(.ink1).opacity(UpcomingMetrics.chipFill), in: shape)
        .overlay {
            shape.strokeBorder(
                theme.borderColor(.ink1, opacity: UpcomingMetrics.chipHairline), lineWidth: theme.a11y.hairlineWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
    }

    private var label: String {
        let label = UpcomingList.accessibilityLabel(chip)
        return privacyActive ? PrivacyMask.scrub(label, removing: [chip.title, chip.calendarName]) : label
    }
}

/// `JOIN CALL ↵`: the accent inline chip as a button.
struct UpcomingJoinButton: View {
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            InlineChip(text: CalendarText.resource("calendar.upcoming.join"), tone: .accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(CalendarText.resource("calendar.upcoming.a11y.joinButton")))
    }
}

/// The service tag after a title (`MEET`, `ZOOM`, `TEAMS`).
struct UpcomingServiceTag: View {
    @Environment(\.vigieTheme) private var theme
    let service: VideoService

    var body: some View {
        Text(CalendarText.resource("calendar.service.\(service.rawValue)"))
            .font(theme.font(.code))
            .foregroundStyle(theme.color(.ink3))
            .lineLimit(1)
            .fixedSize()
    }
}

/// The next event: big time, title, countdown in the now color, `15:30–16:15 ● WORK`, `JOIN CALL ↵` when linked,
/// and the event track along the bottom.
struct UpcomingHeroRow: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    let hero: UpcomingHero
    let now: Date
    let isSelected: Bool
    let actions: UpcomingActions

    var body: some View {
        let row = hero.row
        let nowColor = UpcomingNowColor(theme: theme)
        let shape = RoundedRectangle(cornerRadius: theme.radius(.row), style: .continuous)
        HStack(spacing: UpcomingMetrics.heroGap) {
            Text(verbatim: row.startText)
                .font(theme.font(.numeralBig))
                .monospacedDigit()
                .foregroundStyle(theme.color(.ink1))
                .lineLimit(1)
                .fixedSize()
            VStack(alignment: .leading, spacing: theme.spacing(.glyphGap) / 2) {
                Text(verbatim: row.title)
                    .font(theme.font(.rowPrimary))
                    .foregroundStyle(theme.color(.ink1))
                    .lineLimit(1)
                    .sensitive()
                Text(verbatim: UpcomingList.countdown(start: row.start, now: now))
                    .font(theme.font(.kicker))
                    .tracking(theme.tracking(.kicker))
                    .foregroundStyle(nowColor.text)
                    .lineLimit(1)
                HStack(spacing: theme.spacing(.glyphGap)) {
                    Text(verbatim: CalendarText.format("calendar.upcoming.range", row.startText, row.endText))
                        .font(theme.font(.rowStatus))
                        .foregroundStyle(theme.color(.ink3))
                        .lineLimit(1)
                        .fixedSize()
                    // No service tag here: `JOIN CALL ↵` already says the event has a call, and the line
                    // keeps room for the calendar name.
                    if !row.calendarName.isEmpty {
                        Circle().fill(row.color?.color ?? theme.color(.ink3))
                            .frame(width: UpcomingMetrics.chipDot, height: UpcomingMetrics.chipDot)
                        Text(verbatim: row.calendarName)
                            .font(theme.font(.kicker))
                            .tracking(theme.tracking(.kicker))
                            .textCase(.uppercase)
                            .foregroundStyle(theme.color(.ink3))
                            .lineLimit(1)
                            .layoutPriority(1)
                            .sensitive()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.canJoin {
                UpcomingJoinButton { actions.join(row.id) }
            }
        }
        .padding(.horizontal, UpcomingMetrics.heroPaddingX)
        .padding(.top, UpcomingMetrics.heroPaddingTop)
        .padding(.bottom, UpcomingMetrics.heroPaddingBottom)
        .overlay(alignment: .bottom) {
            EventTrack(
                fraction: UpcomingList.trackFraction(now: now, windowStart: hero.windowStart, start: row.start)
            )
            .padding(.horizontal, UpcomingMetrics.heroPaddingX)
            .padding(.bottom, UpcomingMetrics.heroTrackBottom)
        }
        .background(nowColor.mark.opacity(UpcomingMetrics.heroTint(theme.look)), in: shape)
        .overlay {
            shape.strokeBorder(
                nowColor.mark.opacity(UpcomingMetrics.heroHairline(theme.look)), lineWidth: theme.a11y.hairlineWidth)
        }
        .keyboardSelectionRing(isSelected: isSelected)
        .contentShape(shape)
        .onTapGesture { actions.select(row.id) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: upcomingLabel(row, now: now, privacy: privacyActive)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Another event: time · calendar dot · title (+ service tag) · calendar · relative time. The selected row with
/// a link shows `JOIN CALL ↵` in place of its relative time; rows without a link never show it.
struct UpcomingRowView: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    let row: UpcomingRow
    let now: Date
    let isSelected: Bool
    let actions: UpcomingActions

    var body: some View {
        HStack(spacing: UpcomingMetrics.rowGap) {
            Text(verbatim: row.startText)
                .font(theme.font(.rowPrimary))
                .monospacedDigit()
                .foregroundStyle(theme.color(.ink1))
                .lineLimit(1)
                .frame(width: UpcomingMetrics.timeColumn, alignment: .leading)
            Circle().fill(row.color?.color ?? theme.color(.ink3))
                .frame(width: UpcomingMetrics.dot, height: UpcomingMetrics.dot)
            HStack(spacing: theme.spacing(.glyphGap)) {
                Text(verbatim: row.title)
                    .font(theme.font(.rowPrimary))
                    .foregroundStyle(theme.color(.ink1))
                    .lineLimit(1)
                    .sensitive()
                if let service = row.service { UpcomingServiceTag(service: service) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: row.calendarName)
                .font(theme.font(.kicker))
                .tracking(theme.tracking(.kicker))
                .textCase(.uppercase)
                .foregroundStyle(theme.color(.ink3))
                .lineLimit(1)
                .sensitive()
                .frame(width: UpcomingMetrics.calendarColumn, alignment: .leading)
            Group {
                if isSelected && row.canJoin {
                    UpcomingJoinButton { actions.join(row.id) }
                } else {
                    Text(verbatim: UpcomingList.relative(row, now: now))
                        .font(theme.font(.rowStatus))
                        .foregroundStyle(theme.color(.ink2))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: UpcomingMetrics.relativeColumn, alignment: .trailing)
        }
        .frame(height: UpcomingMetrics.rowHeight)
        .rowHoverBrighten()
        .keyboardSelectionRing(isSelected: isSelected)
        .onTapGesture { actions.select(row.id) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: upcomingLabel(row, now: now, privacy: privacyActive)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A row's VoiceOver label, with its title and calendar name scrubbed in Privacy mode.
func upcomingLabel(_ row: UpcomingRow, now: Date, privacy: Bool) -> String {
    let label = UpcomingList.accessibilityLabel(row, now: now)
    return privacy ? PrivacyMask.scrub(label, removing: [row.title, row.calendarName]) : label
}

/// The event track (DESIGN "Upcoming list and event track"): a 1px line from the track's start (left) to the
/// event (right, a 1 × 7 tick in `ink-1`), with the now marker at `fraction`: A a cyan dot, C a gold diamond.
/// Shared by the hero row and the Home calendar card. Decorative: the countdown carries the meaning.
struct EventTrack: View {
    @Environment(\.vigieTheme) private var theme
    let fraction: Double

    var body: some View {
        let nowColor = UpcomingNowColor(theme: theme)
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = min(max(0, width * fraction), width)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(theme.color(.ink1).opacity(UpcomingMetrics.track(theme.look)))
                    .frame(height: theme.a11y.hairlineWidth)
                Rectangle()
                    .fill(theme.color(.ink1))
                    .frame(width: theme.a11y.hairlineWidth, height: UpcomingMetrics.endTick)
                    .offset(x: width - theme.a11y.hairlineWidth)
                Group {
                    if nowColor.diamond {
                        Rectangle().fill(nowColor.mark).rotationEffect(.degrees(45))
                    } else {
                        Circle().fill(nowColor.mark)
                    }
                }
                .frame(width: UpcomingMetrics.marker, height: UpcomingMetrics.marker)
                .offset(x: x - UpcomingMetrics.marker / 2)
            }
            .frame(width: width, height: UpcomingMetrics.endTick)
        }
        .frame(height: UpcomingMetrics.endTick)
        .accessibilityHidden(true)
    }
}
