import Foundation
import ModuleKit
import Testing
import VigieUI

@testable import Integrations

/// Story 12.6: Settings › Scripts. Per-Mac enable drives the runner without a rescan, configured values and
/// secrets reach the script's environment at the next run, and the pane's rows and generated controls.
@MainActor @Suite struct SettingsPaneTests {
    /// A modules folder in a temp directory.
    struct Folder {
        let root: URL
        var url: URL { root.appendingPathComponent("modules", isDirectory: true) }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "integrations-settings-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        func write(_ name: String, _ data: Data) throws { try data.write(to: url.appendingPathComponent(name)) }
        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    /// A `/bin/sh` script that prints its settings as a text widget: `<repo>|<token>|<warn_at>`.
    static let envScript = runnerScript(
        id: "test.env", runtime: "sh", widget: "text",
        settings: [
            #"{ key: repo, type: string, label: "Repository", default: "a/b" }"#,
            #"{ key: token, type: secret, label: "Token" }"#,
            #"{ key: warn_at, type: int, label: "Warn at", default: 5, min: 1, max: 99 }"#,
        ],
        language: "sh",
        code:
            #"printf '{"widget":{"type":"text","value":"%s|%s|%s"}}' "$VIGIE_SETTING_REPO" "${VIGIE_SETTING_TOKEN-}" "$VIGIE_SETTING_WARN_AT""#
    )

    func start(_ folder: Folder, secrets: FakeSecretStore = FakeSecretStore(), enabled: [String: Bool] = [:])
        async throws -> (IntegrationsModule, FakeModuleContext)
    {
        let context = FakeModuleContext(
            scriptFolder: FakeScriptFolder(url: folder.url, enabled: enabled), secrets: secrets,
            executables: FakeResolver(["sh": URL(fileURLWithPath: "/bin/sh")]))
        let module = IntegrationsModule()
        try await module.start(context: context)
        return (module, context)
    }

    func script(_ module: IntegrationsModule, _ name: String) throws -> ScriptModuleDefinition {
        try #require(module.scripts.first { $0.fileName == name })
    }

    func output(_ module: IntegrationsModule, _ name: String) -> String? {
        guard case .ok(let output, _) = module.runner?.states[name]?.phase else { return nil }
        return output.widget.value
    }

    // MARK: - Enabled on this Mac

    @Test func disablingStopsTheRunAndEnablingStartsItWithoutARescan() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("env.md", Self.envScript)
        let (module, context) = try await start(folder)
        let runner = try #require(module.runner)
        try await module.confirm(try script(module, "env.md"))
        await runner.waitForIdle()
        #expect(runner.states["env.md"] != nil)
        let scans = module.completedScans

        try await module.setEnabled(false, for: try script(module, "env.md"))
        #expect(context.fakeScriptFolder.fakeSettings.flags == ["modules/env.md": false])
        #expect(try !script(module, "env.md").enabled)
        #expect(runner.states["env.md"] == nil)
        #expect(module.paneRows().first?.state == .disabled)

        try await module.setEnabled(true, for: try script(module, "env.md"))
        #expect(context.fakeScriptFolder.fakeSettings.flags.isEmpty)
        #expect(runner.states["env.md"] != nil)
        await runner.waitForIdle()

        // An outside edit of local.toml reaches the runner through the change stream.
        context.fakeScriptFolder.fakeSettings.edit(enabled: false, for: "modules/env.md")
        #expect(await eventually { runner.states["env.md"] == nil })
        #expect(module.completedScans == scans)
        await module.stop()
        #expect(context.fakeScriptFolder.fakeSettings.subscribers == 0)
    }

    // MARK: - Configured values and secrets

    @Test func configuredValuesAndSecretsReachTheEnvironmentAtTheNextRun() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("env.md", Self.envScript)
        let secrets = FakeSecretStore()
        let (module, context) = try await start(folder, secrets: secrets)
        let runner = try #require(module.runner)
        let definition = try script(module, "env.md")
        try await module.confirm(definition)
        await runner.waitForIdle()
        // Front-matter defaults, no secret yet.
        #expect(output(module, "env.md") == "a/b||5")

        let rows = module.settingRows(for: definition)
        #expect(rows.map(\.id) == ["modules.test.env.repo", "modules.test.env.token", "modules.test.env.warn_at"])
        try await rows[0].binding.set(.string("me/project"))
        try await rows[2].binding.set(.int(500))  // clamped to max 99
        let secret = try #require(rows[1].secret)
        #expect(try await secret.isSet() == false)
        try await secret.set("s3cret")
        #expect(try await secret.isSet())

        // Stored where the runner reads them: config values by id and key, the secret in the module's store.
        let store = context.fakeScriptFolder.fakeSettings
        #expect(store.values[.init(id: "test.env", key: "repo")] as? String == "me/project")
        #expect(store.values[.init(id: "test.env", key: "warn_at")] as? Int == 99)
        #expect(store.values[.init(id: "test.env", key: "token")] == nil)
        #expect(try await secrets.read("test.env.token") == "s3cret")
        // A secret row never writes config, and never shows the stored value.
        await #expect(throws: (any Error).self) { try await rows[1].binding.set(.string("leak")) }
        #expect(rows[1].binding.get() == nil)

        module.refresh(scriptID: "env.md")
        await runner.waitForIdle()
        #expect(output(module, "env.md") == "me/project|s3cret|99")

        // An outside edit of config.toml applies at the next run too; clearing the secret unsets it.
        store.edit("x/y", id: "test.env", key: "repo")
        try await secret.set(nil)
        module.refresh(scriptID: "env.md")
        await runner.waitForIdle()
        #expect(output(module, "env.md") == "x/y||99")
        await module.stop()
    }

    @Test func declaredSettingsAreRegisteredPerScriptAndForgottenWithTheFile() async throws {
        let folder = try Folder()
        defer { folder.cleanUp() }
        try folder.write("env.md", Self.envScript)
        try folder.write("broken.md", Data("---\nid: test.broken\n---\nno code".utf8))
        let (module, context) = try await start(folder)
        let store = context.fakeScriptFolder.fakeSettings
        // Secrets are passed along and skipped by the host (Keychain only); errored files register nothing.
        #expect(store.registered == ["test.env": ["repo", "warn_at"]])
        #expect(store.registeredKinds["test.env"]?.last == .int(default: 5, min: 1, max: 99, step: nil))
        let count = store.registerCount

        // A rescan with the same declarations does not register again.
        try await ScriptDiscoveryTests().change(module, context)
        #expect(store.registerCount == count)

        try FileManager.default.removeItem(at: folder.url.appendingPathComponent("env.md"))
        try await ScriptDiscoveryTests().change(module, context)
        #expect(store.registered.isEmpty)
        await module.stop()
    }

    // MARK: - Pane rows

    func row(
        _ data: Data = runnerScript(), name: String = "test.md", local: ScriptLocalState = .confirmed,
        enabled: Bool = true, eligible: Bool = true, run: ScriptRunState? = ScriptRunState()
    ) -> ScriptPaneRow {
        ScriptPaneRow(
            script: runnerDefinition(data, name: name, enabled: enabled), localState: local, isEligible: eligible,
            runState: run)
    }

    @Test func rowStatesAndLabels() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let output = try! ScriptOutput.decode(json: numberOutput)
        let broken = row(Data("---\nid: x\n---\nno code".utf8), eligible: false, run: nil)
        guard case .cantLoad(let message) = broken.state else {
            Issue.record("expected can't load")
            return
        }
        #expect(broken.problem == message)
        #expect(broken.state.label == "CAN’T LOAD")
        #expect(row(local: .declined, eligible: false, run: nil).state.label == "DECLINED")
        #expect(row(local: .awaitingConfirmation, eligible: false, run: nil).state.label == "NOT CONFIRMED")
        #expect(row(enabled: false, eligible: false, run: nil).state.label == "DISABLED")
        #expect(row(run: nil).state.label == "CONFIRMED")
        #expect(row().state.label == "WAITING · FIRST RUN")
        #expect(row(run: ScriptRunState(isRunning: true)).state.label == "RUNNING")
        #expect(row(run: ScriptRunState(phase: .ok(output, at: date))).state.label == "OK")
        let failed = ScriptRunState(phase: .errored(.failed(exitCode: 2), lastGoodOutput: output, at: date))
        #expect(row(run: failed).state == .errored("EXIT 2"))
        let timedOut = ScriptRunState(phase: .errored(.timedOut(seconds: 30), lastGoodOutput: nil, at: date))
        #expect(row(run: timedOut).state.label == "TIMED OUT · 30S")
    }

    @Test func refreshOnlyForAnEligibleScriptThatIsNotRunning() {
        #expect(row().canRefresh)
        #expect(!row(run: ScriptRunState(isRunning: true)).canRefresh)
        #expect(!row(eligible: false).canRefresh)
        #expect(!row(run: nil).canRefresh)
        #expect(!row(local: .awaitingConfirmation, eligible: false, run: nil).canRefresh)
    }

    @Test func lastRunIsRelative() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let record = ScriptRunRecord(
            startedAt: now.addingTimeInterval(-300), duration: .seconds(1), outcome: .failed(exitCode: 1),
            stderrExcerpt: "")
        let ran = row(run: ScriptRunState(records: [record]))
        #expect(ran.lastRun == record.startedAt)
        #expect(ran.lastRunText(now: now) == "Last run 5 minutes ago")
        #expect(row().lastRunText(now: now) == "Not run yet")
        #expect(row().name == "Test")
        #expect(row().file == "modules/test.md")
    }

    @Test func theRepositoryLinkWaitsForTheOwner() {
        // A49 / A84: `vigie-scripts` under the releases owner, still the placeholder.
        #expect(ScriptRepository.name == "vigie-scripts")
        #expect(ScriptRepository.owner == ScriptRepository.placeholderOwner)
        #expect(ScriptRepository.url == nil)
    }
}
