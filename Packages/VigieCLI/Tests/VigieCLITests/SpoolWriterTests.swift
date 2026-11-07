import Darwin
import Foundation
import Testing

@testable import VigieCLI

@Suite struct SpoolWriterTests {
    private static func scratch() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/vw-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func appendsUserOnlyLines() throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let spool = folder.appendingPathComponent("d/spool.jsonl")
        #expect(Spool.append(Data("a\n".utf8), to: spool))
        #expect(Spool.append(Data("b\n".utf8), to: spool))
        #expect(try Data(contentsOf: spool) == Data("a\nb\n".utf8))
        let mode = try FileManager.default.attributesOfItem(atPath: spool.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    /// The app renames the spool while a writer that already opened it waits for the lock: the writer must
    /// reopen and append to the new `spool.jsonl`, never to the renamed file the app has already read.
    @Test func reopensWhenTheSpoolIsRenamedWhileWaitingForTheLock() async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let spool = folder.appendingPathComponent("spool.jsonl")
        let renamed = folder.appendingPathComponent("spool.replaying.jsonl")
        FileManager.default.createFile(atPath: spool.path, contents: Data("old\n".utf8))

        let holder = open(spool.path, O_RDONLY)
        #expect(holder >= 0)
        #expect(flock(holder, LOCK_EX) == 0)
        let writer = Task.detached { Spool.append(Data("new\n".utf8), to: spool) }
        // Let the writer open the old inode and block in flock.
        try await Task.sleep(for: .milliseconds(200))
        #expect(rename(spool.path, renamed.path) == 0)
        flock(holder, LOCK_UN)
        close(holder)

        #expect(await writer.value)
        #expect(try Data(contentsOf: renamed) == Data("old\n".utf8))
        #expect(try Data(contentsOf: spool) == Data("new\n".utf8))
    }
}
