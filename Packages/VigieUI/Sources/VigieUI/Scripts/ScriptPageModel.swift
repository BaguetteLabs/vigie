import Foundation
import ModuleKit

// View models of the script page (Story 12.11, DESIGN "Script page", UX-DR86, UX-DR87). Plain `Sendable` values
// built by the integrations module from a script's definition, run state and state on this Mac; the page only
// renders them. Times count from an injected `now`. Script-provided text (the hero's output text, the
// documentation) is hidden under Privacy mode with no opt-out (AD-24); run times, durations, exit codes, the
// runtime and the file name stay.

/// The widget type a page's hero shows, for the hero header (`STATUS WIDGET · EVERY 1M`).
public enum ScriptWidgetKind: String, Sendable, Equatable, CaseIterable {
    case status
    case number
    case text

    /// `STATUS WIDGET`, `NUMBER WIDGET`, `TEXT WIDGET`.
    public var label: String { L10n.string("script.page.kind.\(rawValue)") }
}

/// How one run ended, as the runs card reads it (UX-DR87).
public enum ScriptRunResult: Sendable, Equatable {
    /// The run succeeded: `OK`.
    case ok
    /// A non-zero exit: `EXIT 3`.
    case exit(Int32)
    /// Killed at the timeout: `TIMED OUT · 30S`.
    case timedOut(seconds: Int)
    /// Any other failure, as core copy from the module (`INVALID OUTPUT`, `RUNTIME NOT FOUND`).
    case failure(String)

    public var label: String {
        switch self {
        case .ok: L10n.string("script.page.run.ok")
        case .exit(let code): L10n.format("script.page.run.exit", Int(code))
        case .timedOut(let seconds): L10n.format("script.page.run.timedOut", seconds)
        case .failure(let text): text
        }
    }

    public var isFailure: Bool { self != .ok }
}

/// One row of the runs list: time, duration, result.
public struct ScriptRunRow: Sendable, Equatable {
    public var startedAt: Date
    public var duration: Duration
    public var result: ScriptRunResult
    /// The exit code when the process exited on its own (`exit 0` on the last-run line).
    public var exitCode: Int32?

    public init(startedAt: Date, duration: Duration, result: ScriptRunResult, exitCode: Int32? = nil) {
        self.startedAt = startedAt
        self.duration = duration
        self.result = result
        self.exitCode = exitCode
    }

    /// `14:46:12`.
    public func timeText(timeZone: TimeZone = .current) -> String {
        ScriptPageFormat.clock(startedAt, timeZone: timeZone)
    }

    /// `0.4 s`.
    public var durationText: String { ScriptPageFormat.duration(duration) }

    /// "14:46:12, 0.4 s, EXIT 3": time, duration, result.
    public func accessibilityLabel(timeZone: TimeZone = .current) -> String {
        [durationText, result.label].reduce(timeText(timeZone: timeZone)) { AccessibilityLabel.joined($0, $1) }
    }
}

/// The 212px runs card (DESIGN "Script page" › Runs): `RUNS` (runtime), `LAST RUN` (time, `exit 0 · 0.4 s`),
/// `NEXT RUN` (time, `in 38 s · every 1 m`), `TIMEOUT`, `SOURCE` (file name, folder), then the runs list.
public struct ScriptRunsCardModel: Sendable, Equatable {
    /// The front matter's `runtime` (`bash`, `python3`).
    public var runtime: String
    public var interval: Duration
    /// `min(interval, 30 s)` (Story 12.4).
    public var timeout: Duration
    /// `site-status.md`.
    public var fileName: String
    /// The file's folder as shown (`~/Vigie/modules/`), or nil.
    public var folder: String?
    /// The latest runs, newest first.
    public var runs: [ScriptRunRow]
    /// When the next scheduled run starts; nil while running, not confirmed or stopped.
    public var nextRunAt: Date?
    /// A run is in progress.
    public var isRunning: Bool

    public init(
        runtime: String, interval: Duration, timeout: Duration, fileName: String, folder: String? = nil,
        runs: [ScriptRunRow] = [], nextRunAt: Date? = nil, isRunning: Bool = false
    ) {
        self.runtime = runtime
        self.interval = interval
        self.timeout = timeout
        self.fileName = fileName
        self.folder = folder
        self.runs = runs
        self.nextRunAt = nextRunAt
        self.isRunning = isRunning
    }

    public var lastRun: ScriptRunRow? { runs.first }

    /// The last run's sub-line: `exit 0 · 0.4 s`, or the failure and the duration (`TIMED OUT · 30S · 30 s`).
    public var lastRunDetail: String? {
        guard let run = lastRun else { return nil }
        let head = run.exitCode.map { L10n.format("script.page.lastRun.exit", Int($0)) } ?? run.result.label
        return StatusLabelFormatter.joined(head, run.durationText)
    }

    /// `14:47:12`, `RUNNING` while a run is in progress, `NOT SCHEDULED` otherwise.
    public func nextRunText(timeZone: TimeZone = .current) -> String {
        if isRunning { return L10n.string("script.page.nextRun.running") }
        guard let nextRunAt else { return L10n.string("script.page.nextRun.none") }
        return ScriptPageFormat.clock(nextRunAt, timeZone: timeZone)
    }

    /// `in 38 s · every 1 m` (the countdown, whole seconds rounded up), or `every 1 m` with no run scheduled.
    public func nextRunDetail(now: Date) -> String {
        let every = L10n.format("script.page.every", ScriptPageFormat.duration(interval))
        guard let nextRunAt, !isRunning else { return every }
        let left = max(0, nextRunAt.timeIntervalSince(now)).rounded(.up)
        let countdown = L10n.format("script.page.nextRun.in", ScriptPageFormat.duration(.seconds(left)))
        return StatusLabelFormatter.joined(countdown, every)
    }

    /// `10 s`.
    public var timeoutText: String { ScriptPageFormat.duration(timeout) }
}

/// The script page (DESIGN "Script page", `components.script-page`): the hero (the widget at large size), the
/// documentation under `ABOUT · FROM <file>`, and the runs card.
public struct ScriptPageModel: Sendable, Equatable, PrivacyRedactable {
    /// The widget as on the Home card: name and target, cadence, body per state, meta line, WARN badge.
    public var hero: ScriptCardModel
    public var kind: ScriptWidgetKind
    /// The file's Markdown documentation, script text.
    @Sensitive public var documentation: String
    public var runs: ScriptRunsCardModel

    public init(hero: ScriptCardModel, kind: ScriptWidgetKind, documentation: String, runs: ScriptRunsCardModel) {
        self.hero = hero
        self.kind = kind
        self.documentation = documentation
        self.runs = runs
    }

    /// The hero header's right side: `STATUS WIDGET · EVERY 1M`.
    public var heroMeta: String { StatusLabelFormatter.joined(kind.label, hero.cadence) }

    /// `ABOUT`.
    public static var aboutTitle: String { L10n.string("script.page.about") }

    /// `FROM site-status.md`.
    public var aboutMeta: String { L10n.format("script.page.about.from", runs.fileName) }

    /// `ABOUT · FROM site-status.md`.
    public var aboutHeading: String { StatusLabelFormatter.joined(Self.aboutTitle, aboutMeta) }

    /// The hero is a control: `NOT CONFIRMED` opens the Script Confirmation, an output with an action runs it.
    public var heroIsActionable: Bool {
        if case .notConfirmed = hero.body { return true }
        if case .output = hero.body { return hero.action != nil }
        return false
    }

    public func redacted() -> ScriptPageModel {
        var copy = self
        copy.hero = hero.redacted()
        copy.documentation = $documentation.masked
        return copy
    }

    /// "vigie.app, OK, up, 200, 142 ms, checked 2 minutes ago" (UX-DR86): the name, the target when it differs,
    /// the level, the qualifier, the value's parts, then the meta line spoken.
    public func heroAccessibilityLabel(now: Date, timeZone: TimeZone = .current) -> String {
        var parts = [hero.name]
        if let target = hero.target, !target.isEmpty, target != hero.name { parts.append(target) }
        switch hero.body {
        case .output(.status(let level, let qualifier, let value)):
            parts.append(StatusLabelFormatter().label(for: level))
            if let qualifier { parts.append(qualifier) }
            if let value { parts += ScriptPageFormat.spokenParts(value) }
        case .output(let content):
            parts += content.spokenParts
        case .notConfirmed:
            parts.append(ScriptStateLabel.notConfirmedText)
        case .state(let text):
            parts.append(text)
        }
        if hero.warningBadge { parts.append(StatusLabelFormatter().label(for: StatusLevel.warn)) }
        if let meta = hero.meta { parts.append(ScriptPageFormat.spoken(meta, now: now, timeZone: timeZone)) }
        return parts.dropFirst().reduce(parts[0]) { AccessibilityLabel.joined($0, $1) }
    }
}

/// The page's number and time formats.
public enum ScriptPageFormat {
    /// `14:46:12` (24-hour clock).
    public static func clock(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let style = Date.VerbatimFormatStyle(
            format: """
                \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\
                \(second: .twoDigits)
                """,
            timeZone: timeZone, calendar: calendar)
        return style.format(date)
    }

    /// `0.4 s` and `2.3 s` under ten seconds, `12 s`, `1 m 5 s`, `2 m`, `1 h 30 m`.
    public static func duration(_ duration: Duration) -> String {
        let components = duration.components
        let seconds = max(0, Double(components.seconds) + Double(components.attoseconds) / 1e18)
        if seconds < 10, seconds != seconds.rounded(.down) {
            return L10n.format("script.page.duration.decimalSeconds", (seconds * 10).rounded() / 10)
        }
        let whole = Int(seconds.rounded())
        if whole < 60 { return L10n.format("script.page.duration.seconds", whole) }
        if whole < 3600 {
            let minutes = whole / 60
            let rest = whole % 60
            return rest == 0
                ? L10n.format("script.page.duration.minutes", minutes)
                : L10n.format("script.page.duration.minutesSeconds", minutes, rest)
        }
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        return minutes == 0
            ? L10n.format("script.page.duration.hours", hours)
            : L10n.format("script.page.duration.hoursMinutes", hours, minutes)
    }

    /// A value line read as separate parts: `200 · 142 ms` → `200`, `142 ms`.
    static func spokenParts(_ value: String) -> [String] {
        value.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The meta line as VoiceOver reads it: "checked 2 minutes ago", "updated 4 minutes ago"; failures and
    /// `DOWN SINCE 14:44` as shown.
    static func spoken(_ meta: ScriptCardMeta, now: Date, timeZone: TimeZone) -> String {
        switch meta {
        case .checked(let date):
            L10n.format("script.page.a11y.checked", spokenElapsed(from: date, to: now))
        case .updated(let date):
            L10n.format("script.page.a11y.updated", spokenElapsed(from: date, to: now))
        case .downSince, .label:
            meta.text(now: now, timeZone: timeZone)
        }
    }

    private static func spokenElapsed(from date: Date, to now: Date) -> String {
        AccessibilityLabel.duration(ScriptCardMeta.elapsed(from: date, to: now))
    }
}
