import Foundation
import Testing

@testable import Time

@Suite struct TimeBoardTests {
    let t0 = Fixture.start

    @Test func timerRunsPausesResumesAndResets() throws {
        var board = TimeBoard()
        let itemStarted = board.startTimer(minutes: 5, label: "Tea", now: t0)
        let item = try #require(itemStarted)
        #expect(item.endsAt == t0.addingTimeInterval(300))
        let r1 = board.pause(item.id, now: t0.addingTimeInterval(108))
        #expect(r1)
        #expect(board[item.id]?.state == .paused)
        #expect(board[item.id]?.remaining(now: t0.addingTimeInterval(1000)) == 192)
        #expect(board.nextEnd == nil, "a paused timer has no end job")
        let r2 = board.resume(item.id, now: t0.addingTimeInterval(200))
        #expect(r2)
        #expect(board[item.id]?.endsAt == t0.addingTimeInterval(392))
        let r3 = board.reset(item.id, now: t0.addingTimeInterval(250))
        #expect(r3)
        #expect(board[item.id]?.endsAt == t0.addingTimeInterval(550))
        #expect(board[item.id]?.startedAt == t0.addingTimeInterval(250))
    }

    @Test func resetWhilePausedKeepsItPausedWithTheFullLength() throws {
        var board = TimeBoard()
        let itemStarted = board.startTimer(minutes: 10, label: "x", now: t0)
        let item = try #require(itemStarted)
        board.pause(item.id, now: t0.addingTimeInterval(60))
        board.reset(item.id, now: t0.addingTimeInterval(90))
        #expect(board[item.id]?.state == .paused)
        #expect(board[item.id]?.pausedRemaining == 600)
    }

    @Test func togglePauseFlips() throws {
        var board = TimeBoard()
        let itemStarted = board.startTimer(minutes: 1, label: "x", now: t0)
        let item = try #require(itemStarted)
        board.togglePause(item.id, now: t0)
        #expect(board[item.id]?.state == .paused)
        board.togglePause(item.id, now: t0)
        #expect(board[item.id]?.state == .running)
    }

    @Test func countdownCannotPauseOrReset() throws {
        var board = TimeBoard()
        let itemStarted = board.startCountdown(to: t0.addingTimeInterval(3600), label: "Release", now: t0)
        let item = try #require(itemStarted)
        let paused = board.pause(item.id, now: t0)
        let reset = board.reset(item.id, now: t0)
        let past = board.startCountdown(to: t0, label: "past", now: t0)
        #expect(!paused)
        #expect(!reset)
        #expect(past == nil)
    }

    @Test func rejectsOutOfRangeTimers() {
        var board = TimeBoard()
        let zero = board.startTimer(minutes: 0, label: "x", now: t0)
        let tooLong = board.startTimer(minutes: 1441, label: "x", now: t0)
        let day = board.startTimer(minutes: 1440, label: "x", now: t0)
        #expect(zero == nil)
        #expect(tooLong == nil)
        #expect(day != nil)
    }

    @Test func removeAndRestorePutsTheItemBackInPlace() throws {
        var board = TimeBoard()
        let aStarted = board.startTimer(minutes: 1, label: "a", now: t0)
        let a = try #require(aStarted)
        let bStarted = board.startTimer(minutes: 2, label: "b", now: t0)
        let b = try #require(bStarted)
        let cStarted = board.startTimer(minutes: 3, label: "c", now: t0)
        let c = try #require(cStarted)
        let removal = board.remove(b.id)
        let removed = try #require(removal)
        #expect(removed.index == 1)
        #expect(board.items.map(\.id) == [a.id, c.id])
        board.restore(removed.item, at: removed.index)
        #expect(board.items.map(\.id) == [a.id, b.id, c.id])
        board.restore(removed.item, at: 0)
        #expect(board.items.count == 3, "restoring twice is a no-op")
    }

    @Test func evaluateEndsDueItemsAtTheirOwnEndOnce() throws {
        var board = TimeBoard()
        let aStarted = board.startTimer(minutes: 1, label: "a", now: t0)
        let a = try #require(aStarted)
        board.startTimer(minutes: 10, label: "b", now: t0)
        let late = t0.addingTimeInterval(3600 * 5)
        let first = board.evaluate(now: t0.addingTimeInterval(120))
        #expect(first.map(\.id) == [a.id])
        #expect(board[a.id]?.state == .ended(at: t0.addingTimeInterval(60)))
        let r4 = board.evaluate(now: t0.addingTimeInterval(130))
        #expect(r4.isEmpty)
        let lateEnds = board.evaluate(now: late)
        #expect(lateEnds.count == 1)
        #expect(board.hasUnacknowledgedEnd)
    }

    @Test func acknowledgeRemovesOnlyEndedItems() throws {
        var board = TimeBoard()
        let aStarted = board.startTimer(minutes: 1, label: "a", now: t0)
        let a = try #require(aStarted)
        let early = board.acknowledge(a.id)
        #expect(!early)
        _ = board.evaluate(now: t0.addingTimeInterval(60))
        let acknowledged = board.acknowledge(a.id)
        #expect(acknowledged)
        #expect(board.items.isEmpty)
        #expect(!board.hasUnacknowledgedEnd)
    }

    @Test func sortsEndedFirstThenByEndTimeWithPausedAtTheirProjectedEnd() throws {
        var board = TimeBoard()
        let longStarted = board.startTimer(minutes: 30, label: "long", now: t0)
        let long = try #require(longStarted)
        let shortStarted = board.startTimer(minutes: 5, label: "short", now: t0)
        let short = try #require(shortStarted)
        let pausedStarted = board.startTimer(minutes: 20, label: "paused", now: t0)
        let paused = try #require(pausedStarted)
        let doneStarted = board.startTimer(minutes: 1, label: "done", now: t0)
        let done = try #require(doneStarted)
        let countdownStarted = board.startCountdown(to: t0.addingTimeInterval(86_400), label: "cd", now: t0)
        let countdown = try #require(countdownStarted)
        let now = t0.addingTimeInterval(120)
        board.pause(paused.id, now: t0.addingTimeInterval(60))  // 19 min left → projected end now + 19 min
        _ = board.evaluate(now: now)
        #expect(
            board.sorted(now: now).map(\.id) == [done.id, short.id, paused.id, long.id, countdown.id])
    }

    @Test func nextEndIsTheNearestRunningEnd() throws {
        var board = TimeBoard()
        board.startTimer(minutes: 10, label: "a", now: t0)
        let bStarted = board.startTimer(minutes: 3, label: "b", now: t0)
        let b = try #require(bStarted)
        #expect(board.nextEnd == b.endsAt)
        board.pause(b.id, now: t0)
        #expect(board.nextEnd == t0.addingTimeInterval(600))
    }
}
