import AgentKit
import Foundation
import ModuleKit

/// Why an Account could not be added (Settings › Usage).
public enum AccountSettingsError: Error, Hashable, Sendable {
    case emptyLabel
    case emptyLocation
    /// Another Account (or the default) already uses this folder.
    case duplicateLocation
    case notAvailable
}

// MARK: - Accounts (Story 7.10)

extension AgentsUsageModule {
    /// Characters of the Account label on the closed-notch wing (`CLAUDE · WORK`, UX-DR99).
    nonisolated static let wingAccountLength = 6

    /// The adapter's Accounts, the default first (AD-23 amended). A setup from before Story 7.10 has the default
    /// alone, with its 7.3 settings.
    public func accounts(of id: AgentID) -> [AgentAccount] {
        guard let adapter = adapters.adapter(for: id) else { return [] }
        return accounts(adapter)
    }

    /// Providers whose adapter supports Accounts (it declares a default location), in the user's order.
    var accountAdapters: [AgentID] {
        orderableProviders.filter { $0.defaultAccountLocation != nil }.map(\.id)
    }

    func accounts(_ adapter: any AgentAdapter) -> [AgentAccount] {
        adapter.accounts(settings: adapterSettings(adapter))
    }

    /// True when the provider has several Accounts: only then do labels carry the Account (UX-DR99).
    public func hasSeveralAccounts(_ id: AgentID) -> Bool { accounts(of: id).count > 1 }

    func account(_ key: UsageAccountKey) -> AgentAccount? {
        accounts(of: key.provider).first { $0.id == key.account }
    }

    /// The Account's label, `Default` for an unnamed default Account.
    nonisolated static func label(of account: AgentAccount) -> String {
        account.label.isEmpty
            ? (account.isDefault ? UsageText.string("agentsUsage.account.default") : account.id.rawValue)
            : account.label
    }

    /// `Claude · Work` with several Accounts, else `Claude`.
    nonisolated static func displayName(_ name: String, account: AgentAccount?, several: Bool) -> String {
        guard several, let account else { return name }
        return UsageText.format("agentsUsage.account.join", name, label(of: account))
    }

    /// The sources of the Account (`usage_providers`): its own key past the default (Story 7.10).
    func usageSources(_ adapter: any AgentAdapter, account: AgentAccount) -> [String] {
        adapterSettings(adapter).value(
            account.settingKey(UsageProviderRegistry.usageProvidersKey), as: [String].self)
            ?? [UsageProviderRegistry.localSource]
    }

    // MARK: Settings actions

    /// Adds an Account bound to `location` (Settings › Usage): id slugged from `label`, keys in `local.toml`.
    @discardableResult
    public func addAccount(label: String, location: String, to id: AgentID) async throws -> AccountID {
        guard let store = adapterSettingsStores[id], let adapter = adapters.adapter(for: id) else {
            throw AccountSettingsError.notAvailable
        }
        let label = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentAccounts.maxLabelLength))
        let path = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw AccountSettingsError.emptyLabel }
        guard !path.isEmpty else { throw AccountSettingsError.emptyLocation }
        let existing = accounts(adapter)
        let wanted = AccountLocation.configDirectory(path)
        if existing.contains(where: { $0.location?.matches(wanted, home: homeDirectory) == true }) {
            throw AccountSettingsError.duplicateLocation
        }
        let account = AccountID.slug(from: label, taken: Set(existing.map(\.id)))
        let prefix = "\(AgentAccounts.tableSegment).\(account.rawValue)."
        try await store.set(label, for: prefix + AgentAccounts.labelKey)
        try await store.set(path, for: prefix + AgentAccounts.locationKey)
        let listed = adapterSettings(adapter).value(AgentAccounts.listKey, as: [String].self) ?? []
        try await store.set(listed + [account.rawValue], for: AgentAccounts.listKey)
        log?.info("agents.usage added an Account to \(id.rawValue, privacy: .public)")
        restartPlanObservers()
        await refreshPlans()
        return account
    }

    /// Removes a non-default Account: its keys, its pasted token and its consent. Its history stays in the
    /// database (re-adding the same id shows it again).
    public func removeAccount(_ account: AccountID, from id: AgentID) async throws {
        guard !account.isDefault, let store = adapterSettingsStores[id], let adapter = adapters.adapter(for: id),
            let removed = accounts(adapter).first(where: { $0.id == account })
        else { throw AccountSettingsError.notAvailable }
        let key = UsageAccountKey(provider: id, account: account)
        dropPlan(key)
        if let context = adapterContexts[id] {
            try? await context.secrets.write(nil, for: removed.secretKey(PlanSettings.tokenKey))
            if let descriptor = adapter.usageProvider?.externalCredential(for: removed) {
                try? await context.secrets.revokeConsent(for: descriptor)
            }
        }
        let listed = adapterSettings(adapter).value(AgentAccounts.listKey, as: [String].self) ?? []
        try await store.set(listed.filter { $0 != account.rawValue }, for: AgentAccounts.listKey)
        for field in [
            AgentAccounts.labelKey, AgentAccounts.locationKey, UsageProviderRegistry.usageProvidersKey,
            PlanSettings.authKey,
        ] {
            try? await store.set(nil as String?, for: removed.settingKey(field))
        }
        restartPlanObservers()
    }

    /// Names the Account (the default Account too: `account.default.label`).
    public func renameAccount(_ account: AccountID, of id: AgentID, to label: String) async throws {
        guard let store = adapterSettingsStores[id] else { throw AccountSettingsError.notAvailable }
        let label = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentAccounts.maxLabelLength))
        guard !label.isEmpty || account.isDefault else { throw AccountSettingsError.emptyLabel }
        try await store.set(
            label.isEmpty ? nil : label,
            for: "\(AgentAccounts.tableSegment).\(account.rawValue).\(AgentAccounts.labelKey)")
    }
}
