import AgentKit
import AgentsSessions
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
    private var eventServer: EventServer?
    private var activityStore: ActivityStore?
    private var notifyRules: ConfigNotifyRules?
    private var executableOverrides: ExecutableOverrides?
    private var alertCenter: AlertCenter?
    private var appTopics: AppTopics?
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

        // Built once and shared by the agent modules (AD-4). Adapters arrive with Epics 5 and 8.
        let agentAdapters = AgentAdapters([])
        let terminalAdapters = TerminalAdapters([])

        var descriptors: [ModuleDescriptor] = [
            ModuleDescriptor(manifest: AgentsSessionsModule.staticManifest) {
                AgentsSessionsModule(adapters: agentAdapters, terminals: terminalAdapters)
            }
        ]
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
        guard !isShuttingDown, let instanceLock else {
            configStore.stop()
            return
        }
        self.configStore = configStore

        // The socket is bound only while the instance lock is held (AD-21); messages queue until modules run.
        let server = EventServer(
            socketURL: environment.socketURL, bus: eventBus,
            logger: Logger(subsystem: environment.logSubsystem, category: "server"))
        do {
            try server.start(lockHeld: instanceLock)
            self.eventServer = server
        } catch {
            logger.error("event server failed to start: \(String(describing: error), privacy: .public)")
        }

        let activityStore = ActivityStore(
            environment: environment, logger: Logger(subsystem: environment.logSubsystem, category: "activity"))
        await activityStore.startDailyPruning()
        self.activityStore = activityStore

        let executableOverrides = ExecutableOverrides(store: configStore)
        executableOverrides.start()
        self.executableOverrides = executableOverrides
        let executables = ExecutableResolverImpl(
            overrides: { executableOverrides.current },
            log: Logger(subsystem: environment.logSubsystem, category: "executables"))
        Task { await executables.prime() }

        let notifierLog = Logger(subsystem: environment.logSubsystem, category: "notifier")
        let notifyRules = ConfigNotifyRules(store: configStore, logger: notifierLog)
        notifyRules.start()
        self.notifyRules = notifyRules
        let actionRouter = AppAlertActionRouter(
            registry: { [weak self] in self?.registry },
            logger: Logger(subsystem: environment.logSubsystem, category: "alert-actions"))
        let alertCenter = AlertCenter(
            rules: notifyRules, sinks: AlertSinks(actionRouter: actionRouter), log: notifierLog)
        self.alertCenter = alertCenter

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
            permissions: coordinator, hotkeyCenter: hotkeyCenter, alertCenter: alertCenter,
            activityStore: activityStore, executables: executables)
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
            closedSlots: {
                configStore.value(CoreSettings.path("closed", "slots"), as: Int.self) ?? ClosedNotchArbiter.defaultSlots
            },
            logger: Logger(subsystem: environment.logSubsystem, category: "host"))

        // `vigie reload` and `vigie expand` (Story 4.3). Subscribed before the server's queue is released.
        let appTopics = AppTopics(
            bus: eventBus, logger: logger,
            onReload: { await configStore.reload() },
            onExpand: { [logger] _ in logger.info("expand requested (Story 2.10)") })
        appTopics.start()

        self.hotkeyBridge = bridge
        self.registry = registry
        self.notchHost = host
        self.appTopics = appTopics

        host.start()
        await registry.start()
        eventServer?.releaseQueue()

        installCLI()
    }

    /// Links `~/.local/bin/<cliName>` to the bundled helper (FR8, AD-22); never overwrites a foreign file.
    private func installCLI() {
        guard let bundled = CLIInstaller.bundledCLIURL(in: .main, cliName: environment.cliName) else {
            logger.error("bundled CLI \(self.environment.cliName, privacy: .public) missing; not linked")
            return
        }
        let installer = CLIInstaller(environment: environment, bundledCLIURL: bundled)
        let logger = logger
        Task.detached {
            let result = await installer.install()
            logger.info(
                "CLI install at \(installer.linkURL.path, privacy: .public): \(String(describing: result), privacy: .public)"
            )
        }
    }

    /// Stops modules before quitting (their storage flushes asynchronously).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isShuttingDown else { return .terminateNow }
        isShuttingDown = true
        guard let registry else {
            eventServer?.stop()
            return .terminateNow
        }
        notchHost?.stop()
        hotkeyBridge?.stop()
        appTopics?.stop()
        notifyRules?.stop()
        executableOverrides?.stop()
        Task {
            await registry.shutdown()
            eventServer?.stop()
            await activityStore?.stopPruning()
            configStore?.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventServer?.stop()  // idempotent; covers a quit before assembly finished
        instanceLock?.release()
        instanceLock = nil
    }
}
