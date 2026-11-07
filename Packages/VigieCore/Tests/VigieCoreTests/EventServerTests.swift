import Darwin
import Foundation
import ModuleKit
import Synchronization
import Testing
import Wire

@testable import VigieCore

/// A short socket path under the Darwin user temp dir (sun_path holds 104 bytes) plus the instance lock.
private final class Fixture {
    let directory: URL
    let socketURL: URL
    let lock: InstanceLock
    let bus = InProcessEventBus()

    init(nested: Bool = false) throws {
        let base = AppEnvironment.darwinUserTempDirectory() ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("vs-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let parent = nested ? directory.appendingPathComponent("d", isDirectory: true) : directory
        socketURL = parent.appendingPathComponent("e.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        lock = try InstanceLock.acquire(at: directory.appendingPathComponent("i.lock"))
    }

    var path: String { socketURL.path }

    func server(maxLineBytes: Int = 1 << 20, maxQueuedLines: Int = 10_000) -> EventServer {
        EventServer(
            socketURL: socketURL, bus: bus, logger: testLogger, maxLineBytes: maxLineBytes,
            maxQueuedLines: maxQueuedLines)
    }

    deinit {
        lock.release()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Collects messages from a bus subscription.
private final class Inbox: Sendable {
    private let messages = Mutex<[EventMessage]>([])
    private let task: Mutex<Task<Void, Never>?> = Mutex(nil)
    private let token: RegistrationToken

    init(_ bus: InProcessEventBus, prefix: String) {
        let (stream, token) = bus.subscription(topicPrefix: prefix)
        self.token = token
        let consumer = Task { [weak self] in
            for await message in stream { self?.messages.withLock { $0.append(message) } }
        }
        task.withLock { $0 = consumer }
    }

    var all: [EventMessage] { messages.withLock { $0 } }
    var topics: [String] { all.map(\.topic) }
    var payloads: [JSONValue] { all.compactMap { try? JSONDecoder().decode(JSONValue.self, from: $0.payload) } }

    deinit {
        token.cancel()
        task.withLock { $0?.cancel() }
    }
}

/// A raw client: connects, writes, and closes on `close()` or deinit.
private final class RawClient {
    let fd: Int32

    init(path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let code = errno
            Darwin.close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .ECONNREFUSED)
        }
    }

    func send(_ data: Data) {
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    func send(_ text: String) { send(Data(text.utf8)) }

    func close() { Darwin.close(fd) }
}

private func envelope(_ topic: String, _ payload: JSONValue = .object([:]), v: Int = WireProtocol.version) -> Envelope {
    Envelope(v: v, topic: topic, sentAt: Date(timeIntervalSince1970: 1_793_000_000.25), payload: payload)
}

private func line(_ topic: String, _ payload: JSONValue = .object([:]), v: Int = WireProtocol.version) throws -> Data {
    try envelope(topic, payload, v: v).encodeLine()
}

private func send(_ data: Data, to path: String) throws {
    let client = try RawClient(path: path)
    client.send(data)
    client.close()
}

@Suite struct EventServerTests {
    @Test func bindsWithUserOnlyModeAndCreatesTheParentDirectory() throws {
        let fixture = try Fixture(nested: true)
        #expect(fixture.path.utf8.count < AppEnvironment.maxSocketPathBytes)
        let server = fixture.server()
        try server.start(lockHeld: fixture.lock)
        defer { server.stop() }

        #expect(server.isRunning)
        var info = stat()
        #expect(lstat(fixture.path, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFSOCK)
        #expect(info.st_mode & 0o777 == 0o600)
        var parent = stat()
        #expect(stat(fixture.socketURL.deletingLastPathComponent().path, &parent) == 0)
        #expect(parent.st_mode & 0o777 == 0o700)
    }

    @Test func unlinksAStaleSocketAndBinds() async throws {
        let fixture = try Fixture()
        // A stale socket left by a crashed instance: bound, never unlinked.
        let crashed = fixture.server()
        try crashed.start(lockHeld: fixture.lock)
        var staleInfo = stat()
        #expect(lstat(fixture.path, &staleInfo) == 0)
        // Simulate the crash: close without unlinking by moving the path aside and back.
        let aside = fixture.directory.appendingPathComponent("a.sock").path
        #expect(rename(fixture.path, aside) == 0)
        crashed.stop()
        #expect(rename(aside, fixture.path) == 0)
        #expect(FileManager.default.fileExists(atPath: fixture.path))

        let server = fixture.server()
        try server.start(lockHeld: fixture.lock)
        defer { server.stop() }
        server.releaseQueue()
        var info = stat()
        #expect(lstat(fixture.path, &info) == 0)
        #expect(info.st_ino != staleInfo.st_ino)

        let inbox = Inbox(fixture.bus, prefix: "")
        try send(line("agent.hook"), to: fixture.path)
        #expect(await eventually { inbox.all.count == 1 })
    }

    @Test func unlinksAStaleRegularFileAndBinds() throws {
        let fixture = try Fixture()
        FileManager.default.createFile(atPath: fixture.path, contents: Data("stale".utf8))
        let server = fixture.server()
        try server.start(lockHeld: fixture.lock)
        defer { server.stop() }
        var info = stat()
        #expect(lstat(fixture.path, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFSOCK)
    }

    @Test func rejectsATooLongPath() throws {
        let fixture = try Fixture()
        let long = fixture.directory.appendingPathComponent(String(repeating: "x", count: 120))
        let server = EventServer(socketURL: long, bus: fixture.bus, logger: testLogger)
        #expect(throws: EventServerError.pathTooLong) { try server.start(lockHeld: fixture.lock) }
        #expect(throws: EventServerError.alreadyStarted) {
            let started = fixture.server()
            try started.start(lockHeld: fixture.lock)
            defer { started.stop() }
            try started.start(lockHeld: fixture.lock)
        }
    }

    @Test func queuesUntilReleasedThenDeliversInOrder() async throws {
        let fixture = try Fixture()
        let server = fixture.server()
        try server.start(lockHeld: fixture.lock)
        defer { server.stop() }
        let inbox = Inbox(fixture.bus, prefix: "")

        var batch = Data()
        for index in 0..<5 { batch.append(try line("agent.hook", .object(["n": .number(Double(index))]))) }
        try send(batch, to: fixture.path)
        // Order is per connection; wait for the first one before opening the second.
        #expect(await eventually { server.queuedCount == 5 })
        try send(line("agent.hook", .object(["n": .number(5)])), to: fixture.path)

        #expect(await eventually { server.queuedCount == 6 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(inbox.all.isEmpty)

        server.releaseQueue()
        #expect(server.queuedCount == 0)
        #expect(await eventually { inbox.all.count == 6 })
        #expect(inbox.payloads == (0..<6).map { JSONValue.object(["n": .number(Double($0))]) })

        try send(line("agent.hook", .object(["n": .number(6)])), to: fixture.path)
        #expect(await eventually { inbox.all.count == 7 })
        #expect(inbox.payloads.last == .object(["n": .number(6)]))
        #expect(server.queuedCount == 0)
        #expect(inbox.all.allSatisfy { !$0.replayed })
    }

    @Test func queueOverflowDropsTheOldest() async throws {
        let fixture = try Fixture()
        let server = fixture.server(maxQueuedLines: 3)
        try server.start(lockHeld: fixture.lock)
        defer { server.stop() }
        let inbox = Inbox(fixture.bus, prefix: "")

        var batch = Data()
        for index in 0..<5 { batch.append(try line("t", .number(Double(index)))) }
        try send(batch, to: fixture.path)
        #expect(await eventually { server.queuedCount == 3 && server.clientCount == 0 })
        server.releaseQueue()
        #expect(await eventually { inbox.all.count == 3 })
        #expect(inbox.payloads == [.number(2), .number(3), .number(4)])
    }

    @Test func routesByTopicPrefix() async throws {
        let fixture = try Fixture()
        let server = fixture.server()
        try server.start(lockHeld: fixture.lock)
        defer { server.stop() }
        server.releaseQueue()
        let agents = Inbox(fixture.bus, prefix: "agent.")
        let app = Inbox(fixture.bus, prefix: "app.")

        var batch = try line(Topic.agentHook)
        batch.append(try line("app.expand"))
        try send(batch, to: fixture.path)

        #expect(await eventually { agents.all.count == 1 && app.all.count == 1 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(agents.topics == [Topic.agentHook])
        #expect(app.topics == ["app.expand"])
    }

    @Test func acceptsCurrentAndPreviousVersionsOnly() async throws {
        let fixture = try Fixture()
        let server = fixture.server()
        try server.start(lockHeld: fixture.lock)
        defer { server.stop() }
        server.releaseQueue()
        let inbox = Inbox(fixture.bus, prefix: "")
        let current = WireProtocol.version

        let client = try RawClient(path: fixture.path)
        client.send(try line("v.current", v: current))
        client.send(try line("v.previous", v: current - 1))
        client.send(try line("v.older", v: current - 2))
        client.send(try line("v.newer", v: current + 1))
        client.send(
            #"{"v":\#(current),"topic":"v.extra","sent_at":"2026-11-07T09:41:12.345Z","payload":{"a":1},"#
                + #""future":{"x":[1,2]},"id":"abc"}"# + "\n")
        client.send("not json\n")
        client.send("\n")
        client.send(#"{"v":\#(current),"topic":"v.baddate","sent_at":"yesterday","payload":{}}"# + "\n")
        client.send(try line("v.after"))
        client.close()

        #expect(await eventually { inbox.all.count == 4 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(inbox.topics == ["v.current", "v.previous", "v.extra", "v.after"])
        #expect(inbox.payloads[2] == .object(["a": .number(1)]))
    }

    @Test func passesThePayloadThroughAndStampsTheMessage() async throws {
        let fixture = try Fixture()
        let server = fixture.server()
        try server.start(lockHeld: fixture.lock)
        defer { server.stop() }
        server.releaseQueue()
        let inbox = Inbox(fixture.bus, prefix: "")

        let payload: JSONValue = .object([
            "agent": .string("claude"),
            "raw": .object([
                "hook_event_name": .string("Stop"),
                "nested": .array([.null, .bool(true), .number(1.5), .string("é\n\"")]),
            ]),
        ])
        let sent = envelope(Topic.agentHook, payload)
        let before = Date()
        try send(sent.encodeLine(), to: fixture.path)

        #expect(await eventually { inbox.all.count == 1 })
        let message = try #require(inbox.all.first)
        #expect(message.topic == Topic.agentHook)
        #expect(try JSONDecoder().decode(JSONValue.self, from: message.payload) == payload)
        #expect(abs(message.sentAt.timeIntervalSince(sent.sentAt)) < 0.001)
        #expect(message.receivedAt >= before.addingTimeInterval(-1))
        #expect(!message.replayed)
    }

    @Test func dropsATrailingFragmentAtEOF() async throws {
        let fixture = try Fixture()
        let server = fixture.server()
        try server.start(lockHeld: fixture.lock)
        defer { server.stop() }
        server.releaseQueue()
        let inbox = Inbox(fixture.bus, prefix: "")

        var data = try line("complete")
        var fragment = try line("fragment")
        fragment.removeLast()
        data.append(fragment)
        try send(data, to: fixture.path)

        #expect(await eventually { inbox.all.count == 1 && server.clientCount == 0 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(inbox.topics == ["complete"])
    }

    @Test func closesAConnectionWhoseLineExceedsTheLimit() async throws {
        let fixture = try Fixture()
        let server = fixture.server(maxLineBytes: 256)
        try server.start(lockHeld: fixture.lock)
        defer { server.stop() }
        server.releaseQueue()
        let inbox = Inbox(fixture.bus, prefix: "")

        let client = try RawClient(path: fixture.path)
        defer { client.close() }
        client.send(Data(repeating: UInt8(ascii: "x"), count: 1024))
        #expect(await eventually { server.clientCount == 0 })

        try send(line("ok"), to: fixture.path)
        #expect(await eventually { inbox.topics == ["ok"] })
    }

    @Test func stopUnlinksTheSocketAndIsIdempotent() throws {
        let fixture = try Fixture()
        let server = fixture.server()
        try server.start(lockHeld: fixture.lock)
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: fixture.path))
        #expect(!server.isRunning)
        server.stop()
        #expect(throws: (any Error).self) { try RawClient(path: fixture.path) }
    }

    @Test func stopLeavesAPathThatIsNoLongerItsInode() throws {
        let fixture = try Fixture()
        let server = fixture.server()
        try server.start(lockHeld: fixture.lock)
        #expect(unlink(fixture.path) == 0)
        FileManager.default.createFile(atPath: fixture.path, contents: Data("other".utf8))
        server.stop()
        #expect(FileManager.default.fileExists(atPath: fixture.path))
    }

    @Test func stopLeavesASocketBoundByAnotherServer() throws {
        let fixture = try Fixture()
        let first = fixture.server()
        try first.start(lockHeld: fixture.lock)
        // A relaunched instance (holding the lock after this one released it) rebinds the path.
        let second = fixture.server()
        try second.start(lockHeld: fixture.lock)
        first.stop()
        #expect(FileManager.default.fileExists(atPath: fixture.path))
        #expect(throws: Never.self) { try RawClient(path: fixture.path).close() }
        second.stop()
        #expect(!FileManager.default.fileExists(atPath: fixture.path))
    }

    @Test func deinitStopsTheServer() throws {
        let fixture = try Fixture()
        do {
            let server = fixture.server()
            try server.start(lockHeld: fixture.lock)
            #expect(FileManager.default.fileExists(atPath: fixture.path))
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.path))
    }
}

@Suite struct LineSplitterTests {
    @Test func splitsAcrossChunks() {
        var splitter = LineSplitter(maxLineBytes: 100)
        var result = splitter.append(Array("ab".utf8))
        #expect(result.lines.isEmpty)
        result = splitter.append(Array("c\nde\n\nf".utf8))
        #expect(result.lines == [Data("abc".utf8), Data("de".utf8), Data()])
        #expect(!result.overflow)
        #expect(splitter.pending == Array("f".utf8))
    }

    @Test func reportsOverflow() {
        var splitter = LineSplitter(maxLineBytes: 4)
        let result = splitter.append(Array("ok\nabcdef".utf8))
        #expect(result.lines == [Data("ok".utf8)])
        #expect(result.overflow)
        #expect(splitter.pending.isEmpty)
    }
}
