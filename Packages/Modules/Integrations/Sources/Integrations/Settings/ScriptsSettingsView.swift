import ModuleKit
import SwiftUI
import VigieUI

/// Settings › Scripts (Story 12.6, UX-DR74), the integrations module's pane. A regular macOS window: native
/// controls and text styles (DESIGN "Settings window"), rows inside the pane's grouped `Form` section.
///
/// Per script: name, file, state (running, ok, errored with its run label, `NOT CONFIRMED`, declined, disabled,
/// can't load) and last run, then Refresh (eligible scripts only), Review (the Script Confirmation sheet) and the
/// per-Mac enable switch. Expanding a script shows its declared settings as generated controls; `secret` fields
/// save to this Mac's Keychain only. A footer links to the Script repository.
struct ScriptsSettingsView: View {
    let module: IntegrationsModule
    @State private var failure: String?
    @State private var expanded: String?
    @State private var notice: String?

    var body: some View {
        // A Group, so each part is its own row of the pane's Form section; the sheet hangs on the heading only
        // (a modifier on the Group would attach one sheet per row).
        Group {
            Text(verbatim: IntegrationsText.string("script.settings.title"))
                .font(.headline)
                .sheet(item: reviewBinding) { script in
                    ScriptConfirmationView(
                        content: module.confirmationContent(for: script),
                        onConfirm: { decide(script, confirm: true) },
                        onDecline: { decide(script, confirm: false) },
                        onCancel: { module.cancelConfirmation() })
                }
            if module.scripts.isEmpty {
                Text(verbatim: IntegrationsText.string("script.settings.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(module.paneRows()) { row in
                if let script = module.scripts.first(where: { $0.id == row.id }) {
                    DisclosureGroup(isExpanded: expansion(row.id)) {
                        detail(script, row: row)
                    } label: {
                        summary(script, row: row)
                    }
                }
            }
            if let failure {
                Label {
                    Text(verbatim: failure).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
            }
            if let notice {
                Text(verbatim: notice).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                examplesMenu
                Spacer()
                repositoryFooter
            }
        }
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(get: { expanded == id }, set: { expanded = $0 ? id : nil })
    }

    private var reviewBinding: Binding<ScriptModuleDefinition?> {
        Binding(get: { module.reviewing }, set: { if $0 == nil { module.cancelConfirmation() } })
    }

    // MARK: - Rows

    private func summary(_ script: ScriptModuleDefinition, row: ScriptPaneRow) -> some View {
        LabeledContent {
            HStack {
                stateView(script, row: row)
                Button {
                    module.refresh(scriptID: row.id)
                } label: {
                    Text(verbatim: IntegrationsText.string("script.settings.refresh"))
                }
                .disabled(!row.canRefresh)
                Button {
                    failure = nil
                    module.openConfirmation(for: script)
                } label: {
                    Text(verbatim: IntegrationsText.string("script.settings.review"))
                }
                Toggle(
                    isOn: Binding(get: { row.isEnabled }, set: { setEnabled(script, $0) })
                ) {
                    Text(verbatim: IntegrationsText.string("script.settings.enabled"))
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .help(IntegrationsText.string("script.settings.enabled.help"))
            }
        } label: {
            Text(verbatim: row.name).sensitive()
            Text(verbatim: row.file).sensitive()
            Text(verbatim: row.lastRunText())
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func stateView(_ script: ScriptModuleDefinition, row: ScriptPaneRow) -> some View {
        switch row.state {
        case .awaitingConfirmation:
            // `NOT CONFIRMED`, no level glyph (UX-DR87); `.secondary` is the native counterpart of `ink-3`.
            Button {
                failure = nil
                module.openConfirmation(for: script)
            } label: {
                Text(verbatim: row.state.label).font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        default:
            Text(verbatim: row.state.label)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .help(row.problem ?? "")
        }
    }

    @ViewBuilder private func detail(_ script: ScriptModuleDefinition, row: ScriptPaneRow) -> some View {
        if let problem = row.problem {
            Text(verbatim: problem)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .sensitive()
        } else {
            let settings = module.settingRows(for: script)
            if settings.isEmpty {
                Text(verbatim: IntegrationsText.string("script.settings.noSettings"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(settings) { SettingRow($0) }
        }
    }

    @ViewBuilder private var repositoryFooter: some View {
        let title = IntegrationsText.string("script.settings.repository")
        if let url = ScriptRepository.url {
            Link(destination: url) { Text(verbatim: title) }
        } else {
            Text(verbatim: title)
                .foregroundStyle(.secondary)
                .help(IntegrationsText.string("script.settings.repository.unpublished"))
        }
    }

    /// "Add example…" (Story 12.7): copies a bundled example into the scripts folder; the copy then waits for
    /// confirmation like any new file.
    private var examplesMenu: some View {
        Menu {
            ForEach(IntegrationsModule.bundledExamples) { example in
                Button {
                    add(example)
                } label: {
                    Text(verbatim: example.name)
                }
                .disabled(module.scripts.contains { $0.fileName == example.fileName })
            }
        } label: {
            Text(verbatim: IntegrationsText.string("script.settings.addExample"))
        }
        .fixedSize()
        .help(IntegrationsText.string("script.settings.addExample.help"))
    }

    // MARK: - Actions

    private func add(_ example: BundledExample) {
        failure = nil
        notice = nil
        Task {
            do {
                try await module.addExample(example)
                notice = IntegrationsText.format("script.settings.addExample.added", example.fileName)
            } catch let error as ExampleAddError {
                switch error {
                case .noFolder: failure = IntegrationsText.string("script.settings.addExample.noFolder")
                case .exists(let name): failure = IntegrationsText.format("script.settings.addExample.exists", name)
                case .idInUse(let name, let other):
                    failure = IntegrationsText.format("script.settings.addExample.idInUse", name, other)
                }
            } catch {
                failure = IntegrationsText.format(
                    "script.settings.saveFailed", example.fileName, String(describing: error))
            }
        }
    }

    private func setEnabled(_ script: ScriptModuleDefinition, _ enabled: Bool) {
        failure = nil
        Task {
            do {
                try await module.setEnabled(enabled, for: script)
            } catch {
                failure = IntegrationsText.format(
                    "script.settings.saveFailed", script.fileName, String(describing: error))
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
