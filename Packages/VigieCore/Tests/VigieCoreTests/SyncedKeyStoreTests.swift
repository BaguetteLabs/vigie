import Foundation
import ModuleKit
import OSLog
import Security
import Synchronization
import Testing
import Wire

@testable import VigieCore

/// In-memory Keychain for the notes key: items keyed by group and service; `deniedGroups` answer
/// `errSecMissingEntitlement` (a build without that access group). Never touches the real Keychain.
final class FakeNotesKeychain: KeychainClient {
    struct Item: Hashable { let group: String, service: String, account: String }
    struct State {
        var items: [Item: Data] = [:]
        var queries: [[String: String]] = []
    }

    let state = Mutex(State())
    let deniedGroups: Set<String>

    init(deniedGroups: Set<String> = []) { self.deniedGroups = deniedGroups }

    var queries: [[String: String]] { state.withLock { $0.queries } }
    func put(_ data: Data, group: String, service: String) {
        state.withLock { $0.items[Item(group: group, service: service, account: "notes")] = data }
    }
    func data(group: String, service: String) -> Data? {
        state.withLock { $0.items[Item(group: group, service: service, account: "notes")] }
    }

    private static func item(_ query: [CFString: Any]) -> Item {
        Item(
            group: query[kSecAttrAccessGroup] as? String ?? "", service: query[kSecAttrService] as? String ?? "",
            account: query[kSecAttrAccount] as? String ?? "")
    }

    private func record(_ query: [CFString: Any]) -> Item? {
        let item = Self.item(query)
        state.withLock { $0.queries.append(FakeKeychainClient.describe(query)) }
        return deniedGroups.contains(item.group) ? nil : item
    }

    func add(_ attributes: [CFString: Any]) -> OSStatus {
        guard let item = record(attributes) else { return errSecMissingEntitlement }
        return state.withLock { s in
            if s.items[item] != nil { return errSecDuplicateItem }
            s.items[item] = attributes[kSecValueData] as? Data
            return errSecSuccess
        }
    }

    func update(_ query: [CFString: Any], _ attributes: [CFString: Any]) -> OSStatus {
        guard let item = record(query) else { return errSecMissingEntitlement }
        return state.withLock { s in
            guard s.items[item] != nil else { return errSecItemNotFound }
            s.items[item] = attributes[kSecValueData] as? Data
            return errSecSuccess
        }
    }

    func copyMatching(_ query: [CFString: Any]) -> (OSStatus, Data?) {
        guard let item = record(query) else { return (errSecMissingEntitlement, nil) }
        return state.withLock { s in
            guard let data = s.items[item] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, query[kSecReturnData] as? Bool == true ? data : nil)
        }
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        guard let item = record(query) else { return errSecMissingEntitlement }
        return state.withLock { $0.items.removeValue(forKey: item) == nil ? errSecItemNotFound : errSecSuccess }
    }
}

@Suite struct SyncedKeyStoreTests {
    static let release = SecretStoreIdentity(teamID: "TEAM123", bundleID: "fr.baguettelabs.vigie")
    static let dev = SecretStoreIdentity(
        teamID: "TEAM123", bundleID: "fr.baguettelabs.vigie.dev", releaseBundleID: "fr.baguettelabs.vigie")
    static let log = Logger(subsystem: "test", category: "notes-key")

    static func store(
        _ identity: SecretStoreIdentity, _ client: FakeNotesKeychain, poll: Duration = .seconds(30)
    ) -> KeychainSyncedKeyStore {
        KeychainSyncedKeyStore(
            identity: identity, ownFolderName: identity.isDevBuild ? "Vigie Dev" : "Vigie", client: client, log: log,
            pollInterval: poll)
    }

    // MARK: Identity

    @Test func notesAccessGroupUsesTheReleaseBundleIDInBothBuilds() {
        #expect(Self.release.notesAccessGroup == "TEAM123.fr.baguettelabs.vigie.notes")
        #expect(Self.dev.notesAccessGroup == "TEAM123.fr.baguettelabs.vigie.notes")
        #expect(Self.release.notesService == "fr.baguettelabs.vigie.notes")
        #expect(Self.dev.notesService == "fr.baguettelabs.vigie.notes")
        #expect(Self.dev.ownNotesService == "fr.baguettelabs.vigie.dev.notes")
        #expect(Self.dev.accessGroup == "TEAM123.fr.baguettelabs.vigie.dev")
        #expect(!Self.release.isDevBuild)
        #expect(Self.dev.isDevBuild)
        #expect(SecretStoreIdentity(teamID: nil, bundleID: "fr.baguettelabs.vigie").notesAccessGroup == nil)
    }

    @Test func identityFromTheEnvironmentNamesTheReleaseBundle() {
        let dev = SecretStoreIdentity(environment: AppEnvironment(flavor: .dev))
        #expect(dev.bundleID == "fr.baguettelabs.vigie.dev")
        #expect(dev.releaseBundleID == "fr.baguettelabs.vigie")
        #expect(dev.isDevBuild)
        let release = SecretStoreIdentity(environment: AppEnvironment(flavor: .release))
        #expect(release.releaseBundleID == release.bundleID)
        #expect(!release.isDevBuild)
    }

    // MARK: Queries

    @Test func itemQueryIsSynchronizableInTheDataProtectionKeychain() {
        let query = FakeKeychainClient.describe(
            KeychainSyncedKeyStore.itemQuery(
                accessGroup: "TEAM123.fr.baguettelabs.vigie.notes", service: "fr.baguettelabs.vigie.notes"))
        #expect(
            query == [
                kSecClass as String: kSecClassGenericPassword as String,
                kSecUseDataProtectionKeychain as String: "true",
                kSecAttrAccessGroup as String: "TEAM123.fr.baguettelabs.vigie.notes",
                kSecAttrSynchronizable as String: "true",
                kSecAttrService as String: "fr.baguettelabs.vigie.notes",
                kSecAttrAccount as String: "notes",
            ])
    }

    @Test func createdItemIsAccessibleAfterFirstUnlockNotThisDeviceOnly() async throws {
        let client = FakeNotesKeychain()
        let store = Self.store(Self.release, client)
        let key = try await store.createKey()
        let add = try #require(client.queries.last)
        #expect(add[kSecAttrAccessible as String] == kSecAttrAccessibleAfterFirstUnlock as String)
        #expect(add[kSecAttrSynchronizable as String] == "true")
        #expect(add[kSecValueData as String] == "<data>")
        #expect(
            client.data(group: "TEAM123.fr.baguettelabs.vigie.notes", service: "fr.baguettelabs.vigie.notes")
                == key.data)
        #expect(key.data.count == 32)
    }

    // MARK: Behavior

    @Test func createNeverReplacesAStoredKey() async throws {
        let client = FakeNotesKeychain()
        let existing = SyncedKey(data: Data(repeating: 7, count: 32))!
        client.put(existing.data, group: "TEAM123.fr.baguettelabs.vigie.notes", service: "fr.baguettelabs.vigie.notes")
        let store = Self.store(Self.release, client)
        await #expect(throws: SyncedKeyError.alreadyExists) { try await store.createKey() }
        #expect(try await store.readKey() == existing)
    }

    @Test func importReplacesAndDeleteRemoves() async throws {
        let client = FakeNotesKeychain()
        let store = Self.store(Self.release, client)
        _ = try await store.createKey()
        let recovered = SyncedKey(data: Data(repeating: 1, count: 32))!
        try await store.importKey(recovered)
        #expect(try await store.readKey() == recovered)
        try await store.delete()
        #expect(try await store.readKey() == nil)
    }

    @Test func adHocBuildIsUnavailableAndNeverCallsTheKeychain() async {
        let client = FakeNotesKeychain()
        let dev = SecretStoreIdentity(
            teamID: nil, bundleID: "fr.baguettelabs.vigie.dev", releaseBundleID: "fr.baguettelabs.vigie")
        let store = Self.store(dev, client)
        #expect(await store.availability() == .unavailable(.noSigningTeam))
        #expect(await store.scope() == .ownBuild(folderName: "Vigie Dev"))
        await #expect(throws: SyncedKeyError.unavailable(.noSigningTeam)) { try await store.readKey() }
        await #expect(throws: SyncedKeyError.unavailable(.noSigningTeam)) { try await store.createKey() }
        #expect(client.queries.isEmpty)
    }

    @Test func releaseWithoutTheNotesGroupIsUnavailable() async {
        let client = FakeNotesKeychain(deniedGroups: ["TEAM123.fr.baguettelabs.vigie.notes"])
        let store = Self.store(Self.release, client)
        #expect(await store.availability() == .unavailable(.missingEntitlement))
        #expect(await store.scope() == .shared)
    }

    @Test func devBuildSharesTheReleaseKeyWhenItCanReadIt() async throws {
        let client = FakeNotesKeychain()
        let releaseKey = SyncedKey(data: Data(repeating: 3, count: 32))!
        client.put(
            releaseKey.data, group: "TEAM123.fr.baguettelabs.vigie.notes", service: "fr.baguettelabs.vigie.notes")
        let store = Self.store(Self.dev, client)
        #expect(await store.availability() == .available)
        #expect(await store.scope() == .shared)
        #expect(try await store.readKey() == releaseKey)
    }

    @Test func devBuildThatCannotReadTheReleaseKeyUsesItsOwnGroupAndService() async throws {
        let client = FakeNotesKeychain(deniedGroups: ["TEAM123.fr.baguettelabs.vigie.notes"])
        let store = Self.store(Self.dev, client)
        #expect(await store.availability() == .available)
        #expect(await store.scope() == .ownBuild(folderName: "Vigie Dev"))
        let key = try await store.createKey()
        #expect(
            client.data(group: "TEAM123.fr.baguettelabs.vigie.dev", service: "fr.baguettelabs.vigie.dev.notes")
                == key.data)
    }

    @Test func changesYieldOnWritesAndOnAKeyThatArrives() async throws {
        let client = FakeNotesKeychain()
        let store = Self.store(Self.release, client, poll: .seconds(3600))
        #expect(try await store.readKey() == nil)
        var iterator = store.changes().makeAsyncIterator()
        while await store.listenerCount == 0 { await Task.yield() }
        // A synced item arrives from another Mac; the next poll notices it.
        client.put(
            Data(repeating: 9, count: 32), group: "TEAM123.fr.baguettelabs.vigie.notes",
            service: "fr.baguettelabs.vigie.notes")
        await store.poll()
        #expect(await iterator.next() != nil)
        // An unchanged item does not yield again; a write does.
        await store.poll()
        try await store.importKey(SyncedKey(data: Data(repeating: 4, count: 32))!)
        #expect(await iterator.next() != nil)
    }

    @MainActor @Test func onlyTheNotesModuleContextGetsTheStoreAndUserFolderResolves() async throws {
        let environment = AppEnvironment(
            flavor: .dev,
            applicationSupportURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                "notes-key-\(UUID().uuidString)"))
        let client = FakeNotesKeychain()
        let factory = CoreModuleContextFactory(
            environment: environment, eventBus: InProcessEventBus(), notesKey: Self.store(Self.release, client))
        let notes = ModuleManifest(
            id: "notes", name: "Notes", icon: "note.text",
            settings: [
                SettingDescriptor(
                    key: "folder", label: "Folder", kind: .path(default: "~/Notes/Vigie"), scope: .local)
            ])
        let notesContext = factory.makeContext(for: notes, tracker: RegistrationTracker())
        #expect(await notesContext.notesKey.availability() == .available)
        let folder = try #require(notesContext.storage.userFolder(setting: "folder"))
        #expect(folder.path.hasSuffix("/Notes/Vigie"))
        #expect(!folder.path.contains("~"))
        #expect(notesContext.storage.userFolder(setting: "missing") == nil)

        let other = factory.makeContext(
            for: ModuleManifest(id: "calendar", name: "Calendar", icon: "calendar"), tracker: RegistrationTracker())
        #expect(await other.notesKey.availability() == .unavailable(.notOwner))
        await #expect(throws: SyncedKeyError.unavailable(.notOwner)) { try await other.notesKey.readKey() }
    }
}
