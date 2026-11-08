import Foundation
import ModuleKit
import Synchronization
import Testing

@testable import VigieCore

/// Story 20.3: `CoreAwayService` on a counting idle reader, a scripted screen observer and a hand-driven sleep.
@MainActor @Suite struct AwayServiceTests {
    /// Idle seconds the test sets; counts reads.
    final class CountingIdle: IdleTimeReading, Sendable {
        private let state = Mutex((seconds: 0.0, reads: 0))
        var reads: Int { state.withLock { $0.reads } }
        func set(_ seconds: TimeInterval) { state.withLock { $0.seconds = seconds } }
        func secondsSinceLastInput() -> TimeInterval {
            state.withLock {
                $0.reads += 1
                return $0.seconds
            }
        }
    }

    /// Screen signals the test sends; counts open observer streams.
    final class ScriptedSignals: LockStateObserving, Sendable {
        private let state = Mutex((continuations: [UUID: AsyncStream<ScreenSignalEvent>.Continuation](), locked: false))
        var openStreams: Int { state.withLock { $0.continuations.count } }
        func setLockedAtStart(_ locked: Bool) { state.withLock { $0.locked = locked } }
        var signals: AsyncStream<ScreenSignalEvent> {
            let (stream, continuation) = AsyncStream<ScreenSignalEvent>.makeStream()
            let id = UUID()
            state.withLock { $0.continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                _ = self?.state.withLock { $0.continuations.removeValue(forKey: id) }
            }
            return stream
        }
        func isScreenLockedNow() -> Bool { state.withLock { $0.locked } }
        func send(_ event: ScreenSignalEvent) {
            for continuation in state.withLock({ Array($0.continuations.values) }) { continuation.yield(event) }
        }
    }

    /// Each `sleep` waits until `tick()`.
    final class ManualSleeper: Sendable {
        private let state = Mutex([UUID: CheckedContinuation<Void, any Error>]())
        var waiting: Int { state.withLock { $0.count } }

        func sleep(_ duration: Duration) async throws {
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    state.withLock { $0[id] = continuation }
                    if Task.isCancelled, let c = state.withLock({ $0.removeValue(forKey: id) }) {
                        c.resume(throwing: CancellationError())
                    }
                }
            } onCancel: {
                if let c = state.withLock({ $0.removeValue(forKey: id) }) { c.resume(throwing: CancellationError()) }
            }
        }

        func tick() {
            let all = state.withLock { state in
                defer { state.removeAll() }
                return Array(state.values)
            }
            for continuation in all { continuation.resume() }
        }
    }

    final class RecordingActivity: ActivityLog, Sendable {
        private let state = Mutex([ActivityEntry]())
        var entries: [ActivityEntry] { state.withLock { $0 } }
        func record(_ entry: ActivityEntry) { state.withLock { $0.append(entry) } }
    }

    final class Clock: Sendable {
        private let state = Mutex(Date(timeIntervalSinceReferenceDate: 800_000_000))
        var now: Date { state.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { state.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    let idle = CountingIdle()
    let signals = ScriptedSignals()
    let sleeper = ManualSleeper()
    let activity = RecordingActivity()
    let clock = Clock()

    func makeService(threshold: Duration = .seconds(90)) -> CoreAwayService {
        let clock = clock
        let sleeper = sleeper
        return CoreAwayService(
            idle: idle, observer: signals, threshold: { threshold }, now: { clock.now },
            sleep: { try await sleeper.sleep($0) }, activity: activity)
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Lets one poll run: waits for the loop to sleep, wakes it, waits for it to sleep again.
    func poll() async {
        _ = await eventually { sleeper.waiting > 0 }
        let before = idle.reads
        sleeper.tick()
        _ = await eventually { idle.reads > before && sleeper.waiting > 0 }
    }

    // MARK: Subscribers

    @Test func nothingIsReadOrObservedWithoutSubscribers() async {
        let service = makeService()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(!service.isMonitoring)
        #expect(idle.reads == 0, "PRD FR-4: no polling without a subscriber")
        #expect(signals.openStreams == 0)
        #expect(sleeper.waiting == 0)
        #expect(service.context.presence == .present)
        #expect(activity.entries.isEmpty)
    }

    @Test func firstSubscriberStartsAndLastOneLeavingStops() async {
        let service = makeService()
        let (held1, first) = service.context.subscription()
        defer { withExtendedLifetime(held1) {} }
        #expect(await eventually { service.isMonitoring })
        #expect(signals.openStreams == 1)
        #expect(idle.reads == 1, "one check at start")
        let (held2, second) = service.context.subscription()
        defer { withExtendedLifetime(held2) {} }
        await poll()
        #expect(idle.reads == 2)
        first.cancel()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(service.isMonitoring, "one subscriber left")
        second.cancel()
        #expect(await eventually { !service.isMonitoring })
        #expect(await eventually { signals.openStreams == 0 })
        let reads = idle.reads
        sleeper.tick()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(idle.reads == reads, "polling stopped with the last subscriber")
        #expect(sleeper.waiting == 0)
    }

    @Test func aStreamEndingByCancellationStopsTheService() async {
        let service = makeService()
        let stream = service.context.changes
        let task = Task { for await _ in stream {} }
        #expect(await eventually { service.isMonitoring })
        task.cancel()
        #expect(await eventually { !service.isMonitoring })
    }

    @Test func aModulesStreamsEndWhenItStops() async {
        let service = makeService()
        let tracker = RegistrationTracker()
        let away = TrackedAwayService(base: service.context, tracker: tracker)
        let held = away.changes
        defer { withExtendedLifetime(held) {} }
        #expect(await eventually { service.isMonitoring })
        tracker.cancelAll()
        #expect(await eventually { !service.isMonitoring })
    }

    // MARK: Thresholds

    @Test func awayOnceIdleReachesTheThresholdSinceTheLastInput() async {
        let service = makeService()
        let stream = service.context.changes
        #expect(await eventually { service.isMonitoring })
        idle.set(89)
        await poll()
        #expect(service.presence == .present)
        idle.set(92)
        await poll()
        #expect(service.presence == .away(since: clock.now.addingTimeInterval(-92)))
        #expect(service.context.presence == service.presence)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .away(since: clock.now.addingTimeInterval(-92)))
        // Staying away keeps the first `since`.
        clock.advance(5)
        idle.set(97)
        await poll()
        #expect(service.presence == .away(since: clock.now.addingTimeInterval(-97)))
        idle.set(1)
        await poll()
        #expect(service.presence == .present)
        #expect(await iterator.next() == .present)
    }

    @Test func thresholdIsReadOnEveryCheck() async {
        let value = Mutex(Duration.seconds(90))
        let clock = clock
        let sleeper = sleeper
        let service = CoreAwayService(
            idle: idle, observer: signals, threshold: { value.withLock { $0 } }, now: { clock.now },
            sleep: { try await sleeper.sleep($0) })
        let (held3, token) = service.context.subscription()
        defer { withExtendedLifetime(held3) {} }
        defer { token.cancel() }
        #expect(await eventually { service.isMonitoring })
        idle.set(60)
        await poll()
        #expect(service.presence == .present)
        value.withLock { $0 = .seconds(45) }
        await poll()
        #expect(service.presence.isAway)
    }

    // MARK: Screen signals

    @Test func lockMakesAwayAtOnceWithTheEventTime() async {
        let service = makeService()
        let (held4, token) = service.context.subscription()
        defer { withExtendedLifetime(held4) {} }
        defer { token.cancel() }
        #expect(await eventually { service.isMonitoring && signals.openStreams == 1 })
        idle.set(3)
        let lockedAt = clock.now.addingTimeInterval(-1)
        signals.send(ScreenSignalEvent(.screenLocked, at: lockedAt))
        #expect(await eventually { service.presence == .away(since: lockedAt) })
        // Unlocking alone is not presence while input idle is past the threshold.
        idle.set(200)
        signals.send(ScreenSignalEvent(.screenUnlocked, at: clock.now))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(service.presence == .away(since: lockedAt))
        // The unlock input: Present.
        idle.set(0.5)
        await poll()
        #expect(service.presence == .present)
    }

    @Test func screensaverAndDisplaySleepAreAway() async {
        for (start, end) in [
            (ScreenSignal.screensaverStarted, ScreenSignal.screensaverStopped), (.displaysSlept, .displaysWoke),
            (.sessionResigned, .sessionActivated),
        ] {
            let service = makeService()
            let (held5, token) = service.context.subscription()
            defer { withExtendedLifetime(held5) {} }
            #expect(await eventually { service.isMonitoring && signals.openStreams == 1 })
            signals.send(ScreenSignalEvent(start, at: clock.now))
            #expect(await eventually { service.presence.isAway }, "\(start)")
            signals.send(ScreenSignalEvent(end, at: clock.now))
            #expect(await eventually { service.presence == .present }, "\(end)")
            token.cancel()
            #expect(await eventually { !service.isMonitoring && signals.openStreams == 0 })
        }
    }

    @Test func systemSleepCountsAsAwayFromTheSleepTime() async {
        let service = makeService()
        let (held6, token) = service.context.subscription()
        defer { withExtendedLifetime(held6) {} }
        defer { token.cancel() }
        #expect(await eventually { service.isMonitoring && signals.openStreams == 1 })
        let sleptAt = clock.now
        signals.send(ScreenSignalEvent(.systemWillSleep, at: sleptAt))
        #expect(await eventually { service.presence == .away(since: sleptAt) })
        clock.advance(3600)
        signals.send(ScreenSignalEvent(.systemDidWake, at: clock.now))
        #expect(await eventually { service.presence == .present })
    }

    @Test func lockedAtStartStartsAway() async {
        signals.setLockedAtStart(true)
        let service = makeService()
        let (held7, token) = service.context.subscription()
        defer { withExtendedLifetime(held7) {} }
        defer { token.cancel() }
        #expect(await eventually { service.presence.isAway })
    }

    @Test func keepAwakeDoesNotHideAway() async {
        // The service never consults the power service: a held keep-awake request changes nothing.
        let power = CorePowerService(isEnabled: { true }, activities: NoActivities())
        let request = power.preventIdleSleep(reason: "agent working")
        defer { request.cancel() }
        let service = makeService()
        let (held8, token) = service.context.subscription()
        defer { withExtendedLifetime(held8) {} }
        defer { token.cancel() }
        #expect(await eventually { service.isMonitoring })
        idle.set(120)
        await poll()
        #expect(service.presence.isAway)
    }

    struct NoActivities: IdleSleepActivities {
        func begin(reason: String) -> IdleSleepActivity { IdleSleepActivity(NSObject()) }
        func end(_ activity: IdleSleepActivity) {}
    }

    // MARK: Activity log

    @Test func transitionsAreLogged() async {
        let service = makeService()
        let (held9, token) = service.context.subscription()
        defer { withExtendedLifetime(held9) {} }
        #expect(await eventually { service.isMonitoring })
        idle.set(100)
        await poll()
        idle.set(0)
        await poll()
        token.cancel()
        #expect(await eventually { !service.isMonitoring })
        let entries = activity.entries
        #expect(entries.map(\.kind) == ["away.away", "away.present"], "stopping is not a transition")
        #expect(entries.allSatisfy { $0.category == .presence && $0.module == nil })
        #expect(entries.first?.detail["reason"] == "idle")
        #expect(entries.first?.detail["since"] != nil)
        #expect(service.context.presence == .present)
    }

    // MARK: Factory

    @Test func everyModuleGetsTheSharedService() throws {
        let factory = CoreModuleContextFactory(
            environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus())
        let manifest = ModuleManifest(id: "sample", name: "Sample", icon: "circle")
        let context = factory.makeContext(for: manifest, tracker: RegistrationTracker())
        let away = try #require(context.away as? TrackedAwayService)
        #expect(away.base === factory.away.context)
        #expect(!factory.away.isMonitoring)
    }
}
