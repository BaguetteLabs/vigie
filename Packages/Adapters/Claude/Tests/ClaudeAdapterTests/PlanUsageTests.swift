import AgentKit
import Foundation
import Testing
import os

@testable import ClaudeAdapter

// MARK: - Fakes

/// Returns one canned response and records each request.
final class CannedHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    let result: Result<(Data, Int), URLError>

    init(_ result: Result<(Data, Int), URLError>) { self.result = result }
    convenience init(fixture: String, status: Int = 200) {
        self.init(.success((PlanFixtures.data(fixture), status)))
    }

    var requests: [URLRequest] { lock.withLock { _requests } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        let (data, status) = try result.get()
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

/// A secret store with a pasted token and an external item behind a consent flag.
final class PlanSecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    var token: String?
    var external: String?
    var consent: Bool
    private var _externalReads: [ExternalCredentialDescriptor] = []
    private var _writes = 0

    init(token: String? = nil, external: String? = nil, consent: Bool = false) {
        self.token = token
        self.external = external
        self.consent = consent
    }

    var externalReads: [ExternalCredentialDescriptor] { lock.withLock { _externalReads } }
    var writes: Int { lock.withLock { _writes } }

    func read(_ key: String) async throws -> String? { key == "plan_token" ? token : nil }
    func write(_ value: String?, for key: String) async throws { lock.withLock { _writes += 1 } }
    func readExternal(_ descriptor: ExternalCredentialDescriptor) async throws -> String {
        lock.withLock { _externalReads.append(descriptor) }
        guard consent else { throw SecretStoreError.consentRequired }
        guard let external else { throw SecretStoreError.notFound }
        return external
    }
    func hasConsent(for descriptor: ExternalCredentialDescriptor) async -> Bool { consent }
}

/// Answers each request with the next status of `statuses` (the last one repeats) and the `ok` fixture body.
final class ScriptedHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [Int]
    private var _authorizations: [String?] = []

    init(_ statuses: [Int]) { self.statuses = statuses }

    var authorizations: [String?] { lock.withLock { _authorizations } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let status = lock.withLock {
            _authorizations.append(request.value(forHTTPHeaderField: "Authorization"))
            return statuses.count > 1 ? statuses.removeFirst() : statuses[0]
        }
        let body = PlanFixtures.data(status == 200 ? "ok" : "unauthorized")
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

/// A clock tests move by hand.
final class PlanClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ now: Date = planNow) { _now = now }
    var now: Date { lock.withLock { _now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now += seconds } }
}

enum PlanFixtures {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("PlanUsageFixtures", isDirectory: true)

    static func data(_ name: String) -> Data {
        (try? Data(contentsOf: root.appendingPathComponent("\(name).json"))) ?? Data()
    }
}

let planNow = Date(timeIntervalSince1970: 1_793_000_000)

func planContext(
    auth: String? = nil, secrets: PlanSecrets, http: any HTTPClient
) -> AdapterContextBox {
    AdapterContextBox(
        settings: StaticSettings(
            values: auth.map { ["plan_auth": $0] } ?? [:],
            defaults: DefaultsReadOnlySettings(descriptors: ClaudeAdapter().settings)),
        secrets: secrets, executables: StubResolver(paths: [:]), http: http,
        log: Logger(subsystem: "fr.baguettelabs.vigie.tests", category: "claude"))
}

func credentialJSON(token: String, expiresAt: Date) -> String {
    """
    {"claudeAiOauth":{"accessToken":"\(token)","refreshToken":"r-\(token)",\
    "expiresAt":\(Int(expiresAt.timeIntervalSince1970 * 1000)),"scopes":["user:inference"],"subscriptionType":"max"}}
    """
}

// MARK: - Decode

@Suite struct PlanDecodeTests {
    func iso(_ text: String) -> Date { ClaudePlanUsageClient.parseDate(text)! }

    @Test func okFixtureDecodesBothWindows() throws {
        let windows = try ClaudePlanUsageClient.decode(PlanFixtures.data("ok"))
        #expect(windows.map(\.name) == ["5h", "weekly"])
        #expect(windows[0].used == 37 && windows[0].limit == nil)
        #expect(windows[1].used == 12)
        let reset = try #require(windows[0].resetsAt)
        #expect(abs(reset.timeIntervalSince(iso("2026-11-08T15:00:00Z")) - 0.123456) < 0.0001)
        #expect(windows[1].resetsAt == iso("2026-11-12T08:00:00Z"))
    }

    @Test func windowWithMissingFieldIsSkipped() throws {
        let windows = try ClaudePlanUsageClient.decode(PlanFixtures.data("missing-window"))
        #expect(windows.map(\.name) == ["5h"])
        #expect(windows[0].used == 81.5)
    }

    @Test func extraWindowsAreKeptByKeyAndOtherEntriesIgnored() throws {
        let windows = try ClaudePlanUsageClient.decode(PlanFixtures.data("extra-window"))
        #expect(windows.map(\.name) == ["5h", "weekly", "seven_day_opus", "seven_day_sonnet"])
        #expect(windows[2].resetsAt == nil && windows[2].used == 0)
        #expect(windows[3].used == 22.25)
    }

    @Test(arguments: ["garbage", "no-windows", "unauthorized"])
    func unknownShapesAreAFormatChange(_ fixture: String) {
        #expect(throws: PlanUsageError.formatChanged) { try ClaudePlanUsageClient.decode(PlanFixtures.data(fixture)) }
    }
}

// MARK: - Client

@Suite struct PlanClientTests {
    @Test func requestCarriesTheBearerAndBetaHeaders() async throws {
        let http = CannedHTTP(fixture: "ok")
        let snapshot = try await ClaudePlanUsageClient(http: http).fetch(token: "tok-1", now: planNow)
        #expect(snapshot.fetchedAt == planNow && snapshot.windows.count == 2)
        let request = try #require(http.requests.first)
        #expect(request.url == URL(string: "https://api.anthropic.com/api/oauth/usage"))
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    }

    @Test func statusMapping() async {
        let cases: [(String, Int, PlanUsageError)] = [
            ("unauthorized", 401, .unauthorized), ("unauthorized", 403, .unauthorized),
            ("server-error", 500, .unavailable(status: 500)), ("server-error", 503, .unavailable(status: 503)),
            ("garbage", 200, .formatChanged),
        ]
        for (fixture, status, expected) in cases {
            let client = ClaudePlanUsageClient(http: CannedHTTP(fixture: fixture, status: status))
            await #expect(throws: expected) { try await client.fetch(token: "t", now: planNow) }
        }
    }

    @Test func transportFailureIsUnavailable() async {
        let client = ClaudePlanUsageClient(http: CannedHTTP(.failure(URLError(.notConnectedToInternet))))
        await #expect(throws: PlanUsageError.unavailable(status: nil)) {
            try await client.fetch(token: "t", now: planNow)
        }
    }
}

// MARK: - Provider

@Suite struct PlanProviderTests {
    let provider = ClaudePlanUsageProvider(now: { planNow })

    @Test func tokenPathUsesThePastedToken() async throws {
        let http = CannedHTTP(fixture: "ok")
        let secrets = PlanSecrets(token: " pasted-token\n")
        let snapshot = try await provider.fetch(context: planContext(secrets: secrets, http: http))
        #expect(snapshot.windows.map(\.name) == ["5h", "weekly"])
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer pasted-token")
        #expect(secrets.externalReads.isEmpty && secrets.writes == 0)
    }

    @Test func tokenPathWithoutTokenMakesNoRequest() async {
        let http = CannedHTTP(fixture: "ok")
        await #expect(throws: PlanUsageError.credentialMissing) {
            try await provider.fetch(context: planContext(auth: "token", secrets: PlanSecrets(), http: http))
        }
        #expect(http.requests.isEmpty)
    }

    @Test func claudeCodePathRequiresConsent() async {
        let http = CannedHTTP(fixture: "ok")
        let secrets = PlanSecrets(external: credentialJSON(token: "cc", expiresAt: planNow + 3600), consent: false)
        await #expect(throws: PlanUsageError.consentRequired) {
            try await provider.fetch(context: planContext(auth: "claude_code", secrets: secrets, http: http))
        }
        #expect(http.requests.isEmpty)
    }

    @Test func claudeCodePathReadsTheDescriptorAndUsesTheAccessToken() async throws {
        let token = "sk-ant-oat-\(UUID().uuidString)"
        let http = CannedHTTP(fixture: "ok")
        let secrets = PlanSecrets(external: credentialJSON(token: token, expiresAt: planNow + 3600), consent: true)
        let snapshot = try await provider.fetch(context: planContext(auth: "claude_code", secrets: secrets, http: http))
        #expect(snapshot.windows.count == 2)
        #expect(secrets.externalReads == [ClaudeCodeCredential.descriptor])
        #expect(secrets.externalReads.first?.service == "Claude Code-credentials")
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        // Never written back, never renewed (one request, to the usage endpoint only).
        #expect(secrets.writes == 0)
        #expect(http.requests.count == 1 && http.requests[0].url == ClaudePlanUsageClient.endpoint)
    }

    @Test func expiredClaudeCodeLoginIsNeverRenewed() async {
        let http = CannedHTTP(fixture: "ok")
        let secrets = PlanSecrets(external: credentialJSON(token: "old", expiresAt: planNow - 1), consent: true)
        await #expect(throws: PlanUsageError.credentialExpired) {
            try await provider.fetch(context: planContext(auth: "claude_code", secrets: secrets, http: http))
        }
        #expect(http.requests.isEmpty && secrets.writes == 0)
    }

    @Test func missingOrMalformedClaudeCodeLogin() async {
        for external in [nil, "not json", #"{"claudeAiOauth":{}}"#] {
            let http = CannedHTTP(fixture: "ok")
            let secrets = PlanSecrets(external: external, consent: true)
            await #expect(throws: PlanUsageError.credentialMissing) {
                try await provider.fetch(context: planContext(auth: "claude_code", secrets: secrets, http: http))
            }
            #expect(http.requests.isEmpty)
        }
    }

    @Test func consentTextNamesTheKeychainItem() {
        let descriptor = ClaudeCodeCredential.descriptor
        #expect(descriptor.id == "claude.claude_code_login")
        #expect(descriptor.displayName == "Claude Code" && descriptor.accountHint == nil)
        let text = String(localized: descriptor.explanation)
        #expect(!text.hasPrefix("claude.") && text.contains("Claude Code"))
    }
}

// MARK: - Held login (keychain prompt loop fix)

@Suite struct PlanHeldLoginTests {
    let clock = PlanClock()
    var provider: ClaudePlanUsageProvider {
        let clock = clock
        return ClaudePlanUsageProvider(credentialCache: cache, now: { clock.now })
    }
    let cache = ExternalCredentialCache()

    func fetch(_ secrets: PlanSecrets, _ http: any HTTPClient) async throws -> UsageSnapshot {
        try await provider.fetch(context: planContext(auth: "claude_code", secrets: secrets, http: http))
    }

    @Test func secondFetchReusesTheHeldLoginWithoutTheKeychain() async throws {
        let http = ScriptedHTTP([200])
        let secrets = PlanSecrets(external: credentialJSON(token: "held", expiresAt: planNow + 3600), consent: true)
        _ = try await fetch(secrets, http)
        clock.advance(300)
        _ = try await fetch(secrets, http)
        clock.advance(300)
        _ = try await fetch(secrets, http)
        #expect(secrets.externalReads.count == 1)
        #expect(http.authorizations == Array(repeating: "Bearer held", count: 3))
        #expect(secrets.writes == 0)
    }

    @Test func theAdapterKeepsTheLoginAcrossUsageProviderCalls() async throws {
        let adapter = ClaudeAdapter()
        let http = ScriptedHTTP([200])
        let secrets = PlanSecrets(external: credentialJSON(token: "t", expiresAt: Date() + 3600), consent: true)
        let context = planContext(auth: "claude_code", secrets: secrets, http: http)
        _ = try await #require(adapter.usageProvider).fetch(context: context)
        _ = try await #require(adapter.usageProvider).fetch(context: context)
        #expect(secrets.externalReads.count == 1 && http.authorizations.count == 2)
        // Another adapter (another launch) reads again.
        _ = try await #require(ClaudeAdapter().usageProvider).fetch(context: context)
        #expect(secrets.externalReads.count == 2)
    }

    @Test func anExpiredHeldTokenIsReadAgain() async throws {
        let http = ScriptedHTTP([200])
        let secrets = PlanSecrets(external: credentialJSON(token: "old", expiresAt: planNow + 100), consent: true)
        _ = try await fetch(secrets, http)
        // Claude Code renewed its login meanwhile.
        secrets.external = credentialJSON(token: "new", expiresAt: planNow + 7200)
        clock.advance(200)
        _ = try await fetch(secrets, http)
        #expect(secrets.externalReads.count == 2)
        #expect(http.authorizations == ["Bearer old", "Bearer new"])
        clock.advance(300)
        _ = try await fetch(secrets, http)
        #expect(secrets.externalReads.count == 2)
    }

    @Test func anExpiredReadIsNotHeld() async throws {
        let http = ScriptedHTTP([200])
        let secrets = PlanSecrets(external: credentialJSON(token: "old", expiresAt: planNow - 1), consent: true)
        await #expect(throws: PlanUsageError.credentialExpired) { try await fetch(secrets, http) }
        await #expect(throws: PlanUsageError.credentialExpired) { try await fetch(secrets, http) }
        #expect(secrets.externalReads.count == 2 && http.authorizations.isEmpty)
    }

    @Test func aRejectedTokenIsDroppedAndReadAgainOnTheNextFetch() async throws {
        let http = ScriptedHTTP([200, 401, 200])
        let secrets = PlanSecrets(external: credentialJSON(token: "a", expiresAt: planNow + 7200), consent: true)
        _ = try await fetch(secrets, http)
        await #expect(throws: PlanUsageError.unauthorized) { try await fetch(secrets, http) }
        // Not re-read within the failing refresh.
        #expect(secrets.externalReads.count == 1)
        secrets.external = credentialJSON(token: "b", expiresAt: planNow + 7200)
        _ = try await fetch(secrets, http)
        #expect(secrets.externalReads.count == 2)
        #expect(http.authorizations == ["Bearer a", "Bearer a", "Bearer b"])
    }

    @Test func aRevokedConsentIsNeverBypassedByTheHeldLogin() async throws {
        let http = ScriptedHTTP([200])
        let secrets = PlanSecrets(external: credentialJSON(token: "t", expiresAt: planNow + 3600), consent: true)
        _ = try await fetch(secrets, http)
        secrets.consent = false
        await #expect(throws: PlanUsageError.consentRequired) { try await fetch(secrets, http) }
        #expect(http.authorizations.count == 1)
        // Allowed again: read again (the held login was dropped).
        secrets.consent = true
        _ = try await fetch(secrets, http)
        #expect(secrets.externalReads.count == 3)
    }

    @Test func thePastedTokenIsReadAtEachFetchAndNeverHeld() async throws {
        let http = ScriptedHTTP([401, 200])
        let secrets = PlanSecrets(token: "one", external: credentialJSON(token: "x", expiresAt: planNow + 3600))
        let context = planContext(auth: "token", secrets: secrets, http: http)
        await #expect(throws: PlanUsageError.unauthorized) { try await provider.fetch(context: context) }
        secrets.token = "two"
        _ = try await provider.fetch(context: context)
        #expect(http.authorizations == ["Bearer one", "Bearer two"])
        #expect(secrets.externalReads.isEmpty && secrets.writes == 0)
        #expect(await cache.login(for: ClaudeCodeCredential.descriptor.id) == nil)
    }
}

@Suite struct PlanProviderIdentityTests {
    @Test func nameAndCredential() {
        let provider = ClaudePlanUsageProvider()
        #expect(String(localized: provider.name) == "Claude")
        #expect(provider.externalCredential == ClaudeCodeCredential.descriptor)
    }
}
