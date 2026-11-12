import Darwin
import Foundation
import ModuleKit
import Testing

@testable import Integrations

/// The production launcher with real, tiny `/bin/sh` scripts (absolute path, as the process-launch guard
/// requires). Timeouts are sub-second.
@Suite struct RunnerProcessTests {
    let sh = URL(fileURLWithPath: "/bin/sh")

    /// A scratch folder with `script` written in it as `run.sh`.
    func folder(_ script: String) throws -> (folder: URL, file: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "runner-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("run.sh")
        try Data(script.utf8).write(to: file)
        return (folder, file)
    }

    func request(_ file: URL, in folder: URL, environment: [String: String] = [:], timeout: Duration = .seconds(5))
        -> ScriptLaunchRequest
    {
        ScriptLaunchRequest(
            executable: sh, arguments: [file.path], environment: environment, workingDirectory: folder,
            timeout: timeout, scratchDirectory: folder)
    }

    @Test func capturesStdoutStderrExitCodeEnvironmentAndWorkingDirectory() async throws {
        let (folder, file) = try folder(
            """
            echo "out:$VIGIE_SETTING_X:$PWD:${INHERITED-unset}"
            cat
            echo "problem" >&2
            exit 3
            """)
        defer { try? FileManager.default.removeItem(at: folder) }
        setenv("INHERITED", "leak", 1)
        defer { unsetenv("INHERITED") }
        let result = try await ScriptProcessLauncher().launch(
            request(file, in: folder, environment: ["VIGIE_SETTING_X": "42", "PATH": "/usr/bin:/bin"]))
        #expect(result.termination == .exited(3))
        let stdout = String(decoding: result.stdout, as: UTF8.self)
        // stdin is /dev/null (cat returns at once); nothing is inherited from this process. `$PWD` is the real
        // path (`/private/var/...`).
        #expect(stdout.hasPrefix("out:42:/"), "\(stdout)")
        #expect(stdout.hasSuffix("/\(folder.lastPathComponent):unset\n"), "\(stdout)")
        #expect(String(decoding: result.stderr, as: UTF8.self) == "problem\n")
        // Captured output files are removed.
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(left == ["run.sh"])
    }

    @Test func theChildRunsInItsOwnProcessGroup() async throws {
        let (folder, file) = try folder(#"ps -o pgid= -p $$; echo $$"#)
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await ScriptProcessLauncher().launch(
            request(file, in: folder, environment: ["PATH": "/usr/bin:/bin"]))
        let lines = String(decoding: result.stdout, as: UTF8.self).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.count == 2)
        #expect(lines.first == lines.last)
        #expect(lines.first != String(getpgrp()))
    }

    @Test func aTimeoutKillsTheWholeProcessGroup() async throws {
        let (folder, file) = try folder(
            """
            /bin/sleep 30 &
            echo $! > "$PIDFILE"
            wait
            """)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pidFile = folder.appendingPathComponent("grandchild.pid")
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await ScriptProcessLauncher().launch(
            request(file, in: folder, environment: ["PIDFILE": pidFile.path], timeout: .milliseconds(300)))
        #expect(result.termination == .timedOut)
        #expect(clock.now - start < .seconds(5))

        let text = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let grandchild = try #require(pid_t(text))
        var gone = false
        for _ in 0..<200 {
            if kill(grandchild, 0) == -1 && errno == ESRCH {
                gone = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(gone, "grandchild \(grandchild) still alive")
        if !gone { kill(grandchild, SIGKILL) }
    }

    @Test func cancellingTheCallerKillsTheGroup() async throws {
        let (folder, file) = try folder("/bin/sleep 30")
        defer { try? FileManager.default.removeItem(at: folder) }
        let request = request(file, in: folder, timeout: .seconds(30))
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task { try await ScriptProcessLauncher().launch(request) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        _ = try await task.value
        #expect(clock.now - start < .seconds(5))
    }

    @Test func aRelativeExecutableIsRefused() async throws {
        var request = request(URL(fileURLWithPath: "/dev/null"), in: FileManager.default.temporaryDirectory)
        request.executable = URL(string: "sh")!
        await #expect(throws: ScriptLaunchError.self) { try await ScriptProcessLauncher().launch(request) }
    }

    @MainActor
    @Test func theRunnerRunsARealScriptEndToEnd() async throws {
        let modules = FileManager.default.temporaryDirectory.appendingPathComponent(
            "runner-modules-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        let scratch = modules.appendingPathComponent("scratch", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: modules) }
        let log = LogSink()
        let runner = ScriptRunner(
            dependencies: ScriptRunner.Dependencies(
                executables: FakeResolver(["sh": sh], searchPath: ["/usr/bin", "/bin"]),
                secrets: FakeSecretStore(["e2e.script.token": "tok"]), scheduler: FakeScheduler(),
                launcher: ScriptProcessLauncher(), scratchDirectory: scratch, workingDirectory: modules,
                configuredValue: { _, _ in nil }, home: NSHomeDirectory(), language: nil, now: { Date() },
                log: { log.append($0) }),
            isEligible: { _ in true })
        let code = #"""
            [ "$VIGIE_SETTING_TOKEN" = tok ] || exit 9
            echo "warn $VIGIE_SETTING_LIMIT" >&2
            printf '{"widget":{"type":"text","value":"%s"}}' "$VIGIE_SETTING_LIMIT"
            """#
        let data = runnerScript(
            id: "e2e.script", interval: "1s", runtime: "sh", widget: "text",
            settings: [
                #"{ key: token, type: secret, label: "T" }"#, #"{ key: limit, type: int, label: "L", default: 7 }"#,
            ], language: "sh", code: code)
        runner.update([runnerDefinition(data, name: "e2e.md")])
        await runner.waitForIdle()
        let state = try #require(runner.states["e2e.md"])
        guard case .ok(let output, _) = state.phase else {
            Issue.record("expected ok, got \(state.phase); log: \(log.text)")
            await runner.stop()
            return
        }
        #expect(output.widget.value == "7")
        #expect(state.records.first?.stderrExcerpt == "warn 7")
        #expect(state.records.first?.duration ?? .zero > .zero)
        // The code file and captured output are gone.
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty)
        let attributes = try FileManager.default.attributesOfItem(atPath: scratch.path)
        #expect(attributes[.posixPermissions] as? Int == 0o700)
        await runner.stop()
    }
}
