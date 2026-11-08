import Foundation
import ModuleKit
import os

@testable import Time

/// `ModuleContext` with recording settings, storage (JSON in memory), scheduler, hotkeys, notifier, host and a
/// sleep/wake stream the test drives; every other service is a no-op.
final class FakeModuleContext: ModuleContext, @unchecked Sendable {
    let fakeSettings: FakeSettings
    let fakeStorage: FakeStorage
    let fakeScheduler = FakeScheduler()
    let fakeHotkeys = FakeHotkeys()
    let fakeNotifier = RecordingNotifier()
    let fakeHost = RecordingHost()
    let fakePower = FakePower()
    let fakeAway = FakeAway()

    init(settings: [String: any SettingValue] = [:], storage: FakeStorage = FakeStorage()) {
        fakeSettings = FakeSettings(values: settings)
        fakeStorage = storage
    }

    var settings: any ModuleSettings { fakeSettings }
    var storage: any ModuleStorage { fakeStorage }
    var secrets: any SecretStore { NoSecrets() }
    var scheduler: any Scheduler { fakeScheduler }
    var hotkeys: any HotkeyRegistry { fakeHotkeys }
    var notifier: any Notifier { fakeNotifier }
    var events: any EventBus { NoEvents() }
    var host: any HostControl { fakeHost }
    var permissions: any PermissionsService { NoPermissions() }
    var power: any PowerService { fakePower }
    var clipboard: any ClipboardService { NoClipboard() }
    var executables: any ExecutableResolver { NoExecutables() }
    var privacy: any PrivacyService { NoPrivacy() }
    var away: any AwayService { fakeAway }
    var activity: any ActivityLog { NoActivity() }
    var integrations: any IntegrationInstaller { NoIntegrations() }
    var log: Logger { Logger(subsystem: "test", category: "time") }
}

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

/// JSON files in memory, written at once.
final class FakeStorage: ModuleStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("time-tests-\(UUID().uuidString)")

    func data(_ name: String) -> Data? { lock.withLock { files[name] } }

    func readJSON<T: Decodable & Sendable>(
        _ name: String, as type: T.Type, schema: Int, migrate: (@Sendable (Int, Data) throws -> T)?
    ) async throws -> T? {
        guard let data = data(name) else { return nil }
        return try Self.decoder.decode(StateFile<T>.self, from: data).value
    }

    func writeJSON<T: Encodable & Sendable>(_ value: T, name: String, schema: Int) async throws {
        let data = try Self.encoder.encode(StateFile(schema: schema, value: value))
        lock.withLock { files[name] = data }
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

/// Records every job with its cancel state; tests fire them by hand.
final class FakeScheduler: Scheduler, @unchecked Sendable {
    final class Job: @unchecked Sendable {
        let date: Date?
        let interval: Duration?
        let body: @Sendable () async -> Void
        var cancelled = false
        init(date: Date?, interval: Duration?, body: @escaping @Sendable () async -> Void) {
            self.date = date
            self.interval = interval
            self.body = body
        }
    }

    private let lock = NSLock()
    private var all: [Job] = []

    var jobs: [Job] { lock.withLock { all } }
    var liveOneShots: [Job] { jobs.filter { $0.date != nil && !$0.cancelled } }
    var liveRepeating: [Job] { jobs.filter { $0.interval != nil && !$0.cancelled } }

    func every(_ interval: Duration, _ body: @escaping @Sendable () async -> Void) -> RegistrationToken {
        add(Job(date: nil, interval: interval, body: body))
    }

    func at(_ date: Date, _ body: @escaping @Sendable () async -> Void) -> RegistrationToken {
        add(Job(date: date, interval: nil, body: body))
    }

    private func add(_ job: Job) -> RegistrationToken {
        lock.withLock { all.append(job) }
        return RegistrationToken { [weak self] in self?.lock.withLock { job.cancelled = true } }
    }

    /// Runs the live one-shot job due earliest.
    func fireNext() async {
        guard let job = liveOneShots.min(by: { $0.date! < $1.date! }) else { return }
        lock.withLock { job.cancelled = true }
        await job.body()
    }
}

final class FakeHotkeys: HotkeyRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var registered: [(name: String, shortcut: String?, handler: @MainActor @Sendable (UserIntent) -> Void)] = []
    private var cancelledNames: [String] = []

    var names: [String] { lock.withLock { registered.map(\.name) } }
    var defaults: [String?] { lock.withLock { registered.map(\.shortcut) } }
    var cancelled: [String] { lock.withLock { cancelledNames } }

    func register(
        name: String, default shortcut: String?, handler: @escaping @MainActor @Sendable (UserIntent) -> Void
    ) throws -> RegistrationToken {
        lock.withLock { registered.append((name, shortcut, handler)) }
        return RegistrationToken { [weak self] in self?.lock.withLock { self?.cancelledNames.append(name) } }
    }

    @MainActor func press(_ name: String, intent: UserIntent) {
        let handler = lock.withLock { registered.first { $0.name == name }?.handler }
        handler?(intent)
    }
}

final class RecordingNotifier: Notifier, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [NotifierEvent] = []
    private var resolvedCount = 0
    private var resolvedIndices: Set<Int> = []
    var posted: [NotifierEvent] { lock.withLock { events } }
    var resolved: Int { lock.withLock { resolvedCount } }
    /// Posts not resolved yet.
    var unresolved: [NotifierEvent] {
        lock.withLock { events.enumerated().filter { !resolvedIndices.contains($0.offset) }.map(\.element) }
    }

    func post(_ event: NotifierEvent) -> AlertHandle {
        let index = lock.withLock {
            events.append(event)
            return events.count - 1
        }
        return AlertHandle { [weak self] in
            self?.lock.withLock {
                guard let self, self.resolvedIndices.insert(index).inserted else { return }
                self.resolvedCount += 1
            }
        }
    }
}

final class RecordingHost: HostControl, @unchecked Sendable {
    private let lock = NSLock()
    private var opens: [UserIntent?] = []
    var openedOwnTab: [UserIntent?] { lock.withLock { opens } }

    func requestPeek() {}
    func expand(focus: UserIntent?) {}
    func openOwnTab(focus: UserIntent?) { lock.withLock { opens.append(focus) } }
    func registerDynamicModule(_ module: any NotchModule) throws -> RegistrationToken { RegistrationToken {} }
}

/// One sleep/wake stream; `send` yields to it.
final class FakePower: PowerService, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<SleepWakeEvent>.Continuation] = []

    func preventIdleSleep(reason: String) -> RegistrationToken { RegistrationToken {} }

    var sleepWake: AsyncStream<SleepWakeEvent> {
        let (stream, continuation) = AsyncStream<SleepWakeEvent>.makeStream()
        lock.withLock { continuations.append(continuation) }
        return stream
    }

    var subscribers: Int { lock.withLock { continuations.count } }

    func send(_ event: SleepWakeEvent) {
        for continuation in lock.withLock({ continuations }) { continuation.yield(event) }
    }
}

struct NoSecrets: SecretStore {
    func read(_ key: String) async throws -> String? { nil }
    func write(_ value: String?, for key: String) async throws {}
}

struct NoEvents: EventBus {
    func subscribe(topicPrefix: String) -> AsyncStream<EventMessage> { AsyncStream { $0.finish() } }
}

struct NoPermissions: PermissionsService {
    func status(of permission: Permission) async -> PermissionStatus { .notDetermined }
    func request(_ permission: Permission) async -> PermissionStatus { .notDetermined }
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

/// `context.away` the test drives: `send` sets the presence and yields it; counts open streams.
final class FakeAway: AwayService, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Presence = .present
    private var continuations: [UUID: AsyncStream<Presence>.Continuation] = [:]

    var presence: Presence { lock.withLock { current } }
    var subscribers: Int { lock.withLock { continuations.count } }

    var changes: AsyncStream<Presence> {
        let (stream, continuation) = AsyncStream<Presence>.makeStream()
        let id = UUID()
        lock.withLock { continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    func send(_ presence: Presence) {
        let all = lock.withLock {
            current = presence
            return Array(continuations.values)
        }
        for continuation in all { continuation.yield(presence) }
    }
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

/// A mutable clock for tests.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

/// UTC so clock times are stable: the reference instant is Fri 06 Nov 2026 14:43:00 UTC.
enum Fixture {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static let start: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 6
        components.hour = 14
        components.minute = 43
        return calendar.date(from: components)!
    }()
}
