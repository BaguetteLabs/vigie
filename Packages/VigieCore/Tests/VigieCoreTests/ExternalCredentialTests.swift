import Foundation
import ModuleKit
import OSLog
import Security
import Testing

@testable import VigieCore

let claudeLogin = ExternalCredentialDescriptor(
    id: "claude.claude_code_login", displayName: "Claude Code", service: "Claude Code-credentials",
    explanation: "test")

extension FakeKeychainClient {
    /// Puts another app's item in the fake login keychain (no access group).
    func putExternal(_ value: String, service: String, account: String = "") {
        state.withLock { $0.items[Item(group: "", service: service, account: account)] = Data(value.utf8) }
    }
}

@MainActor @Suite struct ExternalCredentialTests {
    @Test func queryTargetsTheLoginKeychainItemOnly() {
        let query = FakeKeychainClient.describe(KeychainSecretStore.externalQuery(claudeLogin))
        #expect(query[kSecClass as String] == "\(kSecClassGenericPassword)")
        #expect(query[kSecAttrService as String] == "Claude Code-credentials")
        #expect(query[kSecReturnData as String] == "true")
        #expect(query[kSecUseDataProtectionKeychain as String] == nil)
        #expect(query[kSecAttrAccessGroup as String] == nil)
        #expect(query[kSecAttrAccount as String] == nil)
        let hinted = ExternalCredentialDescriptor(
            id: "claude.x", displayName: "X", service: "S", accountHint: "me", explanation: "t")
        #expect(
            FakeKeychainClient.describe(KeychainSecretStore.externalQuery(hinted))[kSecAttrAccount as String] == "me")
    }

    @Test func refusesWithoutConsentThenReadsInMemoryEvenWhenOwnSecretsAreUnavailable() async throws {
        let client = FakeKeychainClient()
        let token = "external-\(UUID().uuidString)"
        client.putExternal(token, service: claudeLogin.service)
        // Ad-hoc build: no team, Vigie's own items are unavailable.
        let store = KeychainSecretStore(
            identity: SecretStoreIdentity(teamID: nil, bundleID: "fr.baguettelabs.vigie.dev"), client: client,
            log: testLogger, consents: MemoryConsentRecords())
        await #expect(throws: SecretStoreError.consentRequired) { try await store.readExternal(claudeLogin) }
        #expect(client.calls == 0)  // no Keychain access (and no prompt) before consent

        try await store.grantConsent(for: claudeLogin)
        #expect(try await store.readExternal(claudeLogin) == token)
        // Read only: nothing added, updated or deleted.
        #expect(client.lastAdd == nil && client.updates == 0)
        #expect(client.storedValues == [token])

        try await store.revokeConsent(for: claudeLogin)
        await #expect(throws: SecretStoreError.consentRequired) { try await store.readExternal(claudeLogin) }
    }

    @Test func missingItemIsNotFound() async throws {
        let store = KeychainSecretStore(
            identity: testSecretIdentity, client: FakeKeychainClient(), log: testLogger,
            consents: MemoryConsentRecords())
        try await store.grantConsent(for: claudeLogin)
        await #expect(throws: SecretStoreError.notFound) { try await store.readExternal(claudeLogin) }
    }

    @Test func withoutConsentRecordsNothingCanBeGranted() async {
        let store = makeSecretStore()
        await #expect(throws: SecretStoreError.unavailable(status: SecretStoreError.unimplementedStatus)) {
            try await store.grantConsent(for: claudeLogin)
        }
        #expect(await store.consent(for: claudeLogin) == nil)
    }

    @Test func adapterScopeReadsOnlyItsOwnDescriptors() async throws {
        let client = FakeKeychainClient()
        client.putExternal("v", service: claudeLogin.service)
        let store = KeychainSecretStore(
            identity: testSecretIdentity, client: client, log: testLogger, consents: MemoryConsentRecords())
        let claude = store.scoped(to: KeychainSecretStore.adapterOwner("claude"))
        let codex = store.scoped(to: KeychainSecretStore.adapterOwner("codex"))
        let module = store.scoped(to: "agents.usage")
        try await claude.grantConsent(for: claudeLogin)
        #expect(await claude.hasConsent(for: claudeLogin))
        #expect(try await claude.readExternal(claudeLogin) == "v")
        await #expect(throws: SecretStoreError.consentRequired) { try await codex.readExternal(claudeLogin) }
        await #expect(throws: SecretStoreError.consentRequired) { try await module.readExternal(claudeLogin) }
        await #expect(throws: SecretStoreError.consentRequired) { try await module.grantConsent(for: claudeLogin) }
        #expect(await codex.hasConsent(for: claudeLogin) == false)
        try await claude.revokeConsent(for: claudeLogin)
        #expect(await claude.hasConsent(for: claudeLogin) == false)
    }

    @Test func ownerContainsChecksWithoutReadingTheValue() async throws {
        let client = FakeKeychainClient()
        let store = makeSecretStore(client)
        let scoped = store.scoped(to: "adapter.claude")
        #expect(try await scoped.contains("plan_token") == false)
        try await scoped.write("tok", for: "plan_token")
        #expect(try await scoped.contains("plan_token"))
    }

    /// Consent lives in local.toml under `[consents."<id>"] granted_at`, never in config.toml; revoke removes it.
    @Test func consentRoundTripInLocalTomlOnly() async throws {
        let fixture = ConfigFixture()
        let (config, _) = try await fixture.makeStore()
        let grantedAt = Date(timeIntervalSince1970: 1_793_000_000)
        let client = FakeKeychainClient()
        let token = "external-\(UUID().uuidString)"
        client.putExternal(token, service: claudeLogin.service)
        let store = KeychainSecretStore(
            identity: testSecretIdentity, client: client, log: testLogger,
            consents: ConfigConsentRecords(store: config), now: { grantedAt })
        #expect(await store.consent(for: claudeLogin) == nil)

        try await store.grantConsent(for: claudeLogin)
        let local = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(local.contains(#"[consents."claude.claude_code_login"]"#))
        #expect(local.contains("granted_at = \"\(grantedAt.formatted(.iso8601))\""))
        let synced = (try? String(contentsOf: fixture.configURL, encoding: .utf8)) ?? ""
        #expect(!synced.contains("consents") && !synced.contains("claude_code_login"))
        #expect(
            await store.consent(for: claudeLogin) == ExternalConsent(descriptorID: claudeLogin.id, grantedAt: grantedAt)
        )
        #expect(config.problems.isEmpty)

        // The external value reaches no file.
        #expect(try await store.readExternal(claudeLogin) == token)
        for url in [fixture.localURL, fixture.configURL] {
            let data = (try? Data(contentsOf: url)) ?? Data()
            #expect(data.range(of: Data(token.utf8)) == nil)
        }

        // A second store on the same files (next launch) still sees it.
        let (reloaded, _) = try await fixture.makeStore()
        #expect(await ConfigConsentRecords(store: reloaded).consent(for: claudeLogin.id)?.grantedAt == grantedAt)

        try await store.revokeConsent(for: claudeLogin)
        #expect(await store.consent(for: claudeLogin) == nil)
        let after = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(!after.contains("granted_at"))
        await #expect(throws: SecretStoreError.consentRequired) { try await store.readExternal(claudeLogin) }
        config.stop()
        reloaded.stop()
    }

    /// The external value is never logged.
    @Test func externalValueNeverReachesTheLog() async throws {
        let start = Date()
        let client = FakeKeychainClient()
        let token = "external-\(UUID().uuidString)"
        client.putExternal(token, service: claudeLogin.service)
        let store = KeychainSecretStore(
            identity: testSecretIdentity, client: client, log: testLogger, consents: MemoryConsentRecords())
        try await store.grantConsent(for: claudeLogin)
        #expect(try await store.readExternal(claudeLogin) == token)
        let log = try OSLogStore(scope: .currentProcessIdentifier)
        for entry in try log.getEntries(at: log.position(date: start)) {
            #expect(!entry.composedMessage.contains(token))
        }
    }
}

@MainActor @Suite struct AdapterSettingsConfigTests {
    let descriptors = [
        SettingDescriptor(key: "usage_providers", label: "Sources", kind: .list(of: .string, default: ["local"])),
        SettingDescriptor(
            key: "plan_auth", label: "Auth", kind: .enumeration(options: ["token", "claude_code"], default: "token"),
            scope: .local),
        SettingDescriptor(key: "plan_token", label: "Token", kind: .secret, scope: .local),
    ]

    @Test func adapterSettingsReadAndWriteTheirFilesByScope() async throws {
        let fixture = ConfigFixture()
        let sessions = ModuleManifest(
            id: testManifest.id, name: testManifest.name, icon: testManifest.icon,
            settings: testManifest.settings + [
                SettingDescriptor(key: "adapters", label: "Adapters", kind: .list(of: .string, default: ["claude"]))
            ])
        let (config, watcher) = try await fixture.makeStore(
            manifests: [sessions],
            config: """
                [modules."agents.sessions"]
                adapters = ["claude"]

                [modules."agents.sessions".adapter.claude]
                usage_providers = ["local"]

                """)
        let settings = ConfigAdapterSettings(
            store: config, module: "agents.sessions", adapterID: "claude", settings: descriptors)
        #expect(settings.value("usage_providers", as: [String].self) == ["local"])
        #expect(settings.value("plan_auth", as: String.self) == "token")
        #expect(config.problems.isEmpty)

        let changes = settings.observe("usage_providers")
        try await settings.set(["local", "plan"], for: "usage_providers")
        try await settings.set("claude_code", for: "plan_auth")
        var iterator = changes.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        #expect(settings.value("usage_providers", as: [String].self) == ["local", "plan"])
        #expect(settings.value("plan_auth", as: String.self) == "claude_code")

        let synced = try String(contentsOf: fixture.configURL, encoding: .utf8)
        #expect(synced.contains(#"usage_providers = ["local", "plan"]"#))
        #expect(synced.contains(#"adapters = ["claude"]"#))
        #expect(!synced.contains("plan_auth"))
        let local = try String(contentsOf: fixture.localURL, encoding: .utf8)
        #expect(local.contains(#"plan_auth = "claude_code""#))
        #expect(!local.contains("usage_providers"))

        // Secrets never go through config.
        await #expect(throws: ConfigError.self) { try await settings.set("tok", for: "plan_token") }
        await #expect(throws: ConfigError.self) { try await settings.set("x", for: "undeclared") }
        // Outside edits are seen after a reload.
        try fixture.writeLocal(#"[modules."agents.sessions".adapter.claude]\#nplan_auth = "token"\#n"#)
        await config.fireAndSettle(watcher)
        #expect(settings.value("plan_auth", as: String.self) == "token")
        config.stop()
    }
}
