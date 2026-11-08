import Foundation
import Testing

@testable import ModuleKit

@Suite struct SensitiveCodableTests {
    struct Item: Codable, Equatable {
        @Sensitive var label: String
    }

    @Test func encodesAsTheBareValue() throws {
        let data = try JSONEncoder().encode(Item(label: "Tea"))
        #expect(String(decoding: data, as: UTF8.self) == #"{"label":"Tea"}"#)
        #expect(try JSONDecoder().decode(Item.self, from: data) == Item(label: "Tea"))
    }
}
