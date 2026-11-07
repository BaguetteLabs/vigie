import AgentKit
import ModuleKit
import SwiftUI

/// The `agents.sessions` block of Settings › Agents (Story 4.7), below the generated rows. The Settings window
/// is a regular macOS window: native controls, no island theme tokens (like the generated settings controls).
/// Per adapter: name, detected version and support, connection status, Connect / Disconnect, and the pending
/// diff with Apply / Cancel.
struct AgentIntegrationsView: View {
    let model: AgentIntegrationsModel

    var body: some View {
        VStack(alignment: .leading, spacing: IntegrationMetrics.rowSpacing) {
            Text(verbatim: IntegrationText.string("agentsSessions.integration.title"))
                .font(.headline)
            ForEach(model.rows) { row in
                AgentIntegrationRow(row: row, model: model)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.refresh() }
    }
}

enum IntegrationMetrics {
    static let rowSpacing: CGFloat = 12
    static let lineSpacing: CGFloat = 4
    static let diffMaxHeight: CGFloat = 240
    static let diffPadding: CGFloat = 8
    static let diffCornerRadius: CGFloat = 6
}

struct AgentIntegrationRow: View {
    let row: AgentIntegrationsModel.Row
    let model: AgentIntegrationsModel

    var body: some View {
        VStack(alignment: .leading, spacing: IntegrationMetrics.lineSpacing) {
            LabeledContent {
                HStack {
                    if row.phase == .working {
                        ProgressView().controlSize(.small)
                    }
                    if row.canDisconnect {
                        Button {
                            Task { await model.disconnect(row.id) }
                        } label: {
                            Text(verbatim: IntegrationText.string("agentsSessions.integration.disconnect"))
                        }
                        .disabled(isBusy)
                    }
                    if row.canConnect {
                        Button {
                            Task { await model.connect(row.id) }
                        } label: {
                            Text(verbatim: IntegrationText.string("agentsSessions.integration.connect"))
                        }
                        .disabled(isBusy)
                    }
                }
            } label: {
                Text(verbatim: row.name)
                Text(verbatim: IntegrationText.status(row.status))
            }
            Text(verbatim: IntegrationText.support(row.support))
                .font(.caption)
                .foregroundStyle(isWarning ? .primary : .secondary)
            phaseView
        }
        .accessibilityElement(children: .contain)
    }

    private var isBusy: Bool {
        switch row.phase {
        case .working, .confirming: true
        default: false
        }
    }

    private var isWarning: Bool {
        switch row.support {
        case .assumed, .unsupported: true
        default: false
        }
    }

    @ViewBuilder private var phaseView: some View {
        switch row.phase {
        case .idle, .working:
            EmptyView()
        case .confirming(let preview, let changed):
            IntegrationConfirmation(
                preview: preview, changed: changed,
                apply: { Task { await model.confirm(row.id) } },
                cancel: { model.cancel(row.id) })
        case .applied(let action, let result):
            Text(verbatim: IntegrationText.applied(action, result))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Label {
                Text(verbatim: message).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.caption)
        }
    }
}

/// The diff to confirm: each file's summary and unified diff, then Apply / Cancel.
struct IntegrationConfirmation: View {
    let preview: IntegrationPreview
    let changed: Bool
    let apply: @MainActor () -> Void
    let cancel: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IntegrationMetrics.lineSpacing) {
            if changed {
                Label {
                    Text(verbatim: IntegrationText.string("agentsSessions.integration.changed"))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .font(.caption)
            }
            Text(verbatim: IntegrationText.string("agentsSessions.integration.review"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(preview.files, id: \.diff.path) { file in
                Text(verbatim: file.diff.summary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView([.vertical, .horizontal]) {
                    Text(verbatim: file.unifiedDiff)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(IntegrationMetrics.diffPadding)
                }
                .frame(maxHeight: IntegrationMetrics.diffMaxHeight)
                .background(
                    .quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: IntegrationMetrics.diffCornerRadius)
                )
                .accessibilityLabel(Text(verbatim: file.diff.summary))
            }
            HStack {
                Spacer()
                Button(action: cancel) {
                    Text(verbatim: IntegrationText.string("agentsSessions.integration.cancel"))
                }
                .keyboardShortcut(.cancelAction)
                Button(action: apply) {
                    Text(verbatim: IntegrationText.string("agentsSessions.integration.apply"))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
