import Foundation
import Testing

@testable import VigieCore

/// Golden-file round trip of `TOMLPatcher` (AD-8, CI step `config-corpus`). Each folder of
/// `Tests/ConfigCorpus/` holds `input.toml`, `op.json` (one op or a list) and `expected.toml`; applying the
/// ops to the input must give the expected bytes exactly.
@Suite struct ConfigCorpusTests {
    static let corpusURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ConfigCorpus")

    static var cases: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: corpusURL.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }

    @Test func corpusHasEnoughCases() {
        #expect(Self.cases.count >= 10)
    }

    @Test(arguments: cases)
    func roundTrip(name: String) throws {
        let folder = Self.corpusURL.appendingPathComponent(name)
        let input = try Data(contentsOf: folder.appendingPathComponent("input.toml"))
        let expected = try Data(contentsOf: folder.appendingPathComponent("expected.toml"))
        let ops = try CorpusOp.load(folder.appendingPathComponent("op.json"))
        try #require(!ops.isEmpty)

        var text = String(decoding: input, as: UTF8.self)
        for op in ops {
            let path = try #require(ConfigKeyPath(parsing: op.path), "bad path \(op.path)")
            if let value = op.value {
                text = try TOMLPatcher.set(text, path: path, value: value)
            } else {
                text = try TOMLPatcher.remove(text, path: path)
            }
        }
        let output = Data(text.utf8)
        if output != expected {
            Issue.record("\(name): output differs from expected.toml\n\(unifiedDiff(expected, output))")
        }

        let document = try ConfigDocument.parse(ConfigWriter.droppingBOM(text))
        for op in ops where ops.last(where: { $0.path == op.path }) == op {
            let path = try #require(ConfigKeyPath(parsing: op.path))
            #expect(document.value(at: path) == op.value?.configValue, "\(name): \(op.path)")
        }
    }

    private func unifiedDiff(_ expected: Data, _ actual: Data) -> String {
        let folder = makeTempDirectory()
        let expectedURL = folder.appendingPathComponent("expected.toml")
        let actualURL = folder.appendingPathComponent("actual.toml")
        try? expected.write(to: expectedURL)
        try? actual.write(to: actualURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        process.arguments = ["-u", expectedURL.path, actualURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return "(diff unavailable: \(error))"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// One `op.json` entry: `{ "kind": "set" | "remove", "path": "<key path>", "value": <json> }`.
struct CorpusOp: Decodable, Equatable {
    let path: String
    /// nil for `remove`.
    let value: TOMLScalar?

    private enum Keys: String, CodingKey { case kind, path, value }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        path = try container.decode(String.self, forKey: .path)
        switch try container.decode(String.self, forKey: .kind) {
        case "set": value = try container.decode(JSONScalar.self, forKey: .value).scalar
        case "remove": value = nil
        case let kind:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown \(kind)")
        }
    }

    static func load(_ url: URL) throws -> [CorpusOp] {
        let data = try Data(contentsOf: url)
        if let list = try? JSONDecoder().decode([CorpusOp].self, from: data) { return list }
        return [try JSONDecoder().decode(CorpusOp.self, from: data)]
    }
}

private struct JSONScalar: Decodable {
    let scalar: TOMLScalar

    init(from decoder: any Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var items: [TOMLScalar] = []
            while !array.isAtEnd { items.append(try array.decode(JSONScalar.self).scalar) }
            scalar = .array(items)
            return
        }
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(Bool.self) {
            scalar = .bool(value)
        } else if let value = try? single.decode(Int.self) {
            scalar = .int(value)
        } else if let value = try? single.decode(Double.self) {
            scalar = .double(value)
        } else {
            scalar = .string(try single.decode(String.self))
        }
    }
}
