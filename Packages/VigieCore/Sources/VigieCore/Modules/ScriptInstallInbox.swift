import Foundation
@_spi(Host) import ModuleKit
import os

/// The `vigie://install` links of this launch (Story 12.9, AD-18), between the App's open-URL handler and the
/// integrations module (`context.scriptFolder.installRequests()`). A link that arrives before the module subscribed
/// (macOS delivers the link of a launch-by-URL while the app is still assembling, or the module is not started yet)
/// is queued and delivered when it subscribes.
@MainActor
public final class ScriptInstallInbox {
    private var pending: [ScriptInstallRequest] = []
    private var continuation: AsyncStream<ScriptInstallRequest>.Continuation?
    private var generation = 0

    public init() {}

    /// Requests waiting for a subscriber.
    public var pendingCount: Int { pending.count }
    /// Whether a module is listening.
    public var hasSubscriber: Bool { continuation != nil }

    public func submit(_ request: ScriptInstallRequest) {
        if let continuation {
            continuation.yield(request)
        } else {
            pending.append(request)
        }
    }

    /// Starts the one subscription (a previous one is finished), delivering the queued requests first. `finish`
    /// ends it; later requests queue again.
    public func subscribe() -> (stream: AsyncStream<ScriptInstallRequest>, finish: @Sendable () -> Void) {
        continuation?.finish()
        generation += 1
        let current = generation
        let (stream, continuation) = AsyncStream<ScriptInstallRequest>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation
        for request in pending { continuation.yield(request) }
        pending = []
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.ended(current) }
        }
        return (stream, { continuation.finish() })
    }

    private func ended(_ subscription: Int) {
        if subscription == generation { continuation = nil }
    }
}

/// The App's open-URL handler (AD-20, Story 12.9): routes `<scheme>://install?url=…[&sig=…]` to the
/// ``ScriptInstallInbox`` with a `UserIntent` (the user clicked the link, so the Script Confirmation may come
/// forward in Settings); any other URL is ignored with a log line.
@MainActor
public struct AppURLRouter {
    public let scheme: String
    public let inbox: ScriptInstallInbox
    let logger: Logger

    /// - Parameter scheme: `AppEnvironment.urlScheme` (`vigie`, `vigie-dev` in dev builds, AD-17).
    public init(scheme: String, inbox: ScriptInstallInbox, logger: Logger) {
        self.scheme = scheme
        self.inbox = inbox
        self.logger = logger
    }

    /// Handles the URLs of one open event; returns how many became install requests.
    @discardableResult
    public func handle(_ urls: [URL]) -> Int {
        var routed = 0
        for url in urls {
            switch ScriptInstallRequest.parse(link: url, scheme: scheme, intent: UserIntent()) {
            case .success(let request):
                inbox.submit(request)
                routed += 1
                // The user's browsing: the host only, private in the log.
                logger.info(
                    "install link received for host \(request.fileURL.host() ?? "-", privacy: .private)")
            case .failure(let problem):
                logger.error("ignored URL: \(String(describing: problem), privacy: .public)")
            }
        }
        return routed
    }
}
