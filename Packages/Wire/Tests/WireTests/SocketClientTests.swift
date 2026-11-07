import Darwin
import Foundation
import Testing
import Wire

@Suite struct SocketClientTests {
    /// A short socket path (sun_path is 104 bytes).
    static func socketPath() -> String { "/tmp/wsc-\(UUID().uuidString.prefix(8)).sock" }

    /// Binds and listens on `path`; returns the listening descriptor.
    static func listen(at path: String) throws -> Int32 {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 4) == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        return fd
    }

    @Test func sendsLineToListener() throws {
        let path = Self.socketPath()
        let listener = try Self.listen(at: path)
        defer {
            close(listener)
            unlink(path)
        }
        let line = Data("{\"hello\":1}\n".utf8)
        #expect(SocketClient.send(line, toSocketAt: path, deadline: .now.advanced(by: .milliseconds(500))))
        let client = accept(listener, nil, nil)
        #expect(client >= 0)
        defer { close(client) }
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 { break }
            received.append(contentsOf: buffer[0..<count])
        }
        #expect(received == line)
    }

    @Test func returnsFalseWhenNothingListens() {
        let path = Self.socketPath()
        let start = ContinuousClock.now
        #expect(
            !SocketClient.send(Data("x\n".utf8), toSocketAt: path, deadline: start.advanced(by: .milliseconds(200))))
        #expect(start.duration(to: .now) < .milliseconds(200))
    }

    @Test func returnsFalseForOverlongPath() {
        let path = "/tmp/" + String(repeating: "a", count: 120)
        #expect(!SocketClient.send(Data("x\n".utf8), toSocketAt: path, deadline: .now.advanced(by: .milliseconds(50))))
    }

    @Test func returnsFalseByDeadlineWhenPeerNeverReads() throws {
        let path = Self.socketPath()
        let listener = try Self.listen(at: path)
        defer {
            close(listener)
            unlink(path)
        }
        // Far larger than the socket buffers: the write stalls because nobody accepts or reads.
        let line = Data(repeating: 0x61, count: 8 << 20)
        let start = ContinuousClock.now
        #expect(!SocketClient.send(line, toSocketAt: path, deadline: start.advanced(by: .milliseconds(150))))
        let elapsed = start.duration(to: .now)
        #expect(elapsed >= .milliseconds(140))
        #expect(elapsed < .milliseconds(1000))
    }
}
