import AgentKit
import Foundation
import ModuleKit
import Wire
import os

/// In-memory `ModuleContext`: real behavior for settings, storage, scheduler and events (what
/// `agents.sessions` uses); every other service is a no-op.
final class FakeModuleContext: ModuleContext, @unchecked Sendable {
    let fakeSettings: FakeSettings
    let fakeStorage: FakeStorage
    let fakeScheduler = FakeScheduler()
    let fakeEvents = FakeEventBus()

    init(settings: [String: any SettingValue] = [:], storage: FakeStorage = FakeStorage()) {
        fakeSettings = FakeSettings(values: settings)
        fakeStorage = storage
    }

    var settings: any ModuleSettings { fakeSettings }
    var storage: any ModuleStorage { fakeStorage }
    var secrets: any SecretStore { NoSecrets() }
    var scheduler: any Scheduler { fakeScheduler }
    var hotkeys: any HotkeyRegistry { NoHotkeys() }
    var notifier: any Notifier { NoNotifier() }
    var events: any EventBus { fakeEvents }
    var host: any HostControl { NoHost() }
    var permissions: any PermissionsService { NoPermissions() }
    var power: any PowerService { NoPower() }
    var clipboard: any ClipboardService { NoClipboard() }
    var executables: any ExecutableResolver { NoExecutables() }
    var privacy: any PrivacyService { NoPrivacy() }
    var away: any AwayService { NoAway() }
    var activity: any ActivityLog { NoActivity() }
    var log: Logger { Logger(subsystem: "test", category: "agents.sessions") }
}

struct FakeSettings: ModuleSettings {
    let values: [String: any SettingValue]
    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? { values[key] as? T }
    func set<T: SettingValue>(_ value: T?, for key: String) async throws {}
    func observe(_ key: String) -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// Keeps each file as `{schema, value}` JSON in memory, written immediately.
final class FakeStorage: ModuleStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var writes: [String: Int] = [:]

    var directory: URL { URL(fileURLWithPath: "/dev/null") }

    func data(_ name: String) -> Data? { lock.withLock { files[name] } }
    func writeCount(_ name: String) -> Int { lock.withLock { writes[name, default: 0] } }

    func readJSON<T: Decodable & Sendable>(
        _ name: String, as type: T.Type, schema: Int,
        migrate: (@Sendable (Int, Data) throws -> T)?
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
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(WireDate.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let stamp = try decoder.singleValueContainer().decode(String.self)
            guard let date = WireDate.date(from: stamp) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: stamp))
            }
            return date
        }
        return decoder
    }()
}

struct StateFile<Value> {
    let schema: Int
    let value: Value
}

extension StateFile: Encodable where Value: Encodable {}
extension StateFile: Decodable where Value: Decodable {}

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

/// One subscription; tests `send` messages and `finish()` to let the module drain them.
final class FakeEventBus: EventBus, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<EventMessage>.Continuation] = []
    private(set) var prefixes: [String] = []

    func subscribe(topicPrefix: String) -> AsyncStream<EventMessage> {
        let (stream, continuation) = AsyncStream<EventMessage>.makeStream()
        lock.withLock {
            continuations.append(continuation)
            prefixes.append(topicPrefix)
        }
        return stream
    }

    func send(_ message: EventMessage) {
        for continuation in lock.withLock({ continuations }) { continuation.yield(message) }
    }

    func finish() {
        for continuation in lock.withLock({ continuations }) { continuation.finish() }
    }
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

struct NoNotifier: Notifier {
    func post(_ event: NotifierEvent) -> AlertHandle { AlertHandle {} }
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

/// Maps `raw = {"event": "<SPEC name>", "session": "<id>", "tool"?: "...", "cwd"?: "..."}` to one event.
struct FakeAdapter: AgentAdapter {
    var id: AgentID { "fake" }
    var name: LocalizedStringResource { "Fake" }
    var capabilities: Set<AgentCapability> { [.hooks] }

    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] {
        guard let name = hook.raw["event"]?.stringValue.flatMap(AgentEvent.Name.init(rawValue:)),
            let session = hook.raw["session"]?.stringValue
        else { return [] }
        let context = AgentEventContext(
            sessionKey: SessionKey(agentID: id, sessionID: session),
            cwd: hook.raw["cwd"]?.stringValue.map { URL(fileURLWithPath: $0) },
            tty: hook.tty,
            terminal: TerminalHint(env: hook.env),
            at: sentAt)
        let tool = hook.raw["tool"]?.stringValue ?? "Bash"
        return switch name {
        case .sessionStart: [.sessionStart(context, model: "fake-1")]
        case .promptSubmit: [.promptSubmit(context)]
        case .toolStart: [.toolStart(context, tool: tool)]
        case .toolEnd: [.toolEnd(context, tool: tool)]
        case .subagentEnd: [.subagentEnd(context)]
        case .needsInput: [.needsInput(context, reason: .permissionPrompt, message: "Allow?")]
        case .turnEnd: [.turnEnd(context)]
        case .sessionError: [.sessionError(context, message: "Login required")]
        case .sessionEnd: [.sessionEnd(context)]
        }
    }
}

enum Hook {
    static func message(
        _ event: String, session: String = "s1", agent: String = "fake", at: Date, tool: String? = nil,
        cwd: String? = nil, replayed: Bool = false
    ) throws -> EventMessage {
        var raw: [String: JSONValue] = ["event": .string(event), "session": .string(session)]
        if let tool { raw["tool"] = .string(tool) }
        if let cwd { raw["cwd"] = .string(cwd) }
        let payload = HookPayload(
            agent: agent, raw: .object(raw), tty: "/dev/ttys003", env: ["TERM_PROGRAM": "WarpTerminal"],
            ancestors: [])
        let data = try JSONEncoder().encode(payload)
        return EventMessage(
            topic: "agent.hook", payload: data, sentAt: at, receivedAt: at.addingTimeInterval(1), replayed: replayed)
    }
}

/// Liveness from a mutable set of live processes (pid + start time).
final class FakeLiveness: ProcessLiveness, @unchecked Sendable {
    private let lock = NSLock()
    private var alive: Set<AgentProcessRef>
    private(set) var checks = 0

    init(alive: Set<AgentProcessRef> = []) {
        self.alive = alive
    }

    func kill(_ ref: AgentProcessRef) { _ = lock.withLock { alive.remove(ref) } }

    func isAlive(_ ref: AgentProcessRef) -> Bool {
        lock.withLock {
            checks += 1
            return alive.contains(ref)
        }
    }
}
