import AgentKit
import AgentsSessions
import AgentsUsage
import AppKit
import ClaudeAdapter
import GenericTerminal
import ITermTerminal
import ModuleKit
import OSLog
import Shelf
import TerminalAppTerminal
import Time
import VigieCore
import VigieUI
import WarpTerminal
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
    private var focusMonitor: (any FocusModeMonitor)?
    private var peekPresenter: PeekPresenter?
    private var setupProblems: SetupProblemReporter?
    private var settings: SettingsController?
    private var appTopics: AppTopics?
    private var hostConfig: HostConfigBridge?
    private var privacyConfig: PrivacyConfigBridge?
    private var stashService: StashServiceProvider?
    private var privacy: CorePrivacyService?
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

        let contextMenu = NotchContextMenu(openSettings: { [weak self] in self?.openSettings(pane: nil) })
        self.themeController = themeController
        self.contextMenu = contextMenu

        // Config must be loaded before modules start (enablement, hotkeys and the host read it).
        Task { @MainActor in
            await self.assembleServices(themeController: themeController, contextMenu: contextMenu)
        }
    }

    private func openSettings(pane: String?) {
        guard let settings else {
            logger.info("settings requested before assembly finished")
            return
        }
        settings.open(pane: pane)
    }

    private func assembleServices(themeController: ThemeController, contextMenu: NotchContextMenu) async {
        let eventBus = InProcessEventBus()
        let coordinator = PermissionsCoordinator(checker: SystemPermissionChecker())
        let hotkeyCenter = HotkeyCenter()

        // Built once and shared by the agent modules (AD-4). Terminal.app, iTerm2 and Warp focus their tab or
        // window; any other terminal goes to the generic fallback, which activates the app without a tab (A16).
        let agentAdapters = AgentAdapters([ClaudeAdapter()])
        let terminalAdapters = TerminalAdapters(
            [TerminalAppAdapter(), ITermAdapter(), WarpAdapter()], fallback: GenericTerminalAdapter())
        // Filled once ConfigStore, the resolver and the secret store exist; read when the modules are built.
        let adapterAssembly = AgentAdapterAssembly()

        var descriptors: [ModuleDescriptor] = [
            ModuleDescriptor(manifest: AgentsSessionsModule.staticManifest) {
                // The SettingsController is created later in the sequence; resolve it when the button is used.
                AgentsSessionsModule(
                    adapters: agentAdapters, terminals: terminalAdapters, contexts: adapterAssembly.contexts,
                    openSettings: { [weak self] pane in self?.openSettings(pane: pane) })
            },
            // Same adapter instances and contexts as agents.sessions (AD-23); it also owns the plan-usage block.
            ModuleDescriptor(manifest: AgentsUsageModule.staticManifest) {
                AgentsUsageModule(
                    adapters: agentAdapters, contexts: adapterAssembly.contexts,
                    adapterSettingsStores: adapterAssembly.settings,
                    openSettings: { [weak self] pane in self?.openSettings(pane: pane) })
            },
            // Stash zone and the items it keeps (SPEC §7.3, Story 9.2).
            ModuleDescriptor(manifest: ShelfModule.staticManifest) { ShelfModule() },
            // Timers and Countdowns, the Time tab and the Timer-end alert (SPEC §7.7, Story 20.2). Off by default.
            ModuleDescriptor(manifest: TimeModule.staticManifest) { TimeModule() },
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

        // The host is built after the registry, which needs the Notifier: the link closes that loop.
        let hostLink = NotchHostLink()

        // Privacy mode (Story 21.2, AD-24): one state for the host, the Notifier outputs and every module.
        let privacy = CorePrivacyService()
        self.privacy = privacy

        // Notifier (AD-13): config rules, Focus modes, peek / system outputs, action routing.
        let notifierLog = Logger(subsystem: environment.logSubsystem, category: "notifier")
        let notifyRules = ConfigNotifyRules(store: configStore, logger: notifierLog)
        notifyRules.start()
        self.notifyRules = notifyRules
        let focusMonitor = makeFocusMonitor(log: notifierLog)
        self.focusMonitor = focusMonitor
        let actionRouter = AppAlertActionRouter(
            registry: { [weak self] in self?.registry },
            openSettings: { [weak self] pane in self?.openSettings(pane: pane) },
            logger: Logger(subsystem: environment.logSubsystem, category: "alert-actions"))
        let peeks = PeekPresenter(
            anchors: hostLink, theme: themeController,
            dwell: {
                configStore.value(CoreSettings.path("closed", "peek_duration"), as: Duration.self)
                    ?? PeekPresenter.defaultDwell
            },
            enabled: { _ in configStore.value(CoreSettings.path("closed", "peek"), as: Bool.self) ?? true },
            // ⌥⌘↵ / ⌥⌘⌫ while a peek is visible; other Vigie shortcuts on those keys yield meanwhile (Story 3.3).
            shortcuts: TemporaryShortcuts(others: { [hotkeyCenter] in hotkeyCenter.bound }),
            // No peek while the expanded view is open (Story 3.9).
            isSuppressed: { [hostLink] in hostLink.host?.isExpanded ?? false },
            // Peeks wait while the drop display is open and show after it closes (Story 9.1, UX-DR92).
            isDropDisplayOpen: { [hostLink] in hostLink.host?.dropDisplay.isOpen ?? false },
            privacy: privacy,
            logger: Logger(subsystem: environment.logSubsystem, category: "peek"))
        self.peekPresenter = peeks
        // Set once the core notifier exists; a denial is reported once, as a setup problem.
        var reportPermissionDenied: (String) -> Void = { _ in }
        let systemSink = SystemNotificationSink(
            client: UNUserNotificationCenterClient(), permissions: coordinator, router: actionRouter,
            onPermissionDenied: { message in reportPermissionDenied(message) }, privacy: privacy)
        // Sound problems post through the core notifier, which exists only after the center: late-bound.
        var soundProblems: SoundProblemReporter?
        let soundPlayer = AVAudioPlayerSoundPlayer()
        let soundSink = NotifierSoundSink(
            config: { SoundSettings.read(from: configStore) }, player: soundPlayer,
            onProblem: { problem in soundProblems?.report(problem) },
            onRecovered: { key in soundProblems?.clear(key: key) },
            log: Logger(subsystem: environment.logSubsystem, category: "sounds"))
        let alertCenter = AlertCenter(
            rules: notifyRules,
            sinks: AlertSinks(peek: peeks, system: systemSink, sound: soundSink, actionRouter: actionRouter),
            focus: focusMonitor,
            activity: CoreActivityRecorder(store: activityStore),
            log: notifierLog)
        self.alertCenter = alertCenter
        let coreNotifier = alertCenter.makeNotifier(for: SetupProblemReporter.manifest)
        soundProblems = SoundProblemReporter(
            notifier: coreNotifier, log: Logger(subsystem: environment.logSubsystem, category: "sounds"))
        reportPermissionDenied = { [notifierLog] message in
            notifierLog.error("macOS notifications are denied; reported as a setup problem")
            coreNotifier.post(
                NotifierEvent(
                    kind: SetupProblemReporter.alertKind, severity: .warn, title: message,
                    action: .openSettings(pane: "notify"), dedupeKey: "permission.notifications"))
        }

        do {
            hotkeyTokens = try CoreHotkeys.registerDefaults(
                in: hotkeyCenter,
                actions: CoreHotkeyActions(expand: { [weak self] intent in
                    self?.notchHost?.toggleExpanded(focus: intent)
                }))
        } catch {
            logger.error("core hotkeys failed to register: \(String(describing: error), privacy: .public)")
        }
        let bridge = HotkeyConfigBridge(store: configStore, center: hotkeyCenter, manifests: manifests)
        bridge.start()
        self.hotkeyBridge = bridge

        // Config and hotkey problems become `setup.problem` alerts (Story 3.4).
        let setupProblems = SetupProblemReporter(
            configStore: configStore, hotkeys: hotkeyCenter, notifier: coreNotifier,
            log: Logger(subsystem: environment.logSubsystem, category: "setup-problems"))
        setupProblems.start()
        self.setupProblems = setupProblems

        for problem in configStore.problems {
            logger.error("config problem: \(String(describing: problem), privacy: .public)")
        }
        for problem in hotkeyCenter.problems {
            logger.error("hotkey problem: \(String(describing: problem), privacy: .public)")
        }

        // Secrets (Story 7.2, AD-9): one Keychain store, scoped per module; unentitled builds post a setup problem.
        // External-credential consents (Story 7.3) live in local.toml.
        let secretStore = KeychainSecretStore(environment: environment, configStore: configStore)
        Task { await secretStore.reportAvailability(to: coreNotifier) }

        // One AdapterContext per agent adapter (AD-19, Story 7.3): settings from ConfigStore at
        // `[modules."agents.sessions".adapter.<id>]`, secrets scoped to `adapter.<id>`, the launch's resolver, one
        // ephemeral HTTP client. Given to both agent modules.
        let http = URLSessionHTTPClient()
        for adapter in agentAdapters.adapters {
            let settings = ConfigAdapterSettings(
                store: configStore, module: AgentsSessionsModule.staticManifest.id, adapterID: adapter.id.rawValue,
                settings: adapter.settings)
            adapterAssembly.settings[adapter.id] = settings
            adapterAssembly.contexts[adapter.id] = AdapterContextBox(
                settings: ReadOnlyAdapterSettings(settings),
                secrets: secretStore.scoped(to: KeychainSecretStore.adapterOwner(adapter.id.rawValue)),
                executables: executables, http: http,
                log: Logger(subsystem: environment.logSubsystem, category: "adapter.\(adapter.id.rawValue)"))
        }

        let contextFactory = CoreModuleContextFactory(
            environment: environment, eventBus: eventBus, configStore: configStore,
            permissions: coordinator, hotkeyCenter: hotkeyCenter, alertCenter: alertCenter,
            activityStore: activityStore, executables: executables, secretStore: secretStore,
            hostControl: { CoreHostControl(moduleID: $0, link: hostLink) },
            dropZones: CoreDropZoneDirectory(link: hostLink), privacy: privacy)
        let registry = ModuleRegistry(
            descriptors: descriptors,
            enablement: ConfigModuleEnablement(store: configStore),
            contextFactory: contextFactory,
            logger: Logger(subsystem: environment.logSubsystem, category: "modules"),
            permissions: coordinator)
        self.registry = registry

        let cliInstaller = CLIInstaller.bundledCLIURL(in: .main, cliName: environment.cliName).map {
            CLIInstaller(environment: environment, bundledCLIURL: $0)
        }
        let settings = SettingsController(
            configStore: configStore, registry: registry, permissions: coordinator, hotkeyCenter: hotkeyCenter,
            activityStore: activityStore, cliInstaller: cliInstaller, manifests: manifests,
            loginShellPath: {
                // The resolver's captured login-shell PATH; unknown when the capture fell back.
                guard await executables.searchPathSource == .loginShell else { return nil }
                return await executables.searchPath.joined(separator: ":")
            }, secretStore: secretStore)
        settings.sounds.player = soundPlayer
        settings.privacy = privacy
        self.settings = settings

        let general = { (key: String) in CoreSettings.path("general", key) }
        let displayPrompt = DisplayPromptRecord()
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
            virtualNotch: { VirtualNotchSettings(configStore: configStore) },
            displaySelection: { DisplaySelection(configStore: configStore) },
            hideInFullScreen: { configStore.value(general("hide_in_fullscreen"), as: Bool.self) ?? true },
            displayPromptPending: { displayPrompt.isPending },
            onDisplayPromptAnswer: { [logger] answer in
                Task { @MainActor in
                    do {
                        try await answer.apply(store: configStore, record: displayPrompt)
                    } catch {
                        logger.error("display prompt: \(String(describing: error), privacy: .public)")
                    }
                }
            },
            openOnHover: { configStore.value(general("open_on_hover"), as: Bool.self) ?? false },
            hoverDelay: { configStore.value(general("hover_delay"), as: Duration.self) ?? NotchHost.defaultHoverDelay },
            closeOnLeave: { configStore.value(general("close_on_leave"), as: Bool.self) ?? false },
            tabOrder: { configStore.value(general("tab_order"), as: [String].self) ?? [] },
            openSettings: { [weak self] in self?.openSettings(pane: nil) },
            openSettingsPane: { [weak self] pane in self?.openSettings(pane: pane) },
            homeCardOrder: { configStore.value(CoreSettings.path("home", "cards"), as: [String].self) ?? [] },
            dropsDirectory: environment.dropsDirectory,
            privacy: privacy,
            logger: Logger(subsystem: environment.logSubsystem, category: "host"))
        hostLink.host = host
        self.notchHost = host
        // Services › Stash in Vigie (Story 9.10, AD-20): routed to the Stash zone; never activates Vigie.
        let stashService = StashServiceProvider(
            directory: CoreDropZoneDirectory(link: hostLink), notifier: coreNotifier,
            logger: Logger(subsystem: environment.logSubsystem, category: "services"))
        NSApp.servicesProvider = stashService
        NSUpdateDynamicServices()
        self.stashService = stashService
        host.dropDisplay.onClose = { [weak peeks] in peeks?.resume() }
        // Display selection and the virtual notch (Stories 2.6, 2.7): re-place or re-arbitrate on config edits.
        let hostConfig = HostConfigBridge(store: configStore, host: host)
        hostConfig.start()
        self.hostConfig = hostConfig
        // Privacy mode (Story 21.3): `[privacy] force` / `auto` from the config store. Detection is manual-only
        // (spike 21.1), so `auto` has no effect and Settings shows the row disabled.
        let privacyConfig = PrivacyConfigBridge(store: configStore, privacy: privacy, permissions: coordinator)
        privacyConfig.start()
        self.privacyConfig = privacyConfig

        // `vigie reload` and `app.expand` (Story 4.3, AD-21). Subscribed before the server's queue is released.
        let appTopics = AppTopics(
            bus: eventBus, logger: logger,
            onReload: { await configStore.reload() },
            onExpand: { [weak host] _ in host?.expand(focus: nil) })
        appTopics.start()
        self.appTopics = appTopics

        host.start()
        await registry.start()
        // AD-6 steps 4-6: replay the spool, release the socket queue, then announce readiness.
        if let server = eventServer {
            let report = await server.finishStartup(spool: SpoolLocations(environment: environment))
            logger.info("spool replay: \(String(describing: report), privacy: .public)")
        }
        eventBus.publish(EventMessage(topic: Topic.hostReady, payload: Data("{}".utf8), sentAt: Date()))
        logger.info("host ready")

        installCLI(cliInstaller)
        simulateDropIfAsked(host)
    }

    /// `-VigieSimulateDrop YES` (Debug) opens the drop display for 5 s at launch, as if a file were dragged over
    /// the notch (screenshots, Story 9.1): the running modules' zones, plus a sample Stash when the Shelf is
    /// off.
    private func simulateDropIfAsked(_ host: NotchHost) {
        #if DEBUG
            guard UserDefaults.standard.bool(forKey: "VigieSimulateDrop") else { return }
            logger.info("Drop display opened by -VigieSimulateDrop")
            let real = host.dropDisplay.enabledZones()
            let hasPrimary = real.contains { $0.role == .primary }
            let samples = DropSampleZones.make().filter { sample in
                sample.role == .primary ? !hasPrimary : !real.contains { $0.style == sample.style }
            }
            host.dropDisplay.simulate(zones: real + samples, for: .seconds(5))
        #endif
    }

    /// `-VigieSimulateFocus YES` (Debug) pretends a Focus mode is on, to exercise FR17 without changing the
    /// system's Focus.
    private func makeFocusMonitor(log: Logger) -> any FocusModeMonitor {
        #if DEBUG
            if UserDefaults.standard.bool(forKey: "VigieSimulateFocus") {
                log.info("Focus mode on (simulated by -VigieSimulateFocus)")
                return ManualFocusModeMonitor(isActive: true)
            }
        #endif
        return SystemFocusModeMonitor(assertionsURL: SystemFocusModeMonitor.defaultAssertionsURL(), log: log)
    }

    /// Links `~/.local/bin/<cliName>` to the bundled helper (FR8, AD-22); never overwrites a foreign file.
    private func installCLI(_ installer: CLIInstaller?) {
        guard let installer else {
            logger.error("bundled CLI \(self.environment.cliName, privacy: .public) missing; not linked")
            return
        }
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
        settings?.close()
        hostConfig?.stop()
        privacyConfig?.stop()
        notchHost?.stop()
        hotkeyBridge?.stop()
        setupProblems?.stop()
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

/// The per-adapter contexts and writable settings App assembly builds once (Story 7.3) and hands to both agent
/// modules when the Registry instantiates them.
@MainActor
final class AgentAdapterAssembly {
    var contexts: [AgentID: any AdapterContext] = [:]
    var settings: [AgentID: any AdapterSettingsStore] = [:]
}
