import Darwin
import Foundation
import Synchronization
import Testing
import Wire

@testable import VigieCore

@Suite struct SocketListenerTests {
    @Test func bindsWith0600AndDecodesLines() async throws {
        let path = "/tmp/vc-\(UUID().uuidString.prefix(8)).sock"
        FileManager.default.createFile(atPath: path, contents: Data("stale".utf8))
        let received = Mutex<[Envelope]>([])
        let errors = Mutex(0)
        let listener = try SocketListener(
            path: path,
            onError: { _ in errors.withLock { $0 += 1 } },
            onEnvelope: { envelope in received.withLock { $0.append(envelope) } })
        listener.start()
        defer { listener.stop() }

        var info = stat()
        #expect(stat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)
        #expect(info.st_mode & S_IFMT == S_IFSOCK)

        let first = Envelope(
            topic: Topic.agentHook, sentAt: Date(timeIntervalSince1970: 1_793_000_000.5),
            payload: .object(["n": .number(1)]))
        let second = Envelope(topic: "x", sentAt: Date(timeIntervalSince1970: 1_793_000_001), payload: .null)
        var bytes = try first.encodeLine()
        bytes.append(Data("not json\n".utf8))
        bytes.append(try second.encodeLine())
        try send(bytes, to: path)

        for _ in 0..<100 where received.withLock({ $0.count }) < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(received.withLock { $0 } == [first, second])
        #expect(errors.withLock { $0 } == 1)
    }

    private func send(_ data: Data, to path: String) throws {
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
}
