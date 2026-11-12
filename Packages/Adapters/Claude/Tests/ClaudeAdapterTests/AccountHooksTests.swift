import AgentKit
import Foundation
import Testing

@testable import ClaudeAdapter

/// Story 7.11: hooks per Account location. Real temp folders stand in for `~/.claude`, `~/.claude-work` and
/// `~/.claude-client`; applying a plan writes its `newText` the way `IntegrationInstaller` would.
@Suite struct AccountHooksTests {
    let home: URL
    let inputs: IntegrationInputs
    let adapter: ClaudeAdapter
    let work = AgentAccount(id: "work", label: "Work", location: .configDirectory("~/.claude-work/"))
    let client = AgentAccount(id: "client", label: "Client", location: .configDirectory("~/.claude-client"))
    var personal: AgentAccount {
        AgentAccount(id: .default, label: "", location: adapter.defaultAccountLocation)
    }
    var command: String { inputs.hookCommand(for: ClaudeAdapter.agentID) }

    init() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-account-hooks-\(UUID().uuidString)", isDirectory: true)
        for folder in [".claude", ".claude-work", ".claude-client"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
        }
        inputs = IntegrationInputs(cliPath: home.appendingPathComponent(".local/bin/vigie").path, homeDirectory: home)
        adapter = ClaudeAdapter(homeDirectory: home)
    }

    func settingsURL(_ account: AgentAccount) -> URL {
        account.isDefault
            ? home.appendingPathComponent(".claude/settings.json")
            : account.location!.url(home: home).appendingPathComponent("settings.json")
    }

    func text(_ account: AgentAccount) -> String? {
        try? String(contentsOf: settingsURL(account), encoding: .utf8)
    }

    func apply(_ diffs: [ConfigDiff]) throws {
        for diff in diffs { try Data(diff.newText.utf8).write(to: diff.path) }
    }

    func install(_ account: AgentAccount) async throws -> [ConfigDiff] {
        try await adapter.integrationPlan(context: makeContext(), inputs: inputs, account: account)
    }

    func remove(_ account: AgentAccount) async throws -> [ConfigDiff] {
        try await adapter.removalPlan(context: makeContext(), inputs: inputs, account: account)
    }

    @Test func accountPlanTargetsOnlyItsOwnSettingsFile() async throws {
        let plan = try await install(work)
        #expect(plan.count == 1)
        #expect(plan.first?.path == settingsURL(work))
        #expect(plan.first?.baseHash == nil)
        // Same managed command as the default location (AD-22): attribution comes from CLAUDE_CONFIG_DIR.
        #expect(plan.first?.newText.contains("\"command\": \"\(command)\"") == true)
        #expect(plan.first?.summary.contains("settings.json") == true)
        let defaultPlan = try await install(personal)
        #expect(defaultPlan.first?.newText == plan.first?.newText)
    }

    @Test func installRepairAndRemoveTouchEachLocationIndependently() async throws {
        let userDefault = "{\n  \"model\": \"opus\"\n}\n"
        try Data(userDefault.utf8).write(to: settingsURL(personal))

        // Install into Work only: the default and Client stay as they were.
        try apply(try await install(work))
        #expect(text(personal) == userDefault)
        #expect(text(client) == nil)
        #expect(try await install(work).isEmpty)
        #expect(try await remove(work).count == 1)
        #expect(try await install(client).count == 1)
        #expect(try await install(personal).count == 1)

        // Install into Client and the default.
        try apply(try await install(client))
        try apply(try await install(personal))
        let workText = try #require(text(work))
        let defaultText = try #require(text(personal))
        #expect(defaultText.contains("\"model\": \"opus\""))

        // Repair: Client loses its Stop hook; only Client is planned again, and only Stop comes back.
        let clientText = try #require(text(client))
        let broken = try OrderedJSON.parse(clientText)
        guard case .object(var root) = broken, case .object(var hooks) = root.first(where: { $0.key == "hooks" })?.value
        else {
            Issue.record("no hooks")
            return
        }
        hooks.removeAll { $0.key == "Stop" }
        root[root.firstIndex { $0.key == "hooks" }!].value = .object(hooks)
        try Data((OrderedJSON.object(root).serialized() + "\n").utf8).write(to: settingsURL(client))
        #expect(try await install(work).isEmpty)
        #expect(try await install(personal).isEmpty)
        let repair = try #require(try await install(client).first)
        #expect(repair.summary.contains("1"))
        try apply([repair])
        #expect(try await install(client).isEmpty)
        #expect(text(work) == workText)
        #expect(text(personal) == defaultText)

        // Remove Work (Account removed): Client and the default keep their hooks.
        try apply(try await remove(work))
        #expect(text(work)?.contains(command) == false)
        #expect(text(personal) == defaultText)
        #expect(try await install(client).isEmpty)
        #expect(try await remove(work).isEmpty)

        // Disconnect the default: the Accounts' files are untouched.
        let clientAfterRepair = try #require(text(client))
        try apply(try await remove(personal))
        #expect(text(personal)?.contains(command) == false)
        #expect(text(personal)?.contains("\"model\": \"opus\"") == true)
        #expect(text(client) == clientAfterRepair)
    }

    @Test func missingFolderIsASetupProblemNotAGuess() async throws {
        let gone = AgentAccount(id: "gone", label: "Gone", location: .configDirectory("~/.claude-gone"))
        await #expect(throws: MissingAccountLocation(account: "gone", path: "~/.claude-gone")) {
            try await install(gone)
        }
        #expect(try await remove(gone).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude-gone").path))
    }

    @Test func folderWithoutSettingsGetsOnlyVigieHooks() async throws {
        let diff = try #require(try await install(work).first)
        let parsed = try OrderedJSON.parse(diff.newText)
        guard case .object(let root) = parsed else {
            Issue.record("not an object")
            return
        }
        #expect(root.map(\.key) == ["hooks"])
        #expect(diff.oldText.isEmpty)
    }

    @Test func projectScopeLeavesAccountLocationsAlone() async throws {
        let context = makeContext(settings: [ClaudeAdapter.SettingKey.hooksScope: "project"])
        #expect(try await adapter.integrationPlan(context: context, inputs: inputs, account: work).isEmpty)
        #expect(try await adapter.removalPlan(context: context, inputs: inputs, account: work).isEmpty)
    }

    @Test func accountWithoutLocationHasNoPlan() async throws {
        let bare = AgentAccount(id: "bare", label: "Bare", location: nil)
        #expect(try await install(bare).isEmpty)
    }

    // MARK: Attribution (A82)

    @Test func eventsWithAnAccountsConfigDirGoToThatAccount() {
        let fixed = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let adapter = ClaudeAdapter(homeDirectory: fixed)
        let accounts = [
            AgentAccount(id: .default, label: "", location: adapter.defaultAccountLocation),
            AgentAccount(id: "work", label: "Work", location: .configDirectory("~/.claude-work/")),
        ]
        func attributed(_ env: [String: String]) -> AccountID {
            AgentAccounts.attribute(adapter.accountLocationHint(env: env), among: accounts, home: fixed)
        }
        for form in [
            "/Users/me/.claude-work", "/Users/me/.claude-work/", "~/.claude-work", "~/.claude-work//",
            " /Users/me//.claude-work ", "/Users/me/./.claude-work",
        ] {
            #expect(attributed([ClaudeAdapter.configDirectoryVariable: form]) == "work", "\(form)")
        }
        #expect(attributed([ClaudeAdapter.configDirectoryVariable: "/Users/me/.claude-other"]) == .default)
        #expect(attributed([ClaudeAdapter.configDirectoryVariable: "~/.claude"]) == .default)
        #expect(attributed([:]) == .default)
    }
}
