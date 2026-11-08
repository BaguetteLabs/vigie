import AppKit
import ModuleKit
import SwiftUI
import VigieUI

/// Sidebar + detail split. Native controls, system appearance and text styles (UX-DR39).
struct SettingsRootView: View {
    let controller: SettingsController

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(controller: controller)
                .navigationSplitViewColumnWidth(
                    min: SettingsWindowMetrics.sidebarMinWidth, ideal: SettingsWindowMetrics.sidebarWidth)
        } detail: {
            SettingsPaneView(controller: controller, pane: controller.selectedPane)
                .id(controller.selectedPane.id)
        }
        .toolbar(removing: .sidebarToggle)
        .navigationTitle(Text(SettingsText.resource("settings.window.title")))
    }
}

struct SettingsSidebar: View {
    let controller: SettingsController

    var body: some View {
        let selection = Binding<String?>(
            get: { controller.selectedPaneID },
            set: { if let id = $0 { controller.selectedPaneID = id } })
        List(selection: selection) {
            Section {
                ForEach(controller.panes.filter { !$0.isModule }) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.icon)
                    }
                    .tag(pane.id)
                }
            }
            let modules = controller.panes.filter(\.isModule)
            if !modules.isEmpty {
                Section {
                    ForEach(modules) { pane in
                        Label {
                            Text(pane.title)
                        } icon: {
                            Image(systemName: pane.icon)
                        }
                        .tag(pane.id)
                    }
                } header: {
                    Text(SettingsText.resource("settings.sidebar.modules"))
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// One pane: a grouped `Form` of generated rows plus the pane's extras.
struct SettingsPaneView: View {
    let controller: SettingsController
    let pane: SettingsPane

    var body: some View {
        Form {
            switch pane.content {
            case .core(let sections):
                if pane.id == "general" { LaunchAtLoginSection(controller: controller) }
                if pane.id == "sounds" { SoundsPaneContent(controller: controller) }
                if pane.id == SettingsPaneCatalog.homePaneID { HomePaneContent(model: controller.home) }
                ForEach(Array((pane.id == "sounds" ? [] : sections).enumerated()), id: \.offset) { _, section in
                    Section {
                        ForEach(section.keys.compactMap(controller.rowModel(for:))) { model in
                            if model.id == "privacy.auto" {
                                PrivacyAutoRow(controller: controller, model: model)
                            } else {
                                SettingRow(model)
                            }
                            if model.id == "appearance.presence",
                                NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                            {
                                Text(SettingsText.resource("settings.appearance.reduceMotion"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        if let title = section.title { Text(title) }
                    }
                }
                if pane.id == "general" {
                    CLISection(controller: controller)
                    Section {
                        Button {
                            controller.selectedPaneID = "activity"
                        } label: {
                            Text(SettingsText.resource("settings.general.showActivity"))
                        }
                    }
                }
            case .module(let manifest):
                ModulePaneContent(controller: controller, manifest: manifest)
            case .activity:
                ActivityPaneView(model: controller.activity)
            }
        }
        .formStyle(.grouped)
    }
}

/// `Automatic (when sharing or recording)` (Story 21.3): a toggle that is disabled, with an explanatory line,
/// while no detector exists (spike 21.1: manual only), and a needs-permission line when Screen Recording is denied.
struct PrivacyAutoRow: View {
    let controller: SettingsController
    let model: SettingRowModel
    @State private var isOn = false

    var body: some View {
        let available = controller.privacyDetectionAvailable
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { isOn }, set: { newValue in apply(newValue) })) {
                Text(model.label)
            }
            .disabled(!available)
            if !available {
                Text(SettingsText.resource("settings.privacy.unavailable"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let permission = controller.privacyDeniedPermission {
                Text(SettingsText.resource("settings.privacy.needsPermission"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    controller.openSystemSettings(for: permission)
                } label: {
                    Text(SettingsText.resource("settings.permission.openSystemSettings"))
                }
                .controlSize(.small)
            }
        }
        .onAppear { isOn = model.binding.get() == .bool(true) }
    }

    private func apply(_ value: Bool) {
        isOn = value
        Task { try? await model.binding.set(.bool(value)) }
    }
}

/// `Launch at login` (A61): mirrors the real `SMAppService.mainApp` state, not only the config key.
struct LaunchAtLoginSection: View {
    let controller: SettingsController

    var body: some View {
        Section {
            LabeledContent {
                Toggle(
                    isOn: Binding(
                        get: { controller.loginItemStatus.isOn },
                        set: { on in Task { await controller.setLaunchAtLogin(on) } })
                ) {
                    Text(CoreSettings.label("config.general.launch_at_login"))
                }
                .labelsHidden()
                .toggleStyle(.switch)
            } label: {
                Text(CoreSettings.label("config.general.launch_at_login"))
                if let error = controller.loginItemError {
                    Text(verbatim: error).foregroundStyle(.red)
                }
            }
            if controller.loginItemStatus == .requiresApproval {
                HStack {
                    Text(SettingsText.resource("settings.login.requiresApproval"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        controller.openLoginItemsSettings()
                    } label: {
                        Text(SettingsText.resource("settings.login.openSettings"))
                    }
                }
            }
        }
    }
}

/// CLI status line and PATH hint (Story 4.3), shown when an installer is provided.
struct CLISection: View {
    let controller: SettingsController

    var body: some View {
        if controller.cliInstaller != nil {
            Section {
                if let status = controller.cliStatus {
                    Text(verbatim: Self.text(for: status))
                }
                if let hint = controller.cliPathHint {
                    Text(verbatim: SettingsText.format("settings.cli.pathHint", Self.abbreviate(hint.binDirectory)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: hint.exportLine)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                Text(SettingsText.resource("settings.section.cli"))
            }
        }
    }

    static func text(for status: CLIInstallStatus) -> String {
        switch status {
        case .current(let link): SettingsText.format("settings.cli.current", abbreviate(link))
        case .missing: SettingsText.string("settings.cli.missing")
        case .stale: SettingsText.string("settings.cli.stale")
        case .conflict(let existing): SettingsText.format("settings.cli.conflict", abbreviate(existing))
        case .bundledCLIMissing: SettingsText.string("settings.cli.bundledMissing")
        }
    }

    static func abbreviate(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

/// A module's pane: `enabled`, status, the permission block when needed, its generated rows, the alert
/// settings generated from its declared kinds (Story 3.7), then its own view below them (never instead of
/// them, FR5).
struct ModulePaneContent: View {
    let controller: SettingsController
    let manifest: ModuleManifest

    var body: some View {
        Section {
            if let enabled = controller.rowModel(for: .moduleEnabled(manifest.id)) {
                SettingRow(enabled)
            }
            LabeledContent {
                Text(verbatim: Self.statusText(controller.moduleStatus(manifest.id)))
            } label: {
                Text(SettingsText.resource("settings.module.status"))
            }
        }
        if let prompt = controller.permissionPrompt(for: manifest.id) {
            Section {
                PermissionBlock(controller: controller, prompt: prompt)
            }
        }
        let rows = controller.moduleRows(manifest)
        if !rows.isEmpty {
            Section {
                ForEach(rows) { SettingRow($0) }
            }
        }
        AlertSettingsSection(controller: controller, manifest: manifest)
        if let custom = controller.customSettingsView(manifest.id) {
            Section { custom }
        }
    }

    static func statusText(_ status: ModuleStatus) -> String {
        switch status {
        case .disabled: SettingsText.string("settings.module.status.disabled")
        case .running: SettingsText.string("settings.module.status.running")
        case .stopped: SettingsText.string("settings.module.status.stopped")
        case .errored(let message): SettingsText.format("settings.module.status.errored", message)
        case .needsPermission(let permission):
            SettingsText.format("settings.module.status.needsPermission", permissionName(permission))
        }
    }

    static func permissionName(_ permission: Permission) -> String {
        switch permission {
        case .accessibility: SettingsText.string("settings.permission.accessibility")
        case .automation(let bundleID):
            SettingsText.format(
                "settings.permission.automation",
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                    .map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
        case .calendar: SettingsText.string("settings.permission.calendar")
        case .notifications: SettingsText.string("settings.permission.notifications")
        case .screenRecording: SettingsText.string("settings.permission.screenRecording")
        }
    }
}

/// Setup-card-style block in native controls: the missing permission, `Grant` while undetermined, and
/// `Open System Settings` (deep link).
struct PermissionBlock: View {
    let controller: SettingsController
    let prompt: PermissionPrompt

    var body: some View {
        let name = ModulePaneContent.permissionName(prompt.permission)
        VStack(alignment: .leading) {
            Label {
                Text(verbatim: SettingsText.format("settings.permission.title", name))
                    .font(.headline)
            } icon: {
                Image(systemName: "info.square")
            }
            Text(verbatim: SettingsText.format("settings.permission.sentence", name))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                if prompt.canGrant {
                    Button {
                        Task { await controller.grant(prompt.permission) }
                    } label: {
                        Text(SettingsText.resource("settings.permission.grant"))
                    }
                }
                Button {
                    controller.openSystemSettings(for: prompt.permission)
                } label: {
                    Text(SettingsText.resource("settings.permission.openSystemSettings"))
                }
                .keyboardShortcut(prompt.canGrant ? nil : .defaultAction)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
