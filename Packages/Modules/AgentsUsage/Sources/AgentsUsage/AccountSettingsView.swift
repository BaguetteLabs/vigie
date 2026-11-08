import AgentKit
import SwiftUI
import VigieUI

/// Settings › Usage › <Provider> Accounts (Story 7.10, PRD FR-29, A82): every Account with its label and
/// config folder, the default marked; add one (label + folder) or remove one. Stored in `local.toml` only
/// (AD-8): Accounts and their locations never sync. Native controls, like the generated rows.
struct AccountSettingsView: View {
    let module: AgentsUsageModule
    let id: AgentID
    @State private var label = ""
    @State private var location = ""
    @State private var error: String?

    private var adapter: (any AgentAdapter)? { module.adapters.adapter(for: id) }

    var body: some View {
        VStack(alignment: .leading, spacing: PlanSettingsMetrics.rowSpacing) {
            Text(
                verbatim: UsageText.format(
                    "agentsUsage.accounts.title", adapter.map { String(localized: $0.name) } ?? "")
            )
            .font(.headline)
            ForEach(module.accounts(of: id)) { account in
                AccountRow(module: module, id: id, account: account, onError: { error = $0 })
            }
            HStack {
                TextField(
                    text: $label, prompt: Text(UsageText.resource("agentsUsage.accounts.add.label"))
                ) { Text(UsageText.resource("agentsUsage.accounts.add.label")) }
                .labelsHidden()
                .frame(maxWidth: AccountSettingsMetrics.labelWidth)
                TextField(
                    text: $location, prompt: Text(UsageText.resource("agentsUsage.accounts.add.location"))
                ) { Text(UsageText.resource("agentsUsage.accounts.add.location")) }
                .labelsHidden()
                Button {
                    add()
                } label: {
                    Text(UsageText.resource("agentsUsage.accounts.add"))
                }
                .disabled(
                    label.trimmingCharacters(in: .whitespaces).isEmpty
                        || location.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(UsageText.resource("agentsUsage.accounts.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(verbatim: error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func add() {
        let label = label
        let location = location
        Task { @MainActor in
            do {
                try await module.addAccount(label: label, location: location, to: id)
                self.label = ""
                self.location = ""
                error = nil
            } catch AccountSettingsError.duplicateLocation {
                error = UsageText.string("agentsUsage.accounts.error.duplicate")
            } catch {
                self.error = UsageText.string("agentsUsage.plan.settings.writeFailed")
            }
        }
    }
}

enum AccountSettingsMetrics {
    static let labelWidth: CGFloat = 160
}

/// One Account: its label (editable), `DEFAULT` for the default, its folder, Remove for the others.
struct AccountRow: View {
    let module: AgentsUsageModule
    let id: AgentID
    let account: AgentAccount
    let onError: (String?) -> Void
    @State private var label = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    TextField(
                        text: $label, prompt: Text(verbatim: AgentsUsageModule.label(of: account))
                    ) { Text(UsageText.resource("agentsUsage.accounts.rename")) }
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .onSubmit(rename)
                    .frame(maxWidth: AccountSettingsMetrics.labelWidth)
                    if account.isDefault {
                        Text(UsageText.resource("agentsUsage.accounts.defaultBadge"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(verbatim: account.location?.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .help(account.location?.path ?? "")
            }
            Spacer()
            if !account.isDefault {
                Button(role: .destructive) {
                    Task { @MainActor in
                        do {
                            try await module.removeAccount(account.id, from: id)
                            onError(nil)
                        } catch {
                            onError(UsageText.string("agentsUsage.plan.settings.writeFailed"))
                        }
                    }
                } label: {
                    Text(UsageText.resource("agentsUsage.accounts.remove"))
                }
            }
        }
        .onAppear { label = account.label }
    }

    private func rename() {
        let label = label
        guard label != account.label else { return }
        Task { @MainActor in
            do {
                try await module.renameAccount(account.id, of: id, to: label)
                onError(nil)
            } catch {
                onError(UsageText.string("agentsUsage.plan.settings.writeFailed"))
            }
        }
    }
}
