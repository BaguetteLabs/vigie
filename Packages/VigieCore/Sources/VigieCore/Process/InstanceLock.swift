import Darwin
import Foundation

public enum InstanceLockError: Error, Equatable {
    /// Another open file description already holds the exclusive lock.
    case alreadyHeld
    /// A system call failed; `errno` value attached.
    case system(operation: String, code: Int32)
}

/// Exclusive, non-blocking `flock` on the instance lock file (AD-21).
///
/// `flock` locks belong to the open file description, so a second `open` contends even
/// inside one process. The kernel drops the lock if the process dies.
public final class InstanceLock: @unchecked Sendable {
    private let mutex = NSLock()
    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    public static func acquire(at url: URL) throws -> InstanceLock {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw InstanceLockError.system(operation: "createDirectory", code: Int32((error as NSError).code))
        }
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw InstanceLockError.system(operation: "open", code: errno) }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK { throw InstanceLockError.alreadyHeld }
            throw InstanceLockError.system(operation: "flock", code: code)
        }
        return InstanceLock(descriptor: fd)
    }

    /// Unlocks and closes the file. Idempotent.
    public func release() {
        mutex.lock()
        defer { mutex.unlock() }
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        if descriptor >= 0 {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
    }
}
