import AgentKit
import Foundation
import Testing
import os

@testable import ClaudeAdapter

/// Secrets by key, with external items by service.
final class KeyedSecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    let tokens: [String: String]
    let external: [String: String]
    private var _reads: [String] = []
    private var _externalReads: [ExternalCredentialDescriptor] = []

    init(tokens: [String: String] = [:], external: [String: String] = [:]) {
        self.tokens = tokens
        self.external = external
    }

    var reads: [String] { lock.withLock { _reads } }
    var externalReads: [ExternalCredentialDescriptor] { lock.withLock { _externalReads } }

    func read(_ key: String) async throws -> String? {
        lock.withLock { _reads.append(key) }
        return tokens[key]
    }
    func write(_ value: String?, for key: String) async throws {}
    func readExternal(_ descriptor: ExternalCredentialDescriptor) async throws -> String {
        lock.withLock { _externalReads.append(descriptor) }
        guard let value = external[descriptor.service] else { throw SecretStoreError.notFound }
        return value
    }
}

@Suite struct ClaudeAccountTests {
    let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
    var work: AgentAccount { AgentAccount(id: "work", label: "Work", location: .configDirectory("~/.claude-work/")) }

    func context(_ values: [String: any SettingValue], secrets: any SecretStore, http: any HTTPClient)
        -> AdapterContextBox
    {
        AdapterContextBox(
            settings: StaticSettings(
                values: values, defaults: DefaultsReadOnlySettings(descriptors: ClaudeAdapter().settings)),
            secrets: secrets, executables: StubResolver(paths: [:]), http: http,
            log: Logger(subsystem: "fr.baguettelabs.vigie.tests", category: "claude"))
    }

    @Test func hintIsClaudeConfigDirElseTheDefaultFolder() {
        let adapter = ClaudeAdapter(homeDirectory: home)
        #expect(adapter.defaultAccountLocation == .configDirectory("/Users/me/.claude"))
        #expect(
            adapter.accountLocationHint(env: ["CLAUDE_CONFIG_DIR": " ~/.claude-work "])
                == .configDirectory("~/.claude-work"))
        #expect(adapter.accountLocationHint(env: ["CLAUDE_CONFIG_DIR": ""]) == .configDirectory("/Users/me/.claude"))
        #expect(adapter.accountLocationHint(env: [:]) == .configDirectory("/Users/me/.claude"))
    }

    @Test func settingsDeclareLocalAccountTemplates() {
        let keys = ClaudeAdapter().settings.map(\.key)
        #expect(keys.contains("accounts"))
        #expect(keys.contains("account.*.location"))
        #expect(keys.contains("account.*.usage_providers"))
        #expect(keys.contains("account.*.plan_auth"))
        #expect(!keys.contains("account.*.plan_token"))
        #expect(ClaudeAdapter().settings.filter { $0.key.hasPrefix("account") }.allSatisfy { $0.scope == .local })
    }

    @Test func eachAccountReadsItsOwnProjectsFolder() async throws {
        let temp = try TempHome()
        try temp.write("-p/s1.jsonl", LogLine.assistant(message: "m1"))
        let workProjects = temp.url.appendingPathComponent(".claude-work/projects/-q", isDirectory: true)
        try FileManager.default.createDirectory(at: workProjects, withIntermediateDirectories: true)
        try Data(LogLine.assistant(session: "w1", message: "m2").utf8)
            .write(to: workProjects.appendingPathComponent("w1.jsonl"))
        let adapter = ClaudeAdapter(homeDirectory: temp.url)
        let account = AgentAccount(id: "work", label: "Work", location: .configDirectory("~/.claude-work"))
        let workFiles = try await #require(adapter.logReader(for: account)).logFiles()
        #expect(workFiles.map(\.lastPathComponent) == ["w1.jsonl"])
        let defaultAccount = AgentAccount(id: .default, label: "", location: adapter.defaultAccountLocation)
        let defaultFiles = try await #require(adapter.logReader(for: defaultAccount)).logFiles()
        #expect(defaultFiles.map(\.lastPathComponent) == ["s1.jsonl"])
    }

    @Test func aNonDefaultAccountUsesItsOwnTokenKey() async throws {
        let secrets = KeyedSecrets(tokens: ["plan_token": "personal", "plan_token.work": "tok-work"])
        let http = CannedHTTP(fixture: "ok")
        let provider = ClaudePlanUsageProvider(homeDirectory: home, now: { planNow })
        _ = try await provider.fetch(context: context([:], secrets: secrets, http: http), account: work)
        #expect(secrets.reads == ["plan_token.work"])
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-work")
        // The default Account keeps the 7.3 key.
        _ = try await provider.fetch(context: context([:], secrets: secrets, http: http))
        #expect(secrets.reads.last == "plan_token")
    }

    @Test func aNonDefaultAccountReadsItsOwnClaudeCodeLogin() async throws {
        let service = ClaudeCodeCredential.service(configDirectory: "/Users/me/.claude-work")
        let secrets = KeyedSecrets(external: [service: credentialJSON(token: "tok-cc", expiresAt: planNow + 3600)])
        let http = CannedHTTP(fixture: "ok")
        let provider = ClaudePlanUsageProvider(homeDirectory: home, now: { planNow })
        let values: [String: any SettingValue] = ["account.work.plan_auth": "claude_code"]
        _ = try await provider.fetch(context: context(values, secrets: secrets, http: http), account: work)
        let read = try #require(secrets.externalReads.first)
        #expect(read.id == "claude.claude_code_login.work")
        #expect(read.service == service)
        #expect(service.hasPrefix("Claude Code-credentials-") && service.count == "Claude Code-credentials-".count + 8)
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-cc")
    }

    @Test func theDefaultAccountKeepsThe73Credential() {
        let provider = ClaudePlanUsageProvider(homeDirectory: home)
        let account = AgentAccount(id: .default, label: "", location: .configDirectory("/Users/me/.claude"))
        #expect(provider.externalCredential(for: account) == ClaudeCodeCredential.descriptor)
        #expect(provider.externalCredential(for: AgentAccount(id: "x", label: "X", location: nil)) == nil)
    }
}
