import Foundation
import ModuleKit
import VigieUI

/// Every text the Time tab and the Timer-end alert show, from the Time catalog (Story 20.2).
enum TimeFormat {
    /// `14:52`.
    static func clock(_ date: Date, calendar: Calendar) -> String {
        formatter(TimeText.string("time.timeFormat"), calendar: calendar).string(from: date)
    }

    /// `FRI 14 NOV`.
    static func day(_ date: Date, calendar: Calendar) -> String {
        formatter(TimeText.string("time.dateFormat"), calendar: calendar).string(from: date)
            .uppercased(with: TimeText.catalogLocale)
    }

    /// Remaining time, rounded up to the second: `3:06`, `1:04:10`, `7D 23H`.
    static func value(_ remaining: TimeInterval) -> String {
        let total = Int(max(0, remaining).rounded(.up))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if days > 0 { return TimeText.format("time.value.days", days, hours) }
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func minutes(_ item: TimeItem) -> Int {
        Int(((item.duration ?? 0) / 60).rounded())
    }

    /// `5 MIN TIMER`, `COUNTDOWN · FRI 14 NOV · 14:00`.
    static func kind(_ item: TimeItem, calendar: Calendar) -> String {
        switch item.kind {
        case .timer: TimeText.format("time.kind.timer", minutes(item))
        case .countdown(let date):
            TimeText.format("time.kind.countdown", day(date, calendar: calendar), clock(date, calendar: calendar))
        }
    }

    /// `ENDS 14:52`, `IN 191 H` (a Countdown more than a day away), `PAUSED`, `ENDED 14:48`.
    static func subline(_ item: TimeItem, now: Date, calendar: Calendar) -> String {
        switch item.state {
        case .paused: return TimeText.string("time.subline.paused")
        case .ended(let at): return TimeText.format("time.subline.ended", clock(at, calendar: calendar))
        case .running:
            let remaining = item.remaining(now: now)
            if !item.isTimer, remaining >= 86_400 {
                return TimeText.format("time.subline.inHours", Int(remaining / 3600))
            }
            return TimeText.format("time.subline.ends", clock(item.endsAt, calendar: calendar))
        }
    }

    static func controls(_ item: TimeItem) -> [TimeRowModel.Control] {
        switch item.state {
        case .ended: [.dismiss]
        case .paused: [.resume, .reset, .remove]
        case .running: item.isTimer ? [.pause, .reset, .remove] : [.remove]
        }
    }

    static func visual(_ item: TimeItem, now: Date) -> TimeRowModel.Visual {
        if item.isEnded { return .ended }
        if item.isTimer { return .ring(fractionLeft: item.fractionLeft(now: now), paused: item.state == .paused) }
        return .track(fractionElapsed: 1 - item.fractionLeft(now: now))
    }

    static func row(_ item: TimeItem, now: Date, calendar: Calendar) -> TimeRowModel {
        TimeRowModel(
            id: item.id, label: item.label, kind: kind(item, calendar: calendar),
            value: value(item.remaining(now: now)), subline: subline(item, now: now, calendar: calendar),
            visual: visual(item, now: now), controls: controls(item), isEnded: item.isEnded,
            accessibilityLabel: accessibilityLabel(item, now: now, calendar: calendar))
    }

    // MARK: VoiceOver

    /// "Tea, 5 minute timer, 3 minutes, 12 seconds left, ends 14:52, paused"; ended: "Tea, 5 minute timer,
    /// ended 14:48".
    static func accessibilityLabel(_ item: TimeItem, now: Date, calendar: Calendar) -> String {
        var parts = [item.label, accessibilityKind(item, calendar: calendar)]
        if case .ended(let at) = item.state {
            parts.append(TimeText.format("time.a11y.ended", clock(at, calendar: calendar)))
        } else {
            let remaining = item.remaining(now: now)
            parts.append(TimeText.format("time.a11y.left", spoken(remaining)))
            parts.append(TimeText.format("time.a11y.ends", clock(item.effectiveEnd(now: now), calendar: calendar)))
            if item.state == .paused { parts.append(TimeText.string("time.a11y.paused")) }
        }
        return parts.dropFirst().reduce(parts[0]) { TimeText.format("time.a11y.join", $0, $1) }
    }

    static func accessibilityKind(_ item: TimeItem, calendar: Calendar) -> String {
        switch item.kind {
        case .timer: TimeText.format("time.a11y.timerKind", minutes(item))
        case .countdown(let date):
            TimeText.format(
                "time.a11y.countdownKind",
                formatter(TimeText.string("time.a11y.dateFormat"), calendar: calendar).string(from: date),
                clock(date, calendar: calendar))
        }
    }

    /// "3 minutes, 12 seconds", "1 hour, 4 minutes, 10 seconds"; days and hours only from a day up.
    static func spoken(_ remaining: TimeInterval) -> String {
        let seconds = Int64(max(0, remaining).rounded(.up))
        let units: Set<Duration.UnitsFormatStyle.Unit> =
            seconds >= 86_400 ? [.days, .hours] : [.hours, .minutes, .seconds]
        return Duration.seconds(seconds).formatted(
            .units(allowed: units, width: .wide, zeroValueUnits: .hide).locale(TimeText.catalogLocale))
    }

    // MARK: Alert

    /// `Tea / 5 min`, `Release 0.3 / countdown`.
    static func alertTitle(_ item: TimeItem) -> String {
        let length =
            item.isTimer
            ? TimeText.format("time.alert.minutes", minutes(item)) : TimeText.string("time.alert.countdown")
        return TimeText.format("time.alert.title", item.label, length)
    }

    /// `Started 14:43 · ended 14:48`.
    static func alertBody(_ item: TimeItem, calendar: Calendar) -> String {
        TimeText.format(
            "time.alert.body", clock(item.startedAt, calendar: calendar), clock(item.endsAt, calendar: calendar))
    }

    // MARK: Breaks (Story 20.4)

    static func wholeMinutes(_ seconds: TimeInterval) -> Int { max(0, Int((seconds / 60).rounded())) }

    /// `Time for a break / 5 min break` (UX-DR90's `<cycles> / <length> min break`, with the reminder's name).
    static func breakTitle(length: TimeInterval) -> String {
        TimeText.format(
            "time.alert.title", TimeText.string("time.break.alert.name"),
            TimeText.format("time.break.length", wholeMinutes(length)))
    }

    /// `Focused 55 min since 13:05`, `Focused 1 h 40 min since 13:05`.
    static func breakBody(worked: TimeInterval, since: Date, calendar: Calendar) -> String {
        TimeText.format("time.break.alert.body", focusDuration(worked), clock(since, calendar: calendar))
    }

    /// `55 min`, `1 h 40 min`, `2 h`.
    static func focusDuration(_ seconds: TimeInterval) -> String {
        let minutes = wholeMinutes(seconds)
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return TimeText.format("time.duration.minutes", rest) }
        if rest == 0 { return TimeText.format("time.duration.hours", hours) }
        return TimeText.format("time.duration.hoursMinutes", hours, rest)
    }

    /// "Break due, 5 minute break".
    static func breakDueAccessibility(length: TimeInterval) -> String {
        TimeText.format("time.break.a11y.due", wholeMinutes(length))
    }

    static func breakDueRow(id: UUID, length: TimeInterval) -> TimeRowModel {
        TimeRowModel(
            id: id, label: TimeText.string("time.break.label"),
            kind: TimeText.format("time.break.kind", wholeMinutes(length)), value: value(length),
            subline: TimeText.string("time.break.subline.due"), visual: .breakDue,
            controls: [.startBreak, .snooze, .skip], isEnded: false,
            accessibilityLabel: breakDueAccessibility(length: length))
    }

    static func breakRunningRow(
        id: UUID, length: TimeInterval, endsAt: Date, now: Date, calendar: Calendar
    ) -> TimeRowModel {
        let remaining = max(0, endsAt.timeIntervalSince(now))
        let fraction = length > 0 ? remaining / length : 0
        let label = TimeText.string("time.break.label")
        return TimeRowModel(
            id: id, label: label, kind: TimeText.format("time.break.kind", wholeMinutes(length)),
            value: value(remaining), subline: TimeText.format("time.subline.ends", clock(endsAt, calendar: calendar)),
            visual: .breakRing(fractionLeft: fraction), controls: [.skip], isEnded: false,
            accessibilityLabel: TimeText.format(
                "time.break.a11y.running", spoken(remaining), clock(endsAt, calendar: calendar)))
    }

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = TimeText.catalogLocale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
