import Foundation
import ModuleKit
import Testing

@testable import Notes

@Suite struct RecoveryKeyTests {
    static let zeros = SyncedKey(data: Data(repeating: 0, count: 32))!

    @Test func keyIDIsTheFirstEightBytesOfSHA256InHex() {
        // SHA-256 of 32 zero bytes = 66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925
        #expect(Self.zeros.keyID == "66687aadf862bd77")
        #expect(SyncedKey.isValidKeyID("66687aadf862bd77"))
        #expect(!SyncedKey.isValidKeyID("66687AADF862BD77"))
        #expect(!SyncedKey.isValidKeyID("66687aadf862bd7"))
        #expect(SyncedKey(data: Data(repeating: 0, count: 31)) == nil)
        #expect(!Self.zeros.description.contains("00"))
    }

    @Test func encodesEightGroupsOfSevenUppercaseCrockfordCharacters() {
        let text = RecoveryKey.encode(SyncedKey.random())
        let groups = text.split(separator: "-")
        #expect(groups.count == 8)
        #expect(groups.allSatisfy { $0.count == 7 })
        let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        #expect(text.replacingOccurrences(of: "-", with: "").allSatisfy { alphabet.contains($0) })
        // Version byte 0x01 → the first 5 bits are 00000.
        #expect(RecoveryKey.encode(Self.zeros).hasPrefix("04"))
    }

    @Test func roundTripsAndToleratesCaseDashesAndSpaces() throws {
        for _ in 0..<20 {
            let key = SyncedKey.random()
            let text = RecoveryKey.encode(key)
            #expect(try RecoveryKey.parse(text) == key)
            #expect(try RecoveryKey.parse(text.lowercased()) == key)
            #expect(try RecoveryKey.parse(text.replacingOccurrences(of: "-", with: "")) == key)
            #expect(try RecoveryKey.parse(text.replacingOccurrences(of: "-", with: " ") + "\n") == key)
        }
        // Crockford: O reads as 0, I and L as 1.
        let text = RecoveryKey.encode(Self.zeros)
        #expect(try RecoveryKey.parse(text.replacingOccurrences(of: "0", with: "O")) == Self.zeros)
    }

    @Test func checksumCatchesATypo() {
        let text = Array(RecoveryKey.encode(Self.zeros))
        for index in [3, 20, 40, 60] where text[index] != "-" {
            var typo = text
            typo[index] = typo[index] == "7" ? "8" : "7"
            #expect(throws: RecoveryKey.ParseError.checksumMismatch) { try RecoveryKey.parse(String(typo)) }
        }
    }

    @Test func refusesWrongLengthAndCharacters() {
        let text = RecoveryKey.encode(Self.zeros)
        #expect(throws: RecoveryKey.ParseError.invalidLength) { try RecoveryKey.parse(String(text.dropLast())) }
        #expect(throws: RecoveryKey.ParseError.invalidLength) { try RecoveryKey.parse("") }
        #expect(throws: RecoveryKey.ParseError.invalidCharacter) { try RecoveryKey.parse("U" + text.dropFirst()) }
        #expect(throws: RecoveryKey.ParseError.invalidCharacter) { try RecoveryKey.parse("é" + text.dropFirst()) }
    }

    @Test func noteHeaderIsOneJSONLine() throws {
        let header = NoteFileHeader(keyID: Self.zeros.keyID)
        #expect(String(decoding: header.encoded(), as: UTF8.self) == "{\"format\":1,\"key_id\":\"66687aadf862bd77\"}\n")
        var file = header.encoded()
        file.append(Data([0xFF, 0x00, 0x0A, 0x7B]))
        #expect(NoteFileHeader.parse(file) == header)
        #expect(NoteFileHeader.parse(Data("{\"format\":1,\"key_id\":\"nothex\"}\n".utf8)) == nil)
        #expect(NoteFileHeader.parse(Data([0xFF, 0xFE])) == nil)
    }
}
