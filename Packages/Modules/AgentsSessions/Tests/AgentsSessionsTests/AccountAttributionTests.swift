import AgentKit
import Foundation
import ModuleKit
import Testing

@testable import AgentsSessions

/// The fake adapter with Accounts the way Claude Code has them: `FAKE_CONFIG_DIR`, else `~/.fake`.
private struct AccountAdapter: AgentAdapter {
    let base = FakeAdapter()
    let home: URL
    var id: AgentID { base.id }
    var name: LocalizedStringResource { base.name }
    var capabilities: Set<AgentCapability> { base.capabilities }
    func detectVersion(context: any AdapterContext) async -> AgentVersion? { base.supportState.version }
    func support(for version: AgentVersion?) -> AdapterSupport { base.supportState }
    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] { base.normalize(hook, sentAt: sentAt) }
    var defaultAccountLocation: AccountLocation? { .configDirectory(home.appendingPathComponent(".fake").path) }
    func accountLocationHint(env: [String: String]) -> AccountLocation? {
        env["FAKE_CONFIG_DIR"].map(AccountLocation.configDirectory) ?? defaultAccountLocation
    }
}

private struct AccountSettings: ReadOnlySettings {
    let values: [String: any SettingValue]
    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? { values[key] as? T }
}

@MainActor @Suite struct AccountAttributionTests {
    let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    func makeModule() -> AgentsSessionsModule {
        let settings = AccountSettings(values: [
            "accounts": ["work"], "account.work.label": "Work", "account.work.location": "~/.fake-work",
        ])
        let context = AdapterContextBox(
            settings: settings, secrets: NoSecrets(), executables: NoExecutables(), http: URLSessionHTTPClient(),
            log: .init(subsystem: "test", category: "accounts"))
        return AgentsSessionsModule(
            adapters: AgentAdapters([AccountAdapter(home: home)]), terminals: TerminalAdapters([]),
            contexts: ["fake": context], liveness: FakeLiveness(), homeDirectory: home)
    }

    func run(_ messages: [EventMessage]) async throws -> AgentsSessionsModule {
        let module = makeModule()
        let context = FakeModuleContext()
        try await module.start(context: context)
        for message in messages { context.fakeEvents.send(message) }
        context.fakeEvents.finish()
        await module.eventTask?.value
        return module
    }

    func account(_ module: AgentsSessionsModule, _ session: String) -> AccountID? {
        module.store.table[SessionKey(agentID: "fake", sessionID: session)]?.accountID
    }

    @Test func sessionsAreAttributedByTheCapturedConfigLocation() async throws {
        let now = Date()
        let module = try await run([
            try Hook.message("session.start", session: "w", at: now, env: ["FAKE_CONFIG_DIR": "/Users/me/.fake-work/"]),
            try Hook.message("session.start", session: "d", at: now),
            try Hook.message("session.start", session: "x", at: now, env: ["FAKE_CONFIG_DIR": "/elsewhere"]),
            try Hook.message("session.start", session: "t", at: now, env: ["FAKE_CONFIG_DIR": "~/.fake-work"]),
        ])
        #expect(account(module, "w") == "work")
        #expect(account(module, "d") == .default)
        #expect(account(module, "x") == .default)
        #expect(account(module, "t") == "work")
        await module.stop()
    }

    @Test func theAccountIsChosenOnceAtCreation() async throws {
        let now = Date()
        let module = try await run([
            try Hook.message("session.start", session: "w", at: now, env: ["FAKE_CONFIG_DIR": "~/.fake-work"]),
            try Hook.message("prompt.submit", session: "w", at: now.addingTimeInterval(1)),
        ])
        #expect(account(module, "w") == "work")
        await module.stop()
    }

    @Test func theAccountIsPersistedAndOldFilesReadAsDefault() throws {
        var session = Session(
            key: SessionKey(agentID: "fake", sessionID: "w"), status: .idle, statusSince: Date(), lastEventAt: Date())
        session.accountID = "work"
        let data = try FakeStorage.encoder.encode([session])
        #expect(String(decoding: data, as: UTF8.self).contains(#""account":"work""#))
        #expect(try FakeStorage.decoder.decode([Session].self, from: data).first?.accountID == "work")
        let legacy = Data(
            #"[{"key":"fake:a","status":"idle","status_since":"2026-11-08T10:00:00.000Z","last_event_at":"2026-11-08T10:00:00.000Z"}]"#
                .utf8)
        #expect(try FakeStorage.decoder.decode([Session].self, from: legacy).first?.accountID == .default)
    }
}
