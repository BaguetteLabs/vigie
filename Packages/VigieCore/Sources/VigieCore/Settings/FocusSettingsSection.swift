import AppKit
import SwiftUI

/// What the Focus row of Settings › Alerts shows (Story 3.10).
public enum FocusSetupState: Equatable, Sendable {
    /// The Focus filter has never run on this Mac: the how-to and "Open Focus settings".
    case needsSetup
    /// It has run at least once (`[notify] focus_filter_ran`).
    case ready
}

extension SettingsController {
    /// System Settings › Focus (the `com.apple.Focus-Settings.extension` pane, macOS 13+).
    public static let focusSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension")!

    /// Needs setup until the filter has run once (read live from ConfigStore).
    public var focusSetupState: FocusSetupState {
        FocusFilterSetup.isSetUp(configStore) ? .ready : .needsSetup
    }

    public func openFocusSettings() {
        openURL(Self.focusSettingsURL)
    }

    /// The CLI as the Shortcuts recipe spells it: the installed link (`~/.local/bin/vigie`), else its name.
    var focusShortcutCLI: String {
        guard let installer = cliInstaller else { return "vigie" }
        return CLISection.abbreviate(installer.linkURL)
    }
}

/// The Focus row of Settings › Alerts (Story 3.10, spike `spike-focus-detection.md`): a needs-setup block with
/// the three-step how-to until Vigie's Focus filter has run once, then a one-line status. Below it, the
/// Shortcuts recipe for users who prefer automations. Never shown at launch, never a modal.
struct FocusSettingsSection: View {
    let controller: SettingsController

    var body: some View {
        Section {
            switch controller.focusSetupState {
            case .needsSetup: needsSetup
            case .ready:
                LabeledContent {
                    Text(SettingsText.resource("settings.focus.ready"))
                } label: {
                    Text(SettingsText.resource("settings.focus.title"))
                }
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text(SettingsText.resource("settings.focus.shortcuts.intro"))
                    Text(SettingsText.resource("settings.focus.shortcuts.on"))
                    command(active: true)
                    Text(SettingsText.resource("settings.focus.shortcuts.off"))
                    command(active: false)
                    Text(SettingsText.resource("settings.focus.shortcuts.scripts"))
                    Text(SettingsText.resource("settings.focus.shortcuts.cap"))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            } label: {
                Text(SettingsText.resource("settings.focus.shortcuts.title"))
            }
        } header: {
            Text(SettingsText.resource("settings.section.focus"))
        }
    }

    private var needsSetup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(SettingsText.resource("settings.focus.title"))
                    .font(.headline)
            } icon: {
                Image(systemName: "moon")
            }
            Text(SettingsText.resource("settings.focus.needsSetup"))
                .foregroundStyle(.secondary)
            Text(SettingsText.resource("settings.focus.step1"))
            Text(SettingsText.resource("settings.focus.step2"))
            Text(SettingsText.resource("settings.focus.step3"))
            HStack {
                Spacer()
                Button {
                    controller.openFocusSettings()
                } label: {
                    Text(SettingsText.resource("settings.focus.open"))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private func command(active: Bool) -> some View {
        Text(verbatim: Self.shortcutCommand(cli: controller.focusShortcutCLI, active: active))
            .font(.callout.monospaced())
            .textSelection(.enabled)
    }

    /// The shell command of one automation (not localized: it is typed into Shortcuts as is).
    static func shortcutCommand(cli: String, active: Bool) -> String {
        "\(cli) event app.focus '{\"active\":\(active)}'"
    }
}
