import AgentKit
import Foundation
import ModuleKit
import SwiftUI
import Testing
import os

@testable import AgentsSessions

/// An adapter with Accounts (Story 7.11): one `settings.json` per Account location, each installed, missing,
/// partly installed or without a folder.
final class AccountsFakeAdapter: AgentAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var _installed: Set<AccountID> = []
    private var _partial: Set<AccountID> = []
    private var _missingFolders: Set<AccountID> = []
    let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

    var id: AgentID { "fake" }
    var name: LocalizedStringResource { "Fake Agent" }
    var capabilities: Set<AgentCapability> { [.hooks] }
    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] { [] }
    var defaultAccountLocation: AccountLocation? { .configDirectory("/Users/test/.fake") }

    var installed: Set<AccountID> {
        get { lock.withLock { _installed } }
        set { lock.withLock { _installed = newValue } }
    }
    var partial: Set<AccountID> {
        get { lock.withLock { _partial } }
        set { lock.withLock { _partial = newValue } }
    }
    var missingFolders: Set<AccountID> {
        get { lock.withLock { _missingFolders } }
        set { lock.withLock { _missingFolders = newValue } }
    }

    func settingsURL(_ account: AgentAccount) -> URL {
        account.location!.url(home: home).appendingPathComponent("settings.json")
    }

    func account(for path: URL) -> AccountID? {
        let folder = path.deletingLastPathComponent().lastPathComponent
        return folder == ".fake" ? .default : AccountID(String(folder.dropFirst(".fake-".count)))
    }

    private func diff(_ account: AgentAccount, install: Bool) -> ConfigDiff {
        ConfigDiff(
            path: settingsURL(account), baseHash: "h", oldText: "{}", newText: install ? "{\"hooks\":1}" : "{}",
            summary: install ? "Add hooks to \(account.id.rawValue)" : "Remove hooks from \(account.id.rawValue)")
    }

    func integrationPlan(context: any AdapterContext, inputs: IntegrationInputs, account: AgentAccount)
        async throws -> [ConfigDiff]
    {
        if missingFolders.contains(account.id) {
            throw MissingAccountLocation(account: account.id, path: account.location?.path ?? "")
        }
        let complete = installed.contains(account.id) && !partial.contains(account.id)
        return complete ? [] : [diff(account, install: true)]
    }

    func removalPlan(context: any AdapterContext, inputs: IntegrationInputs, account: AgentAccount)
        async throws -> [ConfigDiff]
    {
        guard !missingFolders.contains(account.id) else { return [] }
        let some = installed.contains(account.id) || partial.contains(account.id)
        return some ? [diff(account, install: false)] : []
    }
}

/// Applies a preview by flipping the adapter's per-Account state of each file it names.
final class AccountsInstaller: IntegrationInstaller, @unchecked Sendable {
    private let lock = NSLock()
    let adapter: AccountsFakeAdapter
    private var _applied: [IntegrationPreview] = []
    init(adapter: AccountsFakeAdapter) { self.adapter = adapter }

    var applied: [IntegrationPreview] { lock.withLock { _applied } }
    var cliPath: String { "/Users/test/.local/bin/vigie-dev" }

    func preview(_ diffs: [ConfigDiff], adapterID: String, action: IntegrationAction) async throws
        -> IntegrationPreview
    {
        IntegrationPreview(
            adapterID: adapterID, action: action,
            files: diffs.map { IntegrationFileChange(diff: $0, unifiedDiff: "+hook", stale: false) })
    }

    func apply(_ preview: IntegrationPreview) async throws -> IntegrationResult {
        lock.withLock { _applied.append(preview) }
        for path in preview.diffs.map(\.path) {
            guard let account = adapter.account(for: path) else { continue }
            adapter.partial.remove(account)
            if preview.action == .install {
                adapter.installed.insert(account)
            } else {
                adapter.installed.remove(account)
            }
        }
        return IntegrationResult(appliedPaths: preview.diffs.map(\.path), backupPaths: [])
    }
}

/// Settings whose `observe(accounts)` yields when the test says so.
final class SignallingSettings: ModuleSettings, @unchecked Sendable {
    let base: FakeSettings
    let stream: AsyncStream<Void>
    let continuation: AsyncStream<Void>.Continuation
    init(_ base: FakeSettings) {
        self.base = base
        (stream, continuation) = AsyncStream.makeStream(of: Void.self)
    }
    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? { base.value(key, as: type) }
    func set<T: SettingValue>(_ value: T?, for key: String) async throws { try await base.set(value, for: key) }
    func observe(_ key: String) -> AsyncStream<Void> { key == "accounts" ? stream : AsyncStream { $0.finish() } }
}

@MainActor @Suite struct AccountIntegrationsTests {
    let adapter = AccountsFakeAdapter()
    let installer: AccountsInstaller
    let moduleSettings = FakeSettings(values: ["adapters": ["claude"]])
    let adapterSettings = FakeSettings(values: [
        "accounts": ["work", "client"],
        "account.work.label": "Work", "account.work.location": "~/.fake-work",
        "account.client.label": "Client", "account.client.location": "/Users/test/.fake-client/",
    ])
    let notifier = RecordingNotifier()

    init() { installer = AccountsInstaller(adapter: adapter) }

    func model() -> AgentIntegrationsModel {
        let context = AdapterContextBox(
            settings: ReadOnlyAdapterSettings(adapterSettings), secrets: NoSecrets(), executables: NoExecutables(),
            http: URLSessionHTTPClient(), log: Logger(subsystem: "test", category: "test"))
        return AgentIntegrationsModel(
            adapters: AgentAdapters([adapter]), contexts: ["fake": context], installer: installer,
            settings: moduleSettings, homeDirectory: adapter.home, log: Logger(subsystem: "test", category: "test"),
            notifier: notifier)
    }

    func row(_ model: AgentIntegrationsModel) -> AgentIntegrationsModel.Row { model.rows[0] }

    func states(_ model: AgentIntegrationsModel) -> [String: AgentIntegrationsModel.LocationState] {
        Dictionary(uniqueKeysWithValues: row(model).locations.map { ($0.id.rawValue, $0.state) })
    }

    func pending(_ model: AgentIntegrationsModel) -> IntegrationPreview? {
        guard case .confirming(let preview, _) = row(model).phase else { return nil }
        return preview
    }

    var paths: (default: String, work: String, client: String) {
        (
            "/Users/test/.fake/settings.json", "/Users/test/.fake-work/settings.json",
            "/Users/test/.fake-client/settings.json"
        )
    }

    @Test func connectShowsOneConfirmationListingEveryLocationDefaultFirst() async throws {
        let model = model()
        await model.refresh()
        #expect(row(model).status == .notConnected)
        #expect(states(model) == ["default": .missing, "work": .missing, "client": .missing])
        await model.connect("fake")
        let preview = try #require(pending(model))
        #expect(preview.diffs.map(\.path.path) == [paths.default, paths.work, paths.client])
        #expect(installer.applied.isEmpty)  // nothing written before Apply
        await model.confirm("fake")
        #expect(adapter.installed == [.default, "work", "client"])
        #expect(row(model).status == .connected)
        #expect(states(model) == ["default": .installed, "work": .installed, "client": .installed])
        #expect(moduleSettings.value("adapters", as: [String].self) == ["claude", "fake"])
    }

    @Test func statusLineListsEachLocationAndInstallRepairsOnlyTheMissingOnes() async throws {
        adapter.installed = [.default, "client"]
        adapter.partial = ["client"]
        let model = model()
        await model.refresh()
        #expect(states(model) == ["default": .installed, "work": .missing, "client": .modified])
        #expect(row(model).status == .partial)
        #expect(row(model).isRepair && row(model).canConnect)
        let lines = row(model).locations.map { IntegrationText.location($0, home: adapter.home) }
        #expect(lines.count == 3)
        #expect(lines[1].contains("Work") && lines[1].contains(".fake-work") && lines[1].contains("missing"))
        #expect(lines[2].contains("modified"))
        #expect(lines[0].contains("Default"))

        await model.connect("fake")
        let preview = try #require(pending(model))
        #expect(preview.action == .install)
        #expect(preview.diffs.map(\.path.path) == [paths.work, paths.client])  // the default is left alone
        await model.confirm("fake")
        #expect(row(model).status == .connected)
    }

    @Test func disconnectRemovesFromEveryLocation() async throws {
        adapter.installed = [.default, "work", "client"]
        try await moduleSettings.set(["claude", "fake"], for: "adapters")
        let model = model()
        await model.refresh()
        await model.disconnect("fake")
        #expect(pending(model)?.diffs.count == 3)
        await model.confirm("fake")
        #expect(adapter.installed.isEmpty)
        #expect(moduleSettings.value("adapters", as: [String].self) == ["claude"])
    }

    @Test func removingAnAccountRemovesItsHooksOnlyAfterConfirmation() async throws {
        adapter.installed = [.default, "work", "client"]
        try await moduleSettings.set(["claude", "fake"], for: "adapters")
        let model = model()
        await model.refresh()
        try await adapterSettings.set(["client"], for: "accounts")
        try await adapterSettings.set(nil as String?, for: "account.work.location")
        await model.accountsChanged("fake")
        let preview = try #require(pending(model))
        #expect(preview.action == .remove)
        #expect(preview.diffs.map(\.path.path) == [paths.work])
        #expect(adapter.installed.contains("work"))  // not before Apply
        await model.confirm("fake")
        #expect(adapter.installed == [.default, "client"])
        // An Account's removal never disconnects the adapter.
        #expect(moduleSettings.value("adapters", as: [String].self) == ["claude", "fake"])
        #expect(row(model).status == .connected)
        #expect(row(model).locations.map(\.id) == [.default, "client"])
    }

    @Test func addingAnAccountWhileConnectedInstallsIntoItsLocationOnly() async throws {
        try await adapterSettings.set(["work"], for: "accounts")
        adapter.installed = [.default, "work"]
        try await moduleSettings.set(["claude", "fake"], for: "adapters")
        let model = model()
        await model.refresh()
        #expect(row(model).status == .connected)
        try await adapterSettings.set(["work", "client"], for: "accounts")
        await model.accountsChanged("fake")
        let preview = try #require(pending(model))
        #expect(preview.action == .install)
        #expect(preview.diffs.map(\.path.path) == [paths.client])
        await model.confirm("fake")
        #expect(adapter.installed == [.default, "work", "client"])
        let client = AgentAccount(
            id: "client", label: "Client", location: .configDirectory("/Users/test/.fake-client/"))
        #expect(row(model).scope == .account(client))
    }

    @Test func theAccountsListIsWatched() async throws {
        try await adapterSettings.set(["work"], for: "accounts")
        adapter.installed = [.default, "work"]
        try await moduleSettings.set(["claude", "fake"], for: "adapters")
        let model = model()
        await model.refresh()
        let signalling = SignallingSettings(adapterSettings)
        model.observeAccounts(["fake": signalling])
        try await adapterSettings.set(["work", "client"], for: "accounts")
        signalling.continuation.yield()
        for _ in 0..<200 where pending(model) == nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(pending(model)?.diffs.map(\.path.path) == [paths.client])
        model.stopObserving()
    }

    @Test func addingAnAccountWhileDisconnectedPlansNothing() async throws {
        try await adapterSettings.set(["work"], for: "accounts")
        let model = model()
        await model.refresh()
        try await adapterSettings.set(["work", "client"], for: "accounts")
        await model.accountsChanged("fake")
        #expect(pending(model) == nil)
        #expect(states(model)["client"] == .missing)
    }

    @Test func accountChangesWaitForThePendingConfirmation() async throws {
        adapter.installed = [.default, "work", "client"]
        try await moduleSettings.set(["claude", "fake"], for: "adapters")
        let model = model()
        await model.refresh()
        try await adapterSettings.set([String](), for: "accounts")
        await model.accountsChanged("fake")
        #expect(pending(model)?.diffs.map(\.path.path) == [paths.work])
        model.cancel("fake")
        // Cancel runs the next queued plan.
        for _ in 0..<50 where pending(model) == nil { await Task.yield() }
        #expect(pending(model)?.diffs.map(\.path.path) == [paths.client])
        await model.confirm("fake")
        #expect(adapter.installed == [.default, "work"])  // Work was kept: its removal was cancelled
    }

    @Test func missingFolderIsASensitiveSetupProblemAndIsSkipped() async throws {
        adapter.missingFolders = ["work"]
        let model = model()
        await model.refresh()
        #expect(states(model)["work"] == .folderMissing)
        let event = try #require(notifier.events.first)
        #expect(event.kind == "setup.problem")
        #expect(event.dedupeKey == "location:fake:work")
        #expect(event.body?.contains("~/.fake-work") == true)
        #expect(event.title.contains("Work"))
        // Privacy mode masks the path (AD-24).
        #expect(event.$body.masked == PrivacyMask.text)
        #expect(event.$title.masked == PrivacyMask.text)

        await model.connect("fake")
        #expect(pending(model)?.diffs.map(\.path.path) == [paths.default, paths.client])
        await model.refresh()
        #expect(notifier.events.count == 1)  // one alert per location, not one per refresh

        adapter.missingFolders = []
        await model.refresh()
        #expect(notifier.openKinds.isEmpty)
        model.stopObserving()
    }

    @Test func installingOneMissingLocationFailsNamingThePath() async throws {
        try await moduleSettings.set(["claude", "fake"], for: "adapters")
        adapter.installed = [.default, "work"]
        adapter.missingFolders = ["client"]
        let model = model()
        await model.refresh()
        try await adapterSettings.set(["work", "client", "extra"], for: "accounts")
        try await adapterSettings.set("~/.fake-extra", for: "account.extra.location")
        adapter.missingFolders = ["client", "extra"]
        await model.accountsChanged("fake")
        guard case .failed(let message) = row(model).phase else {
            Issue.record("expected failed, got \(row(model).phase)")
            return
        }
        #expect(message.contains("~/.fake-extra"))
    }

    @Test func catalogHasTheLocationCopy() {
        for key in [
            "agentsSessions.integration.install", "agentsSessions.integration.location.line",
            "agentsSessions.integration.location.default", "agentsSessions.integration.location.installed",
            "agentsSessions.integration.location.missing", "agentsSessions.integration.location.modified",
            "agentsSessions.integration.location.folderMissing", "agentsSessions.integration.location.unknown",
            "agentsSessions.integration.location.error", "agentsSessions.integration.location.problem.title",
            "agentsSessions.integration.location.problem.body",
        ] {
            #expect(IntegrationText.string(key) != key, "\(key)")
        }
    }

    /// Renders the block with three location lines; with `VIGIE_SETTINGS_SNAPSHOT_DIR` set, writes
    /// `settings-agents-accounts.png` there.
    @Test func locationLinesRenderOffscreen() async throws {
        adapter.installed = [.default]
        adapter.missingFolders = ["client"]
        let model = model()
        await model.refresh()
        #expect(row(model).locations.count == 3)
        let (window, view) = hostOffscreen(
            Form { Section { AgentIntegrationsView(model: model) } }.formStyle(.grouped)
                .frame(width: 620, height: 320),
            size: CGSize(width: 620, height: 320))
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        #expect(rep.pixelsWide > 0)
        if let dir = ProcessInfo.processInfo.environment["VIGIE_SETTINGS_SNAPSHOT_DIR"],
            let png = rep.representation(using: .png, properties: [:])
        {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-agents-accounts.png"))
        }
    }
}
