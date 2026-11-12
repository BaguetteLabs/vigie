import AgentKit
import CryptoKit
import Foundation
import ModuleKit
import Testing

@testable import AgentsUsage

// MARK: - Fakes (Story 6.5)

/// Serves the price table and its signature by URL; records every request. `offline` throws like a missing
/// network; `hold()` keeps requests waiting until `release()`.
final class PriceHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [URL: Data] = [:]
    private var _requests: [URLRequest] = []
    private var _offline = false
    private var holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var requests: [URLRequest] { lock.withLock { _requests } }
    var count: Int { requests.count }
    var offline: Bool {
        get { lock.withLock { _offline } }
        set { lock.withLock { _offline = newValue } }
    }

    func serve(_ data: Data, at url: URL) { lock.withLock { files[url] = data } }

    func hold() { lock.withLock { holding = true } }

    func release() {
        let resumed = lock.withLock {
            holding = false
            defer { waiters = [] }
            return waiters
        }
        for waiter in resumed { waiter.resume() }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        await withCheckedContinuation { continuation in
            let wait = lock.withLock {
                if holding { waiters.append(continuation) }
                return holding
            }
            if !wait { continuation.resume() }
        }
        let (offline, body) = lock.withLock { (_offline, files[request.url!]) }
        if offline { throw URLError(.notConnectedToInternet) }
        let status = body == nil ? 404 : 200
        return (
            body ?? Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }
}

final class FakeUpdates: UpdatesService, @unchecked Sendable {
    private let lock = NSLock()
    private var _enabled: Bool
    private var _location: PriceTableLocation?
    let checkInterval: Duration = .seconds(24 * 3600)

    init(enabled: Bool = true, location: PriceTableLocation?) {
        _enabled = enabled
        _location = location
    }

    var pricesEnabled: Bool {
        get { lock.withLock { _enabled } }
        set { lock.withLock { _enabled = newValue } }
    }
    var priceTable: PriceTableLocation? { lock.withLock { _location } }
}

/// A throwaway Ed25519 key pair (never a keychain) and the release host serving signed tables.
struct PriceHost {
    let key = Curve25519.Signing.PrivateKey()
    let http = PriceHTTP()
    static let tableURL = URL(string: "https://example.invalid/vigie-releases/releases/latest/download/prices.json")!
    static let signatureURL = URL(
        string: "https://example.invalid/vigie-releases/releases/latest/download/prices.json.sig")!

    var location: PriceTableLocation {
        PriceTableLocation(
            tableURL: Self.tableURL, signatureURL: Self.signatureURL, publicKey: key.publicKey.rawRepresentation)
    }

    /// Publishes `table` signed with `signer` (default: the host's key).
    func publish(_ table: PriceTable, signedWith signer: Curve25519.Signing.PrivateKey? = nil) throws {
        let data = try JSONEncoder().encode(table)
        let signature = try (signer ?? key).signature(for: data).base64EncodedString() + "\n"
        http.serve(data, at: Self.tableURL)
        http.serve(Data(signature.utf8), at: Self.signatureURL)
    }
}

let newModelPrice = ModelPrice(input: 7, output: 35, cacheWrite: 8.75, cacheRead: 0.7)

/// A table of `version` whose `claude` section adds `claude-new-9`, or one with only a `codex` section.
func publishedTable(version: Int, claude: Bool = true) throws -> PriceTable {
    let bundled = try PriceTable.bundled()
    var providers: [String: PriceTable.Provider] = [:]
    if claude {
        var models = try require(bundled.providers["claude"]).models
        models["claude-new-9"] = newModelPrice
        providers["claude"] = PriceTable.Provider(updated: "2026-11-12", models: models)
    } else {
        providers["codex"] = PriceTable.Provider(updated: "2026-11-12", models: ["gpt-9": newModelPrice])
    }
    return PriceTable(version: version, providers: providers)
}

@MainActor
final class PriceHarness {
    let clock = FakeClock(Date(timeIntervalSince1970: 1_793_000_000))
    let sandbox: Sandbox
    let host: PriceHost
    let updates: FakeUpdates
    var module: AgentsUsageModule!
    var context: FakeModuleContext!

    init(enabled: Bool = true, location: Bool = true, sandbox: Sandbox? = nil, host: PriceHost = PriceHost()) throws {
        self.sandbox = try sandbox ?? Sandbox()
        self.host = host
        updates = FakeUpdates(enabled: enabled, location: location ? host.location : nil)
        relaunch()
    }

    /// A new module on the same storage folder (an app relaunch).
    func relaunch(adapters: [any AgentAdapter]? = nil) {
        let clock = clock
        module = AgentsUsageModule(
            adapters: AgentAdapters(adapters ?? [LogAdapter(reader: sandbox.reader)]), now: { clock.now },
            homeDirectory: sandbox.root, priceHTTP: host.http)
        context = FakeModuleContext(directory: sandbox.storage, updates: updates)
    }

    func start() async throws {
        try await module.start(context: context)
        await module.priceStartTask?.value
    }

    var notifier: RecordingNotifier { context.recordingNotifier }
    var estimator: CostEstimator? { module.history?.estimator }
    var storedTable: URL { sandbox.storage.appendingPathComponent("prices.json") }
}

// MARK: - Tests

@MainActor @Suite struct PriceTableUpdateTests {
    @Test func validUpdateIsStoredAndRebuildsTheEstimator() async throws {
        let h = try PriceHarness()
        try h.host.publish(try publishedTable(version: 3))
        try await h.start()
        #expect(h.host.http.count == 2)
        #expect(h.module.priceSource == .updated)
        #expect(h.estimator?.version == 3)
        #expect(h.estimator?.price(for: "claude-new-9-20261112", provider: "claude") == newModelPrice)
        #expect(FileManager.default.fileExists(atPath: h.storedTable.path))
        #expect(FileManager.default.fileExists(atPath: h.storedTable.path + ".sig"))
        #expect(h.notifier.posted.isEmpty)
        #expect(h.module.priceCheck.last == .updated(version: 3))
    }

    @Test func requestsArePlainGetsWithoutCookies() async throws {
        let h = try PriceHarness()
        try h.host.publish(try publishedTable(version: 3))
        try await h.start()
        let requests = h.host.http.requests
        #expect(requests.map(\.url) == [PriceHost.tableURL, PriceHost.signatureURL])
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && !$0.httpShouldHandleCookies && $0.httpBody == nil })
        #expect(requests.allSatisfy { ($0.allHTTPHeaderFields ?? [:]).isEmpty })
    }

    @Test func badSignatureIsRejectedWithOneSetupProblem() async throws {
        let h = try PriceHarness()
        try h.host.publish(try publishedTable(version: 3), signedWith: Curve25519.Signing.PrivateKey())
        try await h.start()
        #expect(h.module.priceCheck.last == .badSignature)
        #expect(h.module.priceSource == .bundled)
        #expect(h.estimator?.version == 2)
        #expect(!FileManager.default.fileExists(atPath: h.storedTable.path))
        await h.module.checkPricesNow()
        #expect(h.host.http.count == 4)
        let problems = h.notifier.posted.filter { $0.kind == AgentsUsageModule.setupProblemKind }
        #expect(problems.count == 1)
        #expect(problems.first?.dedupeKey == AgentsUsageModule.priceDedupeKey)
    }

    @Test func lowerVersionIsADowngradeAndEqualIsUpToDate() async throws {
        let h = try PriceHarness()
        try h.host.publish(try publishedTable(version: 1))
        try await h.start()
        #expect(h.module.priceCheck.last == .downgrade(version: 1))
        #expect(h.estimator?.version == 2)
        #expect(h.notifier.posted.count == 1)
        try h.host.publish(try publishedTable(version: 2))
        await h.module.checkPricesNow()
        #expect(h.module.priceCheck.last == .upToDate)
        #expect(h.module.priceSource == .bundled)
        #expect(h.notifier.posted.count == 1)
        #expect(!FileManager.default.fileExists(atPath: h.storedTable.path))
    }

    @Test func offlineKeepsTheNewestTableOnDisk() async throws {
        let h = try PriceHarness()
        try h.host.publish(try publishedTable(version: 3))
        try await h.start()
        await h.module.stop()
        h.host.http.offline = true
        h.clock.advance(2 * 24 * 3600)
        h.relaunch()
        try await h.start()
        #expect(h.module.priceCheck.last == .unavailable)
        #expect(h.module.priceSource == .updated)
        #expect(h.estimator?.version == 3)
        #expect(h.notifier.posted.isEmpty)
    }

    @Test func pricesOffMakesNoRequestAndUsesTheTableOnDisk() async throws {
        let h = try PriceHarness()
        try h.host.publish(try publishedTable(version: 3))
        try await h.start()
        await h.module.stop()
        let before = h.host.http.count
        h.updates.pricesEnabled = false
        h.clock.advance(2 * 24 * 3600)
        h.relaunch()
        try await h.start()
        #expect(!h.module.canCheckPrices)
        await h.module.checkPricesNow()
        await h.context.fakeScheduler.fire()
        #expect(h.host.http.count == before)
        #expect(h.module.priceSource == .updated)
    }

    @Test func pricesOffFromTheFirstLaunchNeverRequests() async throws {
        let h = try PriceHarness(enabled: false)
        try h.host.publish(try publishedTable(version: 3))
        try await h.start()
        await h.module.checkPricesNow()
        await h.context.fakeScheduler.fire()
        #expect(h.host.http.count == 0)
        #expect(h.module.priceSource == .bundled)
    }

    @Test func noReleaseLocationMakesNoRequest() async throws {
        let h = try PriceHarness(location: false)
        try h.host.publish(try publishedTable(version: 3))
        try await h.start()
        #expect(!h.module.canCheckPrices)
        await h.module.checkPricesNow()
        await h.context.fakeScheduler.fire()
        #expect(h.host.http.count == 0)
        #expect(!h.context.fakeScheduler.intervals.contains(AgentsUsageModule.priceTickInterval))
        #expect(h.module.priceCheckUnavailableText != nil)
    }

    @Test func aProviderSectionMissingFromTheStoredTableFallsBackToTheBundledOne() async throws {
        let h = try PriceHarness()
        try h.host.publish(try publishedTable(version: 3, claude: false))
        try await h.start()
        #expect(h.module.priceSource == .updated)
        let bundled = try PriceTable.bundled()
        #expect(
            h.estimator?.price(for: "claude-opus-5-5", provider: "claude")
                == bundled.providers["claude"]?.models["claude-opus-5-5"])
        #expect(h.estimator?.price(for: "gpt-9", provider: "codex") == newModelPrice)
        #expect(h.estimator?.price(for: "claude-new-9", provider: "claude") == nil)
    }

    @Test func storedTableWithABrokenSignatureIsIgnoredAtLoad() async throws {
        let h = try PriceHarness()
        try h.host.publish(try publishedTable(version: 3))
        try await h.start()
        await h.module.stop()
        try Data("AAAA".utf8).write(to: h.sandbox.storage.appendingPathComponent("prices.json.sig"))
        h.host.http.offline = true
        h.relaunch()
        try await h.start()
        #expect(h.module.priceSource == .bundled)
    }

    @Test func footerReadsBundledThenUpdated() async throws {
        let h = try PriceHarness()
        try await h.start()
        #expect(h.module.pricesLabel == "PRICES 2026-11-08 · BUNDLED")
        #expect(h.module.usageTabSnapshot().prices == "PRICES 2026-11-08 · BUNDLED")
        try h.host.publish(try publishedTable(version: 3))
        await h.module.checkPricesNow()
        #expect(h.module.pricesLabel == "PRICES 2026-11-12 · UPDATED")
        #expect(h.module.usageTabSnapshot().prices == "PRICES 2026-11-12 · UPDATED")
    }

    @Test func checkNowFetchesRightAwayAndNotTwiceWhileRunning() async throws {
        let h = try PriceHarness()
        try h.host.publish(try publishedTable(version: 2))
        try await h.start()
        #expect(h.host.http.count == 2)
        // Inside the interval: the scheduled check does nothing, Check now fetches.
        await h.module.priceTick()
        #expect(h.host.http.count == 2)
        try h.host.publish(try publishedTable(version: 3))
        h.host.http.hold()
        let module = h.module!
        let first = Task { await module.checkPricesNow() }
        await settle { h.host.http.count == 3 }
        #expect(h.module.priceCheck.isRunning)
        #expect(!h.module.canCheckPrices)
        #expect(h.module.priceCheckText == "Checking…")
        await h.module.checkPricesNow()
        #expect(h.host.http.count == 3)
        h.host.http.release()
        await first.value
        #expect(!h.module.priceCheck.isRunning)
        #expect(h.module.priceCheckText == "Updated to version 3")
        #expect(h.estimator?.version == 3)
    }

    @Test func persistedLastCheckPreventsAnEarlyRefetchAfterRelaunch() async throws {
        let h = try PriceHarness()
        try h.host.publish(try publishedTable(version: 2))
        try await h.start()
        #expect(h.host.http.count == 2)
        await h.module.stop()
        h.clock.advance(3600)
        h.relaunch()
        try await h.start()
        await h.context.fakeScheduler.fire()
        #expect(h.host.http.count == 2)
        #expect(h.context.fakeScheduler.intervals.contains(AgentsUsageModule.priceTickInterval))
        h.clock.advance(24 * 3600)
        await h.context.fakeScheduler.fire()
        #expect(h.host.http.count == 4)
    }

    @Test func offlineChecksAreNotRecordedSoTheNextTickRetries() async throws {
        let h = try PriceHarness()
        h.host.http.offline = true
        try await h.start()
        #expect(h.host.http.count == 1)
        h.host.http.offline = false
        try h.host.publish(try publishedTable(version: 3))
        await h.context.fakeScheduler.fire()
        #expect(h.module.priceSource == .updated)
    }

    @Test func catalogStringsResolve() {
        for key in [
            "agentsUsage.prices.bundled", "agentsUsage.prices.updated", "agentsUsage.prices.title",
            "agentsUsage.prices.check", "agentsUsage.prices.help", "agentsUsage.prices.check.notSetUp",
            "agentsUsage.prices.check.off", "agentsUsage.prices.check.running", "agentsUsage.prices.check.updated",
            "agentsUsage.prices.check.upToDate", "agentsUsage.prices.check.unavailable",
            "agentsUsage.prices.check.badSignature", "agentsUsage.prices.check.downgrade",
            "agentsUsage.prices.check.unreadable", "agentsUsage.prices.problem.title",
            "agentsUsage.prices.problem.category", "agentsUsage.prices.problem.signature",
            "agentsUsage.prices.problem.downgrade",
        ] {
            #expect(UsageText.string(key) != key, "\(key)")
        }
    }
}

// MARK: - Schema and provider sections

/// A reseller adapter whose models are sold at Anthropic's prices, and a Gemini adapter with an empty section.
struct SectionAdapter: AgentAdapter {
    var id: AgentID
    var section: String?
    var name: LocalizedStringResource { "Adapter" }
    var capabilities: Set<AgentCapability> { [] }
    var priceProviderID: String { section ?? id.rawValue }
    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] { [] }
}

@Suite struct PriceTableSchemaTests {
    /// The repository root, from this file (`Packages/Modules/AgentsUsage/Tests/AgentsUsageTests/`).
    static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url
    }

    @Test func bundledFileRoundTrips() throws {
        let table = try PriceTable.bundled()
        #expect(table.schema == 2)
        #expect(Set(table.providers.keys) == ["claude", "codex", "gemini"])
        for provider in table.providers.values {
            #expect(provider.currency == "USD" && provider.unit == "per_million_tokens")
            #expect(provider.updated.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil)
        }
        let again = try PriceTable.decode(try JSONEncoder().encode(table))
        #expect(again == table)
    }

    @Test func bundledCopyIsTheRepositoryFile() throws {
        let canonical = Self.repositoryRoot.appendingPathComponent("prices/prices.json")
        let bundled = Self.repositoryRoot.appendingPathComponent(
            "Packages/Modules/AgentsUsage/Sources/AgentsUsage/Resources/prices.json")
        #expect(
            try Data(contentsOf: canonical) == Data(contentsOf: bundled),
            "copy prices/prices.json to AgentsUsage/Resources/prices.json")
    }

    @Test func tiersRoundTripAndAnotherSchemaIsRefused() throws {
        let json = """
            {"schema": 2, "version": 9, "providers": {"gemini": {"currency": "USD", "unit": "per_million_tokens",
            "updated": "2026-11-12", "models": {"gemini-9-pro": {"input": 1.25, "output": 10, "cache_write": 0,
            "cache_read": 0.31, "tiers": [{"above_tokens": 200000, "input": 2.5, "output": 15}]}}}}}
            """
        let table = try PriceTable.decode(Data(json.utf8))
        let price = try require(table.providers["gemini"]?.models["gemini-9-pro"])
        #expect(price.tiers == [PriceTier(aboveTokens: 200_000, input: 2.5, output: 15)])
        #expect(try PriceTable.decode(try JSONEncoder().encode(table)) == table)
        let future = json.replacingOccurrences(of: "\"schema\": 2", with: "\"schema\": 3")
        #expect(throws: PriceTable.DecodeError.unsupportedSchema(3)) { try PriceTable.decode(Data(future.utf8)) }
    }

    @Test func adaptersMapToTheirProviderSections() throws {
        let adapters: [any AgentAdapter] = [
            SectionAdapter(id: "claude"), SectionAdapter(id: "reseller", section: "claude"),
            SectionAdapter(id: "gemini"),
        ]
        let estimator = try CostEstimator.bundled(adapters: adapters)
        #expect(estimator.sections == ["claude": "claude", "reseller": "claude", "gemini": "gemini"])
        let opus = try require(estimator.price(for: "claude-opus-5-5", provider: "claude"))
        #expect(estimator.price(for: "claude-opus-5-5", provider: "reseller") == opus)
        #expect(estimator.price(for: "claude-opus-5-5", provider: "gemini") == nil)
        // An adapter the estimator was not told about uses its own id.
        #expect(estimator.price(for: "claude-opus-5-5", provider: "codex") == nil)
    }

    @Test func aModelWithNoPriceAnywhereStaysUnpriced() throws {
        let estimator = try CostEstimator.bundled()
        #expect(estimator.cost(of: TokenCounts(input: 1_000), model: "mystery-1", provider: "claude") == nil)
        #expect(estimator.cost(of: TokenCounts(input: 1_000), model: "mystery-1", provider: "unknown") == nil)
    }

    @Test func signatureVerification() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = Data("{}".utf8)
        let signature = Data(try key.signature(for: data).base64EncodedString().utf8)
        let publicKey = key.publicKey.rawRepresentation
        #expect(PriceTableUpdater.verify(data, signature: signature, publicKey: publicKey))
        #expect(!PriceTableUpdater.verify(Data("{ }".utf8), signature: signature, publicKey: publicKey))
        #expect(!PriceTableUpdater.verify(data, signature: Data("garbage".utf8), publicKey: publicKey))
        #expect(!PriceTableUpdater.verify(data, signature: signature, publicKey: Data(count: 3)))
    }
}
