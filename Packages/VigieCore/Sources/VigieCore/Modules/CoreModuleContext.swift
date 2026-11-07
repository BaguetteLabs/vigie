import Foundation
import ModuleKit
import Wire
import os

/// The `ModuleContext` VigieCore gives each module (AD-19). Services not built yet are stubs (see
/// `ServiceStubs.swift`), replaced by the story that first needs them.
public struct CoreModuleContext: ModuleContext {
    public let settings: any ModuleSettings
    public let storage: any ModuleStorage
    public let secrets: any SecretStore
    public let scheduler: any Scheduler
    public let hotkeys: any HotkeyRegistry
    public let notifier: any Notifier
    public let events: any EventBus
    public let host: any HostControl
    public let permissions: any PermissionsService
    public let power: any PowerService
    public let clipboard: any ClipboardService
    public let executables: any ExecutableResolver
    public let privacy: any PrivacyService
    public let away: any AwayService
    public let activity: any ActivityLog
    public let integrations: any IntegrationInstaller
    public let log: Logger

    public init(
        settings: any ModuleSettings,
        storage: any ModuleStorage,
        secrets: any SecretStore,
        scheduler: any Scheduler,
        hotkeys: any HotkeyRegistry,
        notifier: any Notifier,
        events: any EventBus,
        host: any HostControl,
        permissions: any PermissionsService,
        power: any PowerService,
        clipboard: any ClipboardService,
        executables: any ExecutableResolver,
        privacy: any PrivacyService,
        away: any AwayService,
        activity: any ActivityLog,
        integrations: any IntegrationInstaller,
        log: Logger
    ) {
        self.settings = settings
        self.storage = storage
        self.secrets = secrets
        self.scheduler = scheduler
        self.hotkeys = hotkeys
        self.notifier = notifier
        self.events = events
        self.host = host
        self.permissions = permissions
        self.power = power
        self.clipboard = clipboard
        self.executables = executables
        self.privacy = privacy
        self.away = away
        self.activity = activity
        self.integrations = integrations
        self.log = log
    }
}

/// Builds one context per module run. The Registry passes a fresh `RegistrationTracker` each time.
@MainActor
public protocol ModuleContextFactory {
    func makeContext(for manifest: ModuleManifest, tracker: RegistrationTracker) -> any ModuleContext
}

/// The production factory: real settings (with a `ConfigStore`), storage, scheduler, event bus, hotkeys,
/// notifier, activity log, executable resolver, integration installer (AD-22) and host control; the shared
/// permissions coordinator; stubs for the rest.
public struct CoreModuleContextFactory: ModuleContextFactory {
    public let environment: AppEnvironment
    public let eventBus: InProcessEventBus
    public let configStore: ConfigStore?
    public let permissions: PermissionsCoordinator?
    public let hotkeyCenter: HotkeyCenter
    public let alertCenter: AlertCenter
    public let activityStore: ActivityStore
    /// The one resolver of the launch, given to every module context. App assembly passes the same instance to
    /// each adapter's `AdapterContextBox` (AD-4, AD-19).
    public let executables: ExecutableResolverImpl
    /// `context.host` for a module: a ``CoreHostControl`` bound to the Notch Host through a ``NotchHostLink``.
    public let hostControl: @MainActor @Sendable (ModuleID) -> any HostControl

    /// - Parameters:
    ///   - environment: injected by the App (`AppEnvironment.current`); VigieCore never reads `.current`.
    ///   - configStore: backs `context.settings`; without one, settings read their declared defaults.
    ///   - permissions: the shared coordinator; when nil each context gets its own system-backed one.
    ///   - hotkeyCenter: the app-wide hotkey center (shared with `CoreHotkeys`); defaults to one bound to
    ///     KeyboardShortcuts.
    ///   - alertCenter: the app-wide Notifier; defaults to one with default rules (`StaticNotifyRules`) and
    ///     recording sinks until ConfigStore and the outputs are wired.
    ///   - activityStore: the app-wide activity log store (AD-26); defaults to one for `environment`.
    ///   - executables: the launch's resolver; defaults to one that runs the user's login shell.
    ///   - hostControl: builds `context.host` per module; defaults to a ``CoreHostControl`` on an unbound
    ///     ``NotchHostLink`` (host requests do nothing).
    public init(
        environment: AppEnvironment, eventBus: InProcessEventBus, configStore: ConfigStore? = nil,
        permissions: PermissionsCoordinator? = nil, hotkeyCenter: HotkeyCenter? = nil,
        alertCenter: AlertCenter? = nil, activityStore: ActivityStore? = nil,
        executables: ExecutableResolverImpl? = nil,
        hostControl: (@MainActor @Sendable (ModuleID) -> any HostControl)? = nil
    ) {
        self.environment = environment
        self.eventBus = eventBus
        self.configStore = configStore
        self.permissions = permissions
        self.hotkeyCenter = hotkeyCenter ?? HotkeyCenter()
        self.alertCenter =
            alertCenter
            ?? AlertCenter(
                rules: StaticNotifyRules(), log: Logger(subsystem: environment.bundleID, category: "notifier"))
        self.activityStore = activityStore ?? ActivityStore(environment: environment)
        self.executables =
            executables
            ?? ExecutableResolverImpl(log: Logger(subsystem: environment.logSubsystem, category: "executables"))
        self.hostControl =
            hostControl ?? { @MainActor id in CoreHostControl(moduleID: id, link: NotchHostLink()) }
    }

    public func makeContext(for manifest: ModuleManifest, tracker: RegistrationTracker) -> any ModuleContext {
        let log = Logger(subsystem: environment.bundleID, category: manifest.id.rawValue)
        let settings: any ModuleSettings
        if let configStore {
            configStore.register(manifest: manifest)
            settings = ConfigModuleSettings(store: configStore, moduleID: manifest.id, tracker: tracker)
        } else {
            settings = DefaultsModuleSettings(descriptors: manifest.settings)
        }
        let activity = CoreActivityLog(moduleID: manifest.id, store: activityStore)
        return CoreModuleContext(
            settings: settings,
            storage: ModuleStorageImpl(moduleID: manifest.id, environment: environment, logger: log),
            secrets: UnavailableSecretStore(),
            scheduler: CoreScheduler(tracker: tracker),
            hotkeys: CoreHotkeyRegistry(moduleID: manifest.id, center: hotkeyCenter, tracker: tracker),
            notifier: alertCenter.makeNotifier(for: manifest),
            events: ModuleEventBus(bus: eventBus, tracker: tracker),
            host: hostControl(manifest.id),
            permissions: permissions ?? PermissionsCoordinator(checker: SystemPermissionChecker()),
            power: StubPowerService(tracker: tracker),
            clipboard: StubClipboardService(),
            executables: executables,
            privacy: StubPrivacyService(),
            away: StubAwayService(),
            activity: activity,
            integrations: CoreIntegrationInstaller(
                environment: environment, configStore: configStore, activity: activity),
            log: log
        )
    }
}
