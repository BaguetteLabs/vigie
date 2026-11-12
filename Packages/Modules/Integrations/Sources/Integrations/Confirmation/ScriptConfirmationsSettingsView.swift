import ModuleKit
import SwiftUI
import VigieUI

/// The scripts block of the integrations Settings pane (Story 12.3; Story 12.6 grows it into Settings › Scripts).
/// The Settings window is a regular macOS window: native controls and text styles (DESIGN "Settings window").
/// Per script: name, file, state on this Mac (`NOT CONFIRMED` without a glyph, `CONFIRMED`, `DECLINED`, or the
/// parse problem) and Review, which opens the Script Confirmation as a sheet.
struct ScriptConfirmationsSettingsView: View {
    let module: IntegrationsModule
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ScriptSettingsMetrics.rowSpacing) {
            Text(verbatim: IntegrationsText.string("script.settings.title")).font(.headline)
            if module.scripts.isEmpty {
                Text(verbatim: IntegrationsText.string("script.settings.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(module.scripts) { script in
                row(script)
            }
            if let failure {
                Label {
                    Text(verbatim: failure).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: reviewBinding) { script in
            ScriptConfirmationView(
                content: module.confirmationContent(for: script),
                onConfirm: { decide(script, confirm: true) },
                onDecline: { decide(script, confirm: false) },
                onCancel: { module.cancelConfirmation() })
        }
    }

    private var reviewBinding: Binding<ScriptModuleDefinition?> {
        Binding(get: { module.reviewing }, set: { if $0 == nil { module.cancelConfirmation() } })
    }

    private func row(_ script: ScriptModuleDefinition) -> some View {
        LabeledContent {
            HStack {
                stateView(script)
                Button {
                    failure = nil
                    module.openConfirmation(for: script)
                } label: {
                    Text(verbatim: IntegrationsText.string("script.settings.review"))
                }
            }
        } label: {
            Text(verbatim: script.frontMatter?.name ?? script.fileName).sensitive()
            Text(verbatim: script.relativePath).sensitive()
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func stateView(_ script: ScriptModuleDefinition) -> some View {
        if script.status.error != nil {
            Text(verbatim: IntegrationsText.string("script.settings.state.errored"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(script.errorMessage ?? "")
        } else {
            switch module.localState(for: script) {
            case .awaitingConfirmation:
                // `NOT CONFIRMED`, no level glyph (UX-DR87); `.secondary` is the native counterpart of `ink-3`.
                Button {
                    failure = nil
                    module.openConfirmation(for: script)
                } label: {
                    Text(verbatim: ScriptStateLabel.notConfirmedText).font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            case .confirmed:
                Text(verbatim: IntegrationsText.string("script.settings.state.confirmed"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .declined:
                Text(verbatim: IntegrationsText.string("script.settings.state.declined"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func decide(_ script: ScriptModuleDefinition, confirm: Bool) {
        Task {
            do {
                if confirm { try await module.confirm(script) } else { try await module.decline(script) }
            } catch {
                failure = IntegrationsText.format(
                    "script.settings.saveFailed", script.fileName, String(describing: error))
                module.cancelConfirmation()
            }
        }
    }
}

enum ScriptSettingsMetrics {
    static let rowSpacing: CGFloat = 12
}
