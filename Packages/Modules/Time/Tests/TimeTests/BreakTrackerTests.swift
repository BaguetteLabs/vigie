import Foundation
import ModuleKit
import Testing

@testable import Time

/// Story 20.4: the work / break accounting on its own (UX-DR107, EXPERIENCE Flow 8).
@Suite struct BreakTrackerTests {
    let t0 = Fixture.start
    func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }
    func tracker(_ presence: Presence = .present) -> BreakTracker {
        BreakTracker(workLength: 55 * 60, breakLength: 5 * 60, presence: presence, at: t0)
    }

    @Test func dueAfterFiftyFiveMinutesOfPresence() {
        var tracker = tracker()
        #expect(tracker.nextDeadline == at(55))
        #expect(tracker.tick(at: at(54)).isEmpty)
        #expect(tracker.tick(at: at(55)) == [.due(worked: 55 * 60, cycleStart: t0)])
        #expect(tracker.isDue)
        #expect(tracker.tick(at: at(90)).isEmpty, "no nagging of its own")
        #expect(tracker.nextDeadline == nil)
    }

    @Test func awayTimeDoesNotCountAsWork() {
        var tracker = tracker()
        // Idle Away detected 90 s after the last input at 30:00; back at 33:00 (under the break length).
        #expect(tracker.presence(.away(since: at(30)), at: at(31.5)).isEmpty)
        #expect(tracker.worked(at: at(32)) == 30 * 60)
        #expect(tracker.presence(.present, at: at(33)).isEmpty)
        #expect(tracker.worked(at: at(33)) == 30 * 60, "a short Away is neither work nor break")
        #expect(tracker.cycleStart == t0)
        #expect(tracker.nextDeadline == at(58))
    }

    @Test func awayOfTheBreakLengthStartsANewCycle() {
        var tracker = tracker()
        _ = tracker.presence(.away(since: at(20)), at: at(21.5))
        #expect(tracker.nextDeadline == at(25))
        #expect(tracker.presence(.present, at: at(26)).isEmpty)
        #expect(tracker.worked(at: at(26)) == 0)
        #expect(tracker.cycleStart == at(26))
        #expect(tracker.nextDeadline == at(26 + 55))
    }

    @Test func awayOfTheBreakLengthClearsADueBreakEvenBeforeComingBack() {
        var tracker = tracker()
        _ = tracker.tick(at: at(55))
        _ = tracker.presence(.away(since: at(56)), at: at(57.5))
        #expect(tracker.nextDeadline == at(61))
        #expect(tracker.tick(at: at(61)) == [.cleared])
        #expect(!tracker.isDue)
        #expect(tracker.presence(.present, at: at(70)).isEmpty)
        #expect(tracker.worked(at: at(70)) == 0)
    }

    @Test func shortAwayKeepsADueBreakDue() {
        var tracker = tracker()
        _ = tracker.tick(at: at(55))
        _ = tracker.presence(.away(since: at(56)), at: at(57))
        #expect(tracker.presence(.present, at: at(58)).isEmpty)
        #expect(tracker.isDue)
    }

    @Test func snoozeReRaisesOnceAfterFiveMinutes() {
        var tracker = tracker()
        _ = tracker.tick(at: at(55))
        tracker.snooze(at: at(56))
        #expect(tracker.nextDeadline == at(61))
        #expect(tracker.tick(at: at(60)).isEmpty)
        #expect(tracker.tick(at: at(61)) == [.reRaise])
        #expect(tracker.isDue)
        #expect(tracker.tick(at: at(70)).isEmpty)
    }

    @Test func skipStartsANewCycleWithNoBreak() {
        var tracker = tracker()
        _ = tracker.tick(at: at(55))
        tracker.skip(at: at(56))
        #expect(!tracker.isDue)
        #expect(tracker.cycleStart == at(56))
        #expect(tracker.nextDeadline == at(56 + 55))
    }

    @Test func startedBreakRunsItsLengthThenANewCycle() {
        var tracker = tracker()
        _ = tracker.tick(at: at(55))
        tracker.startBreak(at: at(56))
        #expect(tracker.breakEndsAt == at(61))
        #expect(tracker.nextDeadline == at(61))
        #expect(tracker.tick(at: at(61)) == [.breakEnded])
        #expect(tracker.breakEndsAt == nil)
        #expect(tracker.cycleStart == at(61))
        #expect(tracker.nextDeadline == at(61 + 55))
    }

    @Test func pauseWhilePomodoroRunsThenFreshCycle() {
        var tracker = tracker()
        #expect(tracker.pause(while: true, at: at(10)).isEmpty)
        #expect(tracker.nextDeadline == nil)
        #expect(tracker.tick(at: at(120)).isEmpty, "never due while paused")
        _ = tracker.pause(while: false, at: at(120))
        #expect(tracker.cycleStart == at(120))
        #expect(tracker.worked(at: at(120)) == 0)
        #expect(tracker.nextDeadline == at(175))
        // A due break is cleared when a Pomodoro starts.
        _ = tracker.tick(at: at(175))
        #expect(tracker.pause(while: true, at: at(176)) == [.cleared])
    }

    @Test func startingAwayAccruesNothingUntilPresent() {
        var tracker = tracker(.away(since: t0.addingTimeInterval(-600)))
        #expect(tracker.worked(at: at(30)) == 0)
        #expect(tracker.presence(.present, at: at(30)).isEmpty)
        #expect(tracker.nextDeadline == at(85))
    }
}
