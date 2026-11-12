import Foundation
import ModuleKit

@testable import Integrations

/// A script file's bytes for runner tests.
func runnerScript(
    id: String = "test.script", interval: String = "5m", runtime: String = "python3", widget: String = "number",
    settings: [String] = [], language: String = "python", code: String = "print('hello')"
) -> Data {
    var lines = ["---", "id: \(id)", "name: Test", "interval: \(interval)", "runtime: \(runtime)", "widget: \(widget)"]
    if !settings.isEmpty {
        lines.append("settings:")
        lines += settings.map { "  - " + $0 }
    }
    lines += ["---", "", "Docs.", "", "```" + language, code, "```", ""]
    return Data(lines.joined(separator: "\n").utf8)
}

/// A parsed definition of `data` as file `name` in a `modules` folder.
func runnerDefinition(_ data: Data, name: String = "test.md", enabled: Bool? = nil) -> ScriptModuleDefinition {
    let url = URL(fileURLWithPath: "/runner-tests/modules", isDirectory: true).appendingPathComponent(name)
    return ScriptModuleDefinition(url: url, folderName: "modules", data: data, enabled: { _ in enabled })
}

let numberOutput = Data(#"{"widget":{"type":"number","value":3,"label":"OPEN PRS"}}"#.utf8)

func launchResult(
    _ termination: ScriptLaunchResult.Termination = .exited(0), stdout: Data = numberOutput, stderr: String = ""
) -> ScriptLaunchResult {
    ScriptLaunchResult(
        termination: termination, stdout: stdout, stderr: Data(stderr.utf8), duration: .milliseconds(120))
}

/// Records each launch (with the code file's contents and mode at launch time) and returns queued results
/// (then a good number output). With `hold`, launches wait for `release()` or for their task's cancellation.
final class FakeLauncher: ScriptProcessLaunching, @unchecked Sendable {
    struct Launch {
        let request: ScriptLaunchRequest
        let code: String
        let mode: Int?
    }

    private let lock = NSLock()
    private var queued: [ScriptLaunchResult]
    private var recorded: [Launch] = []
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var cancelledIDs: Set<UUID> = []
    private var cancelledCount = 0
    var hold = false

    init(results: [ScriptLaunchResult] = []) { queued = results }

    var launches: [Launch] { lock.withLock { recorded } }
    var count: Int { launches.count }
    var cancelled: Int { lock.withLock { cancelledCount } }
    var waiting: Int { lock.withLock { waiters.count } }

    func enqueue(_ results: ScriptLaunchResult...) { lock.withLock { queued += results } }

    func release() {
        let all = lock.withLock {
            let all = Array(waiters.values)
            waiters = [:]
            return all
        }
        for waiter in all { waiter.resume(returning: false) }
    }

    func launch(_ request: ScriptLaunchRequest) async throws -> ScriptLaunchResult {
        let path = request.arguments.first ?? ""
        let code = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let mode = (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? Int
        lock.withLock { recorded.append(Launch(request: request, code: code, mode: mode)) }
        if lock.withLock({ hold }) {
            let id = UUID()
            let wasCancelled = await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    let resumeNow = lock.withLock {
                        if cancelledIDs.contains(id) { return true }
                        waiters[id] = continuation
                        return false
                    }
                    if resumeNow { continuation.resume(returning: true) }
                }
            } onCancel: {
                let waiter = lock.withLock {
                    cancelledIDs.insert(id)
                    return waiters.removeValue(forKey: id)
                }
                waiter?.resume(returning: true)
            }
            if wasCancelled {
                lock.withLock { cancelledCount += 1 }
                return launchResult(.timedOut, stdout: Data())
            }
        }
        return lock.withLock { queued.isEmpty ? launchResult() : queued.removeFirst() }
    }
}

/// Resolves the names it knows; records each lookup.
final class FakeResolver: ExecutableResolver, @unchecked Sendable {
    private let lock = NSLock()
    private let known: [String: URL]
    private let path: [String]
    private var asked: [String] = []

    init(
        _ known: [String: URL] = ["python3": URL(fileURLWithPath: "/opt/homebrew/bin/python3")],
        searchPath: [String] = ["/opt/homebrew/bin", "/usr/bin", "/bin"]
    ) {
        self.known = known
        path = searchPath
    }

    var lookups: [String] { lock.withLock { asked } }

    func resolve(_ name: String) async -> URL? {
        lock.withLock { asked.append(name) }
        return known[name]
    }

    var searchPath: [String] {
        get async { path }
    }
}

final class FakeSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var readKeys: [String] = []

    init(_ values: [String: String] = [:]) { self.values = values }

    var reads: [String] { lock.withLock { readKeys } }

    func read(_ key: String) async throws -> String? {
        lock.withLock {
            readKeys.append(key)
            return values[key]
        }
    }

    func write(_ value: String?, for key: String) async throws { lock.withLock { values[key] = value } }
}

/// Collects log lines.
final class LogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []
    var lines: [String] { lock.withLock { all } }
    var text: String { lines.joined(separator: "\n") }
    func append(_ line: String) { lock.withLock { all.append(line) } }
}

/// The time the runner reads; tests move it.
final class TestNow: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = date }
    var date: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

/// A runner on fakes, with what the test inspects.
@MainActor
struct RunnerHarness {
    let runner: ScriptRunner
    let launcher: FakeLauncher
    let resolver: FakeResolver
    let secrets: FakeSecretStore
    let scheduler: FakeScheduler
    let log: LogSink
    let now: TestNow
    let scratch: URL

    init(
        launcher: FakeLauncher = FakeLauncher(), resolver: FakeResolver = FakeResolver(),
        secrets: FakeSecretStore = FakeSecretStore(),
        configured: @escaping @MainActor @Sendable (ModuleID, String) -> (any SettingValue)? = { _, _ in nil },
        isEligible: @escaping @MainActor (ScriptModuleDefinition) -> Bool = { $0.enabled }
    ) {
        self.launcher = launcher
        self.resolver = resolver
        self.secrets = secrets
        scheduler = FakeScheduler()
        log = LogSink()
        now = TestNow()
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent(
            "runner-tests-\(UUID().uuidString)", isDirectory: true)
        let now = now
        let log = log
        runner = ScriptRunner(
            dependencies: ScriptRunner.Dependencies(
                executables: resolver, secrets: secrets, scheduler: scheduler, launcher: launcher,
                scratchDirectory: scratch, workingDirectory: URL(fileURLWithPath: "/runner-tests/modules"),
                configuredValue: configured, home: "/Users/tester", language: "fr_FR.UTF-8", now: { now.date },
                log: { log.append($0) }),
            isEligible: isEligible)
    }

    func state(_ id: String = "test.md") -> ScriptRunState? { runner.states[id] }

    /// Fires the earliest scheduled run and waits for it.
    func fireNext() async {
        await scheduler.fireNext()
        await runner.waitForIdle()
    }

    /// Polls `condition` every 5 ms for at most 2 s; returns whether it became true.
    @discardableResult
    func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    func cleanUp() { try? FileManager.default.removeItem(at: scratch) }
}
