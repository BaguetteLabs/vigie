import Darwin
import Foundation
import Testing

@testable import AgentKit

@Suite struct ProcessLivenessTests {
    let liveness = SystemProcessLiveness()

    @Test func ownProcessIsAliveWithItsStartTime() throws {
        let pid = getpid()
        let start = try #require(SystemProcessLiveness.startTime(of: pid))
        #expect(start < Date())
        #expect(liveness.isAlive(AgentProcessRef(pid: pid, startTime: start)))
        // Through the Wire format (milliseconds), as stored in sessions.json.
        let rounded = Date(timeIntervalSince1970: (start.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
        #expect(liveness.isAlive(AgentProcessRef(pid: pid, startTime: rounded)))
        #expect(liveness.isAlive(AgentProcessRef(pid: pid, startTime: nil)))
    }

    @Test func startTimeMismatchIsARecycledPid() throws {
        let pid = getpid()
        let start = try #require(SystemProcessLiveness.startTime(of: pid))
        #expect(!liveness.isAlive(AgentProcessRef(pid: pid, startTime: start.addingTimeInterval(-60))))
        #expect(!liveness.isAlive(AgentProcessRef(pid: pid, startTime: start.addingTimeInterval(2))))
    }

    @Test func exitedProcessIsDead() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        let pid = process.processIdentifier
        #expect(SystemProcessLiveness.startTime(of: pid) == nil)
        #expect(!liveness.isAlive(AgentProcessRef(pid: pid, startTime: nil)))
    }

    @Test func invalidPidsAreDead() {
        #expect(!liveness.isAlive(AgentProcessRef(pid: 0, startTime: nil)))
        #expect(!liveness.isAlive(AgentProcessRef(pid: -1, startTime: nil)))
        #expect(!liveness.isAlive(AgentProcessRef(pid: 99_999_999, startTime: nil)))
    }
}
