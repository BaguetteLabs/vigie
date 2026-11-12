import Foundation
import Testing
import os

@testable import AgentKit

@Suite struct AgentVersionTests {
    @Test(arguments: [
        ("2.1.319 (Claude Code)", AgentVersion.Semver(2, 1, 319)),
        ("2.1.319", AgentVersion.Semver(2, 1, 319)),
        ("v1.2", AgentVersion.Semver(1, 2, 0)),
        ("codex-cli 0.46.0\n", AgentVersion.Semver(0, 46, 0)),
        ("gemini 10.20.30.40", AgentVersion.Semver(10, 20, 30)),
    ])
    func parsesSemver(raw: String, expected: AgentVersion.Semver) {
        #expect(AgentVersion(raw: raw).semver == expected)
    }

    @Test(arguments: ["", "garbage", "version x.y", "7", "1.", ".5"])
    func garbageHasNoSemver(raw: String) {
        let version = AgentVersion(raw: raw)
        #expect(version.semver == nil)
        #expect(version.raw == raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func semverOrdersNumerically() {
        #expect(AgentVersion.Semver(2, 1, 9) < AgentVersion.Semver(2, 1, 319))
        #expect(AgentVersion.Semver(1, 99, 99) < AgentVersion.Semver(2, 0, 0))
    }
}

@Suite struct IdentifierTests {
    @Test(arguments: [("claude", true), ("gemini-2", true), ("Claude", false), ("agents.sessions", false), ("", false)])
    func validatesAdapterIDs(raw: String, valid: Bool) {
        // A String value, not a literal: `AgentID("literal")` takes the trapping literal init (SE-0213).
        #expect((AgentID(raw) != nil) == valid)
        #expect((TerminalID(raw) != nil) == valid)
    }

    @Test func sessionKeyReadsAsAdapterColonSession() {
        #expect(SessionKey(agentID: "claude", sessionID: "abc").description == "claude:abc")
    }
}

@Suite struct TerminalHintTests {
    /// Env from spike 1.5 (`docs/decisions/spike-warp-focus.md`), as forwarded by `vigie hook`.
    static let warpEnv = [
        "TERM_PROGRAM": "WarpTerminal",
        "TERM_PROGRAM_VERSION": "v0.2026.10.14.08.27.stable_01",
        "WARP_CLIENT_VERSION": "v0.2026.10.14.08.27.stable_01",
        "WARP_TERMINAL_SESSION_UUID": "dbb86f5d0ced4332a8feab247a908497",
        "WARP_FOCUS_URL": "warp://session/dbb86f5d0ced4332a8feab247a908497",
        "WARP_CLI_AGENT_PROTOCOL_VERSION": "1",
        "WARP_IS_LOCAL_SHELL_SESSION": "1",
        "__CFBundleIdentifier": "dev.warp.Warp-Stable",
        "SHELL": "/bin/zsh",
        "PWD": "/Users/romain/www/vigie",
    ]

    @Test func extractsWarpHint() throws {
        let hint = try #require(TerminalHint(env: Self.warpEnv))
        #expect(hint.program == "WarpTerminal")
        #expect(hint.sessionID == "dbb86f5d0ced4332a8feab247a908497")
        #expect(hint.warpFocusURL == "warp://session/dbb86f5d0ced4332a8feab247a908497")
        #expect(hint.bundleID == "dev.warp.Warp-Stable")
        #expect(!hint.insideTmux)
    }

    @Test func prefersITermSessionID() throws {
        let hint = try #require(
            TerminalHint(env: [
                "TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t1p0:ABC", "TERM_SESSION_ID": "w0t1p0:ABC2",
                "TMUX": "/tmp/tmux-501/default,1,0",
            ]))
        #expect(hint.sessionID == "w0t1p0:ABC")
        #expect(hint.insideTmux)
    }

    @Test func headlessEnvHasNoHint() {
        #expect(TerminalHint(env: ["SHELL": "/bin/zsh", "PWD": "/tmp", "TERM_PROGRAM": "  "]) == nil)
    }
}

@Suite struct AgentEventTests {
    static let context = AgentEventContext(
        sessionKey: SessionKey(agentID: "claude", sessionID: "s-1"),
        cwd: URL(fileURLWithPath: "/Users/romain/www/vigie"),
        tty: "/dev/ttys003",
        terminal: TerminalHint(env: TerminalHintTests.warpEnv),
        agentProcess: AgentProcessRef(pid: 85068, startTime: Date(timeIntervalSince1970: 1_800_000_000)),
        at: Date(timeIntervalSince1970: 1_800_000_123.25)
    )

    static let all: [AgentEvent] = [
        .sessionStart(context, model: "claude-fable-5-1"),
        .sessionStart(context),
        .promptSubmit(context),
        .toolStart(context, tool: "Bash"),
        .toolEnd(context, tool: "Bash"),
        .subagentEnd(context),
        .needsInput(context, reason: .permissionPrompt, message: "Claude needs your permission"),
        .needsInput(context, reason: .question),
        .turnEnd(context),
        .sessionError(context, message: "login required"),
        .sessionEnd(context, reason: "prompt_input_exit"),
    ]

    @Test func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for event in Self.all {
            let data = try encoder.encode(event)
            #expect(try decoder.decode(AgentEvent.self, from: data) == event)
        }
    }

    @Test func encodesSpecName() throws {
        let json = try JSONValue(encoding: AgentEvent.needsInput(Self.context, reason: .permissionPrompt))
        #expect(json["event"]?.stringValue == "needs.input")
        #expect(json["reason"]?.stringValue == "permission_prompt")
        #expect(json["message"] == nil)
        #expect(json["context"]?["at"]?.stringValue == "2027-01-15T08:02:03.250Z")
        #expect(json["context"]?["cwd"]?.stringValue == "/Users/romain/www/vigie")
    }

    @Test func namesMatchSpec() {
        #expect(
            AgentEvent.Name.allCases.map(\.rawValue) == [
                "session.start", "prompt.submit", "tool.start", "tool.end", "subagent.end", "needs.input",
                "turn.end", "session.error", "session.end",
            ])
        #expect(Set(Self.all.map(\.name)) == Set(AgentEvent.Name.allCases))
        #expect(Self.all.allSatisfy { $0.context == Self.context })
    }
}

// MARK: - Fakes

struct FakeAdapter: AgentAdapter {
    let id: AgentID = "fake"
    var name: LocalizedStringResource { "Fake" }
    let capabilities: Set<AgentCapability> = [.hooks]

    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] {
        guard let sessionID = hook.raw["session_id"]?.stringValue else { return [] }
        let context = AgentEventContext(
            sessionKey: SessionKey(agentID: id, sessionID: sessionID), tty: hook.tty,
            terminal: TerminalHint(env: hook.env), at: sentAt)
        return [.promptSubmit(context)]
    }
}

struct FakeTerminal: TerminalAdapter {
    let id: TerminalID = "warp"
    var name: LocalizedStringResource { "Warp" }
    let bundleIDs = ["dev.warp.Warp-Stable"]

    func matches(env: [String: String]) -> Bool { env["TERM_PROGRAM"] == "WarpTerminal" }

    func capture(env: [String: String], pid: Int32?, tty: String?) -> TerminalLocator? {
        env["WARP_FOCUS_URL"].map { TerminalLocator(terminalID: id, fields: ["focus_url": $0]) }
    }

    func focus(_ locator: TerminalLocator, context: any AdapterContext) async -> FocusResult { .appOnly }
}

struct NoSecrets: SecretStore {
    func read(_ key: String) async throws -> String? { nil }
    func write(_ value: String?, for key: String) async throws {}
}

struct NoExecutables: ExecutableResolver {
    func resolve(_ name: String) async -> URL? { nil }
}

struct NoHTTP: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

func makeContext(settings: [SettingDescriptor] = []) -> AdapterContextBox {
    AdapterContextBox(
        settings: DefaultsReadOnlySettings(descriptors: settings), secrets: NoSecrets(), executables: NoExecutables(),
        http: NoHTTP(), log: Logger(subsystem: "fr.baguettelabs.vigie.tests", category: "fake"))
}

@Suite struct ContractDefaultsTests {
    @Test func fakeAdapterGetsDefaults() async throws {
        let adapter = FakeAdapter()
        let context = makeContext()
        #expect(adapter.settings.isEmpty)
        #expect(await adapter.detectVersion(context: context) == nil)
        let inputs = IntegrationInputs(
            cliPath: "/Users/romain/.local/bin/vigie", homeDirectory: URL(fileURLWithPath: "/Users/romain"))
        #expect(try await adapter.integrationPlan(context: context, inputs: inputs).isEmpty)
        #expect(try await adapter.removalPlan(context: context, inputs: inputs).isEmpty)
        #expect(adapter.support(for: nil) == .notInstalled)
        #expect(adapter.support(for: AgentVersion(raw: "1.0.0")) == .unsupported(AgentVersion(raw: "1.0.0")))
        let ancestors = [ProcessInfoEntry(pid: 10, ppid: 1, name: "2.1.319", startTime: nil)]
        #expect(adapter.agentProcess(in: ancestors, environment: [:]) == nil)
        #expect(adapter.transcriptWatcher == nil)
        #expect(adapter.logReader == nil)
        #expect(adapter.usageProvider == nil)
        #expect(adapter.launchCommand(files: [], cwd: nil) == nil)
    }

    @Test func normalizeUsesSentAt() {
        let hook = HookPayload(
            agent: "fake", raw: .object(["session_id": .string("s")]), tty: nil, env: TerminalHintTests.warpEnv,
            ancestors: [])
        let sentAt = Date(timeIntervalSince1970: 42)
        let events = FakeAdapter().normalize(hook, sentAt: sentAt)
        #expect(events.map(\.name) == [.promptSubmit])
        #expect(events.first?.context.at == sentAt)
        #expect(events.first?.context.sessionKey.description == "fake:s")
    }

    @Test func fakeTerminalGetsDefaults() async {
        let terminal = FakeTerminal()
        #expect(terminal.requiredPermissions.isEmpty)
        await #expect(throws: AdapterError.notSupported) {
            try await terminal.openTab(argv: ["/usr/bin/true"], cwd: nil, context: makeContext())
        }
        let locator = terminal.capture(env: TerminalHintTests.warpEnv, pid: nil, tty: nil)
        #expect(locator?.fields["focus_url"] == "warp://session/dbb86f5d0ced4332a8feab247a908497")
    }

    @Test func listsLookUpByIDAndEnv() {
        let agents = AgentAdapters([FakeAdapter()])
        #expect(agents.adapter(for: "fake")?.id == "fake")
        #expect(agents.adapter(for: "claude") == nil)
        let terminals = TerminalAdapters([FakeTerminal()])
        #expect(terminals.matching(env: TerminalHintTests.warpEnv)?.id == "warp")
        #expect(terminals.matching(env: ["TERM_PROGRAM": "iTerm.app"]) == nil)
    }

    @Test func defaultsSettingsReturnDeclaredDefault() {
        let settings = DefaultsReadOnlySettings(descriptors: [
            SettingDescriptor(key: "config_dir", label: "Config", kind: .path(default: "~/.claude"))
        ])
        #expect(settings.value("config_dir", as: String.self) == "~/.claude")
        #expect(settings.value("config_dir", as: Int.self) == nil)
        #expect(settings.value("missing", as: String.self) == nil)
    }
}

/// Story 6.5: an adapter's models are priced from the price table section named by `priceProviderID`.
@Suite struct PriceProviderTests {
    struct ResellerAdapter: AgentAdapter {
        let id: AgentID = "reseller"
        var name: LocalizedStringResource { "Reseller" }
        let capabilities: Set<AgentCapability> = []
        var priceProviderID: String { "claude" }
        func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] { [] }
    }

    @Test func defaultsToTheAdapterID() {
        #expect(FakeAdapter().priceProviderID == "fake")
    }

    @Test func anAdapterCanNameAnotherProvidersSection() {
        #expect(ResellerAdapter().priceProviderID == "claude")
    }
}
