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
    private var configStore: ConfigStore?
    private var hotkeyBridge: HotkeyConfigBridge?
    private var hotkeyTokens: [RegistrationToken] = []
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

        let contextMenu = NotchContextMenu()
        self.themeController = themeController
        self.contextMenu = contextMenu

        // Config must be loaded before modules start (enablement, hotkeys and the host read it).
        Task { @MainActor in
            await self.assembleServices(themeController: themeController, contextMenu: contextMenu)
        }
    }

    private func assembleServices(themeController: ThemeController, contextMenu: NotchContextMenu) async {
        let eventBus = InProcessEventBus()
        let coordinator = PermissionsCoordinator(checker: SystemPermissionChecker())
        let hotkeyCenter = HotkeyCenter()

        var descriptors: [ModuleDescriptor] = []
        #if DEBUG
            // The Debug build shows the sample module without touching the user's config.
            let sample = DevSampleModule.staticManifest
            let debugManifest = ModuleManifest(
                id: sample.id, name: sample.name, icon: sample.icon, permissions: sample.permissions,
                settings: sample.settings, alertKinds: sample.alertKinds, defaultEnabled: true)
            descriptors.append(ModuleDescriptor(manifest: debugManifest) { DevSampleModule() })
        #endif
        let manifests = descriptors.map(\.manifest)

        let configStore = ConfigStore(environment: environment, manifests: manifests)
        await configStore.start()
        guard !isShuttingDown else {
            configStore.stop()
            return
        }

        do {
            hotkeyTokens = try CoreHotkeys.registerDefaults(
                in: hotkeyCenter,
                actions: CoreHotkeyActions(expand: { [logger] _ in logger.info("expand requested (Story 2.10)") }))
        } catch {
            logger.error("core hotkeys failed to register: \(String(describing: error), privacy: .public)")
        }
        let bridge = HotkeyConfigBridge(store: configStore, center: hotkeyCenter, manifests: manifests)
        bridge.start()

        for problem in configStore.problems {
            logger.error("config problem: \(String(describing: problem), privacy: .public)")
        }
        for problem in hotkeyCenter.problems {
            logger.error("hotkey problem: \(String(describing: problem), privacy: .public)")
        }

        let contextFactory = CoreModuleContextFactory(
            environment: environment, eventBus: eventBus, configStore: configStore,
            permissions: coordinator, hotkeyCenter: hotkeyCenter)
        let registry = ModuleRegistry(
            descriptors: descriptors,
            enablement: ConfigModuleEnablement(store: configStore),
            contextFactory: contextFactory,
            logger: Logger(subsystem: environment.logSubsystem, category: "modules"),
            permissions: coordinator)

        let host = NotchHost(
            themeController: themeController,
            registry: registry,
            contextMenu: contextMenu,
            maxSideWidth: {
                configStore.value(CoreSettings.path("closed", "max_side_width"), as: Int.self)
                    .map { CGFloat($0) } ?? 120
            },
            logger: Logger(subsystem: environment.logSubsystem, category: "host"))

        self.configStore = configStore
        self.hotkeyBridge = bridge
        self.registry = registry
        self.notchHost = host

        host.start()
        await registry.start()
    }

    /// Stops modules before quitting (their storage flushes asynchronously).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isShuttingDown else { return .terminateNow }
        isShuttingDown = true
        guard let registry else { return .terminateNow }
        notchHost?.stop()
        hotkeyBridge?.stop()
        Task {
            await registry.shutdown()
            configStore?.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        instanceLock?.release()
        instanceLock = nil
    }
}
