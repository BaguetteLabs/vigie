import AgentKit
import AppKit
import Foundation
import GRDB
@_spi(Host) import ModuleKit
import SwiftUI
import Testing
import VigieUI
import os

@testable import AgentsUsage

/// A provider answering per Account: windows or a failure from `results`, keyed by Account id.
final class AccountProvider: UsageProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [AccountID: Result<[UsageWindow], PlanUsageError>]
    private var _fetched: [AccountID] = []
    let clock: FakeClock

    init(_ results: [AccountID: Result<[UsageWindow], PlanUsageError>], clock: FakeClock) {
        self.results = results
        self.clock = clock
    }

    var fetched: [AccountID] { lock.withLock { _fetched } }
    func set(_ account: AccountID, _ result: Result<[UsageWindow], PlanUsageError>) {
        lock.withLock { results[account] = result }
    }

    var id: AgentID { "claude" }
    var name: LocalizedStringResource { "Claude" }
    var refreshInterval: Duration { .seconds(300) }
    var externalCredential: ExternalCredentialDescriptor? { externalLogin }

    func fetch(context: any AdapterContext) async throws -> UsageSnapshot {
        try await fetch(context: context, account: AgentAccount(id: .default, label: "", location: nil))
    }

    func fetch(context: any AdapterContext, account: AgentAccount) async throws -> UsageSnapshot {
        let result = lock.withLock {
            _fetched.append(account.id)
            return results[account.id] ?? .failure(.unavailable(status: nil))
        }
        return UsageSnapshot(windows: try result.get(), fetchedAt: clock.now)
    }

    func externalCredential(for account: AgentAccount) -> ExternalCredentialDescriptor? {
        ExternalCredentialDescriptor(
            id: account.credentialID(externalLogin.id), displayName: "Claude Code", service: "s",
            explanation: "x")
    }
}

/// An adapter with Accounts (default `~/.claude`) and a log reader per location.
struct AccountAdapter: AgentAdapter {
    let provider: AccountProvider?
    var readers: [String: FixtureLogReader] = [:]
    var id: AgentID { "claude" }
    var name: LocalizedStringResource { "Claude Code" }
    var capabilities: Set<AgentCapability> { [.usage, .logReader] }
    var settings: [SettingDescriptor] {
        PlanAdapter(provider: ScriptedProvider([], clock: FakeClock(.now), credential: nil)).settings
    }
    var usageProvider: (any UsageProvider)? { provider }
    var defaultAccountLocation: AccountLocation? { .configDirectory("/Users/me/.claude") }
    var logReader: (any AgentLogReader)? { readers["/Users/me/.claude"] }
    func logReader(for location: AccountLocation) -> (any AgentLogReader)? { readers[location.path] }
    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] { [] }
}

@MainActor @Suite struct AccountUsageTests {
    static let start = Date(timeIntervalSince1970: 1_794_149_280)

    static func window(_ name: String, used: Double, resetIn: TimeInterval) -> UsageWindow {
        UsageWindow(name: name, used: used, limit: nil, resetsAt: start + resetIn)
    }

    static let twoAccounts: [String: any SettingValue] = [
        "usage_providers": ["local", "plan"], "plan_auth": "token", "accounts": ["work"],
        "account.work.label": "Work", "account.work.location": "~/.claude-work",
        "account.work.usage_providers": ["local", "plan"],
    ]

    @MainActor struct Harness {
        let clock = FakeClock(AccountUsageTests.start)
        let notifier = RecordingNotifier()
        let store: MemoryAdapterSettings
        let provider: AccountProvider
        let module: AgentsUsageModule

        init(_ values: [String: any SettingValue], results: [AccountID: Result<[UsageWindow], PlanUsageError>]) {
            store = MemoryAdapterSettings(values)
            provider = AccountProvider(results, clock: clock)
            let context = AdapterContextBox(
                settings: ReadOnlyAdapterSettings(store), secrets: ConsentSecrets(), executables: NoExecutables(),
                http: CountingHTTP(), log: Logger(subsystem: "test", category: "claude"))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let clock = clock
            module = AgentsUsageModule(
                adapters: AgentAdapters([AccountAdapter(provider: provider)]), contexts: ["claude": context],
                adapterSettingsStores: ["claude": store], calendar: calendar, now: { clock.now },
                homeDirectory: URL(fileURLWithPath: "/Users/me"))
            module.notifier = notifier
        }
    }

    // MARK: Store

    @Test func migrationFromV1KeepsTheHistoryAsTheDefaultAccount() async throws {
        let sandbox = try Sandbox()
        try FileManager.default.createDirectory(at: sandbox.storage, withIntermediateDirectories: true)
        let url = sandbox.storage.appendingPathComponent(UsageStore.fileName)
        do {
            let pool = try DatabasePool(path: url.path)
            try UsageStore.migrator.migrate(pool, upTo: "v1")
            try await pool.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO ingest_files (path, provider, read_offset, size, mtime) VALUES ('/a.jsonl', 'claude', 10, 10, 1);
                        INSERT INTO usage_records (id, at, provider, model, project, session_id, message_id, request_id,
                            input, output, cache_create, cache_read)
                        VALUES ('claude/s1/m1', 1794100000, 'claude', 'claude-opus-5-5', '/w/vigie', 's1', 'm1', NULL, 1, 2, 3, 4);
                        """)
            }
        }
        let store = try UsageStore(directory: sandbox.storage)
        #expect(try await store.recordCount() == 1)
        #expect(try await store.recordCount(provider: "claude", account: .default) == 1)
        #expect(try await store.recordCount(provider: "claude", account: "work") == 0)
        #expect(try await store.fileStates(provider: "claude")["/a.jsonl"]?.offset == 10)
        #expect(try await store.latestAccounts() == ["claude": .default])
        // A re-read of the same response by the default Account keeps one row (v1 ids).
        let record = UsageRecord(
            at: Date(timeIntervalSince1970: 1_794_100_000), model: "claude-opus-5-5", project: "/w/vigie",
            sessionID: "s1", messageID: "m1", requestID: nil, inputTokens: 5, outputTokens: 2, cacheCreationTokens: 3,
            cacheReadTokens: 4)
        try await store.commit(
            provider: "claude", path: "/a.jsonl", state: IngestFileState(offset: 20, size: 20, mtime: 2),
            records: [record])
        #expect(try await store.recordCount() == 1)
    }

    @Test func eachAccountRootIsIngestedSeparately() async throws {
        let sandbox = try Sandbox()
        let workRoot = sandbox.root.appendingPathComponent("home/.claude-work/projects", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sandbox.projects, to: workRoot)
        let store = try UsageStore(directory: sandbox.storage)
        let registry = UsageProviderRegistry(sources: [
            UsageSource(id: "claude", reader: sandbox.reader),
            UsageSource(id: "claude", account: "work", reader: FixtureLogReader(root: workRoot)),
        ])
        let ingestor = UsageIngestor(store: store, registry: registry, log: Logger(subsystem: "test", category: "u"))
        let report = await ingestor.ingest()
        let total = try await store.recordCount()
        let personal = try await store.recordCount(provider: "claude", account: .default)
        let work = try await store.recordCount(provider: "claude", account: "work")
        #expect(personal > 0 && personal == work && total == personal + work)
        // Streaming repeats count per write; each Account read its own files.
        #expect(report.records >= total && report.files == 2 * (report.files / 2))
        // A second pass adds nothing.
        #expect(await ingestor.ingest().changedFiles == 0)
        let history = UsageHistory(store: store, estimator: try CostEstimator.bundled())
        let series = try await history.usage(
            since: .distantPast, until: .distantFuture.addingTimeInterval(-1), bucket: .day, provider: "claude",
            account: "work")
        #expect(series.total.records == work)
        #expect(Set(series.byAccount.keys) == ["claude.work"])
    }

    @Test func registryBuildsOneSourcePerAccountWithLocal() {
        let personal = FixtureLogReader(root: URL(fileURLWithPath: "/p"))
        let work = FixtureLogReader(root: URL(fileURLWithPath: "/w"))
        let adapter = AccountAdapter(
            provider: nil, readers: ["/Users/me/.claude": personal, "~/.claude-work": work])
        var values = Self.twoAccounts
        let registry = UsageProviderRegistry(adapters: AgentAdapters([adapter])) { _ in FixedSettings(values: values) }
        #expect(registry.sources.map(\.account) == [.default, "work"])
        values["account.work.usage_providers"] = ["plan"]
        let without = UsageProviderRegistry(adapters: AgentAdapters([adapter])) { _ in FixedSettings(values: values) }
        #expect(without.sources.map(\.account) == [.default])
        #expect(without.ids == ["claude"])
    }

    // MARK: Upgrade

    @Test func aPreStorySetupIsTheDefaultAccountWithItsPlanSettings() async {
        let harness = Harness(
            ["usage_providers": ["local", "plan"], "plan_auth": "claude_code"],
            results: [.default: .success([Self.window("5h", used: 30, resetIn: 3600)])])
        let module = harness.module
        #expect(module.accounts(of: "claude").map(\.id) == [.default])
        #expect(!module.hasSeveralAccounts("claude"))
        #expect(module.isPlanEnabled("claude"))
        await module.refreshPlans()
        #expect(harness.provider.fetched == [.default])
        #expect(module.planState(for: "claude")?.windows.count == 1)
        // Labels stay as before 7.10.
        #expect(module.quotaRings.first?.model.nameLabel == "CLAUDE")
        #expect(module.usageTabSnapshot().providers.map(\.title) == ["Claude Code"])
        #expect(module.usageTabSnapshot().providers.map(\.id) == ["claude"])
    }

    // MARK: Plan per Account

    @Test func plansRefreshPerAccountAndGoStaleAlone() async throws {
        let harness = Harness(
            Self.twoAccounts,
            results: [
                .default: .success([Self.window("5h", used: 30, resetIn: 3600)]),
                "work": .success([Self.window("5h", used: 40, resetIn: 3600)]),
            ])
        let module = harness.module
        await module.refreshPlans()
        #expect(Set(harness.provider.fetched) == [.default, "work"])
        #expect(module.planState(for: "claude.work")?.windows.first?.used == 40)
        harness.provider.set("work", .failure(.unavailable(status: 503)))
        harness.clock.advance(60)
        await module.refreshPlans()
        #expect(module.planState(for: "claude.work")?.isStale == true)
        #expect(module.planState(for: "claude")?.isStale == false)
        let cards = module.usageTabSnapshot().providers
        #expect(cards.map(\.id) == ["claude", "claude.work"])
        #expect(cards.map(\.title) == ["Claude · Default", "Claude · Work"])
        #expect(cards[0].meta.stale == nil)
        #expect(cards[1].meta.stale?.hasPrefix("STALE · ") == true)
        // One setup problem for the failing Account only.
        let problems = harness.notifier.posted.filter { $0.kind == "setup.problem" }
        #expect(problems.map(\.dedupeKey) == ["plan:claude.work"])
        #expect(problems.first?.title == "Claude · Work plan usage unavailable")
        // Turning plan off for one Account drops only its state.
        try await harness.store.set(["local"], for: "account.work.usage_providers")
        await module.refreshPlans()
        #expect(module.planState(for: "claude.work") == nil)
        #expect(module.planState(for: "claude") != nil)
    }

    @Test func quotaWarningsAreDedupedPerAccountAndTitledWithIt() {
        let harness = Harness(Self.twoAccounts, results: [:])
        let module = harness.module
        module.planStates["claude"] = PlanState(windows: [Self.window("5h", used: 82, resetIn: 3600)])
        module.planStates["claude.work"] = PlanState(windows: [Self.window("5h", used: 82, resetIn: 3600)])
        let warnings = harness.notifier.posted.filter { $0.kind == "usage.quota_warning" }
        #expect(warnings.count == 2)
        #expect(Set(warnings.map(\.title)) == ["CLAUDE · DEFAULT · 5H 82 %", "CLAUDE · WORK · 5H 82 %"])
        #expect(warnings.map(\.dedupeKey).contains { $0?.hasPrefix("quota:claude.work:5h:") == true })
        #expect(warnings.map(\.dedupeKey).contains { $0?.hasPrefix("quota:claude:5h:") == true })
        // Re-evaluating posts nothing new.
        module.evaluateQuotaWarnings()
        #expect(harness.notifier.posted.filter { $0.kind == "usage.quota_warning" }.count == 2)
    }

    @Test func aSingleAccountKeepsThe76Title() {
        let harness = Harness(["usage_providers": ["local", "plan"]], results: [:])
        harness.module.planStates["claude"] = PlanState(windows: [Self.window("5h", used: 82, resetIn: 3600)])
        let warning = harness.notifier.posted.first { $0.kind == "usage.quota_warning" }
        #expect(warning?.title == "CLAUDE · 5H 82 %")
        #expect(warning?.dedupeKey?.hasPrefix("quota:claude:5h:") == true)
    }

    // MARK: Ring

    @Test func theRingShowsTheMostRecentAccountLabeled() {
        let harness = Harness(Self.twoAccounts, results: [:])
        let module = harness.module
        module.planStates["claude"] = PlanState(windows: [Self.window("5h", used: 30, resetIn: 3600)])
        module.planStates["claude.work"] = PlanState(windows: [Self.window("5h", used: 82, resetIn: 3600)])
        #expect(module.quotaRings.count == 1)
        #expect(module.quotaRings.first?.account == .default)
        module.recentAccounts = ["claude": "work"]
        let ring = module.quotaRings.first
        #expect(ring?.account == "work")
        #expect(ring?.model.nameLabel == "CLAUDE · WORK")
        #expect(ring?.model.valueText == "82")
        // The most recent Account without windows falls back to one with windows.
        module.planStates["claude.work"] = nil
        #expect(module.quotaRings.first?.account == .default)
        // Cut to six characters on the wing (UX-DR99).
        #expect(module.quotaRings.first?.model.nameLabel == "CLAUDE · DEFAUL")
    }

    @Test func recentAccountsComeFromTheLatestRecord() async throws {
        let sandbox = try Sandbox()
        let store = try UsageStore(directory: sandbox.storage)
        func record(_ id: String, at: TimeInterval) -> UsageRecord {
            UsageRecord(
                at: Date(timeIntervalSince1970: at), model: "m", project: "p", sessionID: id, messageID: id,
                requestID: nil, inputTokens: 1, outputTokens: 1, cacheCreationTokens: 0, cacheReadTokens: 0)
        }
        let state = IngestFileState(offset: 1, size: 1, mtime: 1)
        try await store.commit(provider: "claude", path: "/a", state: state, records: [record("a", at: 100)])
        try await store.commit(
            provider: "claude", account: "work", path: "/b", state: state, records: [record("b", at: 200)])
        #expect(try await store.latestAccounts() == ["claude": "work"])
        try await store.commit(provider: "claude", path: "/c", state: state, records: [record("c", at: 300)])
        #expect(try await store.latestAccounts() == ["claude": .default])
    }

    // MARK: Settings

    @Test func addingAndRemovingAnAccountWritesLocalKeys() async throws {
        let harness = Harness(["usage_providers": ["local"]], results: [:])
        let module = harness.module
        let id = try await module.addAccount(label: " Work ", location: "~/.claude-work/", to: "claude")
        #expect(id == "work")
        #expect(harness.store.value("accounts", as: [String].self) == ["work"])
        #expect(harness.store.value("account.work.label", as: String.self) == "Work")
        #expect(harness.store.value("account.work.location", as: String.self) == "~/.claude-work/")
        #expect(module.accounts(of: "claude").map(\.id) == [.default, "work"])
        await #expect(throws: AccountSettingsError.duplicateLocation) {
            try await module.addAccount(label: "Again", location: "/Users/me/.claude-work", to: "claude")
        }
        await #expect(throws: AccountSettingsError.duplicateLocation) {
            try await module.addAccount(label: "Home", location: "~/.claude", to: "claude")
        }
        try await module.setPlanEnabled(true, for: "claude.work")
        #expect(harness.store.value("account.work.usage_providers", as: [String].self) == ["local", "plan"])
        #expect(harness.store.value("usage_providers", as: [String].self) == ["local"])
        try await module.removeAccount("work", from: "claude")
        #expect(harness.store.value("accounts", as: [String].self) == [])
        #expect(harness.store.value("account.work.location", as: String.self) == nil)
        #expect(module.accounts(of: "claude").map(\.id) == [.default])
        await #expect(throws: AccountSettingsError.notAvailable) {
            try await module.removeAccount(.default, from: "claude")
        }
    }

    @Test func rendersTheSettingsBlockWithTwoAccounts() throws {
        let harness = Harness(Self.twoAccounts, results: [:])
        let view = Form {
            UsageSettingsView(module: harness.module, planAdapters: ["claude"])
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 900)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 560, height: 900)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let dir = "/private/tmp/claude-501/-Users-me-www-vigie/03a97dc6-097f-4d60-a649-a2f93afa8536/scratchpad/s7.10"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("usage-settings-accounts.png"))
    }

    @Test func catalogHasTheAccountStrings() {
        for key in [
            "agentsUsage.account.default", "agentsUsage.account.join", "agentsUsage.accounts.title",
            "agentsUsage.accounts.add", "agentsUsage.accounts.remove", "agentsUsage.accounts.defaultBadge",
            "agentsUsage.accounts.help", "agentsUsage.accounts.error.duplicate", "agentsUsage.accounts.add.label",
            "agentsUsage.accounts.add.location",
        ] {
            #expect(UsageText.string(key) != key, "\(key)")
        }
    }
}
