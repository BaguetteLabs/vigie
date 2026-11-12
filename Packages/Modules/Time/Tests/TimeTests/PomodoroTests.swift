import Foundation
import ModuleKit
import Testing

@testable import Time

/// Story 20.5: the Pomodoro phase machine as a plain value, on explicit dates.
@Suite struct PomodoroTests {
    let t0 = Fixture.start
    let lengths = PomodoroLengths()

    func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    /// Runs work to its end, then takes the break to its end.
    func fullCycle(_ pomodoro: inout Pomodoro) -> [Pomodoro.Event] {
        var events = pomodoro.tick(at: pomodoro.endsAt, away: false)
        pomodoro.startBreak(at: pomodoro.endsAt)
        events += pomodoro.tick(at: pomodoro.endsAt, away: false)
        return events
    }

    @Test func defaultsAreTwentyFiveFiveFifteenEveryFour() {
        #expect(lengths.work == 1500)
        #expect(lengths.shortBreak == 300)
        #expect(lengths.longBreak == 900)
        #expect(lengths.longEvery == 4)
        #expect(lengths.summary == "25 · 5 · 15")
    }

    @Test func workEndMakesTheBreakDueAndItWaits() {
        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        #expect(pomodoro.isWork)
        #expect(pomodoro.nextDeadline == at(25))
        #expect(pomodoro.tick(at: at(24), away: false).isEmpty)
        let events = pomodoro.tick(at: at(25), away: false)
        #expect(events == [.workEnded(cycle: 1, long: false, worked: 1500, since: t0)])
        #expect(pomodoro.phase == .breakDue(since: at(25), snoozedUntil: nil))
        #expect(pomodoro.nextDeadline == nil, "the break waits for the user")
        #expect(pomodoro.tick(at: at(300), away: false).isEmpty)
        #expect(pomodoro.isDue)
        #expect(pomodoro.breakLength == 300)
    }

    @Test func startBreakRunsItThenWorkStartsOnItsOwn() {
        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        _ = pomodoro.tick(at: at(25), away: false)
        pomodoro.startBreak(at: at(27))
        #expect(pomodoro.phase == .onBreak(long: false))
        #expect(pomodoro.endsAt == at(32))
        let events = pomodoro.tick(at: at(32), away: false)
        #expect(events == [.breakEnded(long: false, startedAt: at(27), endedAt: at(32))])
        #expect(pomodoro.isWork)
        #expect(pomodoro.cycle == 2)
        #expect(pomodoro.endsAt == at(57))
    }

    @Test func longBreakEveryFourWorkPeriodsThenANewSet() {
        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        var longs: [Bool] = []
        for _ in 0..<5 {
            let events = fullCycle(&pomodoro)
            for case .workEnded(_, let long, _, _) in events { longs.append(long) }
        }
        #expect(longs == [false, false, false, true, false])
        #expect(pomodoro.cycle == 2, "cycle 1 of the second set ended, cycle 2 runs")
    }

    @Test func fourthBreakIsTheLongOneAndResetsTheSet() {
        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        for _ in 0..<3 { _ = fullCycle(&pomodoro) }
        #expect(pomodoro.cycle == 4)
        let workEnd = pomodoro.endsAt
        let events = pomodoro.tick(at: workEnd, away: false)
        #expect(events == [.workEnded(cycle: 4, long: true, worked: 6000, since: t0)])
        #expect(pomodoro.isLongBreak)
        #expect(pomodoro.breakLength == 900)
        pomodoro.startBreak(at: workEnd)
        #expect(pomodoro.phase == .onBreak(long: true))
        #expect(pomodoro.endsAt == workEnd.addingTimeInterval(900))
        let end = pomodoro.endsAt
        #expect(pomodoro.tick(at: end, away: false) == [.breakEnded(long: true, startedAt: workEnd, endedAt: end)])
        #expect(pomodoro.cycle == 1)
        #expect(pomodoro.setStartedAt == end)
        #expect(pomodoro.workedInSet == 0)
    }

    @Test func snoozeReRaisesOnceAfterFiveMinutes() {
        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        _ = pomodoro.tick(at: at(25), away: false)
        pomodoro.snooze(at: at(26))
        #expect(pomodoro.nextDeadline == at(31))
        #expect(pomodoro.tick(at: at(30), away: false).isEmpty)
        #expect(pomodoro.tick(at: at(31), away: false) == [.reRaise])
        #expect(pomodoro.isDue)
        #expect(pomodoro.tick(at: at(40), away: false).isEmpty)
    }

    @Test func skipMovesToTheNextPhase() {
        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        // Work: ends now, its break starts at once; the work done counts.
        pomodoro.skip(at: at(10))
        #expect(pomodoro.phase == .onBreak(long: false))
        #expect(pomodoro.workedInSet == 600)
        // Break: the next work period now.
        pomodoro.skip(at: at(11))
        #expect(pomodoro.isWork)
        #expect(pomodoro.cycle == 2)
        #expect(pomodoro.endsAt == at(36))
        // A due break: skipped, no break, next work period.
        _ = pomodoro.tick(at: at(36), away: false)
        pomodoro.skip(at: at(40))
        #expect(pomodoro.isWork)
        #expect(pomodoro.cycle == 3)
        #expect(pomodoro.endsAt == at(65))
    }

    @Test func pauseAndResumeKeepTheRemainingTime() {
        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        pomodoro.pause(.user, at: at(10))
        #expect(pomodoro.isPaused)
        #expect(pomodoro.pausedAt == at(10))
        #expect(pomodoro.remaining(at: at(50)) == 900)
        #expect(pomodoro.nextDeadline == nil)
        #expect(pomodoro.tick(at: at(60), away: false).isEmpty)
        pomodoro.resume(at: at(60))
        #expect(!pomodoro.isPaused)
        #expect(pomodoro.endsAt == at(75))
    }

    @Test func awayPausesWorkFromItsStartAndPresentResumes() {
        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        pomodoro.away(since: at(10), at: at(11.5))
        #expect(pomodoro.isAwayPaused)
        #expect(pomodoro.pausedAt == at(10))
        #expect(pomodoro.remaining(at: at(30)) == 900)
        pomodoro.present(at: at(30))
        #expect(!pomodoro.isPaused)
        #expect(pomodoro.endsAt == at(45))
    }

    @Test func awayDoesNotPauseABreakNorPresentAUserPause() {
        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        _ = pomodoro.tick(at: at(25), away: false)
        pomodoro.away(since: at(25), at: at(26))
        #expect(!pomodoro.isPaused, "a due break is not paused")
        pomodoro.startBreak(at: at(26))
        pomodoro.away(since: at(27), at: at(28))
        #expect(!pomodoro.isPaused, "Away pauses work only")
        pomodoro.skip(at: at(28))
        pomodoro.pause(.user, at: at(29))
        pomodoro.present(at: at(30))
        #expect(pomodoro.pauseReason == .user, "Present resumes only an Away pause")
    }

    @Test func breakEndingWhileAwayStartsTheWorkPaused() {
        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        _ = pomodoro.tick(at: at(25), away: false)
        pomodoro.startBreak(at: at(25))
        let events = pomodoro.tick(at: at(90), away: true)
        #expect(events == [.breakEnded(long: false, startedAt: at(25), endedAt: at(30))])
        #expect(pomodoro.isWork)
        #expect(pomodoro.isAwayPaused)
        #expect(pomodoro.remaining(at: at(90)) == 1500)
    }

    @Test func breakEndNoticedLateRunsTheNextWorkFromTheBreakEnd() {
        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        _ = pomodoro.tick(at: at(25), away: false)
        pomodoro.startBreak(at: at(25))
        // Relaunched an hour after the break ended: the next work period ran out too, its break waits.
        let events = pomodoro.tick(at: at(90), away: false)
        #expect(
            events == [
                .breakEnded(long: false, startedAt: at(25), endedAt: at(30)),
                .workEnded(cycle: 2, long: false, worked: 3000, since: t0),
            ])
        #expect(pomodoro.phase == .breakDue(since: at(55), snoozedUntil: nil))
    }

    @Test func newLengthsApplyFromTheNextPhase() {
        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        pomodoro.apply(PomodoroLengths(work: 3000, shortBreak: 600, longBreak: 1200, longEvery: 2))
        #expect(pomodoro.endsAt == at(25), "the running phase keeps its end")
        _ = pomodoro.tick(at: at(25), away: false)
        #expect(pomodoro.breakLength == 600)
        pomodoro.startBreak(at: at(25))
        _ = pomodoro.tick(at: at(35), away: false)
        #expect(pomodoro.endsAt == at(85))
        #expect(pomodoro.longBreakNext, "cycle 2 of 2")
    }

    @Test func configParsingWithDefaults() {
        let parsed = PomodoroLengths(
            FakeSettings(values: [
                "pomodoro.work": Duration.seconds(50 * 60), "pomodoro.short_break": Duration.seconds(600),
                "pomodoro.long_every": 3,
            ]))
        #expect(parsed == PomodoroLengths(work: 3000, shortBreak: 600, longBreak: 900, longEvery: 3))
        let invalid = PomodoroLengths(
            FakeSettings(values: [
                "pomodoro.work": Duration.zero, "pomodoro.long_break": Duration.seconds(-5), "pomodoro.long_every": 0,
            ]))
        #expect(invalid == PomodoroLengths())
        #expect(PomodoroLengths(FakeSettings(values: [:])) == PomodoroLengths())
        #expect(PomodoroLengths(FakeSettings(values: ["pomodoro.long_every": 99])).longEvery == 12)
    }

    @Test func stateFileReadsSchemaOneArraysAndRoundTrips() throws {
        let item = TimeItem(kind: .timer(duration: 300), label: "Tea", startedAt: t0, endsAt: at(5))
        let old = try FakeStorage.encoder.encode([item])
        let legacy = try FakeStorage.decoder.decode(TimeState.self, from: old)
        #expect(legacy.items == [item])
        #expect(legacy.pomodoro == nil)

        var pomodoro = Pomodoro(lengths: lengths, at: t0)
        pomodoro.pause(.away, at: at(3))
        let data = try FakeStorage.encoder.encode(TimeState(items: [item], pomodoro: pomodoro))
        let decoded = try FakeStorage.decoder.decode(TimeState.self, from: data)
        #expect(decoded.items == [item])
        #expect(decoded.pomodoro == pomodoro)
    }
}
