import AgentKit
import ModuleKit
import SwiftUI
import VigieUI

/// The plan-usage block of Settings › Usage (Story 7.3, A57), below the generated rows: per provider with a
/// remote source, the `plan` toggle, how to sign in (`plan_auth`, local), the pasted token (SecretStore) or the
/// consent to read the other app's login, and the last fetch. Native controls, like the generated rows.
///
/// AD-1: `agents.sessions` owns Settings › Agents but cannot import this module, so the block lives here.
struct PlanSettingsView: View {
    let module: AgentsUsageModule
    let adapters: [AgentID]

    var body: some View {
        VStack(alignment: .leading, spacing: PlanSettingsMetrics.blockSpacing) {
            ForEach(adapters, id: \.self) { id in
                // One block per Account (Story 7.10); a single Account keeps the 7.3 block as it was.
                ForEach(module.accounts(of: id)) { account in
                    PlanProviderBlock(module: module, key: UsageAccountKey(provider: id, account: account.id))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum PlanSettingsMetrics {
    static let blockSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 8
}

/// The block of one provider Account.
struct PlanProviderBlock: View {
    let module: AgentsUsageModule
    let key: UsageAccountKey
    private var id: AgentID { key.provider }
    private var account: AgentAccount? { module.accounts(of: key.provider).first { $0.id == key.account } }
    @State private var enabled = false
    @State private var auth = PlanSettings.tokenAuth
    @State private var consent = false
    @State private var error: String?

    private var adapter: (any AgentAdapter)? { module.adapters.adapter(for: id) }
    private var provider: (any UsageProvider)? { adapter?.usageProvider }
    private var credential: ExternalCredentialDescriptor? {
        account.flatMap { provider?.externalCredential(for: $0) }
    }
    private var authOptions: [String] {
        let descriptor = adapter?.settings.first { $0.key == PlanSettings.authKey }
        if case .enumeration(let options, _) = descriptor?.kind { return options }
        return [PlanSettings.tokenAuth]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PlanSettingsMetrics.rowSpacing) {
            Text(verbatim: PlanSettingsText.title(provider, account: account, several: module.hasSeveralAccounts(id)))
                .font(.headline)
            Toggle(
                isOn: Binding(
                    get: { enabled }, set: { value in run { try await module.setPlanEnabled(value, for: key) } })
            ) {
                Text(UsageText.resource("agentsUsage.plan.settings.toggle"))
                Text(UsageText.resource("agentsUsage.plan.settings.toggle.help"))
            }
            .disabled(module.adapterSettingsStores[id] == nil)
            if enabled {
                if authOptions.count > 1 {
                    LabeledContent {
                        Picker(
                            selection: Binding(
                                get: { auth }, set: { value in run { try await module.setPlanAuth(value, for: key) } })
                        ) {
                            ForEach(authOptions, id: \.self) { option in
                                Text(verbatim: PlanSettingsText.authOption(option, credential: credential)).tag(option)
                            }
                        } label: {
                            Text(UsageText.resource("agentsUsage.plan.settings.auth"))
                        }
                        .labelsHidden()
                        .fixedSize()
                    } label: {
                        Text(UsageText.resource("agentsUsage.plan.settings.auth"))
                    }
                }
                if auth == PlanSettings.tokenAuth || credential == nil {
                    tokenRow
                } else if let credential {
                    consentRows(credential)
                }
                Text(verbatim: PlanSettingsText.status(module.planState(for: key)))
                    .font(.caption)
                    .foregroundStyle(module.planState(for: key)?.isStale == true ? .primary : .secondary)
            }
            if let error {
                Text(verbatim: error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task { await reload() }
    }

    @ViewBuilder private var tokenRow: some View {
        if let descriptor = adapter?.settings.first(where: { $0.key == PlanSettings.tokenKey }) {
            SettingRow(
                SettingRowModel(
                    id: "\(key).\(PlanSettings.tokenKey)", label: descriptor.label, help: descriptor.help,
                    kind: .secret, binding: SettingBinding(get: { nil }, set: { _ in }),
                    secret: module.planTokenBinding(for: key)))
        }
    }

    @ViewBuilder private func consentRows(_ credential: ExternalCredentialDescriptor) -> some View {
        Text(credential.explanation)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        Text(verbatim: PlanSettingsText.keychainItem(credential))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if consent {
            Button {
                run { try await module.revokePlanConsent(for: key) }
            } label: {
                Text(verbatim: UsageText.format("agentsUsage.plan.settings.stop", credential.displayName))
            }
        } else {
            Button {
                run { try await module.grantPlanConsent(for: key) }
            } label: {
                Text(UsageText.resource("agentsUsage.plan.settings.allow"))
            }
            Text(UsageText.resource("agentsUsage.plan.settings.allow.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do {
                try await action()
                error = nil
            } catch {
                self.error = UsageText.string("agentsUsage.plan.settings.writeFailed")
            }
            await reload()
        }
    }

    private func reload() async {
        enabled = module.isPlanEnabled(key)
        if let adapter, let account {
            auth = module.planAuth(adapter, account: account)
        } else {
            auth = PlanSettings.tokenAuth
        }
        consent = await module.hasPlanConsent(for: key)
    }
}

/// Copy of the plan block.
enum PlanSettingsText {
    static func title(_ provider: (any UsageProvider)?) -> String {
        title(provider, account: nil, several: false)
    }

    /// `Claude plan limits`, or `Claude · Work plan limits` with several Accounts.
    static func title(_ provider: (any UsageProvider)?, account: AgentAccount?, several: Bool) -> String {
        let name = provider.map { String(localized: $0.name) } ?? ""
        return UsageText.format(
            "agentsUsage.plan.settings.title", AgentsUsageModule.displayName(name, account: account, several: several))
    }

    static func authOption(_ option: String, credential: ExternalCredentialDescriptor?) -> String {
        if option == PlanSettings.tokenAuth { return UsageText.string("agentsUsage.plan.settings.auth.token") }
        return UsageText.format("agentsUsage.plan.settings.auth.external", credential?.displayName ?? option)
    }

    static func keychainItem(_ credential: ExternalCredentialDescriptor) -> String {
        UsageText.format("agentsUsage.plan.settings.keychainItem", credential.service, credential.displayName)
    }

    static func status(_ state: PlanState?) -> String {
        guard let state else { return UsageText.string("agentsUsage.plan.status.never") }
        let error = state.lastError.map(errorText)
        if let fetched = state.fetchedAt {
            let time = PlanState.timeText(fetched)
            guard state.isStale else { return UsageText.format("agentsUsage.plan.status.updated", time) }
            let stale = UsageText.format("agentsUsage.plan.stale", time)
            return error.map { "\(stale) · \($0)" } ?? stale
        }
        return error ?? UsageText.string("agentsUsage.plan.status.never")
    }

    static func errorText(_ error: PlanUsageError) -> String {
        switch error {
        case .unavailable: UsageText.string("agentsUsage.plan.error.network")
        case .formatChanged: UsageText.string("agentsUsage.plan.error.formatChanged")
        case .unauthorized: UsageText.string("agentsUsage.plan.error.unauthorized")
        case .credentialExpired: UsageText.string("agentsUsage.plan.error.expired")
        case .credentialMissing: UsageText.string("agentsUsage.plan.error.missing")
        case .consentRequired: UsageText.string("agentsUsage.plan.error.consent")
        case .credentialDenied: UsageText.string("agentsUsage.plan.error.denied")
        }
    }
}

extension PlanState {
    /// `HH:MM` of `date` (24-hour, current time zone), as in `STALE · HH:MM`.
    public static func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// `STALE · HH:MM` (time of the last good fetch) when stale with values; nil otherwise (UX-DR99).
    public var staleLabel: String? {
        guard isStale, let fetchedAt else { return nil }
        return UsageText.format("agentsUsage.plan.stale", Self.timeText(fetchedAt))
    }
}

extension AgentsUsageModule {
    /// The pasted token, through the adapter's own SecretStore (owner `adapter.<id>`), never read back. One
    /// Account's pasted token: its own Keychain item (`plan_token` for the default Account,
    /// `plan_token.<account>` for another; AD-9: one item per Account).
    func planTokenBinding(for key: UsageAccountKey) -> SecretSettingBinding? {
        guard let secrets = adapterContexts[key.provider]?.secrets, let account = account(key) else { return nil }
        let secretKey = account.secretKey(PlanSettings.tokenKey)
        return SecretSettingBinding(
            isSet: { try await secrets.contains(secretKey) },
            set: { [weak self] value in
                try await secrets.write(value, for: secretKey)
                await self?.refreshPlan(key)
            })
    }
}
