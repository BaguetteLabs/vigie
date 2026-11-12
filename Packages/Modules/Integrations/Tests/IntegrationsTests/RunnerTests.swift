import Foundation
import ModuleKit
import Testing

@testable import Integrations

@MainActor
@Suite struct RunnerTests {
    @Test func runsAtStartThenEveryIntervalWithTheResolvedRuntime() async throws {
        let h = RunnerHarness()
        defer { h.cleanUp() }
        let t0 = h.now.date
        h.runner.update([runnerDefinition(runnerScript(interval: "5m"))])
        #expect(h.state()?.isRunning == true)
        #expect(h.state()?.phase == .waitingFirstRun)
        await h.runner.waitForIdle()

        #expect(h.resolver.lookups == ["python3"])
        let launch = try #require(h.launcher.launches.first)
        #expect(launch.request.executable.path == "/opt/homebrew/bin/python3")
        #expect(launch.request.arguments.count == 1)
        #expect(launch.request.arguments[0].hasPrefix(h.scratch.path))
        #expect(launch.request.arguments[0].hasSuffix(".py"))
        #expect(launch.request.workingDirectory?.path == "/runner-tests/modules")
        #expect(launch.request.timeout == .seconds(30))
        #expect(launch.code == "print('hello')")
        #expect(launch.mode == 0o600)

        let state = try #require(h.state())
        #expect(state.isRunning == false)
        guard case .ok(let output, _) = state.phase else {
            Issue.record("expected ok, got \(state.phase)")
            return
        }
        #expect(output.widget.value == "3")
        #expect(state.nextRunAt == t0.addingTimeInterval(300))
        #expect(h.scheduler.liveOneShots.count == 1)
        #expect(h.scheduler.liveOneShots.first?.date == t0.addingTimeInterval(300))
        // The code file is gone after the run.
        #expect((try? FileManager.default.contentsOfDirectory(atPath: h.scratch.path))?.isEmpty ?? true)

        h.now.advance(300)
        await h.fireNext()
        #expect(h.launcher.count == 2)
        #expect(h.state()?.records.count == 2)
        #expect(h.scheduler.liveOneShots.first?.date == t0.addingTimeInterval(600))
        await h.runner.stop()
    }

    @Test func refreshRunsAtOnceAndReschedules() async {
        let h = RunnerHarness()
        defer { h.cleanUp() }
        h.runner.update([runnerDefinition(runnerScript())])
        await h.runner.waitForIdle()
        let firstJob = h.scheduler.liveOneShots.first
        h.now.advance(42)
        h.runner.refresh(id: "test.md")
        #expect(h.state()?.isRunning == true)
        #expect(h.state()?.nextRunAt == nil)
        #expect(firstJob?.cancelled == true)
        await h.runner.waitForIdle()
        #expect(h.launcher.count == 2)
        #expect(h.scheduler.liveOneShots.count == 1)
        #expect(h.scheduler.liveOneShots.first?.date == h.now.date.addingTimeInterval(300))

        h.runner.refreshAll()
        await h.runner.waitForIdle()
        #expect(h.launcher.count == 3)
        // An unknown id is ignored.
        h.runner.refresh(id: "nope.md")
        await h.runner.waitForIdle()
        #expect(h.launcher.count == 3)
        await h.runner.stop()
    }

    @Test func runsOfOneScriptNeverOverlap() async {
        let launcher = FakeLauncher()
        launcher.hold = true
        let h = RunnerHarness(launcher: launcher)
        defer { h.cleanUp() }
        h.runner.update([runnerDefinition(runnerScript())])
        #expect(await h.until { launcher.waiting == 1 })
        h.runner.refresh(id: "test.md")
        h.runner.refreshAll()
        await h.scheduler.fireNext()  // nothing scheduled while running
        try? await Task.sleep(for: .milliseconds(20))
        #expect(launcher.count == 1)
        #expect(h.scheduler.liveOneShots.isEmpty)
        launcher.release()
        await h.runner.waitForIdle()
        #expect(launcher.count == 1)
        #expect(h.state()?.isRunning == false)
        #expect(h.state()?.records.count == 1)
        await h.runner.stop()
    }

    @Test func settingsArePassedAsEnvironmentVariables() async throws {
        let secrets = FakeSecretStore(["test.script.token": "s3cr3t-value"])
        let h = RunnerHarness(
            secrets: secrets,
            configured: { id, key in
                guard id == "test.script" else { return nil }
                switch key {
                case "repo": return "me/configured"
                case "every": return Duration.seconds(90)
                case "tags": return ["a", "b c"]
                default: return nil
                }
            })
        defer { h.cleanUp() }
        let settings = [
            #"{ key: token, type: secret, label: "Token" }"#,
            #"{ key: repo, type: string, label: "Repo", default: "me/default" }"#,
            #"{ key: warn_at, type: int, label: "Warn", default: 5 }"#,
            #"{ key: ratio, type: double, label: "Ratio", default: 0.5 }"#,
            #"{ key: verbose, type: bool, label: "Verbose" }"#,
            #"{ key: mode, type: enum, label: "Mode", options: [fast, slow], default: slow }"#,
            #"{ key: every, type: duration, label: "Every", default: 1h30m }"#,
            #"{ key: tags, type: list, label: "Tags" }"#,
            #"{ key: folder, type: path, label: "Folder" }"#,
        ]
        h.runner.update([runnerDefinition(runnerScript(settings: settings))])
        await h.runner.waitForIdle()
        let environment = try #require(h.launcher.launches.first?.request.environment)
        #expect(
            environment == [
                "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
                "HOME": "/Users/tester",
                "LANG": "fr_FR.UTF-8",
                "VIGIE_SETTING_TOKEN": "s3cr3t-value",
                "VIGIE_SETTING_REPO": "me/configured",
                "VIGIE_SETTING_WARN_AT": "5",
                "VIGIE_SETTING_RATIO": "0.5",
                "VIGIE_SETTING_VERBOSE": "false",
                "VIGIE_SETTING_MODE": "slow",
                "VIGIE_SETTING_EVERY": "1m30s",
                "VIGIE_SETTING_TAGS": #"["a","b c"]"#,
            ])
        #expect(secrets.reads == ["test.script.token"])
        await h.runner.stop()
    }

    @Test func secretsStayOutOfTheCodeFileTheLogAndTheRecord() async throws {
        let launcher = FakeLauncher(results: [
            launchResult(.exited(1), stdout: Data(), stderr: "auth failed with s3cr3t-value\n")
        ])
        let h = RunnerHarness(launcher: launcher, secrets: FakeSecretStore(["test.script.token": "s3cr3t-value"]))
        defer { h.cleanUp() }
        let script = runnerScript(settings: [#"{ key: token, type: secret, label: "Token" }"#])
        h.runner.update([runnerDefinition(script)])
        await h.runner.waitForIdle()
        let launch = try #require(launcher.launches.first)
        #expect(launch.request.environment["VIGIE_SETTING_TOKEN"] == "s3cr3t-value")
        #expect(!launch.code.contains("s3cr3t"))
        #expect(!h.log.text.contains("s3cr3t"))
        #expect(h.log.text.contains("auth failed with ••••"))
        #expect(h.state()?.records.first?.stderrExcerpt == "auth failed with ••••")
        await h.runner.stop()
    }

    @Test func aMissingSecretLeavesItsVariableUnset() async throws {
        let h = RunnerHarness()
        defer { h.cleanUp() }
        h.runner.update([runnerDefinition(runnerScript(settings: [#"{ key: token, type: secret, label: "T" }"#]))])
        await h.runner.waitForIdle()
        let environment = try #require(h.launcher.launches.first?.request.environment)
        #expect(environment["VIGIE_SETTING_TOKEN"] == nil)
        await h.runner.stop()
    }

    @Test func aTimeoutIsRecordedWithItsSeconds() async throws {
        let launcher = FakeLauncher(results: [launchResult(.timedOut, stdout: Data())])
        let h = RunnerHarness(launcher: launcher)
        defer { h.cleanUp() }
        h.runner.update([runnerDefinition(runnerScript(interval: "5s"))])
        await h.runner.waitForIdle()
        #expect(launcher.launches.first?.request.timeout == .seconds(5))
        let state = try #require(h.state())
        #expect(state.records.first?.outcome == .timedOut(seconds: 5))
        #expect(state.isErrored)
        #expect(ScriptRunLabel.state(state) == "TIMED OUT · 5S")
        #expect(state.records.first.map { ScriptRunLabel.outcome($0.outcome) } == "TIMED OUT · 5S")
        #expect(h.log.text.contains("TIMED OUT · 5S"))
        await h.runner.stop()
    }

    @Test func aNonZeroExitRecordsTheCodeAndLogsStderr() async throws {
        let launcher = FakeLauncher(results: [
            launchResult(.exited(3), stdout: Data(), stderr: "Traceback: boom\n"),
            launchResult(.signaled(9), stdout: Data()),
        ])
        let h = RunnerHarness(launcher: launcher)
        defer { h.cleanUp() }
        h.runner.update([runnerDefinition(runnerScript())])
        await h.runner.waitForIdle()
        let state = try #require(h.state())
        #expect(state.records.first?.outcome == .failed(exitCode: 3))
        #expect(state.records.first?.outcome.exitCode == 3)
        #expect(state.records.first?.stderrExcerpt == "Traceback: boom")
        #expect(ScriptRunLabel.state(state) == "EXIT 3")
        #expect(h.log.text.contains("Traceback: boom"))
        #expect(h.log.text.contains("EXIT 3"))

        h.runner.refresh(id: "test.md")
        await h.runner.waitForIdle()
        #expect(h.state()?.records.first?.outcome == .failed(exitCode: 137))
        await h.runner.stop()
    }

    @Test func invalidOutputKeepsTheLastGoodOutputUntilTheNextGoodRun() async throws {
        let launcher = FakeLauncher(results: [
            launchResult(),
            launchResult(stdout: Data("not json".utf8)),
            launchResult(stdout: Data(#"{"widget":{"type":"number"}}"#.utf8)),
            launchResult(stdout: Data(#"{"widget":{"type":"number","value":"7"}}"#.utf8)),
        ])
        let h = RunnerHarness(launcher: launcher)
        defer { h.cleanUp() }
        h.runner.update([runnerDefinition(runnerScript())])
        await h.runner.waitForIdle()
        let good = try #require(h.state()?.lastGoodOutput)

        h.runner.refresh(id: "test.md")
        await h.runner.waitForIdle()
        var state = try #require(h.state())
        guard case .errored(.invalidOutput(let message), let kept, _) = state.phase else {
            Issue.record("expected invalid output, got \(state.phase)")
            return
        }
        #expect(message == "Standard output is not valid JSON.")
        #expect(kept == good)
        #expect(ScriptRunLabel.state(state) == "INVALID OUTPUT")

        h.runner.refresh(id: "test.md")
        await h.runner.waitForIdle()
        state = try #require(h.state())
        guard case .errored(.invalidOutput(let schemaMessage), let stillKept, _) = state.phase else {
            Issue.record("expected a schema error, got \(state.phase)")
            return
        }
        #expect(schemaMessage.contains("widget.value"))
        #expect(stillKept == good)

        h.runner.refresh(id: "test.md")
        await h.runner.waitForIdle()
        state = try #require(h.state())
        guard case .ok(let output, _) = state.phase else {
            Issue.record("expected ok, got \(state.phase)")
            return
        }
        #expect(output.widget.value == "7")
        #expect(state.records.map(\.outcome.isSuccess) == [true, false, false, true])
        await h.runner.stop()
    }

    @Test func outputOfAnotherWidgetTypeIsInvalid() async throws {
        let launcher = FakeLauncher(results: [
            launchResult(stdout: Data(#"{"widget":{"type":"status","level":"ok"}}"#.utf8))
        ])
        let h = RunnerHarness(launcher: launcher)
        defer { h.cleanUp() }
        h.runner.update([runnerDefinition(runnerScript(widget: "number"))])
        await h.runner.waitForIdle()
        #expect(
            h.state()?.records.first?.outcome
                == .invalidOutput("widget.type is “status” but the front matter declares “number”."))
        await h.runner.stop()
    }

    @Test func emptyOutputIsInvalid() async throws {
        let h = RunnerHarness(launcher: FakeLauncher(results: [launchResult(stdout: Data("\n".utf8))]))
        defer { h.cleanUp() }
        h.runner.update([runnerDefinition(runnerScript())])
        await h.runner.waitForIdle()
        #expect(h.state()?.records.first?.outcome == .invalidOutput("The script printed nothing on standard output."))
        await h.runner.stop()
    }

    @Test func anUnresolvedRuntimeErrorsAndWaitsForTheNextInterval() async throws {
        let h = RunnerHarness(resolver: FakeResolver([:]))
        defer { h.cleanUp() }
        let t0 = h.now.date
        h.runner.update([runnerDefinition(runnerScript(interval: "10s", runtime: "python3"))])
        await h.runner.waitForIdle()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(h.launcher.count == 0)
        let state = try #require(h.state())
        #expect(state.records.count == 1)
        #expect(state.records.first?.outcome == .runtimeNotFound("python3"))
        #expect(ScriptRunLabel.state(state) == "RUNTIME NOT FOUND")
        #expect(state.nextRunAt == t0.addingTimeInterval(10))
        #expect(h.scheduler.liveOneShots.count == 1)
        #expect(h.log.text.contains("runtime python3 not found"))

        h.now.advance(10)
        await h.fireNext()
        #expect(h.state()?.records.count == 2)
        #expect(h.scheduler.liveOneShots.count == 1)
        await h.runner.stop()
    }

    @Test func aChangedFileStartsOverFromTheFirstRun() async throws {
        let launcher = FakeLauncher()
        let h = RunnerHarness(launcher: launcher)
        defer { h.cleanUp() }
        h.runner.update([runnerDefinition(runnerScript(code: "print(1)"))])
        await h.runner.waitForIdle()
        let oldJob = try #require(h.scheduler.liveOneShots.first)
        #expect(h.state()?.lastGoodOutput != nil)

        // Same content again: nothing restarts.
        h.runner.update([runnerDefinition(runnerScript(code: "print(1)"))])
        #expect(h.state()?.isRunning == false)
        #expect(oldJob.cancelled == false)

        launcher.hold = true
        h.runner.update([runnerDefinition(runnerScript(code: "print(2)"))])
        #expect(oldJob.cancelled)
        #expect(h.state() == ScriptRunState(phase: .waitingFirstRun, isRunning: true))
        #expect(ScriptRunLabel.state(try #require(h.state())) == "WAITING · FIRST RUN")
        #expect(await h.until { launcher.waiting == 1 })

        // A change during a run cancels it; its result is dropped.
        h.runner.update([runnerDefinition(runnerScript(code: "print(3)"))])
        #expect(await h.until { launcher.cancelled == 1 })
        #expect(await h.until { launcher.waiting == 1 })
        launcher.release()
        await h.runner.waitForIdle()
        let state = try #require(h.state())
        #expect(state.records.count == 1)
        #expect(state.records.first?.outcome.isSuccess == true)
        #expect(launcher.launches.map(\.code) == ["print(1)", "print(2)", "print(3)"])
        await h.runner.stop()
    }

    @Test func onlyEligibleRunnableScriptsRunAndRemovalStopsThem() async throws {
        var eligible: Set<String> = ["a.md", "c.md"]
        let h = RunnerHarness(isEligible: { eligible.contains($0.id) })
        defer { h.cleanUp() }
        let a = runnerDefinition(runnerScript(id: "a.script"), name: "a.md")
        let b = runnerDefinition(runnerScript(id: "b.script"), name: "b.md")
        let broken = runnerDefinition(Data("no front matter".utf8), name: "c.md")
        h.runner.update([a, b, broken])
        await h.runner.waitForIdle()
        #expect(Set(h.runner.states.keys) == ["a.md"])
        #expect(h.launcher.count == 1)

        eligible = ["a.md", "b.md"]
        h.runner.update([a, b, broken])
        await h.runner.waitForIdle()
        #expect(Set(h.runner.states.keys) == ["a.md", "b.md"])
        #expect(h.launcher.count == 2)
        #expect(h.scheduler.liveOneShots.count == 2)

        h.runner.update([b])
        #expect(Set(h.runner.states.keys) == ["b.md"])
        #expect(h.scheduler.liveOneShots.count == 1)

        eligible = []
        h.runner.update([b])
        #expect(h.runner.states.isEmpty)
        #expect(h.scheduler.liveOneShots.isEmpty)
        await h.runner.stop()
    }

    @Test func stopEndsEveryRunAndSchedule() async throws {
        let launcher = FakeLauncher()
        let h = RunnerHarness(launcher: launcher)
        defer { h.cleanUp() }
        let a = runnerDefinition(runnerScript(id: "a.script"), name: "a.md")
        h.runner.update([a])
        await h.runner.waitForIdle()
        launcher.hold = true
        let b = runnerDefinition(runnerScript(id: "b.script"), name: "b.md")
        let c = runnerDefinition(runnerScript(id: "c.script"), name: "c.md")
        h.runner.update([a, b, c])
        #expect(await h.until { launcher.waiting == 2 })

        await h.runner.stop()
        #expect(launcher.cancelled == 2)
        #expect(h.runner.states.isEmpty)
        #expect(h.scheduler.liveOneShots.isEmpty)

        h.runner.update([a, b, c])
        h.runner.refreshAll()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(launcher.count == 3)
        #expect(h.runner.states.isEmpty)
    }

    @Test func theRecordRingKeepsTheLatestRuns() async throws {
        let h = RunnerHarness()
        defer { h.cleanUp() }
        h.runner.update([runnerDefinition(runnerScript())])
        await h.runner.waitForIdle()
        for _ in 0..<(ScriptRunner.recordLimit + 4) {
            h.now.advance(1)
            h.runner.refresh(id: "test.md")
            await h.runner.waitForIdle()
        }
        let records = try #require(h.state()?.records)
        #expect(records.count == ScriptRunner.recordLimit)
        #expect(records.first?.startedAt == h.now.date)
        #expect(records.first?.duration == .milliseconds(120))
    }

    @Test func timeoutIsTheIntervalCappedAtThirtySeconds() {
        #expect(ScriptRunner.timeout(for: .seconds(5)) == .seconds(5))
        #expect(ScriptRunner.timeout(for: .seconds(300)) == .seconds(30))
        #expect(ScriptRunner.timeoutSeconds(.seconds(30)) == 30)
        #expect(ScriptRunner.timeoutSeconds(.milliseconds(1500)) == 2)
        #expect(ScriptRunner.timeoutSeconds(.milliseconds(200)) == 1)
    }
}
