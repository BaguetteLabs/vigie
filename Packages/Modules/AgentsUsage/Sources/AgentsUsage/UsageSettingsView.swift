import AgentKit
import SwiftUI
import VigieUI

/// Settings › Usage custom block (Story 7.9, then 7.3, 7.10): the provider order list, each provider's Accounts,
/// then the plan block of each Account. The
/// list is every provider in the user's order: drag to reorder, or Move up / Move down (VoiceOver); it writes
/// the same `order` key as the Usage tab. Its rows are direct children so `onMove` works in the Form.
struct UsageSettingsView: View {
    let module: AgentsUsageModule
    let planAdapters: [AgentID]

    var body: some View {
        let rows = module.orderableProviders.map { (id: $0.id.rawValue, name: String(localized: $0.name)) }
        Text(UsageText.resource("agentsUsage.order.title")).font(.headline)
        ForEach(rows, id: \.id) { row in
            HStack {
                Text(verbatim: row.name)
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .accessibilityAction(named: Text(UsageText.resource("agentsUsage.order.moveUp"))) {
                Task { await module.moveProvider(row.id, by: -1) }
            }
            .accessibilityAction(named: Text(UsageText.resource("agentsUsage.order.moveDown"))) {
                Task { await module.moveProvider(row.id, by: 1) }
            }
        }
        .onMove { source, destination in
            let moved = UsageProviderOrder.moved(rows.map(\.id), fromOffsets: source, toOffset: destination)
            Task { await module.setProviderOrder(shown: moved) }
        }
        Text(UsageText.resource("agentsUsage.order.help")).font(.caption).foregroundStyle(.secondary)
        // Accounts first (Story 7.10), then each Account's plan block.
        ForEach(module.accountAdapters, id: \.self) { id in
            AccountSettingsView(module: module, id: id)
        }
        if !planAdapters.isEmpty {
            PlanSettingsView(module: module, adapters: planAdapters)
        }
    }
}
