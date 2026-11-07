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
    /// Called when the instance lock is already held by a running Vigie.
    ///
    /// TODO(Story 4.3): once the Event Server exists, connect to `environment.socketURL`
    /// and send `app.expand` to the running instance before quitting.
    @MainActor
    public static func notifyRunningInstanceAndQuit(
        environment: AppEnvironment,
        terminate: @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        Logger(subsystem: environment.logSubsystem, category: "app")
            .info("another instance holds the lock; quitting")
        terminate()
    }
}
