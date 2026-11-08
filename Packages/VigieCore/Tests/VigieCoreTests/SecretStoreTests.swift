import Foundation
import ModuleKit
import OSLog
import Security
import Synchronization
import Testing
import VigieUI

@testable import VigieCore

/// In-memory Keychain: items keyed by access group, service and account. `status` forces every call's result
/// (e.g. `errSecMissingEntitlement` for an unsigned build).
final class FakeKeychainClient: KeychainClient {
    struct Item: Hashable { let group: String, service: String, account: String }
    struct State {
        var items: [Item: Data] = [:]
        var adds: [[String: String]] = []
        var updates = 0
        var calls = 0
    }

    let state = Mutex(State())
    let forcedStatus: OSStatus?

    init(forcedStatus: OSStatus? = nil) { self.forcedStatus = forcedStatus }

    var calls: Int { state.withLock { $0.calls } }
    var updates: Int { state.withLock { $0.updates } }
    var lastAdd: [String: String]? { state.withLock { $0.adds.last } }
    var storedValues: [String] { state.withLock { $0.items.values.compactMap { String(data: $0, encoding: .utf8) } } }
    func data(account: String) -> Data? { state.withLock { s in s.items.first { $0.key.account == account }?.value } }

    private static func item(_ query: [CFString: Any]) -> Item {
        Item(
            group: query[kSecAttrAccessGroup] as? String ?? "", service: query[kSecAttrService] as? String ?? "",
            account: query[kSecAttrAccount] as? String ?? "")
    }

    /// A string view of a query, so tests can compare attributes exactly.
    static func describe(_ query: [CFString: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in query {
            if key == kSecValueData {
                out[key as String] = "<data>"
            } else if let bool = value as? Bool {
                out[key as String] = bool ? "true" : "false"
            } else {
                out[key as String] = "\(value)"
            }
        }
        return out
    }

    func add(_ attributes: [CFString: Any]) -> OSStatus {
        state.withLock { s in
            s.calls += 1
            if let forcedStatus { return forcedStatus }
            s.adds.append(Self.describe(attributes))
            let item = Self.item(attributes)
            if s.items[item] != nil { return errSecDuplicateItem }
            s.items[item] = attributes[kSecValueData] as? Data
            return errSecSuccess
        }
    }

    func update(_ query: [CFString: Any], _ attributes: [CFString: Any]) -> OSStatus {
        state.withLock { s in
            s.calls += 1
            if let forcedStatus { return forcedStatus }
            let item = Self.item(query)
            guard s.items[item] != nil else { return errSecItemNotFound }
            s.updates += 1
            s.items[item] = attributes[kSecValueData] as? Data
            return errSecSuccess
        }
    }

    func copyMatching(_ query: [CFString: Any]) -> (OSStatus, Data?) {
        state.withLock { s in
            s.calls += 1
            if let forcedStatus { return (forcedStatus, nil) }
            guard let data = s.items[Self.item(query)] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, (query[kSecReturnData] as? Bool) == true ? data : nil)
        }
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        state.withLock { s in
            s.calls += 1
            if let forcedStatus { return forcedStatus }
            return s.items.removeValue(forKey: Self.item(query)) == nil ? errSecItemNotFound : errSecSuccess
        }
    }
}

let testSecretIdentity = SecretStoreIdentity(teamID: "TEAM123456", bundleID: "fr.baguettelabs.vigie.dev")

func makeSecretStore(_ client: FakeKeychainClient = FakeKeychainClient(), teamID: String? = "TEAM123456")
    -> KeychainSecretStore
{
    KeychainSecretStore(
        identity: SecretStoreIdentity(teamID: teamID, bundleID: "fr.baguettelabs.vigie.dev"), client: client,
        log: testLogger)
}

struct SecretStoreTests {
    @Test func identityNamesTheAccessGroupAndService() {
        #expect(testSecretIdentity.accessGroup == "TEAM123456.fr.baguettelabs.vigie.dev")
        #expect(testSecretIdentity.service == "fr.baguettelabs.vigie.dev.secrets")
        #expect(SecretStoreIdentity(teamID: nil, bundleID: "x").accessGroup == nil)
        #expect(KeychainSecretStore.adapterOwner("claude") == "adapter.claude")
    }

    @Test func itemAttributesAreExactlyAsSpecified() async throws {
        let client = FakeKeychainClient()
        let store = makeSecretStore(client)
        try await store.set("s3cr3t", owner: "mod.a", key: "token")
        let added = try #require(client.lastAdd)
        #expect(
            added == [
                kSecClass as String: kSecClassGenericPassword as String,
                kSecUseDataProtectionKeychain as String: "true",
                kSecAttrAccessGroup as String: "TEAM123456.fr.baguettelabs.vigie.dev",
                kSecAttrSynchronizable as String: "false",
                kSecAttrService as String: "fr.baguettelabs.vigie.dev.secrets",
                kSecAttrAccount as String: "mod.a/token",
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
                kSecValueData as String: "<data>",
            ])
    }

    @Test func roundTripUpdateRemoveAndMissing() async throws {
        let client = FakeKeychainClient()
        let store = makeSecretStore(client)
        await #expect(throws: SecretStoreError.notFound) { try await store.get(owner: "mod.a", key: "token") }
        #expect(try await store.exists(owner: "mod.a", key: "token") == false)

        try await store.set("one", owner: "mod.a", key: "token")
        #expect(try await store.get(owner: "mod.a", key: "token") == "one")
        #expect(try await store.exists(owner: "mod.a", key: "token"))

        try await store.set("two", owner: "mod.a", key: "token")
        #expect(client.updates == 1)
        #expect(try await store.get(owner: "mod.a", key: "token") == "two")

        try await store.remove(owner: "mod.a", key: "token")
        await #expect(throws: SecretStoreError.notFound) { try await store.get(owner: "mod.a", key: "token") }
        await #expect(throws: SecretStoreError.notFound) { try await store.remove(owner: "mod.a", key: "token") }
    }

    @Test func otherStatusesAreTypedFailures() async throws {
        let store = makeSecretStore(FakeKeychainClient(forcedStatus: errSecInteractionNotAllowed))
        // The probe only treats a missing entitlement as unavailable.
        #expect(await store.availability() == .available)
        await #expect(throws: SecretStoreError.failed(status: errSecInteractionNotAllowed)) {
            try await store.set("x", owner: "mod.a", key: "token")
        }
    }

    @Test func ownersCannotReadEachOther() async throws {
        let client = FakeKeychainClient()
        let store = makeSecretStore(client)
        let a = store.scoped(to: "mod.a")
        let b = store.scoped(to: "mod.b")
        try await a.write("alpha", for: "token")
        #expect(try await a.read("token") == "alpha")
        #expect(try await b.read("token") == nil)
        try await b.write("beta", for: "token")
        #expect(try await a.read("token") == "alpha")
        #expect(client.data(account: "mod.a/token") == Data("alpha".utf8))
        #expect(client.data(account: "mod.b/token") == Data("beta".utf8))
        // nil deletes; deleting again is not an error through the scoped API.
        try await a.write(nil, for: "token")
        try await a.write(nil, for: "token")
        #expect(try await a.read("token") == nil)
        #expect(try await b.read("token") == "beta")
    }

    @Test func moduleContextSecretsAreScopedByModuleID() async throws {
        let client = FakeKeychainClient()
        let store = makeSecretStore(client)
        let factory = await CoreModuleContextFactory(
            environment: makeEnvironment(makeTempDirectory()), eventBus: InProcessEventBus(), secretStore: store)
        let manifest = ModuleManifest(id: "mod.a", name: "A", icon: "star")
        let context = await factory.makeContext(for: manifest, tracker: RegistrationTracker())
        try await context.secrets.write("v", for: "token")
        #expect(client.data(account: "mod.a/token") == Data("v".utf8))
    }

    @Test func unavailableBuildPostsOneProblemAndEveryCallThrows() async throws {
        let client = FakeKeychainClient(forcedStatus: errSecMissingEntitlement)
        let store = makeSecretStore(client)
        let notifier = SetupRecordingNotifier()
        #expect(await store.reportAvailability(to: notifier) == .unavailable(status: errSecMissingEntitlement))
        await store.reportAvailability(to: notifier)
        #expect(notifier.events.count == 1)
        let event = try #require(notifier.events.first)
        #expect(event.kind == SetupProblemReporter.alertKind)
        #expect(event.category == "SECRETS")
        #expect(event.title == "Secrets are unavailable in this build")
        #expect(event.body?.isEmpty == false)
        #expect(event.action == nil)
        #expect(event.dedupeKey == KeychainSecretStore.unavailableDedupeKey)
        // Probed once; no item call reaches the Keychain afterwards.
        #expect(client.calls == 1)

        let unavailable = SecretStoreError.unavailable(status: errSecMissingEntitlement)
        await #expect(throws: unavailable) { try await store.set("x", owner: "mod.a", key: "k") }
        await #expect(throws: unavailable) { try await store.get(owner: "mod.a", key: "k") }
        await #expect(throws: unavailable) { try await store.exists(owner: "mod.a", key: "k") }
        await #expect(throws: unavailable) { try await store.remove(owner: "mod.a", key: "k") }
        let scoped = store.scoped(to: "mod.a")
        await #expect(throws: unavailable) { try await scoped.read("k") }
        await #expect(throws: unavailable) { try await scoped.write("x", for: "k") }
        await #expect(throws: unavailable) { try await scoped.write(nil, for: "k") }
        #expect(client.calls == 1)
    }

    @Test func noTeamIsUnavailableWithoutTouchingTheKeychain() async {
        let client = FakeKeychainClient()
        let store = makeSecretStore(client, teamID: nil)
        let notifier = SetupRecordingNotifier()
        #expect(await store.reportAvailability(to: notifier) == .unavailable(status: errSecMissingEntitlement))
        #expect(notifier.events.count == 1)
        #expect(client.calls == 0)
    }

    @Test func availableBuildPostsNothing() async {
        let client = FakeKeychainClient()
        let store = makeSecretStore(client)
        let notifier = SetupRecordingNotifier()
        #expect(await store.reportAvailability(to: notifier) == .available)
        #expect(notifier.events.isEmpty)
    }

    /// The real Keychain, under this test process's signature. Test runners are not signed with Vigie's
    /// keychain entitlement, so this normally checks the unavailable branch; a signed, entitled runner gets a
    /// real round trip (on a test-only bundle id, cleaned up).
    @Test func realKeychainMatchesTheEntitlement() async throws {
        let store = KeychainSecretStore(
            identity: SecretStoreIdentity(teamID: SigningTeam.current(), bundleID: "fr.baguettelabs.vigie.tests"),
            log: testLogger)
        let key = "probe-\(UUID().uuidString)"
        switch await store.availability() {
        case .available:
            try await store.set("value", owner: "tests", key: key)
            #expect(try await store.get(owner: "tests", key: key) == "value")
            try await store.remove(owner: "tests", key: key)
        case .unavailable(let status):
            #expect(status == errSecMissingEntitlement)
            await #expect(throws: SecretStoreError.unavailable(status: status)) {
                try await store.set("value", owner: "tests", key: key)
            }
        }
    }
}

@MainActor @Suite(.serialized) struct SecretSettingsTests {
    let tokenPath = ConfigKeyPath.module("custom.test", "token")

    @Test func configStoreRefusesSecretKeys() async throws {
        let h = try await SettingsHarness()
        await #expect(throws: ConfigError.secretKey(tokenPath.description)) {
            try await h.store.set(self.tokenPath, to: .string("leak"))
        }
        await #expect(throws: ConfigError.secretKey(tokenPath.description)) { try await h.store.remove(self.tokenPath) }
        #expect(!h.configText().contains("leak"))
        await h.tearDown()
    }

    @Test func secretRowWritesTheStoreAndNeverConfig() async throws {
        let client = FakeKeychainClient()
        let h = try await SettingsHarness(secretStore: makeSecretStore(client))
        let before = h.configText()
        let row = try #require(h.controller.rowModel(for: tokenPath))
        let secret = try #require(row.secret)
        #expect(row.binding.get() == nil)
        await #expect(throws: SettingWriteError(.secretKey(tokenPath.description))) {
            try await row.binding.set(.string("leak"))
        }

        let field = SettingFieldState()
        let state = SecretFieldState()
        await state.refresh(secret, field: field, services: .standard)
        #expect(state.isSet == false)
        #expect(await state.save("", to: secret, field: field, services: .standard) == false)
        #expect(client.calls == 2)  // probe + exists

        #expect(await state.save("tok-123", to: secret, field: field, services: .standard))
        #expect(state.isSet == true)
        #expect(field.error == nil)
        #expect(client.data(account: "custom.test/token") == Data("tok-123".utf8))

        #expect(await state.clear(secret, field: field, services: .standard))
        #expect(state.isSet == false)
        #expect(client.data(account: "custom.test/token") == nil)
        #expect(h.configText() == before)
        await h.tearDown()
    }

    @Test func secretRowWithoutStoreIsDisabled() async throws {
        let h = try await SettingsHarness()
        #expect(h.controller.rowModel(for: tokenPath)?.secret == nil)
        await h.tearDown()
    }

    @Test func unavailableStoreShowsTheError() async throws {
        let h = try await SettingsHarness(
            secretStore: makeSecretStore(FakeKeychainClient(forcedStatus: errSecMissingEntitlement)))
        let secret = try #require(h.controller.rowModel(for: tokenPath)?.secret)
        let field = SettingFieldState()
        let state = SecretFieldState()
        #expect(await state.save("x", to: secret, field: field, services: .standard) == false)
        #expect(field.error == "Secrets are unavailable in this build.")
        await h.tearDown()
    }

    /// AC 2: a secret entered through the Settings flow or a module's `context.secrets` reaches only the
    /// Keychain: no file under the app's folders and no log line of this process contains it.
    @Test func secretsNeverReachFilesOrLogs() async throws {
        let start = Date()
        let client = FakeKeychainClient()
        let store = makeSecretStore(client)
        let h = try await SettingsHarness(secretStore: store)
        let settingsValue = "vigie-secret-\(UUID().uuidString)"
        let moduleValue = "vigie-secret-\(UUID().uuidString)"

        let secret = try #require(h.controller.rowModel(for: tokenPath)?.secret)
        let field = SettingFieldState()
        #expect(await SecretFieldState().save(settingsValue, to: secret, field: field, services: .standard))
        // A refused config write of the same value.
        _ = try? await h.store.set(tokenPath, to: .string(settingsValue))

        let factory = CoreModuleContextFactory(
            environment: h.fixture.environment, eventBus: InProcessEventBus(), configStore: h.store,
            activityStore: h.activityStore, secretStore: store)
        let context = factory.makeContext(for: customManifest, tracker: RegistrationTracker())
        try await context.secrets.write(moduleValue, for: "other")
        #expect(try await context.secrets.read("other") == moduleValue)
        // Other writes that produce files: config, local, module storage, activity log.
        let name = try #require(h.controller.rowModel(for: .module("custom.test", "name")))
        try await name.binding.set(.string("visible"))
        try await context.storage.writeJSON(["k": "v"], name: "state", schema: 1)
        await context.storage.flush()
        context.activity.record(ActivityEntry(category: .module, kind: "test.secret", outcome: .posted))
        #expect(Set(client.storedValues) == [settingsValue, moduleValue])

        var scanned = 0
        for root in [h.fixture.support, h.fixture.configFolder] {
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                guard let data = try? Data(contentsOf: url) else { continue }
                scanned += 1
                for value in [settingsValue, moduleValue] {
                    #expect(data.range(of: Data(value.utf8)) == nil, "\(url.lastPathComponent) holds the secret")
                }
            }
        }
        #expect(scanned >= 3)

        let log = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try log.getEntries(at: log.position(date: start))
        var lines = 0
        for entry in entries {
            lines += 1
            #expect(!entry.composedMessage.contains(settingsValue))
            #expect(!entry.composedMessage.contains(moduleValue))
        }
        #expect(lines > 0)
        await h.tearDown()
    }
}
