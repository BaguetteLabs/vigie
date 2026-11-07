import Foundation
import ModuleKit
import Testing

@testable import VigieCore

@Suite struct EventBusTests {
    @Test(arguments: [
        ("agent.", "agent.hook", true),
        ("agent", "agent.hook", true),
        ("agent.", "app.expand", false),
        ("agent.", "agents.usage", false),
        ("agent", "agents.usage", false),
        ("agent.hook", "agent.hook", true),
        ("", "app.expand", true),
    ])
    func prefixMatching(prefix: String, topic: String, expected: Bool) {
        #expect(InProcessEventBus.matches(topic: topic, prefix: prefix) == expected)
    }

    @Test func subscriberReceivesOnlyMatchingTopics() async {
        let bus = InProcessEventBus()
        let stream = bus.subscribe(topicPrefix: "agent.")
        for topic in ["agent.hook", "app.expand", "agents.usage", "agent.end"] {
            bus.publish(EventMessage(topic: topic, payload: Data(), sentAt: Date()))
        }
        var received: [String] = []
        for await message in stream {
            received.append(message.topic)
            if received.count == 2 { break }
        }
        #expect(received == ["agent.hook", "agent.end"])
    }

    @Test func trackedSubscriptionEndsWhenTrackerCancels() async {
        let bus = InProcessEventBus()
        let tracker = RegistrationTracker()
        let stream = ModuleEventBus(bus: bus, tracker: tracker).subscribe(topicPrefix: "agent.")
        #expect(bus.subscriberCount == 1)
        tracker.cancelAll()
        for await _ in stream {}  // returns because the stream finished
        #expect(bus.subscriberCount == 0)
    }
}

@Suite struct SchedulerTests {
    @Test func everyFiresRepeatedlyAndStopsWhenCancelled() async throws {
        let tracker = RegistrationTracker()
        let scheduler = CoreScheduler(tracker: tracker)
        let counter = Counter()
        let token = scheduler.every(.milliseconds(10)) { counter.increment() }
        #expect(tracker.activeCount == 1)
        #expect(await eventually { counter.count >= 3 })
        token.cancel()
        #expect(tracker.activeCount == 0)
        try await Task.sleep(for: .milliseconds(30))
        let afterCancel = counter.count
        try await Task.sleep(for: .milliseconds(60))
        #expect(counter.count == afterCancel)
    }

    @Test func atFiresOnce() async throws {
        let scheduler = CoreScheduler(tracker: RegistrationTracker())
        let counter = Counter()
        _ = scheduler.at(Date().addingTimeInterval(0.02)) { counter.increment() }
        #expect(await eventually { counter.count == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(counter.count == 1)
    }

    @Test func trackerCancelAllStopsJobsAndRejectsLateRegistrations() async throws {
        let tracker = RegistrationTracker()
        let scheduler = CoreScheduler(tracker: tracker)
        let counter = Counter()
        _ = scheduler.every(.milliseconds(10)) { counter.increment() }
        tracker.cancelAll()
        _ = scheduler.every(.milliseconds(10)) { counter.increment() }
        try await Task.sleep(for: .milliseconds(80))
        #expect(counter.count == 0)
        #expect(tracker.activeCount == 0)
    }
}

#if DEBUG
    @MainActor @Suite struct DevSampleModuleTests {
        @Test func manifestAndViews() {
            let module = DevSampleModule()
            #expect(DevSampleModule.descriptor.manifest.id == "dev.sample")
            #expect(module.manifest.id == "dev.sample")
            #expect(module.compactView(size: .icon) == nil)
            #expect(module.compactView(size: .short) != nil)
            #expect(module.compactView(size: .wide) != nil)
            #expect(module.leftWingItems().map(\.priority) == [50])
        }

        @Test func cyclesStateThroughTheScheduler() async throws {
            let tracker = RegistrationTracker()
            let context = CoreModuleContextFactory(
                environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus()
            ).makeContext(for: DevSampleModule.staticManifest, tracker: tracker)
            let module = DevSampleModule()
            try await module.start(context: context)
            #expect(module.state == .ambient)
            #expect(tracker.activeCount == 1)
            module.toggle()
            #expect(module.state == .active)
            module.toggle()
            #expect(module.state == .ambient)
            await module.stop()
            tracker.cancelAll()
            #expect(module.state == .hidden)
        }
    }
#endif
