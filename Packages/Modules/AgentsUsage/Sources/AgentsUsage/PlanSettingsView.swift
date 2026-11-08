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
                PlanProviderBlock(module: module, id: id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum PlanSettingsMetrics {
    static let blockSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 8
}

/// The block of one provider.
struct PlanProviderBlock: View {
    let module: AgentsUsageModule
    let id: AgentID
    @State private var enabled = false
    @State private var auth = PlanSettings.tokenAuth
    @State private var consent = false
    @State private var error: String?

    private var adapter: (any AgentAdapter)? { module.adapters.adapter(for: id) }
    private var provider: (any UsageProvider)? { adapter?.usageProvider }
    private var credential: ExternalCredentialDescriptor? { provider?.externalCredential }
    private var authOptions: [String] {
        let descriptor = adapter?.settings.first { $0.key == PlanSettings.authKey }
        if case .enumeration(let options, _) = descriptor?.kind { return options }
        return [PlanSettings.tokenAuth]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PlanSettingsMetrics.rowSpacing) {
            Text(verbatim: PlanSettingsText.title(provider))
                .font(.headline)
            Toggle(
                isOn: Binding(
                    get: { enabled }, set: { value in run { try await module.setPlanEnabled(value, for: id) } })
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
                                get: { auth }, set: { value in run { try await module.setPlanAuth(value, for: id) } })
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
                Text(verbatim: PlanSettingsText.status(module.planState(for: id)))
                    .font(.caption)
                    .foregroundStyle(module.planState(for: id)?.isStale == true ? .primary : .secondary)
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
                    id: "\(id.rawValue).\(PlanSettings.tokenKey)", label: descriptor.label, help: descriptor.help,
                    kind: .secret, binding: SettingBinding(get: { nil }, set: { _ in }),
                    secret: module.planTokenBinding(for: id)))
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
                run { try await module.revokePlanConsent(for: id) }
            } label: {
                Text(verbatim: UsageText.format("agentsUsage.plan.settings.stop", credential.displayName))
            }
        } else {
            Button {
                run { try await module.grantPlanConsent(for: id) }
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
        enabled = module.isPlanEnabled(id)
        auth = adapter.map(module.planAuth) ?? PlanSettings.tokenAuth
        consent = await module.hasPlanConsent(for: id)
    }
}

/// Copy of the plan block.
enum PlanSettingsText {
    static func title(_ provider: (any UsageProvider)?) -> String {
        UsageText.format("agentsUsage.plan.settings.title", provider.map { String(localized: $0.name) } ?? "")
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
    /// The pasted token, through the adapter's own SecretStore (owner `adapter.<id>`). Never read back.
    func planTokenBinding(for id: AgentID) -> SecretSettingBinding? {
        guard let secrets = adapterContexts[id]?.secrets else { return nil }
        return SecretSettingBinding(
            isSet: { try await secrets.contains(PlanSettings.tokenKey) },
            set: { [weak self] value in
                try await secrets.write(value, for: PlanSettings.tokenKey)
                await self?.refreshPlan(id)
            })
    }
}
