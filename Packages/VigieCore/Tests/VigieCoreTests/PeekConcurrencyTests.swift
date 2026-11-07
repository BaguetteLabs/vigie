import AppKit
import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import VigieCore

@MainActor @Suite struct AlertUrgencyTests {
    @Test(arguments: [
        ("session.blocked", 1), ("session.failed", 1), ("time.break_reminder", 2), ("time.timer_end", 2),
        ("calendar.reminder", 2), ("usage.quota_warning", 3), ("session.done", 4), ("setup.problem", 5),
    ])
    func ranksTheKnownKinds(kind: String, rank: Int) {
        #expect(AlertUrgency.rank(forKind: kind) == rank)
        // Severity never changes a known kind's rank.
        #expect(AlertUrgency.rank(forKind: kind, severity: .critical) == rank)
    }

    @Test func unknownKindsRankAfterTheTableBySeverity() {
        #expect(AlertUrgency.rank(forKind: "shelf.expiring", severity: .critical) == 6)
        #expect(AlertUrgency.rank(forKind: "shelf.expiring", severity: .warn) == 7)
        #expect(AlertUrgency.rank(forKind: "shelf.expiring", severity: .info) == 8)
    }

    @Test func onlyBlockedAndFailedPreemptAndOnlyLowerRanks() {
        let blocked = PeekHarness.alert("session.blocked")
        let failed = PeekHarness.alert("session.failed")
        let done = PeekHarness.alert("session.done", severity: .info)
        let timer = PeekHarness.alert("time.timer_end", severity: .info)
        #expect(AlertUrgency.preempts(blocked, over: done))
        #expect(AlertUrgency.preempts(failed, over: timer))
        #expect(!AlertUrgency.preempts(blocked, over: failed))
        #expect(!AlertUrgency.preempts(timer, over: done))
        #expect(!AlertUrgency.preempts(PeekHarness.alert("x.event", severity: .critical), over: done))
    }
}

@MainActor @Suite struct PeekConcurrencyTests {
    @Test func blockedReplacesAVisibleLowerPeekAtOnce() {
        let h = PeekHarness()
        let events = RecordingPeekEvents()
        h.presenter.events = events
        _ = h.presenter.show(PeekHarness.alert("session.done", severity: .info, title: "done"))
        // Same module: the rate limit does not hold a preempting peek.
        _ = h.presenter.show(PeekHarness.alert("session.blocked", title: "blocked"))
        #expect(h.visibleTitle == "blocked")
        #expect(h.driver.retractCount == 1)
        #expect(h.driver.presented.map(\.content.title) == ["done", "blocked"])
        #expect(events.preemptions.map(\.event.title) == ["done"])
        #expect(h.presenter.queuedAlerts.isEmpty)
    }

    @Test func blockedDoesNotReplaceAVisibleFailedPeek() {
        let h = PeekHarness()
        _ = h.presenter.show(PeekHarness.alert("session.failed", module: "m1", title: "failed"))
        _ = h.presenter.show(PeekHarness.alert("session.blocked", module: "m2", title: "blocked"))
        #expect(h.visibleTitle == "failed")
        #expect(h.presenter.queuedAlerts.map(\.event.title) == ["blocked"])
    }

    @Test func queueFollowsTheUrgencyTableWithTiesInArrivalOrder() {
        let h = PeekHarness()
        _ = h.presenter.show(PeekHarness.alert("session.failed", module: "m0", title: "visible"))
        let arrivals: [(String, AlertSeverity, String)] = [
            ("x.other", .info, "other-info"),
            ("setup.problem", .critical, "setup"),
            ("session.done", .info, "done-1"),
            ("usage.quota_warning", .warn, "quota"),
            ("calendar.reminder", .info, "calendar"),
            ("x.other", .critical, "other-critical"),
            ("time.timer_end", .info, "timer"),
            ("session.done", .info, "done-2"),
            ("session.blocked", .warn, "blocked-1"),
            ("time.break_reminder", .warn, "break"),
            ("session.failed", .critical, "failed-2"),
        ]
        for (index, (kind, severity, title)) in arrivals.enumerated() {
            _ = h.presenter.show(
                PeekHarness.alert(kind, module: ModuleID("m\(index + 1)")!, severity: severity, title: title))
        }
        #expect(h.visibleTitle == "visible")
        #expect(
            h.presenter.queuedAlerts.map(\.event.title) == [
                "blocked-1", "failed-2", "calendar", "timer", "break", "quota", "done-1", "done-2", "setup",
                "other-critical", "other-info",
            ])
        // The queue drains in that order as each peek retracts.
        var shown: [String] = []
        while h.presenter.visible != nil {
            h.presenter.performSecondary()
            if let title = h.visibleTitle { shown.append(title) }
        }
        #expect(shown == h.driver.presented.dropFirst().map(\.content.title))
        #expect(shown.first == "blocked-1")
        #expect(shown.last == "other-info")
    }

    @Test func expandedViewSuppressesPeeks() {
        var expanded = true
        let h = PeekHarness()
        let presenter = PeekPresenter(
            anchors: h.anchors, theme: h.themeController, driver: h.driver, clock: h.clock,
            pointer: { NSPoint(x: 700, y: 980) }, announce: { _ in }, isSuppressed: { expanded },
            logger: testLogger)
        _ = presenter.show(PeekHarness.alert(title: "while open"))
        #expect(presenter.visible == nil)
        #expect(presenter.queuedAlerts.isEmpty)
        #expect(h.driver.presented.isEmpty)
        expanded = false
        _ = presenter.show(PeekHarness.alert(title: "after close"))
        #expect(presenter.visible?.event.title == "after close")
    }

    @Test func queuedPeeksAreDroppedWhenTheExpandedViewOpens() {
        var expanded = false
        let h = PeekHarness()
        let presenter = PeekPresenter(
            anchors: h.anchors, theme: h.themeController, driver: h.driver, clock: h.clock,
            pointer: { NSPoint(x: 700, y: 980) }, announce: { _ in }, isSuppressed: { expanded },
            logger: testLogger)
        let first = presenter.show(PeekHarness.alert(module: "m1", title: "one"))
        _ = presenter.show(PeekHarness.alert(module: "m2", title: "two"))
        expanded = true
        presenter.retract(first)
        #expect(presenter.visible == nil)
        #expect(presenter.queuedAlerts.isEmpty)
        #expect(h.driver.presented.count == 1)
    }
}

/// Story 3.9 through `AlertCenter`: history, reminders, resolved-before-shown.
@MainActor @Suite struct PeekConcurrencyCenterTests {
    @Test func preemptedDoneNeverRepeeksButItsReminderReplaysIt() async {
        let h = PeekActionHarness(kinds: ["session.done": NotifyRule(reminder: .seconds(600))])
        h.post("session.done", title: "done", action: nil)
        h.post("session.blocked", title: "blocked")
        #expect(h.presenter.visible?.event.title == "blocked")
        #expect(h.center.history.map(\.outcome).contains(.preempted))
        #expect(h.activity.entries.contains { $0.outcome == .custom("preempted") })
        #expect(h.center.active.count == 2)

        // The blocked peek ends; the done alert does not peek again.
        h.backend.press(TemporaryShortcuts.secondarySpec)
        _ = await eventually { h.clock.sleeperCount >= 1 }
        await h.advance(.seconds(10))
        #expect(h.presenter.visible == nil)
        #expect(h.driver.presented.map(\.content.title) == ["done", "blocked"])

        // Its reminder replays it once.
        await h.advance(.seconds(600))
        #expect(await eventually { h.presenter.visible?.event.title == "done" })
        #expect(h.driver.presented.count == 3)
    }

    @Test func aQueuedAlertResolvedBeforeShowingIsDroppedAndLogged() async {
        let h = PeekActionHarness()
        h.post("session.blocked", title: "visible")
        let queued = h.post("session.done", title: "queued", action: nil)
        #expect(h.presenter.queuedAlerts.map(\.event.title) == ["queued"])
        queued.resolve()
        #expect(h.presenter.queuedAlerts.isEmpty)
        #expect(h.center.history.last?.outcome == .resolved)
        #expect(h.activity.entries.last?.outcome == .resolved)
        h.backend.press(TemporaryShortcuts.secondarySpec)
        _ = await eventually { h.clock.sleeperCount >= 1 }
        await h.advance(.seconds(10))
        #expect(h.driver.presented.map(\.content.title) == ["visible"])
    }
}
