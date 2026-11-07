import AppKit
import Foundation
import ModuleKit
import Synchronization
import Testing

@testable import VigieCore

/// Counts begun and ended activities.
final class FakeIdleSleepActivities: IdleSleepActivities {
    private let state = Mutex((begun: 0, ended: 0, reasons: [String]()))

    var begun: Int { state.withLock { $0.begun } }
    var ended: Int { state.withLock { $0.ended } }
    var held: Int { state.withLock { $0.begun - $0.ended } }
    var reasons: [String] { state.withLock { $0.reasons } }

    func begin(reason: String) -> IdleSleepActivity {
        state.withLock {
            $0.begun += 1
            $0.reasons.append(reason)
        }
        return IdleSleepActivity(NSObject())
    }

    func end(_ activity: IdleSleepActivity) { state.withLock { $0.ended += 1 } }
}

final class Flag: Sendable {
    private let value: Mutex<Bool>
    init(_ value: Bool) { self.value = Mutex(value) }
    var isOn: Bool {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}

@Suite struct PowerServiceTests {
    @Test func settingOffTakesNoAssertion() {
        let activities = FakeIdleSleepActivities()
        let power = CorePowerService(
            isEnabled: { false }, activities: activities, notificationCenter: NotificationCenter())
        let token = power.preventIdleSleep(reason: "Agent session working")
        #expect(activities.begun == 0)
        #expect(!power.isPreventingIdleSleep)
        #expect(power.openRequests == 1)
        token.cancel()
        token.cancel()
        #expect(activities.ended == 0)
        #expect(power.openRequests == 0)
    }

    @Test func settingOnHoldsOneActivityForAllRequests() {
        let activities = FakeIdleSleepActivities()
        let power = CorePowerService(
            isEnabled: { true }, activities: activities, notificationCenter: NotificationCenter())
        let first = power.preventIdleSleep(reason: "Agent session working")
        let second = power.preventIdleSleep(reason: "other")
        #expect(activities.begun == 1)
        #expect(activities.reasons == ["Agent session working"])
        #expect(power.isPreventingIdleSleep)
        first.cancel()
        #expect(activities.held == 1)
        second.cancel()
        second.cancel()
        #expect(activities.begun == 1)
        #expect(activities.ended == 1)
        #expect(!power.isPreventingIdleSleep)
    }

    @Test func settingChangesApplyToOpenRequests() {
        let activities = FakeIdleSleepActivities()
        let flag = Flag(false)
        let power = CorePowerService(
            isEnabled: { flag.isOn }, activities: activities, notificationCenter: NotificationCenter())
        let token = power.preventIdleSleep(reason: "r")
        #expect(activities.held == 0)
        flag.isOn = true
        power.settingChanged()
        #expect(activities.held == 1)
        flag.isOn = false
        power.settingChanged()
        #expect(activities.held == 0)
        token.cancel()
        #expect(activities.begun == 1)
    }

    @Test func deallocationEndsTheActivity() {
        let activities = FakeIdleSleepActivities()
        var power: CorePowerService? = CorePowerService(
            isEnabled: { true }, activities: activities, notificationCenter: NotificationCenter())
        _ = power?.preventIdleSleep(reason: "r")
        #expect(activities.held == 1)
        power = nil
        #expect(activities.held == 0)
    }

    @Test func sleepWakeFollowsTheWorkspaceNotifications() async {
        let center = NotificationCenter()
        let power = CorePowerService(
            isEnabled: { false }, activities: FakeIdleSleepActivities(), notificationCenter: center)
        let stream = power.sleepWake
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        var events: [SleepWakeEvent] = []
        for await event in stream {
            events.append(event)
            if events.count == 2 { break }
        }
        #expect(events == [.willSleep, .didWake])
    }

    @Test func trackedRequestsEndWhenTheModuleStops() {
        let activities = FakeIdleSleepActivities()
        let power = CorePowerService(
            isEnabled: { true }, activities: activities, notificationCenter: NotificationCenter())
        let tracker = RegistrationTracker()
        _ = TrackedPowerService(base: power, tracker: tracker).preventIdleSleep(reason: "r")
        #expect(activities.held == 1)
        tracker.cancelAll()
        #expect(activities.held == 0)
    }

    @MainActor @Test func factoryReadsPreventIdleSleepFromConfig() async throws {
        let fixture = ConfigFixture()
        let (store, watcher) = try await fixture.makeStore(config: "[general]\nprevent_idle_sleep = false\n")
        let factory = CoreModuleContextFactory(
            environment: fixture.environment, eventBus: InProcessEventBus(), configStore: store)
        let enabled = { factory.power.preventIdleSleep(reason: "probe") }
        let token = enabled()
        #expect(!factory.power.isPreventingIdleSleep)
        try fixture.writeConfig("[general]\nprevent_idle_sleep = true\n")
        await store.fireAndSettle(watcher)
        for _ in 0..<100 where !factory.power.isPreventingIdleSleep {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(factory.power.isPreventingIdleSleep)
        token.cancel()
        #expect(!factory.power.isPreventingIdleSleep)
    }
}
