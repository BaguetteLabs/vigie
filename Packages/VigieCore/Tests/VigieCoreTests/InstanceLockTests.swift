import Foundation
import Testing

@testable import VigieCore

@Suite struct InstanceLockTests {
    private func lockURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vigie-lock-\(UUID().uuidString)/nested/instance.lock")
    }

    @Test func acquireCreatesParentDirectoryWithPrivateMode() throws {
        let url = lockURL()
        let lock = try InstanceLock.acquire(at: url)
        defer { lock.release() }
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDir))
        #expect(isDir.boolValue)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attrs[.posixPermissions] as? Int).map { $0 & 0o077 } == 0)
    }

    @Test func secondAcquireThrowsAlreadyHeldUntilRelease() throws {
        let url = lockURL()
        let first = try InstanceLock.acquire(at: url)
        #expect(throws: InstanceLockError.alreadyHeld) { try InstanceLock.acquire(at: url) }
        first.release()
        first.release()  // idempotent
        let second = try InstanceLock.acquire(at: url)
        second.release()
    }

    @Test func deinitReleasesLock() throws {
        let url = lockURL()
        do { _ = try InstanceLock.acquire(at: url) }
        let again = try InstanceLock.acquire(at: url)
        again.release()
    }
}
