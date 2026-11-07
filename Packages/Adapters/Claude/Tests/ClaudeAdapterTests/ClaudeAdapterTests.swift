import AgentKit
import Foundation
import Testing
import os

@testable import ClaudeAdapter

// MARK: - Fakes

struct StubResolver: ExecutableResolver {
    let paths: [String: URL]
    func resolve(_ name: String) async -> URL? { paths[name] }
}

final class RecordingRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(URL, [String], Duration)] = []
    let result: Result<String, ProcessRunnerError>

    init(_ result: Result<String, ProcessRunnerError>) { self.result = result }

    var calls: [(URL, [String], Duration)] { lock.withLock { _calls } }

    func run(executableURL: URL, arguments: [String], timeout: Duration) async throws -> String {
        lock.withLock { _calls.append((executableURL, arguments, timeout)) }
        return try result.get()
    }
}

struct StaticSettings: ReadOnlySettings {
    let values: [String: any SettingValue]
    let defaults: DefaultsReadOnlySettings

    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? {
        (values[key] as? T) ?? defaults.value(key, as: type)
    }
}

struct NoSecrets: SecretStore {
    func read(_ key: String) async throws -> String? { nil }
    func write(_ value: String?, for key: String) async throws {}
}

struct NoHTTP: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

struct MemoryFiles: ConfigFileReader {
    let files: [String: String]
    func read(_ url: URL) throws -> Data? { files[url.path].map { Data($0.utf8) } }
}

func makeContext(settings: [String: any SettingValue] = [:], paths: [String: URL] = [:]) -> AdapterContextBox {
    AdapterContextBox(
        settings: StaticSettings(
            values: settings, defaults: DefaultsReadOnlySettings(descriptors: ClaudeAdapter().settings)),
        secrets: NoSecrets(), executables: StubResolver(paths: paths), http: NoHTTP(),
        log: Logger(subsystem: "fr.baguettelabs.vigie.tests", category: "claude"))
}

// MARK: - Fixtures

@Suite struct FixtureCatalogTests {
    @Test func fixtureVersionsMatchTheSupportMatrix() throws {
        let versions = FixtureCatalog.versions
        #expect(versions == ["2.1.319"])
        let semvers = versions.compactMap { AgentVersion(raw: $0).semver }
        #expect(semvers.count == versions.count)
        // Every fixture version is supported, and every tested upper bound has fixtures.
        for version in versions {
            #expect(
                ClaudeAdapter.supportMatrix.support(for: AgentVersion(raw: version))
                    == .supported(AgentVersion(raw: version)))
        }
        for range in ClaudeAdapter.supportMatrix.testedRanges {
            #expect(semvers.contains(range.upperBound))
        }
    }

    @Test(arguments: FixtureCatalog.versions)
    func everyVersionHasAllEightEventsAndNotes(version: String) throws {
        let fixtures = FixtureCatalog.fixtures(version: version)
        #expect(Set(fixtures.map(\.event)) == Set(ClaudeAdapter.hookEvents))
        for fixture in fixtures {
            #expect(try fixture.raw()["hook_event_name"]?.stringValue == fixture.event)
        }
        let notes = FixtureCatalog.root.appendingPathComponent("\(version)/NOTES.md")
        let text = try String(contentsOf: notes, encoding: .utf8)
        #expect(text.contains("permission_prompt") && text.contains("idle_prompt"))
    }
}

// MARK: - Normalize

@Suite struct NormalizeTests {
    static let sentAt = Date(timeIntervalSince1970: 1_800_000_000.5)
    static let warpEnv = [
        "TERM_PROGRAM": "WarpTerminal", "WARP_FOCUS_URL": "warp://session/abc", "SHELL": "/bin/zsh",
    ]
    static let ancestors = [
        ProcessInfoEntry(
            pid: 85068, ppid: 85067, name: "2.1.319", startTime: Date(timeIntervalSince1970: 1_799_999_000)),
        ProcessInfoEntry(pid: 85067, ppid: 85066, name: "zsh", startTime: nil),
    ]

    static func hook(_ raw: JSONValue, env: [String: String] = warpEnv) -> HookPayload {
        HookPayload(agent: "claude", raw: raw, tty: "/dev/ttys003", env: env, ancestors: ancestors)
    }

    static func normalize(_ name: String) throws -> [AgentEvent] {
        ClaudeAdapter().normalize(hook(try FixtureCatalog.fixture(name).raw()), sentAt: sentAt)
    }

    /// Fixture → expected SPEC §7.1 event (nil = no event).
    static let table: [String: String?] = [
        "SessionStart": "session.start",
        "SessionStart.print": "session.start",
        "UserPromptSubmit": "prompt.submit",
        "UserPromptSubmit.agent_message": "prompt.submit",
        "PreToolUse": "tool.start",
        "PreToolUse.subagent": "tool.start",
        "PostToolUse": "tool.end",
        "Notification.permission_prompt": "needs.input",
        "Notification.idle_prompt": nil,
        "Stop": "turn.end",
        "Stop.background_tasks": "turn.end",
        "SubagentStop": "subagent.end",
        "SubagentStop.internal": nil,
        "SessionEnd": "session.end",
        "SessionEnd.print": "session.end",
    ]

    @Test func tableCoversEveryFixture() {
        #expect(Set(FixtureCatalog.fixtures(version: "2.1.319").map(\.name)) == Set(Self.table.keys))
    }

    @Test(arguments: FixtureCatalog.fixtures(version: "2.1.319").map(\.name))
    func fixtureMapsToExpectedEvent(name: String) throws {
        let events = try Self.normalize(name)
        let expected = try #require(Self.table[name])
        #expect(events.map(\.name.rawValue) == (expected.map { [$0] } ?? []))
        for event in events {
            let raw = try FixtureCatalog.fixture(name).raw()
            #expect(
                event.context.sessionKey == SessionKey(agentID: "claude", sessionID: raw["session_id"]!.stringValue!))
            #expect(event.context.at == Self.sentAt)
            #expect(event.context.cwd?.path == raw["cwd"]?.stringValue)
            #expect(event.context.tty == "/dev/ttys003")
            #expect(event.context.terminal?.warpFocusURL == "warp://session/abc")
            #expect(event.context.agentProcess?.pid == 85068)
        }
    }

    @Test func payloadFieldsAreCarried() throws {
        guard case .sessionStart(_, let model) = try #require(try Self.normalize("SessionStart").first) else {
            Issue.record("not session.start")
            return
        }
        #expect(model == "claude-fable-5-1")
        guard case .sessionStart(_, let noModel) = try #require(try Self.normalize("SessionStart.print").first) else {
            Issue.record("not session.start")
            return
        }
        #expect(noModel == nil)
        #expect(try Self.normalize("PreToolUse").first?.toolName == "Bash")
        #expect(try Self.normalize("PostToolUse").first?.toolName == "Bash")
        guard
            case .needsInput(_, let reason, let message) = try #require(
                try Self.normalize("Notification.permission_prompt").first)
        else {
            Issue.record("not needs.input")
            return
        }
        #expect(reason == .permissionPrompt)
        #expect(message == "Claude needs your permission")
        guard case .sessionEnd(_, let reason) = try #require(try Self.normalize("SessionEnd").first) else {
            Issue.record("not session.end")
            return
        }
        #expect(reason == "prompt_input_exit")
        guard case .sessionEnd(_, let printReason) = try #require(try Self.normalize("SessionEnd.print").first) else {
            Issue.record("not session.end")
            return
        }
        #expect(printReason == "other")
    }

    @Test func idleReminderProducesNothing() throws {
        #expect(try Self.normalize("Notification.idle_prompt").isEmpty)
    }

    @Test func internalSubagentStopProducesNothing() throws {
        #expect(try Self.normalize("SubagentStop.internal").isEmpty)
        let missingType: JSONValue = .object([
            "hook_event_name": .string("SubagentStop"), "session_id": .string("s"),
        ])
        #expect(ClaudeAdapter().normalize(Self.hook(missingType), sentAt: Self.sentAt).isEmpty)
    }

    @Test func stopWithBackgroundTasksIsTurnEnd() throws {
        #expect(try Self.normalize("Stop.background_tasks").map(\.name) == [.turnEnd])
    }

    @Test func errorNotificationIsSessionError() {
        let raw: JSONValue = .object([
            "hook_event_name": .string("Notification"), "session_id": .string("s"),
            "notification_type": .string("api_error"), "message": .string("Login required"),
        ])
        let events = ClaudeAdapter().normalize(Self.hook(raw), sentAt: Self.sentAt)
        #expect(events == [.sessionError(events[0].context, message: "Login required")])
    }

    @Test(arguments: ["elicitation_dialog", "auth_success", ""])
    func otherNotificationsProduceNothing(type: String) {
        let raw: JSONValue = .object([
            "hook_event_name": .string("Notification"), "session_id": .string("s"),
            "notification_type": .string(type),
        ])
        #expect(ClaudeAdapter().normalize(Self.hook(raw), sentAt: Self.sentAt).isEmpty)
    }

    @Test func unknownEventOrMissingSessionProducesNothing() {
        let adapter = ClaudeAdapter()
        for raw: JSONValue in [
            .object(["hook_event_name": .string("PermissionRequest"), "session_id": .string("s")]),
            .object(["hook_event_name": .string("StopFailure"), "session_id": .string("s")]),
            .object(["hook_event_name": .string("Stop")]),
            .object(["hook_event_name": .string("Stop"), "session_id": .string("")]),
            .object(["session_id": .string("s")]),
            .string("garbage"),
        ] {
            #expect(adapter.normalize(Self.hook(raw), sentAt: Self.sentAt).isEmpty)
        }
    }

    @Test func gatedNormalizeDropsUnsupportedVersions() throws {
        let hook = Self.hook(try FixtureCatalog.fixture("Stop").raw())
        let adapter = ClaudeAdapter()
        #expect(
            adapter.normalize(hook, sentAt: Self.sentAt, support: adapter.support(for: AgentVersion(raw: "2.2.0")))
                .isEmpty)
        #expect(adapter.normalize(hook, sentAt: Self.sentAt, support: adapter.support(for: nil)).isEmpty)
        #expect(
            adapter.normalize(hook, sentAt: Self.sentAt, support: adapter.support(for: AgentVersion(raw: "2.1.319")))
                .count == 1)
    }
}

extension AgentEvent {
    var toolName: String? {
        switch self {
        case .toolStart(_, let tool), .toolEnd(_, let tool): tool
        default: nil
        }
    }
}

// MARK: - Agent process

@Suite struct AgentProcessTests {
    static let start = Date(timeIntervalSince1970: 1_799_999_000)
    /// Spike 1.4 run 3, parent first.
    static let spikeChain = [
        ProcessInfoEntry(pid: 85068, ppid: 85067, name: "2.1.319", startTime: start),
        ProcessInfoEntry(pid: 85067, ppid: 85066, name: "expect", startTime: start),
        ProcessInfoEntry(pid: 85066, ppid: 48474, name: "zsh", startTime: start),
        ProcessInfoEntry(pid: 48474, ppid: 31124, name: "2.1.319", startTime: start),
        ProcessInfoEntry(pid: 31124, ppid: 801, name: "zsh", startTime: start),
        ProcessInfoEntry(pid: 801, ppid: 717, name: "stable", startTime: start),
    ]

    @Test func picksTheVersionNamedParent() {
        #expect(
            ClaudeAdapter().agentProcess(in: Self.spikeChain, environment: [:])
                == AgentProcessRef(pid: 85068, startTime: Self.start))
    }

    @Test func skipsAnIntermediateShell() {
        let chain = [ProcessInfoEntry(pid: 9, ppid: 85068, name: "zsh", startTime: nil)] + Self.spikeChain
        #expect(ClaudeAdapter().agentProcess(in: chain, environment: [:])?.pid == 85068)
        let named = [
            ProcessInfoEntry(pid: 9, ppid: 7, name: "sh", startTime: nil),
            ProcessInfoEntry(pid: 7, ppid: 1, name: "claude", startTime: Self.start),
        ]
        #expect(ClaudeAdapter().agentProcess(in: named, environment: [:])?.pid == 7)
    }

    @Test func honoursClaudePID() {
        #expect(ClaudeAdapter().agentProcess(in: Self.spikeChain, environment: ["CLAUDE_PID": "48474"])?.pid == 48474)
        // A CLAUDE_PID that names no ancestor is ignored.
        #expect(ClaudeAdapter().agentProcess(in: Self.spikeChain, environment: ["CLAUDE_PID": "1234"])?.pid == 85068)
    }

    @Test func nodeParentAndNoMatch() {
        let node = [
            ProcessInfoEntry(pid: 5, ppid: 4, name: "node", startTime: nil),
            ProcessInfoEntry(pid: 4, ppid: 1, name: "zsh", startTime: nil),
        ]
        #expect(ClaudeAdapter().agentProcess(in: node, environment: [:])?.pid == 5)
        let shells = [
            ProcessInfoEntry(pid: 5, ppid: 4, name: "zsh", startTime: nil),
            ProcessInfoEntry(pid: 4, ppid: 1, name: "login", startTime: nil),
        ]
        #expect(ClaudeAdapter().agentProcess(in: shells, environment: [:]) == nil)
        #expect(ClaudeAdapter().agentProcess(in: [], environment: [:]) == nil)
    }

    @Test(arguments: [
        ("2.1.319", true), ("10.0.0", true), ("2.1", false), ("2.1.x", false), ("v2.1.3", false), ("zsh", false),
    ])
    func versionNames(name: String, expected: Bool) {
        #expect(ClaudeAdapter.isVersionName(name) == expected)
    }
}

// MARK: - Version gate

@Suite struct VersionGateTests {
    static let claude = URL(fileURLWithPath: "/Users/romain/.local/bin/claude")

    @Test(arguments: [
        ("2.1.319 (Claude Code)", "supported"), ("2.1.0", "supported"), ("2.1.400", "assumed"),
        ("2.2.0", "unsupported"),
        ("1.9.0", "unsupported"), ("", "unsupported"),
    ])
    func supportMatrix(raw: String, expected: String) {
        let version = AgentVersion(raw: raw)
        let expectedSupport: AdapterSupport =
            switch expected {
            case "supported": .supported(version)
            case "assumed": .assumed(version)
            default: .unsupported(version)
            }
        #expect(ClaudeAdapter().support(for: version) == expectedSupport)
    }

    @Test func notInstalled() {
        #expect(ClaudeAdapter().support(for: nil) == .notInstalled)
    }

    @Test func detectsVersionThroughResolver() async {
        let runner = RecordingRunner(.success("2.1.319 (Claude Code)\n"))
        let version = await ClaudeAdapter(runner: runner).detectVersion(
            context: makeContext(paths: ["claude": Self.claude]))
        #expect(version?.semver == AgentVersion.Semver(2, 1, 319))
        #expect(version?.raw == "2.1.319 (Claude Code)")
        #expect(runner.calls.count == 1)
        #expect(runner.calls.first?.0 == Self.claude)
        #expect(runner.calls.first?.1 == ["--version"])
        #expect(runner.calls.first?.2 == .seconds(3))
    }

    @Test func executableSettingWins() async {
        let runner = RecordingRunner(.success("2.1.300 (Claude Code)"))
        let version = await ClaudeAdapter(runner: runner).detectVersion(
            context: makeContext(settings: ["executable": "/opt/claude/bin/claude"], paths: ["claude": Self.claude]))
        #expect(version?.semver == AgentVersion.Semver(2, 1, 300))
        #expect(runner.calls.first?.0.path == "/opt/claude/bin/claude")
    }

    @Test func notFoundIsNil() async {
        let runner = RecordingRunner(.success("2.1.319"))
        #expect(await ClaudeAdapter(runner: runner).detectVersion(context: makeContext()) == nil)
        #expect(runner.calls.isEmpty)
        // A relative override is refused rather than run by name.
        #expect(
            await ClaudeAdapter(runner: runner).detectVersion(context: makeContext(settings: ["executable": "claude"]))
                == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func failingCLIIsUnsupported() async {
        let adapter = ClaudeAdapter(runner: RecordingRunner(.failure(.timedOut)))
        let version = await adapter.detectVersion(context: makeContext(paths: ["claude": Self.claude]))
        #expect(version == AgentVersion(raw: ""))
        #expect(adapter.support(for: version) == .unsupported(AgentVersion(raw: "")))
    }
}

// MARK: - Descriptors and catalog

@Suite struct DescriptorTests {
    @Test func identityAndSettings() {
        let adapter = ClaudeAdapter()
        #expect(adapter.id == "claude")
        #expect(adapter.capabilities == [.hooks, .launch])
        #expect(adapter.settings.map(\.key) == ["executable", "hooks_scope"])
        #expect(adapter.settings[0].kind == .path(default: nil))
        #expect(adapter.settings[0].scope == .local)
        #expect(adapter.settings[1].kind == .enumeration(options: ["user", "project"], default: "user"))
        #expect(adapter.launchCommand(files: [], cwd: nil) == LaunchCommand(executable: "claude", arguments: []))
        #expect(adapter.transcriptWatcher == nil && adapter.logReader == nil && adapter.usageProvider == nil)
    }

    @Test func stringsResolveFromCatalog() {
        #expect(String(localized: ClaudeAdapter().name) == "Claude Code")
        for descriptor in ClaudeAdapter().settings {
            let label = String(localized: descriptor.label)
            #expect(!label.isEmpty && !label.hasPrefix("claude."))
            let help = descriptor.help.map { String(localized: $0) } ?? ""
            #expect(!help.isEmpty && !help.hasPrefix("claude."))
        }
    }
}
