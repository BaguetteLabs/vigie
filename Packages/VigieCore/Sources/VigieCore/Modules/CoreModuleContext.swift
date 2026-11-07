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
        self.log = log
    }
}

/// Builds one context per module run. The Registry passes a fresh `RegistrationTracker` each time.
@MainActor
public protocol ModuleContextFactory {
    func makeContext(for manifest: ModuleManifest, tracker: RegistrationTracker) -> any ModuleContext
}

/// The production factory: real storage, scheduler and event bus; the shared permissions coordinator; stubs for the rest.
public struct CoreModuleContextFactory: ModuleContextFactory {
    public let environment: AppEnvironment
    public let eventBus: InProcessEventBus
    public let permissions: PermissionsCoordinator?

    /// - Parameter environment: injected by the App (`AppEnvironment.current`); VigieCore never reads `.current`.
    /// - Parameter permissions: the shared coordinator; when nil each context gets its own system-backed one.
    public init(
        environment: AppEnvironment, eventBus: InProcessEventBus, permissions: PermissionsCoordinator? = nil
    ) {
        self.environment = environment
        self.eventBus = eventBus
        self.permissions = permissions
    }

    public func makeContext(for manifest: ModuleManifest, tracker: RegistrationTracker) -> any ModuleContext {
        let log = Logger(subsystem: environment.bundleID, category: manifest.id.rawValue)
        return CoreModuleContext(
            settings: DefaultsModuleSettings(descriptors: manifest.settings),
            storage: ModuleStorageImpl(moduleID: manifest.id, environment: environment, logger: log),
            secrets: UnavailableSecretStore(),
            scheduler: CoreScheduler(tracker: tracker),
            hotkeys: StubHotkeyRegistry(tracker: tracker),
            notifier: StubNotifier(log: log),
            events: ModuleEventBus(bus: eventBus, tracker: tracker),
            host: StubHostControl(),
            permissions: permissions ?? PermissionsCoordinator(checker: SystemPermissionChecker()),
            power: StubPowerService(tracker: tracker),
            clipboard: StubClipboardService(),
            executables: StubExecutableResolver(),
            privacy: StubPrivacyService(),
            away: StubAwayService(),
            activity: StubActivityLog(),
            log: log
        )
    }
}
