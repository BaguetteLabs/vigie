import AppKit
import Observation
import SwiftUI

/// Settings › General › Config folder (Story 16.1, FR101): the folder in effect, `Change…`, `Reveal in Finder` and,
/// once relocated, `Use default`. A chosen folder is checked first (``ConfigStore/planRelocation(to:)``) and the
/// row then asks for confirmation, saying whether Vigie will adopt the folder's `config.toml` or move the current
/// files there. Every change goes through ``ConfigStore/relocate(to:)`` (AD-12); errors show in the row.
@MainActor @Observable
public final class ConfigFolderModel {
    @ObservationIgnored public let configStore: ConfigStore
    /// Asks for a folder, starting at the given one; nil when cancelled. Tests replace it (never a real panel).
    @ObservationIgnored var chooseFolder: @MainActor (URL) async -> URL?
    /// Shows a folder in Finder. Tests replace it.
    @ObservationIgnored var reveal: @MainActor (URL) -> Void
    /// The checked relocation waiting for `Move` / `Use This Folder` or `Cancel`.
    public private(set) var pending: ConfigRelocationPlan?
    /// The inline error of the last refused or failed change.
    public private(set) var error: String?
    /// A relocation is running.
    public private(set) var isWorking = false

    public init(configStore: ConfigStore) {
        self.configStore = configStore
        chooseFolder = ConfigFolderModel.openPanel
        reveal = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    }

    /// The folder in effect, home abbreviated to `~`.
    public var displayPath: String { configStore.environment.abbreviatingHome(configStore.configFolderURL) }

    /// `Use default` is offered only away from the default folder.
    public var canUseDefault: Bool { !configStore.isUsingDefaultFolder }

    /// The line under the path when the location recorded in `local.toml` could not be used at launch.
    public var launchProblem: String? {
        guard configStore.environment.configFolderRecordProblem != nil, configStore.isUsingDefaultFolder else {
            return nil
        }
        return SettingsText.string("settings.configFolder.recordMissing")
    }

    /// `Change…`: asks for a folder (starting at the current one), checks it and asks for confirmation.
    public func change() async {
        guard !isWorking, let folder = await chooseFolder(configStore.configFolderURL) else { return }
        prepare(folder)
    }

    /// `Use default`: checks the default folder and asks for confirmation.
    public func useDefault() {
        prepare(configStore.environment.defaultConfigFolderURL)
    }

    public func revealInFinder() {
        reveal(configStore.configFolderURL)
    }

    /// The confirmation sentence of ``pending`` (adopt vs move).
    public var confirmationText: String? {
        guard let pending else { return nil }
        return SettingsText.string(
            pending.adopts ? "settings.configFolder.confirm.adopt" : "settings.configFolder.confirm.move")
    }

    /// The pending target, home abbreviated.
    public var pendingPath: String? {
        pending.map { configStore.environment.abbreviatingHome($0.target) }
    }

    /// Runs the pending relocation.
    public func confirm() async {
        guard let plan = pending, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do throws(ConfigRelocationError) {
            try await configStore.relocate(to: plan.target)
            pending = nil
            error = nil
        } catch {
            pending = nil
            self.error = error.errorDescription
        }
    }

    public func cancel() {
        pending = nil
    }

    private func prepare(_ folder: URL) {
        do throws(ConfigRelocationError) {
            pending = try configStore.planRelocation(to: folder)
            error = nil
        } catch {
            pending = nil
            self.error = error.errorDescription
        }
    }

    /// A folder `NSOpenPanel` opened at `folder`.
    static func openPanel(_ folder: URL) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = SettingsText.string("settings.configFolder.choose.prompt")
        let response = await panel.begin()
        guard response == .OK else { return nil }
        return panel.url
    }
}

/// The Config folder section of Settings › General.
struct ConfigFolderSection: View {
    let model: ConfigFolderModel

    var body: some View {
        Section {
            LabeledContent {
                HStack {
                    Button {
                        Task { await model.change() }
                    } label: {
                        Text(SettingsText.resource("settings.configFolder.change"))
                    }
                    Button {
                        model.revealInFinder()
                    } label: {
                        Text(SettingsText.resource("settings.configFolder.reveal"))
                    }
                    if model.canUseDefault {
                        Button {
                            model.useDefault()
                        } label: {
                            Text(SettingsText.resource("settings.configFolder.useDefault"))
                        }
                    }
                }
                .disabled(model.isWorking)
            } label: {
                Text(SettingsText.resource("settings.configFolder.label"))
                Text(verbatim: model.displayPath)
                    .textSelection(.enabled)
            }
            if let problem = model.launchProblem {
                Text(verbatim: problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let text = model.confirmationText, let path = model.pendingPath {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: path)
                        .font(.callout.monospaced())
                    Text(verbatim: text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button {
                            model.cancel()
                        } label: {
                            Text(SettingsText.resource("settings.configFolder.cancel"))
                        }
                        Button {
                            Task { await model.confirm() }
                        } label: {
                            Text(
                                SettingsText.resource(
                                    model.pending?.adopts == true
                                        ? "settings.configFolder.confirm.adoptButton"
                                        : "settings.configFolder.confirm.moveButton"))
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .disabled(model.isWorking)
                }
            }
            if let error = model.error {
                Text(verbatim: error).foregroundStyle(.red)
            }
        } header: {
            Text(SettingsText.resource("settings.section.configFolder"))
        }
    }
}
