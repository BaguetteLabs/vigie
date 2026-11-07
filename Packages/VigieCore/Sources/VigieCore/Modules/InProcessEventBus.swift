import Foundation
import ModuleKit
import Synchronization

/// The process-wide event bus. The Event Server (Story 4.1) publishes into it; modules subscribe through their
/// context (`ModuleEventBus`), which tracks each subscription.
public final class InProcessEventBus: EventBus {
    private struct Subscriber {
        let prefix: String
        let continuation: AsyncStream<EventMessage>.Continuation
    }

    private let subscribers = Mutex<[UUID: Subscriber]>([:])

    public init() {}

    /// Delivers `message` to every subscriber whose prefix matches its topic.
    public func publish(_ message: EventMessage) {
        let targets = subscribers.withLock { subscribers in
            subscribers.values.filter { Self.matches(topic: message.topic, prefix: $0.prefix) }.map(\.continuation)
        }
        for continuation in targets { continuation.yield(message) }
    }

    /// A subscription stream and the token that ends it.
    public func subscription(topicPrefix: String) -> (stream: AsyncStream<EventMessage>, token: RegistrationToken) {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: EventMessage.self)
        continuation.onTermination = { [weak self] _ in
            _ = self?.subscribers.withLock { $0.removeValue(forKey: id) }
        }
        subscribers.withLock { $0[id] = Subscriber(prefix: topicPrefix, continuation: continuation) }
        return (stream, RegistrationToken(id: id) { continuation.finish() })
    }

    public func subscribe(topicPrefix: String) -> AsyncStream<EventMessage> {
        subscription(topicPrefix: topicPrefix).stream
    }

    public var subscriberCount: Int { subscribers.withLock { $0.count } }

    /// `prefix` matches `topic` when equal, or when `topic` lies under it: `agent` and `agent.` match
    /// `agent.hook` but not `agents.usage`. An empty prefix matches everything.
    public static func matches(topic: String, prefix: String) -> Bool {
        if prefix.isEmpty || topic == prefix { return true }
        let scope = prefix.hasSuffix(".") ? prefix : prefix + "."
        return topic.hasPrefix(scope)
    }
}

/// A module's view of the bus: every subscription is tracked and ends when the module stops.
struct ModuleEventBus: EventBus {
    let bus: InProcessEventBus
    let tracker: RegistrationTracker

    func subscribe(topicPrefix: String) -> AsyncStream<EventMessage> {
        let (stream, token) = bus.subscription(topicPrefix: topicPrefix)
        tracker.track(token)
        return stream
    }
}
