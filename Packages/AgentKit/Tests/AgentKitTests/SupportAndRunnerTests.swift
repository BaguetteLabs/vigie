import Foundation
import Testing

@testable import AgentKit

@Suite struct VersionSupportMatrixTests {
    static let matrix = VersionSupportMatrix(
        testedRanges: [AgentVersion.Semver(2, 1, 0)...AgentVersion.Semver(2, 1, 319)], assumesNewerPatches: true)

    @Test(arguments: [
        ("2.1.319 (Claude Code)", "supported"),
        ("2.1.0", "supported"),
        ("2.1.400", "assumed"),
        ("2.2.0", "unsupported"),
        ("2.0.999", "unsupported"),
        ("1.9.0", "unsupported"),
        ("garbage", "unsupported"),
    ])
    func classifies(raw: String, expected: String) {
        let version = AgentVersion(raw: raw)
        let support = Self.matrix.support(for: version)
        let label =
            switch support {
            case .supported: "supported"
            case .assumed: "assumed"
            case .unsupported: "unsupported"
            case .notInstalled: "notInstalled"
            }
        #expect(label == expected)
        #expect(support.version == version)
        #expect(support.emitsEvents == (expected == "supported" || expected == "assumed"))
    }

    @Test func nilIsNotInstalled() {
        #expect(Self.matrix.support(for: nil) == .notInstalled)
        #expect(!AdapterSupport.notInstalled.emitsEvents)
        #expect(AdapterSupport.notInstalled.version == nil)
    }

    @Test func strictMatrixRejectsNewerPatch() {
        let strict = VersionSupportMatrix(testedRanges: Self.matrix.testedRanges, assumesNewerPatches: false)
        #expect(!strict.support(for: AgentVersion(raw: "2.1.400")).emitsEvents)
    }

    @Test func gatedNormalizeDropsEventsWhenUnsupported() {
        let hook = HookPayload(
            agent: "fake", raw: .object(["session_id": .string("s")]), tty: nil, env: [:], ancestors: [])
        let version = AgentVersion(raw: "9.9.9")
        #expect(FakeAdapter().normalize(hook, sentAt: .now, support: .unsupported(version)).isEmpty)
        #expect(FakeAdapter().normalize(hook, sentAt: .now, support: .notInstalled).isEmpty)
        #expect(FakeAdapter().normalize(hook, sentAt: .now, support: .assumed(version)).count == 1)
    }
}

@Suite struct IntegrationInputsTests {
    @Test func hookCommandUsesAbsoluteLinkPath() {
        let inputs = IntegrationInputs(
            cliPath: "/Users/romain/.local/bin/vigie-dev", homeDirectory: URL(fileURLWithPath: "/Users/romain"))
        #expect(inputs.hookCommand(for: "claude") == "/Users/romain/.local/bin/vigie-dev hook claude")
    }

    @Test func hookCommandQuotesUnsafePath() {
        let inputs = IntegrationInputs(
            cliPath: "/Users/Jo O'Neil/.local/bin/vigie", homeDirectory: URL(fileURLWithPath: "/Users/Jo O'Neil"))
        #expect(inputs.hookCommand(for: "claude") == "'/Users/Jo O'\\''Neil/.local/bin/vigie' hook claude")
    }
}

@Suite struct SystemProcessRunnerTests {
    @Test func returnsStdout() async throws {
        let output = try await SystemProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/echo"), arguments: ["2.1.319 (Claude Code)"], timeout: .seconds(5)
        )
        #expect(output == "2.1.319 (Claude Code)\n")
    }

    @Test func throwsOnNonZeroExit() async {
        await #expect(throws: ProcessRunnerError.exited(status: 1)) {
            try await SystemProcessRunner().run(
                executableURL: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], timeout: .seconds(5))
        }
    }

    @Test func timesOut() async {
        let start = ContinuousClock.now
        await #expect(throws: ProcessRunnerError.timedOut) {
            try await SystemProcessRunner().run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: .milliseconds(200))
        }
        #expect(ContinuousClock.now - start < .seconds(3))
    }

    @Test func rejectsRelativePath() async {
        await #expect(throws: ProcessRunnerError.notAbsolute("claude")) {
            try await SystemProcessRunner().run(
                executableURL: URL(string: "claude")!, arguments: [], timeout: .seconds(1))
        }
    }
}
