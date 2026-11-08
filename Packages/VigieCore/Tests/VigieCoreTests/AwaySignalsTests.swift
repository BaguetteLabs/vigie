import CoreGraphics
import Darwin
import Foundation
import Testing

@testable import VigieCore

/// Story 20.1: the Away signal prototype on fakes, plus the local probe (`VIGIE_AWAY_PROBE=1`).
@Suite struct AwaySignalsTests {
    struct FakeIdle: IdleTimeReading {
        let seconds: TimeInterval
        func secondsSinceLastInput() -> TimeInterval { seconds }
    }

    @Test func idleThresholdComparesTheReading() {
        let threshold = IdleThreshold(threshold: 90)
        #expect(!threshold.isIdle(FakeIdle(seconds: 89.9)))
        #expect(threshold.isIdle(FakeIdle(seconds: 90)))
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(threshold.lastInput(FakeIdle(seconds: 30), now: now) == now.addingTimeInterval(-30))
    }

    @Test func eachScreenConditionIsClearedOnlyByItsOwnEnd() {
        var screen = ScreenAvailability()
        #expect(screen.isAvailable)
        screen.apply(.screenLocked)
        screen.apply(.screensaverStarted)
        #expect(!screen.isAvailable)
        screen.apply(.screensaverStopped)
        #expect(!screen.isAvailable, "still locked")
        screen.apply(.screenUnlocked)
        #expect(screen.isAvailable)
        screen.apply(.sessionResigned)
        #expect(!screen.isAvailable)
        screen.apply(.sessionActivated)
        #expect(screen.isAvailable)
    }

    @Test func systemWakeAlsoClearsDisplaySleep() {
        var screen = ScreenAvailability()
        screen.apply(.displaysSlept)
        screen.apply(.systemWillSleep)
        #expect(!screen.isAvailable)
        screen.apply(.systemDidWake)
        #expect(screen.isAvailable)
    }

    @Test func lockedAtLaunchStartsUnavailable() {
        #expect(!ScreenAvailability(locked: true).isAvailable)
    }

    @Test func observerMapsEveryNotification() async {
        let distributed = NotificationCenter()
        let workspace = NotificationCenter()
        let observer = SystemLockStateObserver(distributedCenter: distributed, workspaceCenter: workspace)
        let stream = observer.signals
        for (name, _) in SystemLockStateObserver.distributed {
            distributed.post(name: Notification.Name(name), object: nil)
        }
        for (name, _) in SystemLockStateObserver.workspace {
            workspace.post(name: name, object: nil)
        }
        var received: [ScreenSignal] = []
        for await event in stream {
            received.append(event.signal)
            if received.count == ScreenSignal.allCases.count { break }
        }
        #expect(Set(received) == Set(ScreenSignal.allCases))
    }

    @Test func realReaderReturnsANonNegativeValue() {
        #expect(CGEventSourceIdleReader().secondsSinceLastInput() >= 0)
    }

    // MARK: Probe

    static var probeEnabled: Bool { ProcessInfo.processInfo.environment["VIGIE_AWAY_PROBE"] == "1" }

    /// The spike measurements: idle value growth, per-type values, call cost, CPU over a polling loop at 1 s and
    /// 5 s, a held idle-sleep activity, and every screen signal seen meanwhile. `VIGIE_AWAY_PROBE_SECONDS`
    /// (default 60) is the length of each loop.
    @Test(.enabled(if: probeEnabled), .timeLimit(.minutes(10)))
    func probe() async throws {
        let seconds = Int(ProcessInfo.processInfo.environment["VIGIE_AWAY_PROBE_SECONDS"] ?? "") ?? 60
        let reader = CGEventSourceIdleReader()
        let observer = SystemLockStateObserver()
        let start = Date()
        print("away probe: start \(start), locked now = \(observer.isScreenLockedNow())")

        let signalTask = Task {
            for await event in observer.signals {
                print(
                    "away probe: signal \(event.signal.rawValue) at +\(String(format: "%.1f", event.at.timeIntervalSince(start))) s"
                )
            }
        }

        let types: [(String, CGEventType)] = [
            ("any", CGEventSourceIdleReader.anyInput), ("null", .null), ("keyDown", .keyDown),
            ("mouseMoved", .mouseMoved), ("leftMouseDown", .leftMouseDown), ("scrollWheel", .scrollWheel),
        ]
        for (name, type) in types {
            let combined = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
            let hid = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type)
            print(
                "away probe: type \(name): combined \(String(format: "%.1f", combined)) s, hid \(String(format: "%.1f", hid)) s"
            )
        }

        // Cost of one call.
        let calls = 10_000
        let usageBefore = Self.cpuSeconds()
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            var sink = 0.0
            for _ in 0..<calls { sink += reader.secondsSinceLastInput() }
            precondition(sink >= 0)
        }
        let cpuPerCall = (Self.cpuSeconds() - usageBefore) / Double(calls)
        print("away probe: \(calls) calls in \(elapsed); cpu per call \(String(format: "%.1f", cpuPerCall * 1e6)) µs")

        // Polling at 1 s, then 5 s while holding an idle-sleep activity.
        for (interval, holdActivity) in [(1, false), (5, true)] {
            let activity =
                holdActivity
                ? ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "away probe") : nil
            let cpu0 = Self.cpuSeconds()
            var first: Double?
            var last = 0.0
            var resets = 0
            let rounds = max(seconds / interval, 1)
            for _ in 0..<rounds {
                try await Task.sleep(for: .seconds(interval))
                let value = reader.secondsSinceLastInput()
                if let previous = first.map({ _ in last }), value < previous { resets += 1 }
                if first == nil { first = value }
                last = value
            }
            let cpu = Self.cpuSeconds() - cpu0
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            print(
                "away probe: poll every \(interval) s for \(rounds * interval) s"
                    + (holdActivity ? " holding .idleSystemSleepDisabled" : "")
                    + ": idle \(String(format: "%.1f", first ?? 0)) -> \(String(format: "%.1f", last)) s, \(resets) resets, process cpu \(String(format: "%.4f", cpu)) s"
            )
        }
        signalTask.cancel()
        print("away probe: locked now = \(observer.isScreenLockedNow())")
    }

    /// User + system CPU time of this process.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }
}
