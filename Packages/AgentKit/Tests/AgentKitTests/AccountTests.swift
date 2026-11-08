import Foundation
import Testing

@testable import AgentKit

private struct Values: ReadOnlySettings {
    var values: [String: any SettingValue]
    func value<T: SettingValue>(_ key: String, as type: T.Type) -> T? { values[key] as? T }
}

private struct PlainAdapter: AgentAdapter {
    var id: AgentID { "plain" }
    var name: LocalizedStringResource { "Plain" }
    var capabilities: Set<AgentCapability> { [] }
    func normalize(_ hook: HookPayload, sentAt: Date) -> [AgentEvent] { [] }
}

@Suite struct AccountTests {
    let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    @Test func slugsComeFromLabelsAndStayUnique() {
        #expect(AccountID.slug(from: "Work", taken: []) == "work")
        #expect(AccountID.slug(from: "Côté Client!", taken: []) == "cote-client")
        #expect(AccountID.slug(from: "2nd", taken: []) == "account-2nd")
        #expect(AccountID.slug(from: "  ", taken: []) == "account")
        #expect(AccountID.slug(from: "Work", taken: ["work"]) == "work-2")
        #expect(AccountID.slug(from: "Default", taken: []) == "default-2")
        #expect(
            AccountID.slug(from: String(repeating: "a", count: 80), taken: []).rawValue.count <= AccountID.maxLength)
    }

    @Test func locationsNormalizeTildeTrailingSlashAndDots() {
        let a = AccountLocation.configDirectory("~/.claude-work/")
        let b = AccountLocation.configDirectory("/Users/me/x/../.claude-work")
        #expect(a.normalizedPath(home: home) == "/Users/me/.claude-work")
        #expect(a.matches(b, home: home))
        #expect(!a.matches(.configDirectory("~/.claude"), home: home))
        #expect(AccountLocation.configDirectory("~").normalizedPath(home: home) == "/Users/me")
    }

    @Test func accountsListTheDefaultFirstThenListedOnesWithALocation() {
        let settings = Values(values: [
            "accounts": ["work", "work", "Bad Id", "nolocation", "perso"],
            "account.work.label": "Work", "account.work.location": "~/.claude-work",
            "account.perso.location": "/p", "account.default.label": "Personal",
        ])
        let accounts = AgentAccounts.accounts(in: settings, defaultLocation: .configDirectory("~/.claude"))
        #expect(accounts.map(\.id) == [.default, "work", "perso"])
        #expect(accounts.map(\.label) == ["Personal", "Work", "perso"])
        #expect(accounts[1].location == .configDirectory("~/.claude-work"))
    }

    @Test func aPreStorySetupIsTheDefaultAccountAlone() {
        let accounts = AgentAccounts.accounts(
            in: Values(values: ["usage_providers": ["local", "plan"], "plan_auth": "token"]),
            defaultLocation: .configDirectory("~/.claude"))
        #expect(accounts == [AgentAccount(id: .default, label: "", location: .configDirectory("~/.claude"))])
        #expect(accounts[0].settingKey("plan_auth") == "plan_auth")
        #expect(accounts[0].secretKey("plan_token") == "plan_token")
        #expect(accounts[0].credentialID("claude.login") == "claude.login")
    }

    @Test func perAccountKeysOfOtherAccounts() {
        let work = AgentAccount(id: "work", label: "Work", location: .configDirectory("/w"))
        #expect(work.settingKey("plan_auth") == "account.work.plan_auth")
        #expect(work.secretKey("plan_token") == "plan_token.work")
        #expect(work.credentialID("claude.login") == "claude.login.work")
    }

    @Test func attributionMatchesNormalizedLocationsElseDefault() {
        let accounts = [
            AgentAccount(id: .default, label: "", location: .configDirectory("~/.claude")),
            AgentAccount(id: "work", label: "Work", location: .configDirectory("~/.claude-work")),
        ]
        #expect(
            AgentAccounts.attribute(.configDirectory("/Users/me/.claude-work/"), among: accounts, home: home) == "work")
        #expect(AgentAccounts.attribute(.configDirectory("/Users/me/.claude"), among: accounts, home: home) == .default)
        #expect(AgentAccounts.attribute(.configDirectory("/elsewhere"), among: accounts, home: home) == .default)
        #expect(AgentAccounts.attribute(nil, among: accounts, home: home) == .default)
    }

    @Test func descriptorsAreLocalTemplatesWithoutSecrets() {
        let perAccount = [
            SettingDescriptor(key: "plan_auth", label: "Auth", kind: .enumeration(options: ["a", "b"], default: "a")),
            SettingDescriptor(key: "plan_token", label: "Token", kind: .secret, scope: .local),
        ]
        let descriptors = AgentAccounts.descriptors(perAccount: perAccount)
        #expect(descriptors.map(\.key) == ["accounts", "account.*.label", "account.*.location", "account.*.plan_auth"])
        #expect(descriptors.allSatisfy { $0.scope == .local })
    }

    @Test func adaptersWithoutAccountsKeepTheirLogReaderForTheDefault() {
        let adapter = PlainAdapter()
        #expect(adapter.defaultAccountLocation == nil)
        #expect(adapter.accountLocationHint(env: ["CLAUDE_CONFIG_DIR": "/x"]) == nil)
        #expect(adapter.accounts(settings: Values(values: [:])).map(\.id) == [.default])
    }
}
