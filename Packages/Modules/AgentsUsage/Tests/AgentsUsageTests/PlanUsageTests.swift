import AgentKit
import Foundation
import ModuleKit
import Testing
import os

@testable import AgentsUsage

// MARK: - Fakes

/// Counts requests; answers 200 with an empty body (the fake provider decodes nothing).
final class CountingHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _count += 1 }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ now: Date) { _now = now }
    var now: Date { lock.withLock { _now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now += seconds } }
}

/// Scripted provider: each fetch makes one request through `context.http`, then returns the next result.
final class ScriptedProvider: UsageProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [Result<[UsageWindow], PlanUsageError>]
    let clock: FakeClock
    let credential: ExternalCredentialDescriptor?

    init(_ script: [Result<[UsageWindow], PlanUsageError>], clock: FakeClock, credential: ExternalCredentialDescriptor?)
    {
        self.script = script
        self.clock = clock
        self.credential = credential
    }

    func push(_ result: Result<[UsageWindow], PlanUsageError>) { lock.withLock { script.append(result) } }

    private var _resets: [AccountID] = []
    var resets: [AccountID] { lock.withLock { _resets } }
    func resetExternalCredential(for account: AgentAccount) async { lock.withLock { _resets.append(account.id) } }

    var id: AgentID { "claude" }
    var name: LocalizedStringResource { "Claude" }
    var refreshInterval: Duration { .seconds(300) }
    var externalCredential: ExternalCredentialDescriptor? { credential }

    func fetch(context: any AdapterContext) async throws -> UsageSnapshot {
        _ = try await context.http.data(for: URLRequest(url: URL(string: "https://example.invalid/usage")!))
        let next = lock.withLock { script.isEmpty ? Result.failure(.unavailable(status: nil)) : script.removeFirst() }
        return UsageSnapshot(windows: try next.get(), fetchedAt: clock.now)
    }
}

struct PlanAdapter: AgentAdapter {
    let provider: ScriptedProvider
    var id: AgentID { "claude" }
    var name: LocalizedStringResource { "Claude Code" }
    var capabilities: Set<AgentCapability> { [.usage] }
    var settings: [SettingDescriptor] {
        [
            SettingDescriptor(key: "usage_providers", label: "Sources", kind: .list(of: .string, default: ["local"])),
            SettingDescriptor(
                key: "plan_auth", label: "Auth",
                kind: .enumeration(options: ["token", "claude_code"], default: "token"),
                scope: .local),
            SettingDescriptor(key: "plan_token", label: "Token", kind: .secret, scope: .local),
        ]
    }
    var usageProvider: (any UsageProvider)? { provider }
    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] { [] }
}

/// Adapter settings in memory, with working observers.
final class MemoryAdapterSettings: AdapterSettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: any SettingValue]
    private var continuations: [String: [AsyncStream<Void>.Continuation]] = [:]
    private(set) var writes: [String] = []

    init(_ values: [String: any SettingValue] = [:]) { self.values = values }

    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? { lock.withLock { values[key] as? T } }

    func set<T: SettingValue>(_ value: T?, for key: String) async throws {
        let observers = lock.withLock {
            values[key] = value
            writes.append(key)
            return continuations[key] ?? []
        }
        for continuation in observers { continuation.yield() }
    }

    func observe(_ key: String) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        lock.withLock { continuations[key, default: []].append(continuation) }
        return stream
    }
}

/// Adapter-scoped secrets with a consent flag; never holds the external value.
final class ConsentSecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var consent = false
    private var token: String?
    private(set) var revokes = 0

    func read(_ key: String) async throws -> String? { lock.withLock { token } }
    func write(_ value: String?, for key: String) async throws { lock.withLock { token = value } }
    func contains(_ key: String) async throws -> Bool { lock.withLock { token != nil } }
    func hasConsent(for descriptor: ExternalCredentialDescriptor) async -> Bool { lock.withLock { consent } }
    func grantConsent(for descriptor: ExternalCredentialDescriptor) async throws { lock.withLock { consent = true } }
    func revokeConsent(for descriptor: ExternalCredentialDescriptor) async throws {
        lock.withLock {
            consent = false
            revokes += 1
        }
    }
}

let externalLogin = ExternalCredentialDescriptor(
    id: "claude.claude_code_login", displayName: "Claude Code", service: "Claude Code-credentials",
    explanation: "Reads Claude Code's login.")

let fiveHour = UsageWindow(name: "5h", used: 37, limit: nil, resetsAt: Date(timeIntervalSince1970: 1_800_000_000))
let weekly = UsageWindow(name: "weekly", used: 12, limit: nil, resetsAt: Date(timeIntervalSince1970: 1_800_400_000))

@MainActor
struct PlanHarness {
    let clock = FakeClock(Date(timeIntervalSince1970: 1_793_000_000))
    let http = CountingHTTP()
    let secrets = ConsentSecrets()
    let store: MemoryAdapterSettings
    let provider: ScriptedProvider
    let module: AgentsUsageModule
    let sandbox: Sandbox
    let context: FakeModuleContext

    init(plan: Bool, auth: String = "token", script: [Result<[UsageWindow], PlanUsageError>] = []) throws {
        store = MemoryAdapterSettings([
            "usage_providers": plan ? ["local", "plan"] : ["local"], "plan_auth": auth,
        ])
        provider = ScriptedProvider(script, clock: clock, credential: externalLogin)
        let adapter = PlanAdapter(provider: provider)
        let adapterContext = AdapterContextBox(
            settings: ReadOnlyAdapterSettings(store), secrets: secrets, executables: NoExecutables(), http: http,
            log: Logger(subsystem: "test", category: "claude"))
        let clock = clock
        module = AgentsUsageModule(
            adapters: AgentAdapters([adapter]), contexts: ["claude": adapterContext],
            adapterSettingsStores: ["claude": store], now: { clock.now })
        sandbox = try Sandbox()
        context = FakeModuleContext(directory: sandbox.storage)
    }

    func start() async throws {
        try await module.start(context: context)
        await module.waitForInitialPlanRefresh()
    }

    var notifier: RecordingNotifier { context.recordingNotifier }
}

/// Lets observer tasks run.
func settle() async {
    // Generous: an ingest pass also schedules the Usage tab overview reload (Story 7.8) on the main actor.
    for _ in 0..<200 { await Task.yield() }
}

// MARK: - Tests

@MainActor @Suite struct PlanUsageTests {
    @Test func noPlanMeansNoNetworkAtAll() async throws {
        let harness = try PlanHarness(plan: false, script: [.success([fiveHour])])
        try await harness.start()
        await harness.context.fakeScheduler.fire()
        await harness.module.expandedViewDidAppear()
        await harness.module.refreshPlans()
        #expect(harness.http.count == 0)
        #expect(harness.module.planState(for: "claude") == nil)
        #expect(harness.context.fakeScheduler.intervals.contains(.seconds(300)))
        #expect(harness.notifier.posted.isEmpty)
        await harness.module.stop()
    }

    @Test func planFetchesAtStartAndMergesIntoTheClaudeSeries() async throws {
        let harness = try PlanHarness(plan: true, script: [.success([fiveHour, weekly])])
        try await harness.start()
        #expect(harness.http.count == 1)
        let state = try #require(harness.module.planState(for: "claude"))
        #expect(state.windows == [fiveHour, weekly])
        #expect(state.fetchedAt == harness.clock.now && !state.isStale && state.lastError == nil)
        let series = try await harness.module.usage(
            since: Date(timeIntervalSince1970: 0), until: Date(timeIntervalSince1970: 4_000_000_000), bucket: .day,
            provider: "claude")
        #expect(series?.windows == [fiveHour, weekly])
        #expect(series?.provider == "claude")
        await harness.module.stop()
    }

    @Test func failureKeepsLastValuesStaleAndAlertsOnceUntilSuccess() async throws {
        let harness = try PlanHarness(
            plan: true,
            script: [
                .success([fiveHour]), .failure(.formatChanged), .failure(.unavailable(status: 503)),
                .success([weekly]),
            ])
        try await harness.start()
        let goodAt = harness.clock.now
        harness.clock.advance(300)
        await harness.context.fakeScheduler.fire()
        var state = try #require(harness.module.planState(for: "claude"))
        #expect(state.windows == [fiveHour] && state.fetchedAt == goodAt)
        #expect(state.isStale && state.lastError == .formatChanged)
        #expect(state.staleLabel == "STALE · \(PlanState.timeText(goodAt))")
        #expect(harness.notifier.posted.count == 1)

        harness.clock.advance(300)
        await harness.context.fakeScheduler.fire()
        state = try #require(harness.module.planState(for: "claude"))
        #expect(
            state.windows == [fiveHour] && state.fetchedAt == goodAt && state.lastError == .unavailable(status: 503))
        #expect(harness.notifier.posted.count == 1)  // once
        let event = try #require(harness.notifier.posted.first)
        #expect(event.kind == "setup.problem" && event.dedupeKey == "plan:claude")
        #expect(event.title == "Claude plan usage unavailable")
        #expect(event.action == .openSettings(pane: "agents.usage"))
        #expect(harness.notifier.resolved == 0)

        harness.clock.advance(300)
        await harness.context.fakeScheduler.fire()
        state = try #require(harness.module.planState(for: "claude"))
        #expect(state.windows == [weekly] && !state.isStale && state.fetchedAt == harness.clock.now)
        #expect(harness.notifier.resolved == 1)
        #expect(harness.http.count == 4)
        await harness.module.stop()
    }

    @Test func problemBodiesPerError() {
        let provider = ScriptedProvider([], clock: FakeClock(Date()), credential: externalLogin)
        func body(_ error: PlanUsageError) -> String? {
            AgentsUsageModule.planProblemEvent("claude", provider: provider, error: error).body
        }
        #expect(body(.credentialExpired) == "Sign in to Claude Code again, or paste a token.")
        #expect(body(.unauthorized) == body(.credentialExpired))
        #expect(body(.credentialDenied)?.contains("Keychain prompt") == true)
        #expect(body(.formatChanged)?.contains("changed") == true)
        #expect(body(.unavailable(status: nil))?.contains("could not reach") == true)
        let tokenOnly = ScriptedProvider([], clock: FakeClock(Date()), credential: nil)
        #expect(
            AgentsUsageModule.planProblemEvent("claude", provider: tokenOnly, error: .unauthorized).body
                == "Paste a new token in Settings › Usage.")
    }

    @Test func expiredClaudeCodeLoginAlertsButUnfinishedSetupDoesNot() async throws {
        let consent = try PlanHarness(plan: true, auth: "claude_code", script: [.failure(.consentRequired)])
        try await consent.start()
        #expect(consent.notifier.posted.isEmpty)
        #expect(consent.module.planState(for: "claude")?.lastError == .consentRequired)
        await consent.module.stop()

        let noToken = try PlanHarness(plan: true, auth: "token", script: [.failure(.credentialMissing)])
        try await noToken.start()
        #expect(noToken.notifier.posted.isEmpty)
        await noToken.module.stop()

        let expired = try PlanHarness(plan: true, auth: "claude_code", script: [.failure(.credentialExpired)])
        try await expired.start()
        #expect(expired.notifier.posted.map(\.body) == ["Sign in to Claude Code again, or paste a token."])
        await expired.module.stop()
    }

    @Test func aRefusedKeychainPromptRaisesOneSetupProblem() async throws {
        let harness = try PlanHarness(
            plan: true, auth: "claude_code", script: Array(repeating: .failure(.credentialDenied), count: 4))
        try await harness.start()
        for _ in 0..<3 {
            harness.clock.advance(300)
            await harness.context.fakeScheduler.fire()
        }
        let denied =
            "Vigie was not allowed to read the Claude Code login. Allow it in the Keychain prompt or paste a token."
        #expect(harness.notifier.posted.map(\.body) == [denied])
        #expect(harness.notifier.posted.first?.dedupeKey == "plan:claude")
        let state = try #require(harness.module.planState(for: "claude"))
        #expect(state.lastError == .credentialDenied)
        #expect(PlanSettingsText.status(state) == denied)
        #expect(PlanSettingsText.errorText(.credentialDenied) == denied)
        await harness.module.stop()
    }

    @Test func grantingAndRevokingConsentResetTheProvidersHeldCredential() async throws {
        let harness = try PlanHarness(
            plan: true, auth: "claude_code", script: [.failure(.credentialDenied), .success([fiveHour])])
        try await harness.start()
        #expect(harness.provider.resets.isEmpty)
        try await harness.module.grantPlanConsent(for: "claude")
        #expect(harness.provider.resets == [.default])
        #expect(harness.module.planState(for: "claude")?.windows == [fiveHour])
        try await harness.module.revokePlanConsent(for: "claude")
        #expect(harness.provider.resets == [.default, .default])
        await harness.module.stop()
    }

    @Test func refreshCadenceWithAFakeClock() async throws {
        let harness = try PlanHarness(plan: true, script: Array(repeating: .success([fiveHour]), count: 5))
        try await harness.start()
        #expect(harness.http.count == 1)
        #expect(harness.context.fakeScheduler.intervals.contains(.seconds(300)))
        // Opening the expanded view right after a fetch does not refetch.
        harness.clock.advance(30)
        await harness.module.expandedViewDidAppear()
        #expect(harness.http.count == 1)
        // A minute later it does.
        harness.clock.advance(31)
        await harness.module.expandedViewDidAppear()
        #expect(harness.http.count == 2)
        // The 5-minute job always does.
        await harness.context.fakeScheduler.fire()
        #expect(harness.http.count == 3)
        await harness.module.stop()
    }

    @Test func toggleWritesUsageProvidersAndRefreshesOrDrops() async throws {
        let harness = try PlanHarness(plan: false, script: [.success([fiveHour])])
        try await harness.start()
        #expect(harness.http.count == 0)
        try await harness.module.setPlanEnabled(true, for: "claude")
        #expect(harness.store.value("usage_providers", as: [String].self) == ["local", "plan"])
        await settle()
        #expect(harness.http.count == 1)
        #expect(harness.module.planState(for: "claude")?.windows == [fiveHour])

        try await harness.module.setPlanEnabled(false, for: "claude")
        #expect(harness.store.value("usage_providers", as: [String].self) == ["local"])
        await settle()
        #expect(harness.module.planState(for: "claude") == nil)
        #expect(harness.http.count == 1)

        try await harness.module.setPlanAuth("claude_code", for: "claude")
        #expect(harness.store.value("plan_auth", as: String.self) == "claude_code")
        await harness.module.stop()
    }

    @Test func consentGrantAndRevokeGoThroughTheAdapterSecrets() async throws {
        let harness = try PlanHarness(
            plan: true, auth: "claude_code", script: [.failure(.consentRequired), .success([fiveHour])])
        try await harness.start()
        #expect(await harness.module.hasPlanConsent(for: "claude") == false)
        try await harness.module.grantPlanConsent(for: "claude")
        #expect(await harness.module.hasPlanConsent(for: "claude"))
        #expect(harness.module.planState(for: "claude")?.windows == [fiveHour])

        try await harness.module.revokePlanConsent(for: "claude")
        #expect(await harness.module.hasPlanConsent(for: "claude") == false)
        #expect(harness.secrets.revokes == 1)
        #expect(harness.module.planState(for: "claude") == nil)
        await harness.module.stop()
    }

    @Test func settingsViewOnlyForProvidersWithAUsageProvider() async throws {
        let harness = try PlanHarness(plan: false)
        #expect(harness.module.settingsView() != nil)
        let logsOnly = AgentsUsageModule(adapters: AgentAdapters([LogAdapter(reader: nil)]))
        #expect(logsOnly.settingsView() == nil)
    }

    @Test func catalogStringsResolve() {
        for key in [
            "agentsUsage.plan.problem.title", "agentsUsage.plan.settings.title", "agentsUsage.plan.stale",
            "agentsUsage.plan.settings.allow", "agentsUsage.plan.settings.stop",
            "agentsUsage.plan.settings.keychainItem", "agentsUsage.plan.error.denied",
        ] {
            #expect(UsageText.string(key) != key)
        }
        #expect(PlanSettingsText.keychainItem(externalLogin).contains("Claude Code-credentials"))
        #expect(PlanSettingsText.authOption("claude_code", credential: externalLogin) == "Use Claude Code's login")
        #expect(PlanSettingsText.authOption("token", credential: externalLogin) == "Paste a token")
        #expect(PlanSettingsText.status(nil) == "Not fetched yet.")
    }
}
