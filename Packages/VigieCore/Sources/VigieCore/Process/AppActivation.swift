import AppKit
import OSLog
import Wire

@MainActor
public enum AppActivation {
    /// Accessory policy: no Dock icon, no menu bar item (AD-21, FR94).
    public static func configureAsAccessory() {
        NSApp.setActivationPolicy(.accessory)
    }
}

public enum SecondInstance {
    /// How long the second instance waits for the running one's socket (AD-21).
    public static let expandBudget: Duration = .milliseconds(250)

    /// Called when the instance lock is already held by a running Vigie.
    ///
    /// Sends an `app.expand` envelope to `environment.socketURL` off the main actor, logs the
    /// outcome, then calls `terminate` on the main actor. There is deliberately no spool
    /// fallback: a spooled expand would be replayed at the next launch and open the island
    /// for no reason. The returned task completes after `terminate` ran and yields whether
    /// the envelope was written.
    @MainActor
    @discardableResult
    public static func notifyRunningInstanceAndQuit(
        environment: AppEnvironment,
        budget: Duration = expandBudget,
        now: @escaping @Sendable () -> Date = { Date() },
        terminate: @escaping @MainActor @Sendable () -> Void = { NSApp.terminate(nil) }
    ) -> Task<Bool, Never> {
        let logger = Logger(subsystem: environment.logSubsystem, category: "app")
        let socketPath = environment.socketURL.path
        return Task.detached(priority: .userInitiated) {
            let envelope = Envelope(topic: Topic.appExpand, sentAt: now(), payload: .object([:]))
            let sent: Bool
            if let line = try? envelope.encodeLine() {
                sent = SocketClient.send(line, toSocketAt: socketPath, deadline: .now.advanced(by: budget))
            } else {
                sent = false
            }
            if sent {
                logger.info("another instance holds the lock; sent app.expand, quitting")
            } else {
                logger.error("another instance holds the lock; app.expand not delivered, quitting")
            }
            await terminate()
            return sent
        }
    }
}
