import Darwin
import Foundation
import ModuleKit
import Synchronization
import Testing
import Wire

@testable import VigieCore

/// CI floor (Story 4.2, AD-6): 1,000 events written by concurrent real `vigie event` processes while the
/// Event Server goes through restart cycles; every event is published exactly once.
///
/// Driven by `Scripts/spool-floor-test.sh`, which builds the CLI (debug, so the dev `AppEnvironment`) and
/// passes it in `VIGIE_CLI_BIN`. Skipped without it, so a plain `swift test` stays fast.
///
/// Each CLI child runs with `CFFIXED_USER_HOME` set to a short scratch home, so its app support folder (and
/// therefore its socket and spool) lies there. Nothing listens on that socket, so every event spools. The
/// test server binds a different socket and replays the child's spool.
private let floorBinaryVariable = "VIGIE_CLI_BIN"

@Suite(.enabled(if: ProcessInfo.processInfo.environment[floorBinaryVariable] != nil))
struct SpoolFloorTests {
    static let binaryVariable = floorBinaryVariable
    static let events = 1_000
    static let writers = 8
    static let topic = "floor.test"

    /// The dev environment a CLI child sees with `CFFIXED_USER_HOME = home`, derived from this process's
    /// own app support folder location relative to its home (no path literals, AD-17).
    static func childEnvironment(home: URL) throws -> AppEnvironment {
        let realHome = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let support = try #require(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ).standardizedFileURL.path
        try #require(support.hasPrefix(realHome))
        let relative = String(support.dropFirst(realHome.count))
        let probe = AppEnvironment(flavor: .dev)
        let childSupport = URL(fileURLWithPath: home.path + relative, isDirectory: true)
            .appendingPathComponent(probe.displayName, isDirectory: true)
        return AppEnvironment(
            flavor: .dev, applicationSupportURL: childSupport, configFolderOverride: home,
            homeDirectoryURL: home)
    }

    @Test func thousandEventsAcrossRestartCyclesNoLossNoDuplicates() async throws {
        let binary = try #require(ProcessInfo.processInfo.environment[Self.binaryVariable])
        // Short, so the child's socket path stays inside its app support folder (never the shared
        // temp-dir fallback, which a running dev app could own).
        var template = Array("/tmp/vf.XXXXXX".utf8CString)
        let homePath = try #require(
            template.withUnsafeMutableBufferPointer { mkdtemp($0.baseAddress) }.map {
                String(cString: $0)
            })
        let home = URL(fileURLWithPath: homePath, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let child = try Self.childEnvironment(home: home)
        try #require(
            child.socketURL.path.hasPrefix(home.path), "child socket path too long; it would use the shared fallback")
        try #require(!FileManager.default.fileExists(atPath: child.socketURL.path))

        let server = try SpoolFixture()
        let inbox = BusInbox(server.bus, prefix: Self.topic)
        let spool = SpoolLocations(environment: child)
        var environment = ProcessInfo.processInfo.environment
        environment["CFFIXED_USER_HOME"] = home.path

        // Writers on dispatch threads: each blocks in `waitUntilExit`, which must not hold a cooperative thread.
        let failures = Mutex<[String]>([])
        let done = Mutex(false)
        let group = DispatchGroup()
        for writer in 0..<Self.writers {
            DispatchQueue.global().async(group: group) {
                var n = writer
                while n < Self.events {
                    if let failure = Self.runCLI(binary, n: n, environment: environment) {
                        failures.withLock { $0.append(failure) }
                    }
                    n += Self.writers
                }
            }
        }
        group.notify(queue: .global()) { done.withLock { $0 = true } }

        // Restart cycles while the writers run: start → finishStartup (replay + watch) → run → stop.
        var cycles = 0
        while !done.withLock({ $0 }) {
            let eventServer = server.server()
            try eventServer.start(lockHeld: server.lock)
            _ = await eventServer.finishStartup(spool: spool)
            try await Task.sleep(for: .milliseconds(Int.random(in: 20...400)))
            eventServer.stop()
            cycles += 1
            try await Task.sleep(for: .milliseconds(Int.random(in: 0...150)))
        }

        // Final launch picks up whatever was spooled after the last stop.
        let last = server.server()
        try last.start(lockHeld: server.lock)
        defer { last.stop() }
        _ = await last.finishStartup(spool: spool)

        #expect(failures.withLock { $0 }.isEmpty, "\(failures.withLock { $0.prefix(5) })")
        #expect(await eventually(timeout: .seconds(10)) { inbox.all.count >= Self.events })
        try await Task.sleep(for: .milliseconds(200))
        let values = inbox.all.compactMap(number)
        #expect(cycles >= 3, "only \(cycles) restart cycles")
        #expect(values.count == Self.events, "published \(values.count), expected \(Self.events)")
        let expected = Set(0..<Self.events)
        let received = Set(values)
        let missing = Array(expected.subtracting(received).sorted().prefix(20))
        #expect(received == expected, "missing \(missing)")
        #expect(inbox.all.allSatisfy { $0.replayed })
        #expect(!FileManager.default.fileExists(atPath: spool.spoolURL.path))
        #expect(!FileManager.default.fileExists(atPath: spool.replayingURL.path))
        print("spool floor: \(Self.events) events, \(Self.writers) writers, \(cycles) restart cycles")
    }

    /// Runs `<binary> event floor.test {"n": n}`; nil on exit 0 with no output.
    private static func runCLI(_ binary: String, n: Int, environment: [String: String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["event", topic, #"{"n": \#(n)}"#]
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return "n=\(n): launch failed: \(error)"
        }
        let text = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return "n=\(n): exit \(process.terminationStatus): \(String(decoding: text, as: UTF8.self))"
        }
        return nil
    }
}
