import Foundation
import ModuleKit
import os

/// Handles the core's own bus topics (`app.*`, sent by `vigie reload` and `vigie expand`, Story 4.3):
/// `app.reload` runs `onReload`, `app.expand` runs `onExpand`, `app.focus` (`vigie event app.focus
/// '{"active":true}'` from a Shortcuts automation, Story 3.10) runs `onFocus`. Others are logged and ignored.
@MainActor
public final class AppTopics {
    public static let reloadTopic = "app.reload"
    public static let expandTopic = "app.expand"
    public static let focusTopic = "app.focus"

    private let bus: InProcessEventBus
    private let onReload: @MainActor () async -> Void
    private let onExpand: @MainActor (EventMessage) -> Void
    private let onFocus: @MainActor (EventMessage) -> Void
    private let logger: Logger
    private var token: RegistrationToken?
    private var task: Task<Void, Never>?

    public init(
        bus: InProcessEventBus,
        logger: Logger,
        onReload: @escaping @MainActor () async -> Void,
        onExpand: @escaping @MainActor (EventMessage) -> Void,
        onFocus: @escaping @MainActor (EventMessage) -> Void = { _ in }
    ) {
        self.bus = bus
        self.logger = logger
        self.onReload = onReload
        self.onExpand = onExpand
        self.onFocus = onFocus
    }

    /// Subscribes to `app.`; call before `EventServer.releaseQueue()` so queued commands are seen.
    public func start() {
        guard task == nil else { return }
        let (stream, token) = bus.subscription(topicPrefix: "app.")
        self.token = token
        task = Task { @MainActor [weak self] in
            for await message in stream {
                guard let self else { return }
                await self.handle(message)
            }
        }
    }

    public func stop() {
        token?.cancel()
        token = nil
        task?.cancel()
        task = nil
    }

    private func handle(_ message: EventMessage) async {
        switch message.topic {
        case Self.reloadTopic:
            logger.info("reload requested")
            await onReload()
            logger.info("reload done")
        case Self.expandTopic:
            onExpand(message)
        case Self.focusTopic:
            onFocus(message)
        default:
            logger.debug("ignored app topic \(message.topic, privacy: .public)")
        }
    }
}
