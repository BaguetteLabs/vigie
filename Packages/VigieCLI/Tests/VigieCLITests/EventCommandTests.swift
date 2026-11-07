import Darwin
import Foundation
import Synchronization
import Testing
import Wire

@testable import VigieCLI

@Suite struct EventCommandTests {
    static let fixedDate = Date(timeIntervalSince1970: 1_793_000_000.5)

    struct Run {
        var status: Int32
        var output: [String]
        var errors: [String]
    }

    /// Runs the CLI against a scratch socket path (nothing listens) and spool.
    static func run(_ arguments: [String], stdin: Data? = nil, in folder: URL) -> Run {
        var output: [String] = []
        var errors: [String] = []
        let delivery = Delivery(
            socketPath: folder.appendingPathComponent("s.sock").path,
            spoolURL: folder.appendingPathComponent("spool/spool.jsonl"),
            deadline: .now.advanced(by: HookCommand.budget))
        let status = CLI.run(
            arguments: arguments, delivery: delivery, readStdin: { stdin }, now: { fixedDate },
            errorOutput: { errors.append($0) }, output: { output.append($0) })
        return Run(status: status, output: output, errors: errors)
    }

    static func spooled(in folder: URL) throws -> [Envelope] {
        let data = try Data(contentsOf: folder.appendingPathComponent("spool/spool.jsonl"))
        return try data.split(separator: 0x0A).map { try Envelope.decodeLine(Data($0)) }
    }

    @Test func eventWithArgumentSpoolsEnvelopeAndExitsZero() throws {
        let folder = try HookCommandTests.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = Self.run(["event", "test.ping", #"{"a":1,"b":["x"]}"#], in: folder)
        #expect(result.status == 0)
        #expect(result.output.isEmpty)
        #expect(result.errors.isEmpty)
        let envelopes = try Self.spooled(in: folder)
        #expect(envelopes.count == 1)
        let envelope = try #require(envelopes.first)
        #expect(envelope.v == WireProtocol.version)
        #expect(envelope.topic == "test.ping")
        #expect(envelope.sentAt == Self.fixedDate)
        #expect(envelope.payload == .object(["a": .number(1), "b": .array([.string("x")])]))
    }

    @Test func payloadComesFromStdinWhenNoArgument() throws {
        let command = try EventCommand.parse(arguments: ["my_tool.done"], readStdin: { Data(#"{"ok":true}"#.utf8) })
        #expect(command.payload == .object(["ok": .bool(true)]))
    }

    @Test func argumentWinsOverStdin() throws {
        let command = try EventCommand.parse(
            arguments: ["t", "[1]"],
            readStdin: {
                Issue.record("stdin read")
                return Data("{}".utf8)
            })
        #expect(command.payload == .array([.number(1)]))
    }

    @Test func payloadDefaultsToEmptyObject() throws {
        #expect(try EventCommand.parse(arguments: ["t"], readStdin: { nil }).payload == .object([:]))
        #expect(try EventCommand.parse(arguments: ["t"], readStdin: { Data(" \n".utf8) }).payload == .object([:]))
        #expect(try EventCommand.parse(arguments: ["t", ""], readStdin: { nil }).payload == .object([:]))
    }

    @Test(arguments: ["", "Test", "a b", "é", "a/b", String(repeating: "a", count: 65)])
    func rejectsBadTopics(_ topic: String) throws {
        let folder = try HookCommandTests.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = Self.run(["event", topic], in: folder)
        #expect(result.status == 2)
        #expect(result.errors.count == 1)
        #expect(result.errors.first?.contains("cli.error") == false)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("spool").path))
    }

    @Test func acceptsTopicCharsetUpTo64() {
        #expect(EventCommand.isValidTopic("a-z_0.9"))
        #expect(EventCommand.isValidTopic(String(repeating: "a", count: 64)))
    }

    @Test func rejectsBadJSONFromArgumentAndStdin() throws {
        let folder = try HookCommandTests.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fromArgument = Self.run(["event", "t", "{nope"], in: folder)
        #expect(fromArgument.status == 2)
        #expect(fromArgument.errors.count == 1)
        let fromStdin = Self.run(["event", "t"], stdin: Data("{nope".utf8), in: folder)
        #expect(fromStdin.status == 2)
        #expect(fromStdin.errors.count == 1)
    }

    @Test func missingTopicAndExtraArgumentsAreUsageErrors() throws {
        let folder = try HookCommandTests.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(Self.run(["event"], in: folder).status == 2)
        #expect(Self.run(["event", "t", "{}", "extra"], in: folder).status == 2)
        #expect(Self.run(["reload", "extra"], in: folder).status == 2)
    }

    @Test func exitsOneWhenNeitherSocketNorSpoolWork() throws {
        let folder = try HookCommandTests.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        // The spool's parent is a regular file, so the spool cannot be created.
        FileManager.default.createFile(atPath: folder.appendingPathComponent("spool").path, contents: Data())
        let result = Self.run(["event", "t"], in: folder)
        #expect(result.status == 1)
        #expect(result.errors.count == 1)
        let reload = Self.run(["reload"], in: folder)
        #expect(reload.status == 1)
        #expect(reload.output.isEmpty)
    }

    @Test func reloadSpoolsAppReloadAndPrintsQueued() throws {
        let folder = try HookCommandTests.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = Self.run(["reload"], in: folder)
        #expect(result.status == 0)
        #expect(result.output == [String(localized: "cli.reload.queued", bundle: CLIResources.bundle)])
        #expect(result.output != ["cli.reload.queued"])
        let envelope = try #require(try Self.spooled(in: folder).first)
        #expect(envelope.topic == Topic.appReload)
        #expect(envelope.topic == "app.reload")
        #expect(envelope.payload == .object([:]))
    }

    @Test func reloadSentToListeningSocketPrintsRequested() throws {
        let folder = try HookCommandTests.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("s.sock").path
        let listener = try TestListener(path: path)
        defer { listener.close() }
        let result = Self.run(["reload"], in: folder)
        #expect(result.status == 0)
        #expect(result.output == [String(localized: "cli.reload.requested", bundle: CLIResources.bundle)])
        let envelope = try Envelope.decodeLine(try listener.acceptLine())
        #expect(envelope.topic == Topic.appReload)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("spool").path))
    }

    @Test func usageListsCommands() {
        for command in ["hook", "event", "reload", "version"] {
            #expect(CLI.usage.contains(command))
        }
    }

    @Test func errorMessagesResolveFromCatalog() {
        let messages = [
            CLI.message(for: .missingTopic), CLI.message(for: .invalidTopic("X")),
            CLI.message(for: .invalidJSON), CLI.message(for: .unexpectedArgument("z")),
        ]
        for message in messages { #expect(!message.hasPrefix("cli.")) }
        #expect(CLI.message(for: .invalidTopic("Bad")).contains("Bad"))
        #expect(CLI.message(for: .invalidTopic("Bad")).contains("64"))
    }
}

/// A blocking `AF_UNIX` listener for tests.
final class TestListener: Sendable {
    let fd: Int32

    init(path: String) throws {
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 4) == 0 else { throw POSIXError(.EADDRINUSE) }
    }

    /// Accepts one connection and reads until EOF.
    func acceptLine() throws -> Data {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { throw POSIXError(.ECONNABORTED) }
        defer { Darwin.close(client) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }

    func close() { Darwin.close(fd) }
}

@Suite struct CLIResourcesTests {
    @Test func findsBundleBesideRealExecutable() throws {
        let bundle = try #require(CLIResources.locate(executable: nil))
        let folder = bundle.bundleURL.deletingLastPathComponent()
        let viaHelpers = CLIResources.locate(executable: folder.appendingPathComponent("vigie"))
        #expect(viaHelpers?.bundleURL == bundle.bundleURL)
        #expect(CLIResources.bundle.bundleURL.lastPathComponent == CLIResources.bundleName + ".bundle")
    }

    @Test func findsBundleInSiblingResourcesFolder() throws {
        let source = try #require(CLIResources.locate(executable: nil))
        let root = try HookCommandTests.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: source.bundleURL, to: resources.appendingPathComponent(CLIResources.bundleName + ".bundle"))
        let found = CLIResources.locate(executable: root.appendingPathComponent("Contents/Helpers/vigie-dev"))
        #expect(found?.bundleURL.standardizedFileURL.path.hasPrefix(resources.standardizedFileURL.path) == true)
    }
}
