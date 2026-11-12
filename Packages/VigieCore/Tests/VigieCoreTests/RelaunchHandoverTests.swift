import Darwin
import Foundation
import Testing
import Wire

@testable import VigieCore

/// AD-21 handover when Sparkle relaunches Vigie after an update (Story 6.3): the old instance quits through
/// `applicationShouldTerminate` (Event Server stopped, socket unlinked) and `applicationWillTerminate` (instance lock
/// released); events sent in the gap are spooled by the CLI; the new instance takes the lock, binds the socket and
/// replays the spool before `host.ready`. Nothing is lost and nothing is delivered twice.
@Suite struct RelaunchHandoverTests {
    @Test func newInstanceTakesOverAfterTheOldOneExitsWithoutLosingEvents() async throws {
        let fixture = try SpoolFixture()  // holds the old instance's lock
        let socketPath = fixture.environment.socketURL.path
        let inbox = BusInbox(fixture.bus)

        // Old instance, running.
        let old = fixture.server()
        try old.start(lockHeld: fixture.lock)
        _ = await old.finishStartup(spool: fixture.locations)
        #expect(sendHandoverLine(try spoolLine("before", 0), to: socketPath))
        #expect(await eventually { inbox.all.count == 1 })

        // The relaunched app starts while the old one is still quitting: the lock stops it from touching the socket.
        #expect(throws: InstanceLockError.alreadyHeld) {
            try InstanceLock.acquire(at: fixture.environment.instanceLockURL)
        }

        // Old instance quits: applicationShouldTerminate stops the server, applicationWillTerminate releases the lock.
        old.stop()
        fixture.lock.release()
        #expect(!FileManager.default.fileExists(atPath: socketPath))

        // The gap: the CLI cannot connect, so it spools (VigieCLI `Spool.append`).
        #expect(!sendHandoverLine(try spoolLine("gap", 1), to: socketPath))
        #expect(spoolAppend(try spoolLine("gap", 1), to: fixture.spoolURL))
        #expect(spoolAppend(try spoolLine("gap", 2), to: fixture.spoolURL))

        // New instance: lock, socket, spool replay (AD-6 steps 4-6).
        let newLock = try InstanceLock.acquire(at: fixture.environment.instanceLockURL)
        defer { newLock.release() }
        let new = fixture.server()
        try new.start(lockHeld: newLock)
        defer { new.stop() }
        let report = await new.finishStartup(spool: fixture.locations)
        #expect(report.newLines == 2)
        #expect(sendHandoverLine(try spoolLine("after", 3), to: socketPath))

        #expect(await eventually { inbox.all.count == 4 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(inbox.topics == ["before", "gap", "gap", "after"])
        #expect(inbox.all.compactMap(number) == [0, 1, 2, 3])
        #expect(inbox.all.map(\.replayed) == [false, true, true, false])
        #expect(!FileManager.default.fileExists(atPath: fixture.spoolURL.path))
    }

    @Test func oldInstanceStoppingLateNeverUnlinksTheNewSocket() throws {
        let fixture = try SpoolFixture()
        let old = fixture.server()
        try old.start(lockHeld: fixture.lock)
        // A new socket at the same path (the new instance's, after a lock handover): the old one must leave it.
        old.stop()
        fixture.lock.release()
        let newLock = try InstanceLock.acquire(at: fixture.environment.instanceLockURL)
        defer { newLock.release() }
        let new = fixture.server()
        try new.start(lockHeld: newLock)
        defer { new.stop() }
        old.stop()  // idempotent: a second stop from applicationWillTerminate
        #expect(FileManager.default.fileExists(atPath: fixture.environment.socketURL.path))
        #expect(new.isRunning)
    }
}

/// Connects and writes one line; false when nothing listens (the CLI then spools).
private func sendHandoverLine(_ data: Data, to path: String) -> Bool {
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
    guard connected == 0 else { return false }
    return data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == data.count
}
