import Foundation
import ModuleKit
import Testing

@testable import VigieCore

struct Sample: Codable, Equatable, Sendable {
    var title: String
    var at: Date
}

struct SampleV1: Codable, Sendable {
    var name: String
}

@Suite struct ModuleStorageTests {
    let root = makeTempDirectory()

    func makeStorage(
        interval: Duration = .milliseconds(250),
        clock: any Clock<Duration> = ContinuousClock(),
        observer: (@Sendable (URL) -> Void)? = nil
    ) -> ModuleStorageImpl {
        ModuleStorageImpl(
            moduleID: "dev.sample", environment: makeEnvironment(root), logger: testLogger,
            coalesceInterval: interval, clock: clock, writeObserver: observer)
    }

    func files(_ storage: ModuleStorageImpl) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: storage.directory.path).sorted()
    }

    @Test func livesUnderApplicationSupportModulesFolder() {
        let storage = makeStorage()
        #expect(storage.directory.path == root.appendingPathComponent("modules/dev.sample").path)
    }

    @Test func schemaWrapperRoundTrip() async throws {
        let storage = makeStorage()
        let value = Sample(title: "hello", at: Date(timeIntervalSince1970: 1_700_000_000.125))
        try await storage.writeJSON(value, name: "state", schema: 3)
        await storage.flush()

        let raw = try Data(contentsOf: storage.directory.appendingPathComponent("state.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(object["schema"] as? Int == 3)
        #expect((object["value"] as? [String: Any])?["at"] as? String == "2023-11-14T22:13:20.125Z")

        let fresh = makeStorage()
        let read = try await fresh.readJSON("state", as: Sample.self, schema: 3)
        #expect(read?.title == "hello")
        #expect(abs((read?.at.timeIntervalSince1970 ?? 0) - 1_700_000_000.125) < 0.001)
    }

    @Test func missingFileReadsNil() async throws {
        #expect(try await makeStorage().readJSON("nothing", as: Sample.self, schema: 1) == nil)
    }

    @Test func readSeesPendingWrite() async throws {
        let storage = makeStorage(interval: .seconds(10))
        try await storage.writeJSON("first", name: "s", schema: 1)
        try await storage.writeJSON("second", name: "s", schema: 1)
        #expect(try await storage.readJSON("s", as: String.self, schema: 1) == "second")
    }

    @Test func olderSchemaIsMigratedForward() async throws {
        let storage = makeStorage()
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        try Data(#"{"schema":1,"value":{"name":"old"}}"#.utf8)
            .write(to: storage.directory.appendingPathComponent("state.json"))

        let calls = Counter()
        let read = try await storage.readJSON("state", as: Sample.self, schema: 2) { from, data in
            calls.increment()
            #expect(from == 1)
            let v1 = try JSONDecoder().decode(SampleV1.self, from: data)
            return Sample(title: v1.name.uppercased(), at: Date(timeIntervalSince1970: 0))
        }
        #expect(calls.count == 1)
        #expect(read?.title == "OLD")
    }

    @Test func newerSchemaThrowsAndLeavesFile() async throws {
        let storage = makeStorage()
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        let file = storage.directory.appendingPathComponent("state.json")
        try Data(#"{"schema":9,"value":"x"}"#.utf8).write(to: file)
        await #expect(throws: ModuleStorageError.newerSchema(found: 9, supported: 2)) {
            try await storage.readJSON("state", as: String.self, schema: 2)
        }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func corruptFileIsSetAsideWithUniqueNames() async throws {
        let storage = makeStorage()
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        let file = storage.directory.appendingPathComponent("state.json")

        try Data("garbage".utf8).write(to: file)
        #expect(try await storage.readJSON("state", as: Sample.self, schema: 1) == nil)
        try Data(#"{"schema":1,"value":{"title":3}}"#.utf8).write(to: file)  // decodes header, not value
        #expect(try await storage.readJSON("state", as: Sample.self, schema: 1) == nil)

        #expect(try files(storage) == ["state.json.corrupt", "state.json.corrupt.2"])
    }

    @Test func rapidWritesAreCoalesced() async throws {
        let writes = Counter()
        let clock = TestClock()
        let storage = makeStorage(clock: clock) { _ in writes.increment() }
        for index in 0..<10 {
            try await storage.writeJSON(index, name: "count", schema: 1)
        }
        // The first write goes out at once; the other nine merge into one trailing write.
        #expect(await eventually { writes.count == 1 })
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: .milliseconds(250))
        #expect(await eventually { writes.count == 2 })
        await storage.flush()
        #expect(writes.count == 2)
        #expect(try await makeStorage().readJSON("count", as: Int.self, schema: 1) == 9)
    }

    @Test func writesAreSpacedByTheInterval() async throws {
        let writes = Counter()
        let clock = TestClock()
        let storage = makeStorage(interval: .seconds(1), clock: clock) { _ in writes.increment() }
        try await storage.writeJSON(1, name: "n", schema: 1)
        #expect(await eventually { writes.count == 1 })
        try await storage.writeJSON(2, name: "n", schema: 1)
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: .milliseconds(999))
        await Task.yield()
        #expect(writes.count == 1)  // second write waits for the interval
        clock.advance(by: .milliseconds(1))
        #expect(await eventually { writes.count == 2 })
    }

    @Test func atomicWriteLeavesNoTempFiles() async throws {
        let storage = makeStorage()
        for index in 0..<5 {
            try await storage.writeJSON(index, name: "a", schema: 1)
            await storage.flush()
        }
        #expect(try files(storage) == ["a.json"])
    }

    @Test func failedWriteCleansTempAndKeepsTarget() async throws {
        let writes = Counter()
        let storage = makeStorage { _ in writes.increment() }
        // A non-empty directory where the file should go makes rename(2) fail.
        let blocker = storage.directory.appendingPathComponent("b.json", isDirectory: true)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: blocker.appendingPathComponent("keep"))

        try await storage.writeJSON(1, name: "b", schema: 1)
        await storage.flush()

        #expect(writes.count == 0)
        #expect(try files(storage) == ["b.json"])
        #expect(FileManager.default.fileExists(atPath: blocker.appendingPathComponent("keep").path))
    }

    @Test func rejectsPathLikeNames() async {
        let storage = makeStorage()
        for name in ["", "../x", "a/b", ".hidden"] {
            await #expect(throws: ModuleStorageError.invalidName(name)) {
                try await storage.writeJSON(1, name: name, schema: 1)
            }
        }
    }
}
