import AppKit
import ModuleKit
import OSLog
import VigieCore
import VigieUI
import Wire

/// Owns process-level lifecycle: accessory policy and the single-instance lock (AD-21), then assembles the
/// theme, module registry and Notch Host (AD-2, AD-4).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var instanceLock: InstanceLock?
    private var themeController: ThemeController?
    private var registry: ModuleRegistry?
    private var notchHost: NotchHost?
    private var contextMenu: NotchContextMenu?
    private var isShuttingDown = false

    private let environment = AppEnvironment.current
    private lazy var logger = Logger(subsystem: environment.logSubsystem, category: "app")

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppActivation.configureAsAccessory()
        // Must run before anything else touches app storage.
        do {
            instanceLock = try InstanceLock.acquire(at: environment.instanceLockURL)
        } catch InstanceLockError.alreadyHeld {
            SecondInstance.notifyRunningInstanceAndQuit(environment: environment)
        } catch {
            logger.error("instance lock failed: \(String(describing: error), privacy: .public)")
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard instanceLock != nil else { return }
        assemble()
    }

    private func assemble() {
        let library: ThemeLibrary
        do {
            library = try ThemeLoader.loadBundled()
        } catch {
            logger.fault("bundled themes unreadable: \(String(describing: error), privacy: .public)")
            NSApp.terminate(nil)
            return
        }
        let themeController = ThemeController(library: library)
        themeController.startObservingSystem()

        let eventBus = InProcessEventBus()
        let contextFactory = CoreModuleContextFactory(environment: environment, eventBus: eventBus)
        var descriptors: [ModuleDescriptor] = []
        var enabled: [ModuleID: Bool] = [:]
        #if DEBUG
            descriptors.append(DevSampleModule.descriptor)
            enabled[DevSampleModule.staticManifest.id] = true
        #endif
        let registry = ModuleRegistry(
            descriptors: descriptors,
            enablement: StaticEnablement(values: enabled),
            contextFactory: contextFactory,
            logger: Logger(subsystem: environment.logSubsystem, category: "modules"))

        let contextMenu = NotchContextMenu()
        let host = NotchHost(
            themeController: themeController,
            registry: registry,
            contextMenu: contextMenu,
            logger: Logger(subsystem: environment.logSubsystem, category: "host"))

        self.themeController = themeController
        self.registry = registry
        self.contextMenu = contextMenu
        self.notchHost = host

        host.start()
        Task { await registry.start() }
    }

    /// Stops modules before quitting (their storage flushes asynchronously).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let registry, !isShuttingDown else { return .terminateNow }
        isShuttingDown = true
        notchHost?.stop()
        Task {
            await registry.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        instanceLock?.release()
        instanceLock = nil
    }
}
