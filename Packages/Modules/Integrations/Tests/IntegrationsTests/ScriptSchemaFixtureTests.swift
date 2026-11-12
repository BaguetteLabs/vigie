import Foundation
import Testing

@testable import Integrations

/// Story 12.1 AC 2: the Swift types accept every valid sample document and reject every invalid one, at the key
/// the fixture names. `Scripts/script-schema-check.py` checks the same fixtures against
/// `schemas/script-module.schema.json`, so the schema and the types agree on every outcome.
@Suite struct ScriptSchemaFixtureTests {
    struct Fixture: Decodable {
        let description: String
        let kind: String
        let error: String?
    }

    struct Sample: CustomTestStringConvertible {
        let name: String
        let fixture: Fixture
        /// The `document` bytes, re-serialized.
        let document: Data
        var testDescription: String { name }
    }

    static let root = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "Fixtures/script-schema")

    static func samples(_ expect: String) -> [Sample] {
        let folder = root.appending(path: expect)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().map { name in
            let data = try! Data(contentsOf: folder.appending(path: name))
            let fixture = try! JSONDecoder().decode(Fixture.self, from: data)
            let object = try! JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as! [String: Any]
            let document = try! JSONSerialization.data(
                withJSONObject: object["document"]!, options: [.fragmentsAllowed])
            return Sample(name: "\(expect)/\(name)", fixture: fixture, document: document)
        }
    }

    static let valid = samples("valid")
    static let invalid = samples("invalid")

    @Test func fixturesExist() {
        #expect(Self.valid.count >= 10)
        #expect(Self.invalid.count >= 50)
    }

    /// Decodes a sample with the type for its kind; true when the value, encoded and decoded again, is equal
    /// (the encoder writes what the schema accepts).
    @discardableResult
    static func decode(_ sample: Sample) throws -> Bool {
        let decoder = JSONDecoder()
        switch sample.fixture.kind {
        case "front-matter":
            let value = try decoder.decode(ScriptFrontMatter.self, from: sample.document)
            let again = try decoder.decode(ScriptFrontMatter.self, from: JSONEncoder().encode(value))
            return value == again
        case "output":
            let value = try decoder.decode(ScriptOutput.self, from: sample.document)
            let again = try decoder.decode(ScriptOutput.self, from: JSONEncoder().encode(value))
            return value == again
        default:
            Issue.record("unknown kind \(sample.fixture.kind) in \(sample.name)")
            throw CancellationError()
        }
    }

    @Test(arguments: valid) func validSampleDecodesAndRoundTrips(_ sample: Sample) throws {
        #expect(try Self.decode(sample), "\(sample.name) does not round-trip")
    }

    @Test(arguments: invalid) func invalidSampleIsRejectedAtItsKey(_ sample: Sample) {
        let expected = sample.fixture.error == "(document)" ? "" : sample.fixture.error
        do {
            try Self.decode(sample)
            Issue.record("\(sample.name) was accepted: \(sample.fixture.description)")
        } catch let error as ScriptSchemaError {
            #expect(error.path == expected, "\(sample.name): \(error.message)")
            // Readable for Story 12.2: the catalog resolved and the message names the key.
            #expect(!error.message.contains("script.error."), "\(sample.name): \(error.message)")
            #expect(!error.message.contains("script.kind."), "\(sample.name): \(error.message)")
            #expect(!error.message.contains("script.format."), "\(sample.name): \(error.message)")
            if let expected, !expected.isEmpty { #expect(error.message.hasPrefix(expected + ":")) }
        } catch {
            Issue.record("\(sample.name) threw \(error), not a ScriptSchemaError")
        }
    }
}
