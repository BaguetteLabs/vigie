import AgentKit
import AppKit
import Foundation
import ModuleKit
import SwiftUI
import Testing
import os

@testable import AgentsSessions

/// An adapter whose hooks are "installed" when `installed` is true; plans one diff of `/tmp/agent.json`.
final class IntegrationFakeAdapter: AgentAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var _installed = false
    private var _plans = 0
    var planError: (any Error)?

    var id: AgentID { "fake" }
    var name: LocalizedStringResource { "Fake Agent" }
    var capabilities: Set<AgentCapability> { [.hooks] }

    var installed: Bool {
        get { lock.withLock { _installed } }
        set { lock.withLock { _installed = newValue } }
    }
    var plans: Int { lock.withLock { _plans } }
    /// Bumped by tests to simulate a concurrent edit (the diff's base hash changes).
    var revision = 0

    func detectVersion(context: any AdapterContext) async -> AgentVersion? { AgentVersion(raw: "2.1.319") }
    func support(for version: AgentVersion?) -> AdapterSupport {
        version.map(AdapterSupport.supported) ?? .notInstalled
    }
    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] { [] }

    func diff(_ install: Bool, cli: String) -> ConfigDiff {
        ConfigDiff(
            path: URL(fileURLWithPath: "/tmp/agent.json"), baseHash: "rev\(revision)", oldText: "{}",
            newText: install ? "{\"hook\":\"\(cli) hook fake\"}" : "{}",
            summary: install ? "Add 1 hook" : "Remove 1 hook")
    }

    func integrationPlan(context: any AdapterContext, inputs: IntegrationInputs) async throws -> [ConfigDiff] {
        lock.withLock { _plans += 1 }
        if let planError { throw planError }
        return installed ? [] : [diff(true, cli: inputs.cliPath)]
    }

    func removalPlan(context: any AdapterContext, inputs: IntegrationInputs) async throws -> [ConfigDiff] {
        if let planError { throw planError }
        return installed ? [diff(false, cli: inputs.cliPath)] : []
    }
}

/// Previews are stale while `staleCount` > 0; `apply` throws `targetChanged` while `changedCount` > 0, else
/// flips the adapter's `installed` state.
final class FakeInstaller: IntegrationInstaller, @unchecked Sendable {
    private let lock = NSLock()
    let adapter: IntegrationFakeAdapter
    var staleCount = 0
    var changedCount = 0
    private(set) var previews: [[ConfigDiff]] = []
    private(set) var applied: [IntegrationPreview] = []

    init(adapter: IntegrationFakeAdapter) { self.adapter = adapter }

    var cliPath: String { "/Users/test/.local/bin/vigie-dev" }

    func preview(_ diffs: [ConfigDiff], adapterID: String, action: IntegrationAction) async throws
        -> IntegrationPreview
    {
        let stale = lock.withLock {
            previews.append(diffs)
            defer { staleCount = max(0, staleCount - 1) }
            return staleCount > 0
        }
        return IntegrationPreview(
            adapterID: adapterID, action: action,
            files: diffs.map { IntegrationFileChange(diff: $0, unifiedDiff: "+hook", stale: stale) })
    }

    func apply(_ preview: IntegrationPreview) async throws -> IntegrationResult {
        let changed = lock.withLock {
            defer { changedCount = max(0, changedCount - 1) }
            return changedCount > 0
        }
        if changed { throw IntegrationError.targetChanged(paths: preview.diffs.map(\.path)) }
        lock.withLock { applied.append(preview) }
        adapter.installed = preview.action == .install
        return IntegrationResult(
            appliedPaths: preview.diffs.map(\.path),
            backupPaths: [URL(fileURLWithPath: "/tmp/agent.json.vigie-backup-20261108-101500")])
    }
}

@MainActor @Suite struct AgentIntegrationsTests {
    let adapter = IntegrationFakeAdapter()
    let installer: FakeInstaller
    let settings = FakeSettings(values: ["adapters": ["claude"]])

    init() { installer = FakeInstaller(adapter: adapter) }

    func model() -> AgentIntegrationsModel {
        AgentIntegrationsModel(
            adapters: AgentAdapters([adapter]), contexts: [:], installer: installer, settings: settings,
            homeDirectory: URL(fileURLWithPath: "/Users/test"), log: Logger(subsystem: "test", category: "test"))
    }

    var row: (AgentIntegrationsModel) -> AgentIntegrationsModel.Row { { $0.rows[0] } }

    @Test func refreshDetectsVersionAndStatus() async {
        let model = model()
        #expect(row(model).status == .unknown)
        await model.refresh()
        #expect(row(model).support == .supported(AgentVersion(raw: "2.1.319")))
        #expect(row(model).status == .notConnected)
        #expect(row(model).canConnect && !row(model).canDisconnect)
        adapter.installed = true
        await model.refresh()
        #expect(row(model).status == .connected)
    }

    @Test func connectPlansWithTheCLILinkPreviewsAppliesAndEnablesTheAdapter() async throws {
        let model = model()
        await model.refresh()
        await model.connect("fake")
        guard case .confirming(let preview, let changed) = row(model).phase else {
            Issue.record("expected a diff to confirm, got \(row(model).phase)")
            return
        }
        #expect(!changed)
        #expect(preview.action == .install)
        #expect(preview.diffs.first?.newText.contains("/Users/test/.local/bin/vigie-dev hook fake") == true)
        #expect(installer.applied.isEmpty)  // nothing written before Apply

        await model.confirm("fake")
        #expect(installer.applied.map(\.action) == [.install])
        guard case .applied(.install, let result) = row(model).phase else {
            Issue.record("expected applied, got \(row(model).phase)")
            return
        }
        #expect(result.backupPaths.count == 1)
        #expect(row(model).status == .connected)
        #expect(settings.value("adapters", as: [String].self) == ["claude", "fake"])
    }

    @Test func cancelWritesNothing() async {
        let model = model()
        await model.connect("fake")
        model.cancel("fake")
        #expect(row(model).phase == .idle)
        #expect(installer.applied.isEmpty)
        #expect(settings.value("adapters", as: [String].self) == ["claude"])
    }

    @Test func stalePreviewIsReplannedBeforeShowing() async {
        installer.staleCount = 1
        let model = model()
        await model.connect("fake")
        #expect(installer.previews.count == 2)
        #expect(adapter.plans == 2)
        guard case .confirming(_, let changed) = row(model).phase else {
            Issue.record("expected confirming, got \(row(model).phase)")
            return
        }
        #expect(changed)
    }

    @Test func targetChangedOnApplyShowsTheNewDiff() async {
        let model = model()
        await model.connect("fake")
        installer.changedCount = 1
        adapter.revision = 1
        await model.confirm("fake")
        guard case .confirming(let preview, let changed) = row(model).phase else {
            Issue.record("expected the re-planned diff, got \(row(model).phase)")
            return
        }
        #expect(changed)
        #expect(preview.diffs.first?.baseHash == "rev1")
        #expect(installer.applied.isEmpty)
        await model.confirm("fake")
        #expect(installer.applied.count == 1)
    }

    @Test func endlesslyStaleFileFails() async {
        installer.staleCount = 99
        let model = model()
        await model.connect("fake")
        #expect(adapter.plans == AgentIntegrationsModel.maxReplans)
        guard case .failed = row(model).phase else {
            Issue.record("expected failed, got \(row(model).phase)")
            return
        }
    }

    @Test func disconnectRemovesTheAdapterFromTheList() async {
        adapter.installed = true
        try? await settings.set(["claude", "fake"], for: "adapters")
        let model = model()
        await model.refresh()
        await model.disconnect("fake")
        guard case .confirming(let preview, _) = row(model).phase else {
            Issue.record("expected confirming, got \(row(model).phase)")
            return
        }
        #expect(preview.action == .remove)
        await model.confirm("fake")
        #expect(row(model).status == .notConnected)
        #expect(settings.value("adapters", as: [String].self) == ["claude"])
    }

    @Test func planErrorIsShown() async {
        struct Broken: Error {}
        adapter.planError = Broken()
        let model = model()
        await model.connect("fake")
        guard case .failed(let message) = row(model).phase else {
            Issue.record("expected failed, got \(row(model).phase)")
            return
        }
        #expect(message.hasPrefix("Couldn't prepare the changes"))
    }

    @Test func statusTable() {
        #expect(AgentIntegrationsModel.status(installEmpty: true, removeEmpty: false) == .connected)
        #expect(AgentIntegrationsModel.status(installEmpty: false, removeEmpty: true) == .notConnected)
        #expect(AgentIntegrationsModel.status(installEmpty: false, removeEmpty: false) == .partial)
        #expect(AgentIntegrationsModel.status(installEmpty: true, removeEmpty: true) == .none)
    }

    @Test func catalogHasTheIntegrationCopy() {
        let keys = [
            "agentsSessions.integration.title", "agentsSessions.integration.connect",
            "agentsSessions.integration.disconnect", "agentsSessions.integration.apply",
            "agentsSessions.integration.cancel", "agentsSessions.integration.review",
            "agentsSessions.integration.changed", "agentsSessions.integration.status.connected",
            "agentsSessions.integration.status.notConnected", "agentsSessions.integration.status.partial",
            "agentsSessions.integration.status.none", "agentsSessions.integration.status.unknown",
            "agentsSessions.integration.version.checking", "agentsSessions.integration.version.supported",
            "agentsSessions.integration.version.assumed", "agentsSessions.integration.version.unsupported",
            "agentsSessions.integration.version.notInstalled", "agentsSessions.integration.applied.install",
            "agentsSessions.integration.applied.remove", "agentsSessions.integration.applied.backup",
            "agentsSessions.integration.error.plan", "agentsSessions.integration.error.apply",
            "agentsSessions.integration.error.unstable",
        ]
        for key in keys { #expect(IntegrationText.string(key) != key, "\(key)") }
        #expect(IntegrationText.support(.unsupported(AgentVersion(raw: "3.0.0"))).contains("3.0.0"))
    }

    @Test func moduleOffersTheSettingsViewWhileRunning() async throws {
        let module = AgentsSessionsModule(
            adapters: AgentAdapters([adapter]), terminals: TerminalAdapters([]), liveness: FakeLiveness())
        #expect(module.settingsView() == nil)
        let context = FakeModuleContext(integrations: installer)
        try await module.start(context: context)
        #expect(module.settingsView() != nil)
        #expect(module.integrations?.inputs.cliPath == installer.cliPath)
        context.fakeEvents.finish()
        await module.stop()
        #expect(module.settingsView() == nil)
    }

    /// Renders the block with a pending diff; with `VIGIE_SETTINGS_SNAPSHOT_DIR` set, writes
    /// `settings-agents-connect.png` there.
    @Test func pendingDiffRendersOffscreen() async throws {
        let model = model()
        await model.refresh()
        let unified = """
            --- ~/.claude/settings.json
            +++ ~/.claude/settings.json
            @@ -1,5 +1,13 @@
             {
               "model": "opus",
               "hooks": {
                 "Stop": [
                   { "hooks": [{ "type": "command", "command": "~/bin/notify.sh" }] }
            +      ,{ "hooks": [{ "type": "command", "command": "/Users/test/.local/bin/vigie hook claude" }] }
                 ]
            +    "SessionStart": [
            +      { "hooks": [{ "type": "command", "command": "/Users/test/.local/bin/vigie hook claude" }] }
            +    ]
               }
             }
            """
        let diff = ConfigDiff(
            path: URL(fileURLWithPath: "/Users/test/.claude/settings.json"), baseHash: "x", oldText: "",
            newText: "", summary: "Add Vigie's hook to 8 events in ~/.claude/settings.json")
        model.showForTesting(
            "fake",
            .confirming(
                IntegrationPreview(
                    adapterID: "fake", action: .install,
                    files: [IntegrationFileChange(diff: diff, unifiedDiff: unified, stale: false)]),
                changed: true))
        let (window, view) = hostOffscreen(
            Form { Section { AgentIntegrationsView(model: model) } }.formStyle(.grouped)
                .frame(width: 620, height: 520),
            size: CGSize(width: 620, height: 520))
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        #expect(rep.pixelsWide > 0)
        if let dir = ProcessInfo.processInfo.environment["VIGIE_SETTINGS_SNAPSHOT_DIR"],
            let png = rep.representation(using: .png, properties: [:])
        {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-agents-connect.png"))
        }
    }
}
