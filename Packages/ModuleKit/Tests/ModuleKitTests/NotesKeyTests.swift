import Foundation
import Testing

@testable import ModuleKit

@Suite struct NotesKeyTests {
    @Test func keyIDVectorAndRandomKeys() {
        let zeros = SyncedKey(data: Data(repeating: 0, count: 32))!
        #expect(zeros.keyID == "66687aadf862bd77")
        #expect(zeros.description == "SyncedKey(66687aadf862bd77)")
        let a = SyncedKey.random()
        let b = SyncedKey.random()
        #expect(a.data.count == 32)
        #expect(a != b)
        #expect(SyncedKey.isValidKeyID(a.keyID))
        #expect(SyncedKey(data: Data(repeating: 0, count: 33)) == nil)
    }

    @Test func unavailableStoreRefusesEverything() async {
        let store = UnavailableSyncedKeyStore()
        #expect(await store.availability() == .unavailable(.notOwner))
        await #expect(throws: SyncedKeyError.unavailable(.notOwner)) { try await store.readKey() }
        await #expect(throws: SyncedKeyError.unavailable(.notOwner)) { try await store.createKey() }
        var iterator = store.changes().makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }
}
