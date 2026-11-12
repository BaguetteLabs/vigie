import Foundation
import ModuleKit

/// `[modules.time.pomodoro]`: `work = "25m"`, `short_break = "5m"`, `long_break = "15m"`, `long_every = 4`
/// (SPEC §11; a table so Settings can write it, an inline table in a user's file still reads).
public struct PomodoroLengths: Codable, Hashable, Sendable {
    nonisolated static let workKey = "pomodoro.work"
    nonisolated static let shortBreakKey = "pomodoro.short_break"
    nonisolated static let longBreakKey = "pomodoro.long_break"
    nonisolated static let longEveryKey = "pomodoro.long_every"
    nonisolated static let keys = [workKey, shortBreakKey, longBreakKey, longEveryKey]

    public nonisolated static let defaultWork: Duration = .seconds(25 * 60)
    public nonisolated static let defaultShortBreak: Duration = .seconds(5 * 60)
    public nonisolated static let defaultLongBreak: Duration = .seconds(15 * 60)
    public nonisolated static let defaultLongEvery = 4
    /// The most work periods in a set the settings accept (and the pips draw).
    public nonisolated static let maxLongEvery = 12

    public var work: TimeInterval = defaultWork.timeInterval
    public var shortBreak: TimeInterval = defaultShortBreak.timeInterval
    public var longBreak: TimeInterval = defaultLongBreak.timeInterval
    /// A long break after every `longEvery` work periods.
    public var longEvery: Int = defaultLongEvery

    public init() {}

    public init(work: TimeInterval, shortBreak: TimeInterval, longBreak: TimeInterval, longEvery: Int) {
        self.work = work
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.longEvery = min(max(longEvery, 1), Self.maxLongEvery)
    }

    /// The configured lengths; a missing, zero or negative value falls back to its default.
    init(_ settings: any ModuleSettings) {
        work = Self.positive(settings.value(Self.workKey, as: Duration.self), or: Self.defaultWork)
        shortBreak = Self.positive(settings.value(Self.shortBreakKey, as: Duration.self), or: Self.defaultShortBreak)
        longBreak = Self.positive(settings.value(Self.longBreakKey, as: Duration.self), or: Self.defaultLongBreak)
        let every = settings.value(Self.longEveryKey, as: Int.self) ?? Self.defaultLongEvery
        longEvery = every >= 1 ? min(every, Self.maxLongEvery) : Self.defaultLongEvery
    }

    private static func positive(_ value: Duration?, or fallback: Duration) -> TimeInterval {
        guard let value, value > .zero else { return fallback.timeInterval }
        return value.timeInterval
    }

    /// `25 · 5 · 15`: the quick-start button's lengths, in minutes.
    var summary: String {
        [work, shortBreak, longBreak].map { String(TimeFormat.wholeMinutes($0)) }.joined(separator: " · ")
    }

    nonisolated static func descriptors(bundle: LocalizedStringResource.BundleDescription) -> [SettingDescriptor] {
        func text(_ key: String) -> LocalizedStringResource {
            LocalizedStringResource(String.LocalizationValue(key), bundle: bundle)
        }
        return [
            SettingDescriptor(
                key: workKey, label: text("time.setting.pomodoro.work"), kind: .duration(default: defaultWork),
                help: text("time.setting.pomodoro.work.help")),
            SettingDescriptor(
                key: shortBreakKey, label: text("time.setting.pomodoro.shortBreak"),
                kind: .duration(default: defaultShortBreak), help: text("time.setting.pomodoro.shortBreak.help")),
            SettingDescriptor(
                key: longBreakKey, label: text("time.setting.pomodoro.longBreak"),
                kind: .duration(default: defaultLongBreak), help: text("time.setting.pomodoro.longBreak.help")),
            SettingDescriptor(
                key: longEveryKey, label: text("time.setting.pomodoro.longEvery"),
                kind: .int(default: defaultLongEvery, min: 1, max: maxLongEvery, step: 1),
                help: text("time.setting.pomodoro.longEvery.help")),
        ]
    }
}

/// A Pomodoro (SPEC §7.7, Story 20.5, PRD FR-46 / FR-48): work periods and breaks, a long break after every
/// `longEvery` work periods. A plain value with absolute times, persisted in `items.json`, so a relaunch or a
/// sleep restores it like a Timer.
///
/// - A **work** phase that ends makes its break **due** (``Event/workEnded``): it waits for Start break (ruled
///   2026-11-07, overriding A87's auto-advance), Snooze keeps it due and asks for one re-raise after 5 min, Skip
///   goes straight to the next work period.
/// - A **break** that ends starts the next work period on its own (``Event/breakEnded``), at the break's end;
///   while the user is Away that work period starts paused.
/// - **Away** pauses a work phase only (`AWAY · PAUSED`, from the Away start); Present resumes it, and so does
///   Resume, at once. Pause by the user is never resumed by presence.
public struct Pomodoro: Codable, Hashable, Sendable, Identifiable {
    public enum Phase: Codable, Hashable, Sendable {
        case work
        /// The work period ended at `since`; the break waits for the user. `snoozedUntil` while a snooze waits.
        case breakDue(since: Date, snoozedUntil: Date?)
        case onBreak(long: Bool)
    }

    /// Why a running phase is paused.
    public enum PauseReason: String, Codable, Hashable, Sendable {
        case user
        /// Away during a work phase: resumed by Present (or Resume).
        case away
    }

    /// What the module reacts to.
    enum Event: Equatable, Sendable {
        /// Post `time.break_reminder`: work period `cycle` ended; `worked` seconds of work in the set since
        /// `since`.
        case workEnded(cycle: Int, long: Bool, worked: TimeInterval, since: Date)
        /// The snooze ran out: raise the break again.
        case reRaise
        /// Post `time.timer_end` (`BREAK · ENDED`); the next work period has started.
        case breakEnded(long: Bool, startedAt: Date, endedAt: Date)
    }

    static let snoozeLength: TimeInterval = 5 * 60

    public let id: UUID
    public var lengths: PomodoroLengths
    /// The work period in the set, 1...`longEvery` (the current one, or the one whose break is due or running).
    public private(set) var cycle: Int
    public private(set) var phase: Phase
    /// The length of the current work or break phase (the ring's whole).
    public private(set) var phaseLength: TimeInterval
    /// The running phase's end; stale while paused or while a break is due.
    public private(set) var endsAt: Date
    public private(set) var pausedRemaining: TimeInterval?
    /// When the pause began (`PAUSED 14:31`): the Away start for an Away pause.
    public private(set) var pausedAt: Date?
    public private(set) var pauseReason: PauseReason?
    /// The first work period of the set (`Focused 1 h 40 min since 13:05`).
    public private(set) var setStartedAt: Date
    /// Work done in the set's finished work periods.
    public private(set) var workedInSet: TimeInterval

    /// A Pomodoro whose first work period starts at `date`.
    public init(id: UUID = UUID(), lengths: PomodoroLengths, at date: Date) {
        self.id = id
        self.lengths = lengths
        cycle = 1
        phase = .work
        phaseLength = lengths.work
        endsAt = date.addingTimeInterval(lengths.work)
        setStartedAt = date
        workedInSet = 0
    }

    // MARK: State

    public var isWork: Bool { phase == .work }

    public var isDue: Bool {
        if case .breakDue = phase { return true }
        return false
    }

    public var isOnBreak: Bool {
        if case .onBreak = phase { return true }
        return false
    }

    public var isPaused: Bool { pauseReason != nil }
    public var isAwayPaused: Bool { pauseReason == .away }

    /// The break after the current work period is the long one.
    public var longBreakNext: Bool { cycle >= lengths.longEvery }

    /// The break due (or running): its length.
    public var breakLength: TimeInterval {
        if case .onBreak = phase { return phaseLength }
        return longBreakNext ? lengths.longBreak : lengths.shortBreak
    }

    public var isLongBreak: Bool {
        switch phase {
        case .work: false
        case .breakDue: longBreakNext
        case .onBreak(let long): long
        }
    }

    /// Seconds left in the running or paused phase (a due break: its whole length).
    public func remaining(at date: Date) -> TimeInterval {
        if isDue { return breakLength }
        if let pausedRemaining { return max(0, pausedRemaining) }
        return max(0, endsAt.timeIntervalSince(date))
    }

    /// When the phase ends (or would, if resumed now); nil while a break is due.
    public func effectiveEnd(at date: Date) -> Date? {
        isDue ? nil : date.addingTimeInterval(remaining(at: date))
    }

    public func fractionLeft(at date: Date) -> Double {
        guard phaseLength > 0 else { return 0 }
        return min(max(remaining(at: date) / phaseLength, 0), 1)
    }

    /// The next moment ``tick(at:away:)`` has something to decide.
    var nextDeadline: Date? {
        switch phase {
        case .breakDue(_, let snoozed): snoozed
        case .work, .onBreak: isPaused ? nil : endsAt
        }
    }

    // MARK: Clock

    /// Applies what is due at `date`. `away`: the user is Away now (a work period that starts on its own then
    /// starts paused).
    mutating func tick(at date: Date, away: Bool) -> [Event] {
        var events: [Event] = []
        while true {
            switch phase {
            case .work where !isPaused && endsAt <= date:
                workedInSet += phaseLength
                phase = .breakDue(since: endsAt, snoozedUntil: nil)
                events.append(.workEnded(cycle: cycle, long: longBreakNext, worked: workedInSet, since: setStartedAt))
                return events
            case .breakDue(let since, let snoozed?) where snoozed <= date:
                phase = .breakDue(since: since, snoozedUntil: nil)
                events.append(.reRaise)
                return events
            case .onBreak(let long) where !isPaused && endsAt <= date:
                let end = endsAt
                events.append(.breakEnded(long: long, startedAt: end.addingTimeInterval(-phaseLength), endedAt: end))
                beginWork(at: end, afterLong: long)
                if away {
                    pause(.away, at: end)
                    return events
                }
            default:
                return events
            }
        }
    }

    // MARK: Actions

    /// Start break (the break peek, the macOS notification or the Time tab).
    mutating func startBreak(at date: Date) {
        guard isDue else { return }
        let long = longBreakNext
        phaseLength = long ? lengths.longBreak : lengths.shortBreak
        phase = .onBreak(long: long)
        endsAt = date.addingTimeInterval(phaseLength)
        clearPause()
    }

    /// Snooze 5m: the break stays due and is raised again in five minutes.
    mutating func snooze(at date: Date) {
        guard case .breakDue(let since, _) = phase else { return }
        phase = .breakDue(since: since, snoozedUntil: date.addingTimeInterval(Self.snoozeLength))
    }

    /// Skip the current phase: a work period ends now and its break starts at once (the work done counts); a due
    /// or running break gives way to the next work period now.
    mutating func skip(at date: Date) {
        switch phase {
        case .work:
            workedInSet += max(0, phaseLength - remaining(at: date))
            phase = .breakDue(since: date, snoozedUntil: nil)
            startBreak(at: date)
        case .breakDue:
            beginWork(at: date, afterLong: longBreakNext)
        case .onBreak(let long):
            beginWork(at: date, afterLong: long)
        }
    }

    /// Pause a running work or break phase (`reason` `.away`: work only, from `date`, the Away start).
    mutating func pause(_ reason: PauseReason, at date: Date) {
        guard !isDue, !isPaused else { return }
        if reason == .away, !isWork { return }
        pausedRemaining = min(phaseLength, max(0, endsAt.timeIntervalSince(date)))
        pausedAt = date
        pauseReason = reason
    }

    /// Resume (the user, or Present after an Away pause): the phase runs again from `date`.
    mutating func resume(at date: Date) {
        guard let remaining = pausedRemaining, isPaused else { return }
        endsAt = date.addingTimeInterval(remaining)
        clearPause()
    }

    /// Away from `since` (Story 20.3): pauses a running work phase where the Away began.
    mutating func away(since: Date, at date: Date) {
        guard isWork, !isPaused else { return }
        pause(.away, at: min(since, date))
    }

    /// Present again: an Away pause resumes on its own.
    mutating func present(at date: Date) {
        guard pauseReason == .away else { return }
        resume(at: date)
    }

    /// New lengths from the settings: they apply from the next phase; the running one keeps its end.
    mutating func apply(_ lengths: PomodoroLengths) {
        self.lengths = lengths
        cycle = min(cycle, lengths.longEvery)
    }

    // MARK: Helpers

    private mutating func beginWork(at date: Date, afterLong: Bool) {
        if afterLong {
            cycle = 1
            setStartedAt = date
            workedInSet = 0
        } else {
            cycle = min(cycle + 1, lengths.longEvery)
        }
        phase = .work
        phaseLength = lengths.work
        endsAt = date.addingTimeInterval(lengths.work)
        clearPause()
    }

    private mutating func clearPause() {
        pausedRemaining = nil
        pausedAt = nil
        pauseReason = nil
    }
}

/// `items.json` (schema 2, Story 20.5): the Timers and Countdowns, and the Pomodoro. A schema 1 file (a plain
/// array of items, Story 20.2) reads as items with no Pomodoro.
struct TimeState: Codable, Sendable {
    var items: [TimeItem]
    var pomodoro: Pomodoro?

    init(items: [TimeItem], pomodoro: Pomodoro?) {
        self.items = items
        self.pomodoro = pomodoro
    }

    private enum CodingKeys: String, CodingKey {
        case items, pomodoro
    }

    init(from decoder: any Decoder) throws {
        if let items = try? decoder.singleValueContainer().decode([TimeItem].self) {
            self.items = items
            pomodoro = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([TimeItem].self, forKey: .items) ?? []
        pomodoro = try container.decodeIfPresent(Pomodoro.self, forKey: .pomodoro)
    }
}
