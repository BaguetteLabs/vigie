import Foundation
import ModuleKit

/// Break reminders (SPEC §7.7, Story 20.4, EXPERIENCE Flow 8, UX-DR107): pure work and break accounting on
/// Present / Away transitions and a clock. No timers of its own: the module calls ``tick(at:)`` at
/// ``nextDeadline`` and feeds every presence change.
///
/// - **Work** accrues only while Present (and not paused). An Away keeps the time up to its `since`.
/// - An Away shorter than the break length counts as neither work nor break; an Away of at least the break
///   length, at any point (a due break included), is a break taken: a new cycle starts with no action.
/// - At `work` of accrued work the break is **due** (``Event/due``); it stays due until Start break, Skip, or an
///   Away of the break length. Snooze keeps it due and asks for one re-raise after ``snoozeLength``.
/// - Start break runs a break of the break length, then a new cycle. Skip starts a new cycle at once.
/// - ``pause(while:at:)``: while a Pomodoro runs (Story 20.5) nothing accrues and nothing comes due; when it
///   stops a fresh cycle starts.
struct BreakTracker: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case working
        /// Due since `at`; `snoozedUntil` while a snooze waits.
        case due(at: Date, snoozedUntil: Date?)
        case onBreak(startedAt: Date, endsAt: Date)
        /// A Pomodoro runs.
        case paused
    }

    /// What the module reacts to.
    enum Event: Equatable, Sendable {
        /// Raise the break alert: `worked` seconds of work since `cycleStart`.
        case due(worked: TimeInterval, cycleStart: Date)
        /// The snooze ran out: raise it again.
        case reRaise
        /// A due break ended without an alert action: taken by an Away of the break length, or paused.
        case cleared
        /// A started break ran its length (a plain reminder's break end is silent, SPEC §7.7).
        case breakEnded
    }

    static let snoozeLength: TimeInterval = 5 * 60

    var workLength: TimeInterval
    var breakLength: TimeInterval
    private(set) var phase: Phase = .working
    /// Work before the current Present stretch.
    private(set) var accrued: TimeInterval = 0
    /// Start of the current Present stretch that counts as work.
    private(set) var presentSince: Date?
    /// The current Away, while Away.
    private(set) var awaySince: Date?
    /// The first moment of the cycle (`Focused … since <time>`).
    private(set) var cycleStart: Date

    init(workLength: TimeInterval, breakLength: TimeInterval, presence: Presence, at date: Date) {
        self.workLength = workLength
        self.breakLength = breakLength
        cycleStart = date
        switch presence {
        case .present: presentSince = date
        case .away(let since): awaySince = min(since, date)
        }
    }

    var isAway: Bool { awaySince != nil }

    var isDue: Bool {
        if case .due = phase { return true }
        return false
    }

    var dueSince: Date? {
        if case .due(let at, _) = phase { return at }
        return nil
    }

    var breakEndsAt: Date? {
        if case .onBreak(_, let end) = phase { return end }
        return nil
    }

    /// Work done in this cycle, as of `date`.
    func worked(at date: Date) -> TimeInterval {
        guard phase == .working, let presentSince else { return accrued }
        return accrued + max(0, date.timeIntervalSince(presentSince))
    }

    /// The next moment ``tick(at:)`` has something to decide: the work reaching `workLength`, an Away reaching
    /// the break length, a snooze or a break ending.
    var nextDeadline: Date? {
        var dates: [Date] = []
        switch phase {
        case .working:
            if let presentSince { dates.append(presentSince.addingTimeInterval(max(0, workLength - accrued))) }
        case .due(_, let snoozed):
            if let snoozed { dates.append(snoozed) }
        case .onBreak(_, let end):
            dates.append(end)
        case .paused:
            break
        }
        if let awaySince, phase != .paused, breakEndsAt == nil, !(phase == .working && accrued == 0) {
            dates.append(awaySince.addingTimeInterval(breakLength))
        }
        return dates.min()
    }

    // MARK: Inputs

    /// A Present / Away transition from `context.away` (or sleep).
    mutating func presence(_ presence: Presence, at date: Date) -> [Event] {
        switch presence {
        case .away(let since):
            guard awaySince == nil else { return tick(at: date) }
            let start = min(since, date)
            if phase == .working, let presentSince {
                accrued += max(0, start.timeIntervalSince(presentSince))
            }
            presentSince = nil
            awaySince = start
            return tick(at: date)
        case .present:
            var events = tick(at: date)
            guard let away = awaySince else { return events }
            awaySince = nil
            if date.timeIntervalSince(away) >= breakLength, phase != .paused, breakEndsAt == nil {
                events += takeBreak(at: date)
            }
            if phase == .working { presentSince = date }
            return events + tick(at: date)
        }
    }

    /// Applies what is due at `date`.
    mutating func tick(at date: Date) -> [Event] {
        var events: [Event] = []
        switch phase {
        case .paused:
            return []
        case .onBreak(_, let end) where date >= end:
            newCycle(at: end, presentAt: isAway ? nil : end)
            events.append(.breakEnded)
        case .due(let at, let snoozed?) where date >= snoozed:
            phase = .due(at: at, snoozedUntil: nil)
            events.append(.reRaise)
        default:
            break
        }
        // An Away of the break length is a break taken, even before coming back.
        if let away = awaySince, breakEndsAt == nil, date.timeIntervalSince(away) >= breakLength,
            isDue || accrued > 0
        {
            events += takeBreak(at: date)
        }
        if phase == .working, worked(at: date) >= workLength {
            let worked = worked(at: date)
            accrued = worked
            presentSince = isAway ? nil : date
            phase = .due(at: date, snoozedUntil: nil)
            events.append(.due(worked: worked, cycleStart: cycleStart))
        }
        return events
    }

    // MARK: Actions

    /// Start break (the peek, the macOS notification or the Time tab): a break of the break length.
    mutating func startBreak(at date: Date) {
        guard phase != .paused else { return }
        phase = .onBreak(startedAt: date, endsAt: date.addingTimeInterval(breakLength))
        presentSince = nil
        accrued = 0
    }

    /// Snooze 5m: still due, raised again after five minutes.
    mutating func snooze(at date: Date) {
        guard case .due(let at, _) = phase else { return }
        phase = .due(at: at, snoozedUntil: date.addingTimeInterval(Self.snoozeLength))
    }

    /// Skip: no break counted, a new work cycle now (also ends a running break early).
    mutating func skip(at date: Date) {
        guard phase != .paused else { return }
        newCycle(at: date, presentAt: isAway ? nil : date)
    }

    /// While `running` (a Pomodoro, Story 20.5) nothing accrues and nothing is due; a due break is cleared. When
    /// it stops, a fresh cycle starts.
    mutating func pause(while running: Bool, at date: Date) -> [Event] {
        if running {
            guard phase != .paused else { return [] }
            let wasDue = isDue
            phase = .paused
            accrued = 0
            presentSince = nil
            return wasDue ? [.cleared] : []
        }
        guard phase == .paused else { return [] }
        newCycle(at: date, presentAt: isAway ? nil : date)
        return []
    }

    // MARK: Helpers

    private mutating func takeBreak(at date: Date) -> [Event] {
        let wasDue = isDue
        newCycle(at: date, presentAt: isAway ? nil : date)
        return wasDue ? [.cleared] : []
    }

    private mutating func newCycle(at date: Date, presentAt: Date?) {
        phase = .working
        accrued = 0
        cycleStart = date
        presentSince = presentAt
    }
}
