import SwiftUI
import VigieUI

/// The month grid's lengths, read from `components.month-grid` (DESIGN, AD-14). Each fallback repeats the token's
/// DESIGN value, for a theme file that lacks it.
struct MonthGridMetrics: Equatable {
    var cardWidth: CGFloat = 300
    var weekColumn: CGFloat = 22
    var cellWidth: CGFloat = 36
    var cellHeight: CGFloat = 37
    var todayRadius: CGFloat = 0
    var headerHeight: CGFloat = 20
    var navSize: CGFloat = 20
    var weekdayHeight: CGFloat = 16
    var dotSize: CGFloat = 4
    var dotGap: CGFloat = 3
    var maxDots = MonthGrid.defaultMaxDots

    init() {}

    init(theme: Theme) {
        let name = "month-grid"
        func length(_ key: String) -> CGFloat? { theme.componentLength(name, key) }
        cardWidth = length("card-width") ?? cardWidth
        if let columns = Self.columns(theme.component(name, "columns")) {
            weekColumn = columns.week
            cellWidth = columns.cell
        }
        cellHeight = length("cell-height") ?? cellHeight
        // `{rounded.a-day-cell}`: 8px in Chrome Hologram; Twin Metal Tactical has no day-cell radius (square).
        todayRadius = length("a-today-radius") ?? theme.radius(.dayCell)
        headerHeight = length("header-height") ?? headerHeight
        navSize = length("nav-size") ?? navSize
        weekdayHeight = length("weekday-height") ?? weekdayHeight
        dotSize = length("dot-size") ?? dotSize
        dotGap = length("dot-gap") ?? dotGap
        maxDots = length("max-dots").map { Int($0) } ?? maxDots
    }

    /// `22px repeat(7, 36px)` → the week column and the day column widths.
    static func columns(_ raw: String?) -> (week: CGFloat, cell: CGFloat)? {
        guard let raw, let open = raw.firstIndex(of: "(") else { return nil }
        let week = raw[..<open].split(separator: " ").first.flatMap { px(String($0)) }
        let inner = raw[raw.index(after: open)...].prefix { $0 != ")" }
        let parts = inner.split(separator: ",")
        guard let week, parts.count == 2, Int(parts[0].trimmingCharacters(in: .whitespaces)) == 7,
            let cell = px(String(parts[1]))
        else { return nil }
        return (week, cell)
    }

    private static func px(_ raw: String) -> CGFloat? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let number = trimmed.hasSuffix("px") ? String(trimmed.dropLast(2)) : trimmed
        return Double(number).map { CGFloat($0) }
    }

    // Proportions DESIGN states in prose or the mockup draws (`key-calendar-tab.html` `.mg`): not lengths.
    /// Adjacent-month days: `ink-3` at 55%.
    static let adjacentOpacity = 0.55
    /// The selected-day platinum tint and its hairline (graphite in light looks).
    static func selectedFill(_ look: Look) -> Double { look == .dark ? 0.10 : 0.06 }
    static func selectedHairline(_ look: Look) -> Double { look == .dark ? 0.30 : 0.28 }
    /// The 1px platinum line at 28% (30% graphite in light looks) tracing the month's days.
    static func monthLine(_ look: Look) -> Double { look == .dark ? 0.28 : 0.30 }
    /// The today outline and selected tint sit 4px in from the cell sides and 2px from its top and bottom.
    static let markInsetX: CGFloat = 4
    static let markInsetY: CGFloat = 2
    /// The day number starts 6px below the cell top.
    static let numberTop: CGFloat = 6
    /// The header dot is 6px; the dim one is at 60%.
    static let headerDot: CGFloat = 6
    static let headerDotDim = 0.6
    /// The week numbers sit 6px lower than the cell top, level with the day numbers.
    static let weekTop: CGFloat = 6
}

/// What the grid card's controls do.
struct MonthGridActions {
    var previous: @MainActor () -> Void
    var next: @MainActor () -> Void
    var today: @MainActor () -> Void
    var select: @MainActor (Date) -> Void
    var move: @MainActor (Int) -> Void
}

/// The Itsycal-style month card (Story 13.2, DESIGN "Month grid", UX-DR34): `NOVEMBER 2026` with `‹ ● ›`, the
/// weekday initials, the ISO week column, 6 × 7 day cells with one dot per calendar in its EventKit color
/// (UX-DR79), today outlined in the now color, the selected day tinted, the month's days traced by a 1px line,
/// then the legend of the calendars with events this month. Calendar titles are sensitive (AD-24); dots are not.
///
/// Keyboard (when the grid has focus): ←/→ move the selection a day, ↑/↓ a week. EXPERIENCE names no month
/// shortcut, so `‹ ›` stay mouse (and VoiceOver) controls.
struct MonthGridCard: View {
    @Environment(\.vigieTheme) private var theme
    let grid: MonthGrid
    let canReturnToToday: Bool
    let legend: [CalendarInfo]
    let calendar: Calendar
    let locale: Locale
    let actions: MonthGridActions

    var body: some View {
        let metrics = MonthGridMetrics(theme: theme)
        WidgetCard {
            VStack(alignment: .leading, spacing: theme.spacing(.rowGap)) {
                header(metrics)
                days(metrics)
                legendRow
            }
        }
        .frame(width: metrics.cardWidth)
    }

    // MARK: Header

    private var tactical: Bool { theme.defines(.structure) }
    /// The now color: A `iris-1`, C `gold` (outline) with the day number in `gold-text`.
    private var nowOutline: Color { theme.color(tactical ? .gold : .iris1) }
    private var nowText: Color { theme.color(tactical ? .goldText : .iris1) }

    private func header(_ metrics: MonthGridMetrics) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: grid.title)
                .font(theme.font(.readoutValue))
                .tracking(theme.tracking(.readoutValue))
                .foregroundStyle(theme.color(.ink1))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: theme.spacing(.glyphGap))
            navButton("‹", label: "calendar.grid.previous", metrics: metrics, action: actions.previous)
            Button(action: actions.today) {
                Circle()
                    .fill(canReturnToToday ? nowOutline : theme.color(.ink3))
                    .opacity(canReturnToToday ? 1 : MonthGridMetrics.headerDotDim)
                    .frame(width: MonthGridMetrics.headerDot, height: MonthGridMetrics.headerDot)
                    .frame(width: metrics.navSize, height: metrics.navSize)
                    .overlay {
                        if canReturnToToday {
                            Circle().strokeBorder(nowOutline, lineWidth: theme.a11y.hairlineWidth)
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(CalendarText.resource("calendar.grid.today")))
            navButton("›", label: "calendar.grid.next", metrics: metrics, action: actions.next)
        }
        .frame(height: metrics.headerHeight)
    }

    private func navButton(
        _ glyph: String, label: String, metrics: MonthGridMetrics, action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: glyph)
                .font(theme.font(.tab))
                .foregroundStyle(theme.color(.ink2))
                .frame(width: metrics.navSize, height: metrics.navSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(CalendarText.resource(label)))
    }

    // MARK: Days

    private func days(_ metrics: MonthGridMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: metrics.weekColumn, height: metrics.weekdayHeight)
                ForEach(Array(grid.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .font(theme.font(.readoutLabel))
                        .tracking(theme.tracking(.readoutLabel))
                        .foregroundStyle(theme.color(.ink3))
                        .frame(width: metrics.cellWidth, height: metrics.weekdayHeight)
                }
            }
            .accessibilityHidden(true)
            ForEach(grid.weeks) { week in
                HStack(spacing: 0) {
                    Text(week.weekNumber, format: .number)
                        .font(theme.font(.rowStatus))
                        .foregroundStyle(theme.color(.ink3))
                        .padding(.top, MonthGridMetrics.weekTop)
                        .frame(width: metrics.weekColumn, height: metrics.cellHeight, alignment: .topLeading)
                        .accessibilityLabel(
                            Text(verbatim: CalendarText.format("calendar.grid.week", week.weekNumber)))
                    ForEach(week.days) { day in
                        cell(day, metrics)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            MonthOutline(firstColumn: grid.firstColumn, lastColumn: grid.lastColumn, lastRow: grid.lastRow)
                .stroke(
                    theme.borderColor(.ink1, opacity: MonthGridMetrics.monthLine(theme.look)),
                    lineWidth: theme.a11y.hairlineWidth
                )
                .frame(width: metrics.cellWidth * 7, height: metrics.cellHeight * CGFloat(MonthGrid.rowCount))
                .offset(x: metrics.weekColumn, y: metrics.weekdayHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            switch press.key {
            case .leftArrow: actions.move(-1)
            case .rightArrow: actions.move(1)
            case .upArrow: actions.move(-7)
            default: actions.move(7)
            }
            return .handled
        }
    }

    private func cell(_ day: MonthGridDay, _ metrics: MonthGridMetrics) -> some View {
        let mark = RoundedRectangle(cornerRadius: metrics.todayRadius, style: .continuous)
        return Button {
            actions.select(day.date)
        } label: {
            VStack(spacing: metrics.dotGap) {
                Text(day.day, format: .number)
                    .font(theme.font(.rowPrimary))
                    .monospacedDigit()
                    .foregroundStyle(numberColor(day))
                HStack(spacing: metrics.dotGap) {
                    ForEach(day.dots) { dot in
                        Circle().fill(dot.color.color).frame(width: metrics.dotSize, height: metrics.dotSize)
                    }
                }
                .frame(height: metrics.dotSize)
                .opacity(day.isCurrentMonth ? 1 : MonthGridMetrics.adjacentOpacity)
            }
            .padding(.top, MonthGridMetrics.numberTop)
            .frame(width: metrics.cellWidth, height: metrics.cellHeight, alignment: .top)
            .background {
                if day.isSelected {
                    mark.fill(theme.color(.ink1).opacity(MonthGridMetrics.selectedFill(theme.look)))
                        .overlay {
                            mark.strokeBorder(
                                theme.borderColor(.ink1, opacity: MonthGridMetrics.selectedHairline(theme.look)),
                                lineWidth: theme.a11y.hairlineWidth)
                        }
                        .padding(.horizontal, MonthGridMetrics.markInsetX)
                        .padding(.vertical, MonthGridMetrics.markInsetY)
                }
            }
            .overlay {
                if day.isToday {
                    mark.strokeBorder(nowOutline, lineWidth: theme.a11y.hairlineWidth)
                        .padding(.horizontal, MonthGridMetrics.markInsetX)
                        .padding(.vertical, MonthGridMetrics.markInsetY)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: MonthGrid.accessibilityLabel(for: day, calendar: calendar, locale: locale)))
        .accessibilityAddTraits(day.isSelected ? .isSelected : [])
    }

    private func numberColor(_ day: MonthGridDay) -> Color {
        if day.isToday { return nowText }
        if !day.isCurrentMonth { return theme.color(.ink3).opacity(MonthGridMetrics.adjacentOpacity) }
        return theme.color(.ink1)
    }

    // MARK: Legend

    @ViewBuilder private var legendRow: some View {
        if !legend.isEmpty {
            HStack(spacing: theme.spacing(.rowGap)) {
                ForEach(legend) { info in
                    HStack(spacing: theme.spacing(.glyphGap)) {
                        Circle().fill(info.color.color).frame(
                            width: MonthGridMetrics.headerDot, height: MonthGridMetrics.headerDot)
                        Text(verbatim: info.title)
                            .font(theme.font(.kicker))
                            .tracking(theme.tracking(.kicker))
                            .textCase(.uppercase)
                            .foregroundStyle(theme.color(.ink3))
                            .lineLimit(1)
                            .sensitive()
                    }
                }
            }
            .lineLimit(1)
        }
    }
}

/// The 1px line around the month's days: from the first day's column on the first row to the last day's column
/// on `lastRow`, drawn in a frame of 7 × 6 cells.
struct MonthOutline: Shape {
    let firstColumn: Int
    let lastColumn: Int
    let lastRow: Int

    func path(in rect: CGRect) -> Path {
        let w = rect.width / 7
        let h = rect.height / CGFloat(MonthGrid.rowCount)
        let inset: CGFloat = 0.5
        let left = rect.minX + inset
        let right = rect.maxX - inset
        let top = rect.minY + inset
        let bottom = rect.minY + CGFloat(lastRow + 1) * h - inset
        let s = rect.minX + CGFloat(firstColumn) * w + inset
        let e = rect.minX + CGFloat(lastColumn + 1) * w - inset
        var path = Path()
        path.move(to: CGPoint(x: s, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: lastColumn == 6 ? bottom : bottom - h))
        path.addLine(to: CGPoint(x: e, y: lastColumn == 6 ? bottom : bottom - h))
        path.addLine(to: CGPoint(x: e, y: bottom))
        path.addLine(to: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: firstColumn == 0 ? top : top + h))
        path.addLine(to: CGPoint(x: s, y: firstColumn == 0 ? top : top + h))
        path.closeSubpath()
        return path
    }
}
