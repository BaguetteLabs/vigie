import AppKit
import OSLog
import VigieCore
import Wire

/// Owns process-level lifecycle: accessory policy and the single-instance lock (AD-21).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var instanceLock: InstanceLock?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let env = AppEnvironment.current
        AppActivation.configureAsAccessory()
        // Must run before anything else touches app storage.
        do {
            instanceLock = try InstanceLock.acquire(at: env.instanceLockURL)
        } catch InstanceLockError.alreadyHeld {
            SecondInstance.notifyRunningInstanceAndQuit(environment: env)
        } catch {
            Logger(subsystem: env.logSubsystem, category: "app")
                .error("instance lock failed: \(String(describing: error), privacy: .public)")
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        instanceLock?.release()
        instanceLock = nil
    }
}
