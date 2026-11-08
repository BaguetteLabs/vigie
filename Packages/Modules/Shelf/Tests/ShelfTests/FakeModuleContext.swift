import Foundation
import ModuleKit
import Synchronization
import os

@testable import Shelf

/// `ModuleContext` with real behavior for settings, storage (JSON in memory, folder on disk), scheduler,
/// notifier and activity; every other service is a no-op.
final class FakeModuleContext: ModuleContext, @unchecked Sendable {
    let fakeSettings: FakeSettings
    let fakeStorage: FakeStorage
    let fakeScheduler = FakeScheduler()
    let fakeNotifier = RecordingNotifier()
    let fakeActivity = RecordingActivity()
    let fakeClipboard = RecordingClipboard()
    let fakeDropZones = FakeDropZoneDirectory()

    init(settings: [String: any SettingValue] = [:], storage: FakeStorage = FakeStorage()) {
        fakeSettings = FakeSettings(values: settings)
        fakeStorage = storage
    }

    var settings: any ModuleSettings { fakeSettings }
    var storage: any ModuleStorage { fakeStorage }
    var secrets: any SecretStore { NoSecrets() }
    var scheduler: any Scheduler { fakeScheduler }
    var hotkeys: any HotkeyRegistry { NoHotkeys() }
    var notifier: any Notifier { fakeNotifier }
    var events: any EventBus { NoEvents() }
    var host: any HostControl { NoHost() }
    var permissions: any PermissionsService { NoPermissions() }
    var power: any PowerService { NoPower() }
    var clipboard: any ClipboardService { fakeClipboard }
    var executables: any ExecutableResolver { NoExecutables() }
    var privacy: any PrivacyService { NoPrivacy() }
    var away: any AwayService { NoAway() }
    var activity: any ActivityLog { fakeActivity }
    var integrations: any IntegrationInstaller { NoIntegrations() }
    var dropZones: any DropZoneDirectory { fakeDropZones }
    var log: Logger { Logger(subsystem: "test", category: "shelf") }
}

/// Settings from a dictionary; `set` stores the value and signals `observe`.
final class FakeSettings: ModuleSettings, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: any SettingValue]
    private var observers: [String: [AsyncStream<Void>.Continuation]] = [:]

    init(values: [String: any SettingValue]) { self.values = values }

    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? { lock.withLock { values[key] as? T } }

    func set<T: SettingValue>(_ value: T?, for key: String) async throws {
        let continuations = lock.withLock {
            values[key] = value
            return observers[key] ?? []
        }
        for continuation in continuations { continuation.yield() }
    }

    func observe(_ key: String) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        lock.withLock { observers[key, default: []].append(continuation) }
        return stream
    }
}

/// JSON files in memory (`{schema, value}`, written at once); `directory` is a fresh temp folder.
final class FakeStorage: ModuleStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var writes: [String: Int] = [:]
    let directory: URL

    init(directory: URL = makeTempDirectory()) {
        self.directory = directory
    }

    func data(_ name: String) -> Data? { lock.withLock { files[name] } }
    func writeCount(_ name: String) -> Int { lock.withLock { writes[name, default: 0] } }

    func readJSON<T: Decodable & Sendable>(
        _ name: String, as type: T.Type, schema: Int, migrate: (@Sendable (Int, Data) throws -> T)?
    ) async throws -> T? {
        guard let data = data(name) else { return nil }
        return try Self.decoder.decode(StateFile<T>.self, from: data).value
    }

    func writeJSON<T: Encodable & Sendable>(_ value: T, name: String, schema: Int) async throws {
        let data = try Self.encoder.encode(StateFile(schema: schema, value: value))
        lock.withLock {
            files[name] = data
            writes[name, default: 0] += 1
        }
    }

    func flush() async {}
    func userFolder(setting key: String) -> URL? { nil }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct StateFile<Value> {
    let schema: Int
    let value: Value
}

extension StateFile: Encodable where Value: Encodable {}
extension StateFile: Decodable where Value: Decodable {}

/// Records jobs; tests run the repeating ones with `fire()`.
final class FakeScheduler: Scheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [(Duration, @Sendable () async -> Void)] = []

    var intervals: [Duration] { lock.withLock { jobs.map(\.0) } }

    func every(_ interval: Duration, _ body: @escaping @Sendable () async -> Void) -> RegistrationToken {
        lock.withLock { jobs.append((interval, body)) }
        return RegistrationToken {}
    }

    func at(_ date: Date, _ body: @escaping @Sendable () async -> Void) -> RegistrationToken { RegistrationToken {} }

    func fire() async {
        for job in lock.withLock({ jobs }) { await job.1() }
    }
}

final class RecordingNotifier: Notifier, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [NotifierEvent] = []
    var posted: [NotifierEvent] { lock.withLock { events } }

    func post(_ event: NotifierEvent) -> AlertHandle {
        lock.withLock { events.append(event) }
        return AlertHandle {}
    }
}

final class RecordingActivity: ActivityLog, @unchecked Sendable {
    private let lock = NSLock()
    private var all: [ActivityEntry] = []
    var entries: [ActivityEntry] { lock.withLock { all } }
    func record(_ entry: ActivityEntry) { lock.withLock { all.append(entry) } }
}

/// Real bookmarks, counted start/stop calls; `failBookmarks` makes bookmark creation throw.
final class CountingScope: SecurityScopedResources, @unchecked Sendable {
    private let lock = NSLock()
    private let system = SystemSecurityScope()
    private var counts = (starts: 0, stops: 0, bookmarks: 0)
    var failBookmarks = false
    var reportStale = false

    var starts: Int { lock.withLock { counts.starts } }
    var stops: Int { lock.withLock { counts.stops } }
    var bookmarks: Int { lock.withLock { counts.bookmarks } }

    struct Failure: Error {}

    func bookmark(for url: URL) throws -> Data {
        if lock.withLock({ failBookmarks }) { throw Failure() }
        lock.withLock { counts.bookmarks += 1 }
        return try system.bookmark(for: url)
    }

    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        let resolved = try system.resolve(bookmark)
        return (resolved.url, lock.withLock { reportStale } || resolved.isStale)
    }

    func startAccessing(_ url: URL) -> Bool {
        lock.withLock { counts.starts += 1 }
        return true
    }

    func stopAccessing(_ url: URL) { lock.withLock { counts.stops += 1 } }
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

struct NoEvents: EventBus {
    func subscribe(topicPrefix: String) -> AsyncStream<EventMessage> { AsyncStream { $0.finish() } }
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

/// Records every copy (thread-safe: Image to Text copies from its handler).
final class RecordingClipboard: ClipboardService, @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []
    var copied: [String] { lock.withLock { all } }
    func copy(_ text: String, clearAfter: Duration?) { lock.withLock { all.append(text) } }
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

/// A mutable clock for tests.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
    func set(_ date: Date) { lock.withLock { current = date } }
}

func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes `contents` to a fresh file named `name` in a fresh temp folder.
func makeFile(_ name: String = "report.pdf", contents: String = "hello shelf") -> URL {
    let url = makeTempDirectory().appendingPathComponent(name)
    try! Data(contents.utf8).write(to: url)
    return url
}

/// Moves files into its own "Trash" folder (like the real Trash: the file survives) and records them.
final class RecordingRecycler: Recycler, @unchecked Sendable {
    private let lock = NSLock()
    private var all: [URL] = []
    let trash = makeTempDirectory()
    var fail = false

    var recycled: [URL] { lock.withLock { all } }

    struct Failure: Error {}

    func recycle(_ url: URL) async throws {
        if lock.withLock({ fail }) { throw Failure() }
        try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        lock.withLock { all.append(url) }
    }
}

/// Zones to list; records every `perform` (zone, payload) and answers `result`. `onPerform` runs inside the
/// call (to look at the security scope while the handler "runs").
final class FakeDropZoneDirectory: DropZoneDirectory, @unchecked Sendable {
    private let lock = NSLock()
    var summaries: [DropZoneSummary] = []
    var result: DropResult = .accepted
    var onPerform: (@Sendable () -> Void)?
    private var calls: [(zoneID: String, payload: DropPayload)] = []

    var performed: [(zoneID: String, payload: DropPayload)] { lock.withLock { calls } }

    @MainActor func zones() -> [DropZoneSummary] { lock.withLock { summaries } }

    @MainActor func perform(zoneID: String, payload: DropPayload) async -> DropResult {
        lock.withLock { calls.append((zoneID, payload)) }
        onPerform?()
        return lock.withLock { result }
    }
}
