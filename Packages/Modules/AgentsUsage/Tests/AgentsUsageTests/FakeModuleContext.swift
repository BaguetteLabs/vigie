import AgentKit
import Foundation
import ModuleKit
import os

/// `ModuleContext` with a real storage folder (a temp directory) and a recording scheduler; every other service
/// is a no-op.
final class FakeModuleContext: ModuleContext, @unchecked Sendable {
    let fakeStorage: FolderStorage
    let fakeScheduler = FakeScheduler()
    let recordingNotifier = RecordingNotifier()
    let recordingHost = RecordingHost()

    /// The module's own settings (`[modules."agents.usage"]`); none by default.
    let moduleSettings: any ModuleSettings

    init(directory: URL, settings: any ModuleSettings = NoSettings()) {
        fakeStorage = FolderStorage(directory: directory)
        moduleSettings = settings
    }

    var settings: any ModuleSettings { moduleSettings }
    var storage: any ModuleStorage { fakeStorage }
    var secrets: any SecretStore { NoSecrets() }
    var scheduler: any Scheduler { fakeScheduler }
    var hotkeys: any HotkeyRegistry { NoHotkeys() }
    var notifier: any Notifier { recordingNotifier }
    var events: any EventBus { NoEvents() }
    var host: any HostControl { recordingHost }
    var permissions: any PermissionsService { NoPermissions() }
    var power: any PowerService { NoPower() }
    var clipboard: any ClipboardService { NoClipboard() }
    var executables: any ExecutableResolver { NoExecutables() }
    var privacy: any PrivacyService { NoPrivacy() }
    var away: any AwayService { NoAway() }
    var activity: any ActivityLog { NoActivity() }
    var integrations: any IntegrationInstaller { NoIntegrations() }
    var log: Logger { Logger(subsystem: "test", category: "agents.usage") }
}

struct NoSettings: ModuleSettings {
    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? { nil }
    func set<T: SettingValue>(_ value: T?, for key: String) async throws {}
    func observe(_ key: String) -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// Storage rooted at a real folder; JSON state is not used by `agents.usage`.
struct FolderStorage: ModuleStorage {
    let directory: URL
    func readJSON<T: Decodable & Sendable>(
        _ name: String, as type: T.Type, schema: Int, migrate: (@Sendable (Int, Data) throws -> T)?
    ) async throws -> T? { nil }
    func writeJSON<T: Encodable & Sendable>(_ value: T, name: String, schema: Int) async throws {}
    func flush() async {}
    func userFolder(setting key: String) -> URL? { nil }
}

/// Records jobs; tests run them with `fire()`.
final class FakeScheduler: Scheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [(Duration, @Sendable () async -> Void)] = []

    var intervals: [Duration] { lock.withLock { jobs.map(\.0) } }

    func every(_ interval: Duration, _ body: @escaping @Sendable () async -> Void) -> RegistrationToken {
        lock.withLock { jobs.append((interval, body)) }
        return RegistrationToken {}
    }

    func at(_ date: Date, _ body: @escaping @Sendable () async -> Void) -> RegistrationToken {
        RegistrationToken {}
    }

    func fire() async {
        for job in lock.withLock({ jobs }) { await job.1() }
    }
}

struct NoEvents: EventBus {
    func subscribe(topicPrefix: String) -> AsyncStream<EventMessage> { AsyncStream { $0.finish() } }
}

struct NoSecrets: SecretStore {
    func read(_ key: String) async throws -> String? { nil }
    func write(_ value: String?, for key: String) async throws {}
}

struct NoHotkeys: HotkeyRegistry {
    func register(
        name: String, default shortcut: String?, handler: @escaping @MainActor @Sendable (UserIntent) -> Void
    ) throws -> RegistrationToken { RegistrationToken {} }
}

/// Records posts and resolutions.
final class RecordingNotifier: Notifier, @unchecked Sendable {
    private let lock = NSLock()
    private var _posted: [NotifierEvent] = []
    private var _resolved = 0

    var posted: [NotifierEvent] { lock.withLock { _posted } }
    var resolved: Int { lock.withLock { _resolved } }

    func post(_ event: NotifierEvent) -> AlertHandle {
        lock.withLock { _posted.append(event) }
        return AlertHandle { [weak self] in self?.lock.withLock { self?._resolved += 1 } }
    }
}

/// Records `openOwnTab` calls.
final class RecordingHost: HostControl, @unchecked Sendable {
    private let lock = NSLock()
    private var _openedTabs: [UserIntent?] = []
    var openedTabs: [UserIntent?] { lock.withLock { _openedTabs } }

    func requestPeek() {}
    func expand(focus: UserIntent?) {}
    func openOwnTab(focus: UserIntent?) { lock.withLock { _openedTabs.append(focus) } }
    func registerDynamicModule(_ module: any NotchModule) throws -> RegistrationToken { RegistrationToken {} }
}

struct NoHost: HostControl {
    func requestPeek() {}
    func expand(focus: UserIntent?) {}
    func openOwnTab(focus: UserIntent?) {}
    func registerDynamicModule(_ module: any NotchModule) throws -> RegistrationToken { RegistrationToken {} }
}

struct NoPermissions: PermissionsService {
    func status(of permission: Permission) async -> PermissionStatus { .notDetermined }
    func request(_ permission: Permission) async -> PermissionStatus { .notDetermined }
}

struct NoPower: PowerService {
    func preventIdleSleep(reason: String) -> RegistrationToken { RegistrationToken {} }
    var sleepWake: AsyncStream<SleepWakeEvent> { AsyncStream { $0.finish() } }
}

struct NoClipboard: ClipboardService {
    func copy(_ text: String, clearAfter: Duration?) {}
}

struct NoExecutables: ExecutableResolver {
    func resolve(_ name: String) async -> URL? { nil }
}

struct NoPrivacy: PrivacyService {
    var isActive: Bool { false }
    var changes: AsyncStream<Bool> { AsyncStream { $0.finish() } }
}

struct NoAway: AwayService {
    var presence: Presence { .present }
    var changes: AsyncStream<Presence> { AsyncStream { $0.finish() } }
}

struct NoActivity: ActivityLog {
    func record(_ entry: ActivityEntry) {}
}

struct NoIntegrations: IntegrationInstaller {
    var cliPath: String { "/Users/test/.local/bin/vigie" }
    func preview(_ diffs: [ConfigDiff], adapterID: String, action: IntegrationAction) async throws
        -> IntegrationPreview
    {
        IntegrationPreview(adapterID: adapterID, action: action, files: [])
    }
    func apply(_ preview: IntegrationPreview) async throws -> IntegrationResult {
        IntegrationResult(appliedPaths: [], backupPaths: [])
    }
}
