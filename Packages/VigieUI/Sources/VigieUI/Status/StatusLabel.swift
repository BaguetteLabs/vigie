import Foundation
import SwiftUI

/// The state of an agent session (SPEC §6, EXPERIENCE "Session states").
public enum SessionStatus: String, Sendable, CaseIterable, Codable {
    case idle
    case working
    case done
    case blocked
    case failed
    /// Neutral: no event for a while. Its time is time since the last event.
    case stale

    /// The theme color role for this status. Stale is neutral and uses `ink-3`.
    public var colorRole: ColorRole {
        switch self {
        case .idle: .statusIdle
        case .working: .statusWorking
        case .done: .statusDone
        case .blocked: .statusBlocked
        case .failed: .statusFailed
        case .stale: .ink3
        }
    }

    var labelKey: String { "status.\(rawValue)" }
    var accessibilityKey: String { "a11y.status.\(rawValue)" }
}

/// The state of a run: a `vigie run` process session, or a module result on the OK / WARN / DOWN scale.
public enum RunStatus: Sendable, Equatable, Hashable {
    /// Process-only session, no time (neutral).
    case running
    /// A run that exited non-zero, with its exit code.
    case failedExit(Int32)
    case ok
    case warn
    case down

    public init(_ level: StatusLevel) {
        switch level {
        case .ok: self = .ok
        case .warn: self = .warn
        case .down: self = .down
        }
    }

    /// The level on the status-vocabulary scale, when the status is one.
    public var level: StatusLevel? {
        switch self {
        case .ok: .ok
        case .warn: .warn
        case .down: .down
        case .running, .failedExit: nil
        }
    }

    /// The theme color role for the label text. `quota-warning-text` falls back to `quota-warning` in looks
    /// that do not define it (dark), so WARN text is text-safe in light looks (DESIGN "Contrast").
    public var colorRole: ColorRole {
        switch self {
        case .running: .ink3
        case .failedExit: .statusFailed
        case .ok: .statusIdle
        case .warn: .quotaWarningText
        case .down: .statusFailed
        }
    }
}

/// What follows a run status after the `·` (UX-DR82, UX-DR103).
public enum StatusQualifier: Sendable, Equatable, Hashable {
    /// `CHECKED 2 MIN AGO`.
    case checkedAgo(Duration)
    /// `SINCE 14:44`; on DOWN it reads `DOWN SINCE 14:44` (EXPERIENCE copy table).
    case since(Date)
    /// Free detail from the module or script (`OK · UP`), shown as given.
    case detail(String)
}

/// Builds every status label from the VigieUI String Catalog (AD-15, UX-DR43, UX-DR103).
///
/// Session labels: `IDLE`, `WORKING · 14M`, `DONE · 1M`, `BLOCKED · 12M`, `FAILED · 41M`, `STALE · 18M`.
/// Elapsed time: minutes `14M`, then hours with two-digit minutes `1H52` (as in `RESET 16:40 · IN 1H52`),
/// whole hours `2H`, then days `1D 18H` (as in the Shelf `1D 18H LEFT`).
/// Run labels: `RUNNING`, `FAILED · EXIT 3`, `OK · CHECKED 2 MIN AGO`, `WARN`, `DOWN SINCE 14:44`.
public struct StatusLabelFormatter: Sendable, Equatable {
    /// Time zone for clock times (`SINCE 14:44`).
    public var timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    // MARK: Sessions

    /// `IDLE` (never timed), `WORKING`, or `WORKING · 14M` when `elapsed` is given.
    public func label(for status: SessionStatus, elapsed: Duration? = nil) -> String {
        let word = L10n.string(status.labelKey)
        guard status != .idle, let elapsed else { return word }
        return Self.joined(word, self.elapsed(elapsed))
    }

    // MARK: Runs and levels

    public func label(for status: RunStatus, qualifier: StatusQualifier? = nil) -> String {
        let word: String
        switch status {
        case .running: word = L10n.string("status.running")
        case .failedExit(let code): word = L10n.format("status.failedExit", Int(code))
        case .ok: word = L10n.string("status.ok")
        case .warn: word = L10n.string("status.warn")
        case .down:
            if case .since(let date) = qualifier { return L10n.format("status.down.since", clock(date)) }
            word = L10n.string("status.down")
        }
        guard let qualifier else { return word }
        return Self.joined(word, self.qualifier(qualifier))
    }

    public func label(for level: StatusLevel, qualifier: StatusQualifier? = nil) -> String {
        label(for: RunStatus(level), qualifier: qualifier)
    }

    // MARK: Parts

    /// Compact elapsed time (`14M`, `1H52`, `2H`, `1D 18H`); under a minute reads `0M`.
    public func elapsed(_ duration: Duration) -> String {
        let minutes = Self.wholeMinutes(duration)
        if minutes < 60 { return L10n.format("status.elapsed.minutes", minutes) }
        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest == 0
                ? L10n.format("status.elapsed.hours", hours)
                : L10n.format("status.elapsed.hoursMinutes", hours, rest)
        }
        let days = hours / 24
        let restHours = hours % 24
        return restHours == 0
            ? L10n.format("status.elapsed.days", days)
            : L10n.format("status.elapsed.daysHours", days, restHours)
    }

    /// The qualifier text alone: `CHECKED 2 MIN AGO`, `SINCE 14:44`, or the detail as given.
    public func qualifier(_ qualifier: StatusQualifier) -> String {
        switch qualifier {
        case .checkedAgo(let duration):
            let minutes = Self.wholeMinutes(duration)
            if minutes < 1 { return L10n.string("status.qualifier.checkedUnderMinute") }
            if minutes < 60 { return L10n.format("status.qualifier.checkedMinutesAgo", minutes) }
            return L10n.format("status.qualifier.checkedAgo", elapsed(duration))
        case .since(let date):
            return L10n.format("status.qualifier.since", clock(date))
        case .detail(let text):
            return text
        }
    }

    /// `14:44` (24-hour clock, as everywhere in Vigie).
    func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let style = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: timeZone, calendar: calendar)
        return style.format(date)
    }

    static func joined(_ head: String, _ tail: String) -> String {
        L10n.format("status.withDetail", head, tail)
    }

    static func wholeMinutes(_ duration: Duration) -> Int {
        max(0, Int(duration.components.seconds / 60))
    }
}

/// A status label in `row-status` type, in the status hue (`ink-3` for neutral states).
public struct StatusLabel: View {
    private enum Content: Equatable {
        case session(SessionStatus, Duration?)
        case run(RunStatus, StatusQualifier?)
    }

    @Environment(\.vigieTheme) private var theme
    @Environment(\.timeZone) private var timeZone
    private let content: Content

    /// A session label, e.g. `BLOCKED · 12M`.
    public init(_ status: SessionStatus, elapsed: Duration? = nil) {
        content = .session(status, elapsed)
    }

    /// A run or level label, e.g. `FAILED · EXIT 3`, `OK · CHECKED 2 MIN AGO`.
    public init(_ status: RunStatus, qualifier: StatusQualifier? = nil) {
        content = .run(status, qualifier)
    }

    public var body: some View {
        let formatter = StatusLabelFormatter(timeZone: timeZone)
        let text: String
        let role: ColorRole
        switch content {
        case .session(let status, let elapsed):
            text = formatter.label(for: status, elapsed: elapsed)
            role = status.colorRole
        case .run(let status, let qualifier):
            text = formatter.label(for: status, qualifier: qualifier)
            role = status.colorRole
        }
        return Text(verbatim: text)
            .font(theme.font(.rowStatus))
            .tracking(theme.tracking(.rowStatus))
            .foregroundStyle(theme.color(role))
            .lineLimit(1)
    }
}

#Preview("Status labels · dark") {
    StatusLabelPreview(look: .dark)
}

#Preview("Status labels · light") {
    StatusLabelPreview(look: .light)
}

private struct StatusLabelPreview: View {
    let look: Look

    var body: some View {
        let theme = PreviewThemes.theme(look)
        VStack(alignment: .leading, spacing: theme.spacing(.rowGap)) {
            StatusLabel(.idle)
            StatusLabel(.working, elapsed: PreviewSamples.minutes(14))
            StatusLabel(.done, elapsed: PreviewSamples.minutes(1))
            StatusLabel(.blocked, elapsed: PreviewSamples.minutes(12))
            StatusLabel(.failed, elapsed: PreviewSamples.minutes(41))
            StatusLabel(.stale, elapsed: PreviewSamples.minutes(18))
            StatusLabel(.running)
            StatusLabel(.failedExit(3))
            StatusLabel(.ok, qualifier: .checkedAgo(PreviewSamples.minutes(2)))
            StatusLabel(.warn)
            StatusLabel(.down, qualifier: .since(.now))
        }
        .padding(theme.spacing(.gridPaddingX))
        .background(theme.color(.surfacePanel))
        .vigieTheme(theme)
    }
}
