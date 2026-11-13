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
    public let dropZones: any DropZoneDirectory
    public let scriptFolder: any ScriptFolderService
    public let updates: any UpdatesService
    public let notesKey: any SyncedKeyStore
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
        dropZones: any DropZoneDirectory = EmptyDropZoneDirectory(),
        scriptFolder: any ScriptFolderService = NoScriptFolder(),
        updates: any UpdatesService = NoUpdatesService(),
        notesKey: any SyncedKeyStore = UnavailableSyncedKeyStore(),
        log: Logger
    ) {
        self.notesKey = notesKey
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
        self.dropZones = dropZones
        self.scriptFolder = scriptFolder
        self.updates = updates
        self.log = log
    }
}

/// Builds one context per module run. The Registry passes a fresh `RegistrationTracker` each time.
@MainActor
public protocol ModuleContextFactory {
    func makeContext(for manifest: ModuleManifest, tracker: RegistrationTracker) -> any ModuleContext
}

/// The production factory: real settings (with a `ConfigStore`), storage, scheduler, event bus, hotkeys,
/// notifier, activity log, executable resolver, integration installer (AD-22), power service (Story 4.12),
/// owner-scoped secrets (Story 7.2), the clipboard (Story 9.9) and host control; the shared permissions
/// coordinator; stubs for the rest.
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
    /// The launch's power service (keep-awake and sleep/wake), wrapped per module by its tracker.
    public let power: CorePowerService
    /// The launch's secret store; each module gets ``KeychainSecretStore/scoped(to:)`` with its id.
    public let secretStore: KeychainSecretStore
    /// The notes key store (Story 15.1, AD-9): `context.notesKey` of the `notes` module only; every other module
    /// gets an ``UnavailableSyncedKeyStore``.
    public let notesKey: any SyncedKeyStore
    /// `context.host` for a module: a ``CoreHostControl`` bound to the Notch Host through a ``NotchHostLink``.
    public let hostControl: @MainActor @Sendable (ModuleID) -> any HostControl
    /// `context.clipboard` for every module: copy-only, on the general pasteboard (Story 9.9).
    public let clipboard: any ClipboardService
    /// `context.dropZones` for every module (Story 9.7): a ``CoreDropZoneDirectory`` bound to the Notch Host in
    /// the app; nil gives an empty directory.
    public let dropZones: (any DropZoneDirectory)?
    /// The launch's Privacy mode state (Story 21.2, AD-24); every module reads its ``CorePrivacyService/context``.
    public let privacy: CorePrivacyService
    /// The launch's Away service (Story 20.3, AD-25); each module gets a ``TrackedAwayService`` on its
    /// ``CoreAwayService/context``.
    public let away: CoreAwayService
    /// Ids a script module must not declare (AD-18): the modules registered with `configStore` when the factory
    /// is built (App assembly passes every built-in manifest to ConfigStore) plus ``ModuleID/specBuiltIns``.
    public let builtInModuleIDs: Set<ModuleID>
    /// The signed price table's location (Story 6.5), for `context.updates`; nil = never fetched.
    public let priceTable: PriceTableLocation?
    /// The launch's `vigie://install` inbox (Story 12.9), handed to `context.scriptFolder`; nil: no links.
    public let scriptInstalls: ScriptInstallInbox?

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
    ///   - power: the launch's power service; defaults to one reading `[general] prevent_idle_sleep` from
    ///     `configStore` (off without one) and following that key's changes.
    ///   - secretStore: the launch's secret store; defaults to one on the real Keychain for `environment`.
    ///   - notesKey: the notes key store; defaults to a ``KeychainSyncedKeyStore`` for `environment` (it touches
    ///     the Keychain only once the `notes` module uses it).
    ///   - hostControl: builds `context.host` per module; defaults to a ``CoreHostControl`` on an unbound
    ///     ``NotchHostLink`` (host requests do nothing).
    ///   - clipboard: `context.clipboard`; defaults to a ``CoreClipboardService`` on the general pasteboard.
    ///   - dropZones: `context.dropZones`; nil gives every module an empty directory.
    ///   - privacy: the launch's Privacy mode state, shared with the host and the Notifier outputs; defaults to
    ///     one that is off.
    ///   - builtInModuleIDs: the ids scripts must not take; defaults to the modules `configStore` knows plus
    ///     ``ModuleID/specBuiltIns``.
    ///   - scriptInstalls: the `vigie://install` inbox the App's open-URL handler feeds (Story 12.9).
    ///   - away: the launch's Away service; defaults to one on the real idle reader and screen signals, its
    ///     threshold read from `[modules.time.breaks] away_after` (90 s without it), transitions recorded in
    ///     `activityStore`.
    ///   - priceTable: where `agents.usage` fetches the signed price table; defaults to the location the app
    ///     bundle's `SUFeedURL` and `SUPublicEDKey` give (nil in builds without them).
    public init(
        environment: AppEnvironment, eventBus: InProcessEventBus, configStore: ConfigStore? = nil,
        permissions: PermissionsCoordinator? = nil, hotkeyCenter: HotkeyCenter? = nil,
        alertCenter: AlertCenter? = nil, activityStore: ActivityStore? = nil,
        executables: ExecutableResolverImpl? = nil,
        power: CorePowerService? = nil,
        secretStore: KeychainSecretStore? = nil,
        notesKey: (any SyncedKeyStore)? = nil,
        hostControl: (@MainActor @Sendable (ModuleID) -> any HostControl)? = nil,
        clipboard: (any ClipboardService)? = nil,
        dropZones: (any DropZoneDirectory)? = nil,
        privacy: CorePrivacyService? = nil,
        away: CoreAwayService? = nil,
        builtInModuleIDs: Set<ModuleID>? = nil,
        priceTable: PriceTableLocation? = UpdaterConfiguration.priceTableLocation(
            infoDictionary: Bundle.main.infoDictionary ?? [:]),
        scriptInstalls: ScriptInstallInbox? = nil
    ) {
        self.priceTable = priceTable
        self.scriptInstalls = scriptInstalls
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
        self.power = power ?? Self.makePower(configStore: configStore)
        self.secretStore = secretStore ?? KeychainSecretStore(environment: environment)
        self.notesKey = notesKey ?? KeychainSyncedKeyStore(environment: environment)
        self.hostControl =
            hostControl ?? { @MainActor id in CoreHostControl(moduleID: id, link: NotchHostLink()) }
        self.clipboard = clipboard ?? CoreClipboardService()
        self.dropZones = dropZones
        self.privacy = privacy ?? CorePrivacyService()
        self.builtInModuleIDs =
            builtInModuleIDs ?? (configStore?.schema.registeredModules ?? []).union(ModuleID.specBuiltIns)
        self.away =
            away
            ?? Self.makeAway(
                configStore: configStore, activity: CoreActivityRecorder(store: self.activityStore),
                logger: Logger(subsystem: environment.logSubsystem, category: "away"))
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
            storage: ModuleStorageImpl(
                moduleID: manifest.id, environment: environment, logger: log,
                userFolderResolver: Self.userFolderResolver(settings)),
            secrets: secretStore.scoped(to: manifest.id.rawValue),
            scheduler: CoreScheduler(tracker: tracker),
            hotkeys: CoreHotkeyRegistry(moduleID: manifest.id, center: hotkeyCenter, tracker: tracker),
            notifier: alertCenter.makeNotifier(for: manifest),
            events: ModuleEventBus(bus: eventBus, tracker: tracker),
            host: hostControl(manifest.id),
            permissions: permissions ?? PermissionsCoordinator(checker: SystemPermissionChecker()),
            power: TrackedPowerService(base: power, tracker: tracker),
            clipboard: clipboard,
            executables: executables,
            privacy: privacy.context,
            away: TrackedAwayService(base: away.context, tracker: tracker),
            activity: activity,
            integrations: CoreIntegrationInstaller(
                environment: environment, configStore: configStore, activity: activity),
            dropZones: dropZones ?? EmptyDropZoneDirectory(),
            scriptFolder: CoreScriptFolder(
                url: environment.scriptModulesFolderURL, builtInModuleIDs: builtInModuleIDs, tracker: tracker,
                confirmations: configStore.map {
                    ConfigScriptConfirmations(store: $0, tracker: tracker) as any ScriptConfirmationStore
                } ?? NoScriptConfirmations(),
                settings: configStore.map {
                    ConfigScriptSettings(store: $0, tracker: tracker) as any ScriptSettingsStore
                } ?? NoScriptSettings(),
                folderLocation: configStore?.location,
                installInbox: scriptInstalls),
            updates: CoreUpdatesService(shared: configStore?.shared, priceTable: priceTable),
            notesKey: manifest.id == Self.notesModuleID ? notesKey : UnavailableSyncedKeyStore(reason: .notOwner),
            log: log
        )
    }

    /// The one module that holds the notes key (AD-9).
    static let notesModuleID: ModuleID = "notes"

    /// `context.storage.userFolder(setting:)` (AD-11): the folder a `path` setting resolves to (config, else its
    /// declared default), `~` expanded.
    static func userFolderResolver(_ settings: any ModuleSettings) -> @Sendable (String) -> URL? {
        { key in
            if let url = settings.value(key, as: URL.self) { return url }
            guard let path = settings.value(key, as: String.self), !path.isEmpty else { return nil }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
    }

    /// The `[modules.time.breaks] away_after` key the Away service reads (declared by the Time module, Story
    /// 20.4; the spike placed the threshold there, SPEC §11).
    static let awayAfterPath = ConfigKeyPath.module("time", "breaks.away_after")

    /// A ``CoreAwayService`` on the real signals, its threshold re-read from `away_after` on every check.
    static func makeAway(configStore: ConfigStore?, activity: any ActivityLog, logger: Logger) -> CoreAwayService {
        let shared = configStore?.shared
        let path = awayAfterPath
        return CoreAwayService(
            threshold: {
                guard let value = shared?.value(at: path)?.typed(as: Duration.self), value > .zero else {
                    return CoreAwayService.defaultThreshold
                }
                return value
            },
            activity: activity, logger: logger)
    }

    /// A ``CorePowerService`` bound to `[general] prevent_idle_sleep`.
    static func makePower(configStore: ConfigStore?) -> CorePowerService {
        let path = CoreSettings.path("general", "prevent_idle_sleep")
        let shared = configStore?.shared
        let power = CorePowerService(isEnabled: { shared?.value(at: path)?.typed(as: Bool.self) ?? false })
        if let configStore {
            // The store's change feed (not a key observer): one load may change several keys.
            let changes = configStore.changes
            Task { [weak power] in
                for await keys in changes where keys.contains(path) {
                    guard let power else { return }
                    power.settingChanged()
                }
            }
        }
        return power
    }
}
