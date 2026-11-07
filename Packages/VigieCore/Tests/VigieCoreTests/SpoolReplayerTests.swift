import Darwin
import Foundation
import ModuleKit
import Synchronization
import Testing
import Wire

@testable import VigieCore

/// A short app support folder stand-in (socket paths must fit in `sun_path`), its spool locations,
/// the instance lock and a bus.
final class SpoolFixture {
    let directory: URL
    let environment: AppEnvironment
    let lock: InstanceLock
    let bus = InProcessEventBus()

    init() throws {
        let base = AppEnvironment.darwinUserTempDirectory() ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("sp-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        environment = AppEnvironment(flavor: .dev, applicationSupportURL: directory, configFolderOverride: directory)
        lock = try InstanceLock.acquire(at: environment.instanceLockURL)
    }

    var locations: SpoolLocations { SpoolLocations(environment: environment) }
    var spoolURL: URL { environment.spoolURL }
    var replayingURL: URL { environment.spoolReplayingURL }

    func server() -> EventServer {
        EventServer(socketURL: environment.socketURL, bus: bus, logger: testLogger)
    }

    deinit {
        lock.release()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Collects bus messages.
final class BusInbox: Sendable {
    private let box = Collected()
    private let token: RegistrationToken

    init(_ bus: InProcessEventBus, prefix: String = "") {
        let (stream, token) = bus.subscription(topicPrefix: prefix)
        self.token = token
        Task { [box] in
            for await message in stream { box.messages.withLock { $0.append(message) } }
        }
    }

    var all: [EventMessage] { box.all }
    var topics: [String] { all.map(\.topic) }

    deinit { token.cancel() }
}

/// Mirrors the CLI writer (`VigieCLI.Spool.append`, which VigieCore cannot import): `O_APPEND|O_CREAT` 0600,
/// `flock(LOCK_EX)`, reopen if the path no longer names the opened inode, one `write`.
/// `afterOpen` runs between `open` and `flock` on the first attempt.
func spoolAppend(_ line: Data, to url: URL, afterOpen: () -> Void = {}) -> Bool {
    for attempt in 0..<8 {
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        if attempt == 0 { afterOpen() }
        guard flock(fd, LOCK_EX) == 0 else { return false }
        defer { flock(fd, LOCK_UN) }
        var opened = stat()
        var current = stat()
        guard fstat(fd, &opened) == 0 else { return false }
        guard stat(url.path, &current) == 0, current.st_ino == opened.st_ino, current.st_dev == opened.st_dev else {
            continue
        }
        return line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == line.count
    }
    return false
}

func spoolLine(_ topic: String, _ n: Int, v: Int = WireProtocol.version) throws -> Data {
    try Envelope(
        v: v, topic: topic, sentAt: Date(timeIntervalSince1970: 1_793_000_000),
        payload: .object(["n": .number(Double(n))])
    )
    .encodeLine()
}

func number(_ message: EventMessage) -> Int? {
    guard case .object(let object)? = try? JSONDecoder().decode(JSONValue.self, from: message.payload),
        case .number(let value)? = object["n"]
    else { return nil }
    return Int(value)
}

/// Messages collected by a publish callback or a bus subscription.
final class Collected: Sendable {
    let messages = Mutex<[EventMessage]>([])
    var all: [EventMessage] { messages.withLock { $0 } }
}

private func replayer(_ fixture: SpoolFixture, into collected: Collected) -> SpoolReplayer {
    let server = fixture.server()
    return SpoolReplayer(
        spoolURL: fixture.spoolURL, replayingURL: fixture.replayingURL,
        decode: { [server] in server.decode(line: $0) },
        publish: { message in
            collected.messages.withLock { $0.append(message) }
            return true
        },
        logger: testLogger)
}

@Suite struct SpoolReplayerTests {
    @Test func replaysTheSpoolInFileOrderMarkedReplayedAndDeletesIt() async throws {
        let fixture = try SpoolFixture()
        var data = Data()
        for n in 0..<20 { data.append(try spoolLine("agent.hook", n)) }
        try data.write(to: fixture.spoolURL)
        let collected = Collected()

        let report = await replayer(fixture, into: collected).replayAtLaunch()

        #expect(report == SpoolReplayReport(leftoverLines: 0, newLines: 20, dropped: 0))
        #expect(collected.all.compactMap(number) == Array(0..<20))
        #expect(collected.all.allSatisfy { $0.replayed && $0.topic == "agent.hook" })
        #expect(abs(collected.all[0].sentAt.timeIntervalSince1970 - 1_793_000_000) < 0.001)
        #expect(!FileManager.default.fileExists(atPath: fixture.spoolURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.replayingURL.path))
    }

    @Test func replaysALeftoverReplayingFileFirst() async throws {
        let fixture = try SpoolFixture()
        try (try spoolLine("left", 0) + spoolLine("left", 1)).write(to: fixture.replayingURL)
        try (try spoolLine("new", 2)).write(to: fixture.spoolURL)
        let collected = Collected()

        let report = await replayer(fixture, into: collected).replayAtLaunch()

        #expect(report == SpoolReplayReport(leftoverLines: 2, newLines: 1, dropped: 0))
        #expect(collected.all.map(\.topic) == ["left", "left", "new"])
        #expect(collected.all.compactMap(number) == [0, 1, 2])
        #expect(!FileManager.default.fileExists(atPath: fixture.spoolURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.replayingURL.path))
    }

    @Test func dropsBadLinesAndKeepsTheOthers() async throws {
        let fixture = try SpoolFixture()
        var data = try spoolLine("ok", 0)
        data.append(Data("not json\n".utf8))
        data.append(Data("\n".utf8))
        data.append(try spoolLine("old", 1, v: WireProtocol.version - 2))
        data.append(try spoolLine("ok", 2))
        try data.write(to: fixture.spoolURL)
        let collected = Collected()

        let report = await replayer(fixture, into: collected).replayAtLaunch()

        #expect(report.newLines == 2)
        #expect(report.dropped == 3)
        #expect(collected.all.compactMap(number) == [0, 2])
    }

    @Test func dropsAPartialLastLine() async throws {
        let fixture = try SpoolFixture()
        var data = try spoolLine("ok", 0) + spoolLine("ok", 1)
        var partial = try spoolLine("ok", 2)
        partial.removeLast()
        data.append(partial)
        try data.write(to: fixture.spoolURL)
        let collected = Collected()

        let report = await replayer(fixture, into: collected).replayAtLaunch()

        #expect(report == SpoolReplayReport(leftoverLines: 0, newLines: 2, dropped: 1))
        #expect(collected.all.compactMap(number) == [0, 1])
        #expect(!FileManager.default.fileExists(atPath: fixture.replayingURL.path))
    }

    @Test func nothingToReplayIsANoOp() async throws {
        let fixture = try SpoolFixture()
        let collected = Collected()
        let replayer = replayer(fixture, into: collected)
        #expect(await replayer.replayAtLaunch() == SpoolReplayReport())
        #expect(collected.all.isEmpty)
    }

    @Test func keepsTheFileWhenTheReceiverRefuses() async throws {
        let fixture = try SpoolFixture()
        try (try spoolLine("ok", 0) + spoolLine("ok", 1)).write(to: fixture.spoolURL)
        let server = fixture.server()
        let refusing = SpoolReplayer(
            spoolURL: fixture.spoolURL, replayingURL: fixture.replayingURL,
            decode: { server.decode(line: $0) }, publish: { _ in false }, logger: testLogger)

        let report = await refusing.replayAtLaunch()

        #expect(report.published == 0)
        #expect(FileManager.default.fileExists(atPath: fixture.replayingURL.path))
        // The next launch picks it up as a leftover.
        let collected = Collected()
        let next = replayer(fixture, into: collected)
        #expect(await next.replayAtLaunch().leftoverLines == 2)
    }

    /// The writer holds the lock when the app renames: the rename waits, the line lands in the renamed file.
    @Test func writerHoldingTheLockDuringTheRenameIsReplayedOnce() async throws {
        let fixture = try SpoolFixture()
        try (try spoolLine("w", 0)).write(to: fixture.spoolURL)
        let collected = Collected()
        let replayer = replayer(fixture, into: collected)

        let holder = open(fixture.spoolURL.path, O_WRONLY | O_APPEND)
        #expect(flock(holder, LOCK_EX) == 0)
        let pass = Task.detached { await replayer.replayAtLaunch() }
        try await Task.sleep(for: .milliseconds(150))
        // The rename is blocked on our lock: the spool is still in place.
        #expect(FileManager.default.fileExists(atPath: fixture.spoolURL.path))
        let line = try spoolLine("w", 1)
        _ = line.withUnsafeBytes { write(holder, $0.baseAddress, $0.count) }
        flock(holder, LOCK_UN)
        close(holder)

        let report = await pass.value
        #expect(report.newLines == 2)
        #expect(collected.all.compactMap(number) == [0, 1])
        #expect(await replayer.replayAtLaunch() == SpoolReplayReport())
    }

    /// The writer opened the spool before the rename but locks after it: it reopens a new `spool.jsonl`,
    /// and the next pass replays its line, exactly once.
    @Test func writerThatOpenedBeforeTheRenameLandsInTheNewSpool() async throws {
        let fixture = try SpoolFixture()
        try (try spoolLine("w", 0)).write(to: fixture.spoolURL)
        let collected = Collected()
        let replayer = replayer(fixture, into: collected)
        let url = fixture.spoolURL

        let renamed = DispatchSemaphore(value: 0)
        let opened = Mutex(false)
        let line = try spoolLine("w", 1)
        let writer = Task.detached {
            spoolAppend(line, to: url) {
                opened.withLock { $0 = true }
                renamed.wait()
            }
        }
        #expect(await eventually { opened.withLock { $0 } })
        let first = await replayer.replayAtLaunch()
        renamed.signal()
        #expect(await writer.value)
        let second = await replayer.replayAtLaunch()

        #expect(first.newLines == 1)
        #expect(second.newLines == 1)
        #expect(collected.all.compactMap(number) == [0, 1])
    }
}

@Suite struct EventServerSpoolTests {
    @Test func replayedLinesReachTheBusBeforeQueuedSocketLines() async throws {
        let fixture = try SpoolFixture()
        let server = fixture.server()
        try server.start(lockHeld: fixture.lock)
        defer { server.stop() }
        let inbox = BusInbox(fixture.bus)

        try sendLine(try spoolLine("live", 100), to: fixture.environment.socketURL.path)
        #expect(await eventually { server.queuedCount == 1 })
        #expect(spoolAppend(try spoolLine("spooled", 0), to: fixture.spoolURL))
        #expect(spoolAppend(try spoolLine("spooled", 1), to: fixture.spoolURL))

        let report = await server.finishStartup(spool: fixture.locations)

        #expect(report.newLines == 2)
        #expect(server.queuedCount == 0)
        #expect(await eventually { inbox.all.count == 3 })
        #expect(inbox.topics == ["spooled", "spooled", "live"])
        #expect(inbox.all.map(\.replayed) == [true, true, false])
        #expect(await server.finishStartup(spool: fixture.locations) == SpoolReplayReport())
    }

    @Test func drainsASpoolThatAppearsWhileRunning() async throws {
        let fixture = try SpoolFixture()
        let server = fixture.server()
        try server.start(lockHeld: fixture.lock)
        defer { server.stop() }
        let inbox = BusInbox(fixture.bus)
        _ = await server.finishStartup(spool: fixture.locations)
        // Let the initial post-startup pass run, so only the directory watch can pick the spool up.
        try await Task.sleep(for: .milliseconds(300))

        let appended = ContinuousClock.now
        #expect(spoolAppend(try spoolLine("late", 7), to: fixture.spoolURL))

        // Directory watch + 250 ms debounce, well under the 30 s safety timer.
        #expect(await eventually(timeout: .seconds(5)) { inbox.all.count == 1 })
        // Debounced, not immediate.
        #expect(ContinuousClock.now - appended >= .milliseconds(200))
        #expect(inbox.all.first?.replayed == true)
        #expect(inbox.all.compactMap(number) == [7])
        let spoolPath = fixture.spoolURL.path
        #expect(await eventually { !FileManager.default.fileExists(atPath: spoolPath) })
        #expect(!FileManager.default.fileExists(atPath: fixture.replayingURL.path))
    }

    @Test func liveAndSpoolLinesShareTheDecodingRules() throws {
        let fixture = try SpoolFixture()
        let server = fixture.server()
        #expect(server.decode(line: try spoolLine("ok", 1)) != nil)
        #expect(server.decode(line: try spoolLine("old", 1, v: WireProtocol.version - 2)) == nil)
        #expect(server.decode(line: Data("{}".utf8)) == nil)
        #expect(server.decode(line: Data()) == nil)
    }

    @Test func stopDuringRuntimeDrainLosesNothing() async throws {
        let fixture = try SpoolFixture()
        let inbox = BusInbox(fixture.bus)
        var sent = 0
        for _ in 0..<3 {
            let server = fixture.server()
            try server.start(lockHeld: fixture.lock)
            _ = await server.finishStartup(spool: fixture.locations)
            for _ in 0..<50 {
                #expect(spoolAppend(try spoolLine("s", sent), to: fixture.spoolURL))
                sent += 1
            }
            try await Task.sleep(for: .milliseconds(240))
            server.stop()
        }
        let last = fixture.server()
        try last.start(lockHeld: fixture.lock)
        defer { last.stop() }
        _ = await last.finishStartup(spool: fixture.locations)
        #expect(await eventually { inbox.all.count >= sent })
        try await Task.sleep(for: .milliseconds(100))
        #expect(inbox.all.compactMap(number).sorted() == Array(0..<sent))
    }
}

private func sendLine(_ data: Data, to path: String) throws {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(fd) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }
    _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
}
