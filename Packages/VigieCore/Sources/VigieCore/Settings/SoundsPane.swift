import AppKit
import ModuleKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import VigieUI

/// Settings › Sounds (Story 10.2, UX-DR72, UX-DR74): the global switch, then per sound event an on/off switch, a
/// picker (built-ins, the current custom file, `Choose file…`) and a preview. Every change writes `[sounds]`
/// through `ConfigStore` (`"off"`, `"builtin:<name>"` or a path).
@MainActor @Observable
public final class SoundsPaneModel {
    @ObservationIgnored public let configStore: ConfigStore
    /// Preview output; the App passes the player the ``NotifierSoundSink`` uses.
    @ObservationIgnored public var player: any SoundPlayer
    @ObservationIgnored public let catalog: SoundCatalog
    /// Asks for a sound file; returns its path (`~` abbreviated) or nil when cancelled.
    @ObservationIgnored var chooseFile: @MainActor () async -> String?
    /// Inline error per key (a refused write or a preview that cannot play).
    public private(set) var errors: [String: String] = [:]
    /// The last value a key had before it was switched off in this window.
    @ObservationIgnored private var remembered: [String: SoundValue] = [:]

    public init(
        configStore: ConfigStore, player: any SoundPlayer = AVAudioPlayerSoundPlayer(),
        catalog: SoundCatalog = .bundled
    ) {
        self.configStore = configStore
        self.player = player
        self.catalog = catalog
        chooseFile = SoundsPaneModel.openPanel
    }

    /// The events listed, in order (four today; the table keeps room for the other three).
    public var keys: [String] { SoundTable.settingsKeys }

    public var isEnabled: Bool { configStore.value(SoundSettings.path("enabled"), as: Bool.self) ?? false }

    public func value(for key: String) -> SoundValue {
        SoundValue(configStore.value(SoundSettings.path(key), as: String.self) ?? "off")
    }

    public func isOn(_ key: String) -> Bool { !value(for: key).isOff }

    /// What the picker shows: the value, or while off the value switching on would restore.
    public func displayedValue(for key: String) -> SoundValue {
        let current = value(for: key)
        return current.isOff ? restoreValue(for: key) : current
    }

    public func setEnabled(_ on: Bool) async {
        await write("enabled", .bool(on))
    }

    public func setOn(_ key: String, _ on: Bool) async {
        if on {
            await select(key, restoreValue(for: key))
        } else {
            let current = value(for: key)
            if !current.isOff { remembered[key] = current }
            await select(key, .off)
        }
    }

    public func select(_ key: String, _ value: SoundValue) async {
        await write(key, .string(value.raw))
    }

    /// `Choose file…`: writes the chosen path; cancelling writes nothing.
    public func chooseFile(for key: String) async {
        guard let path = await chooseFile() else { return }
        await select(key, SoundValue(path))
    }

    /// Plays the shown sound through the alert player.
    public func preview(_ key: String) async {
        switch catalog.resolve(displayedValue(for: key)) {
        case .silent:
            return
        case .problem(let reason):
            errors[key] = SoundProblemText.title(SoundProblem(key: key, reason: reason))
        case .play(let url):
            do {
                try await player.play(url: url)
                errors[key] = nil
            } catch {
                errors[key] = SoundProblemText.title(SoundProblem(key: key, reason: .unreadable(url.path)))
            }
        }
    }

    private func restoreValue(for key: String) -> SoundValue {
        remembered[key] ?? .builtIn(SoundTable.naturalBuiltIn(for: key))
    }

    private func write(_ key: String, _ value: ConfigResolvedValue) async {
        do throws(ConfigError) {
            try await configStore.set(SoundSettings.path(key), to: value)
            errors[key] = nil
        } catch {
            errors[key] = SettingWriteError(error).errorDescription
        }
    }

    /// An audio-file `NSOpenPanel`.
    static func openPanel() async -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.prompt = SettingsText.string("sounds.chooseFile.prompt")
        let response = await panel.begin()
        guard response == .OK, let url = panel.url else { return nil }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }
}

/// The Sounds pane's sections inside the Settings `Form`.
struct SoundsPaneContent: View {
    let controller: SettingsController

    var body: some View {
        let model = controller.sounds
        Section {
            if let row = controller.rowModel(for: SoundSettings.path("enabled")) { SettingRow(row) }
        }
        Section {
            ForEach(model.keys, id: \.self) { key in
                SoundEventRow(model: model, key: key)
            }
        } footer: {
            Text(SettingsText.resource("sounds.footer"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!model.isEnabled)
    }
}

/// One sound event: label, picker, preview, on/off.
struct SoundEventRow: View {
    let model: SoundsPaneModel
    let key: String

    private static let chooseTag = "\u{0}choose"

    var body: some View {
        let isOn = model.isOn(key)
        let shown = model.displayedValue(for: key)
        LabeledContent {
            HStack {
                Picker(selection: selection(shown)) {
                    ForEach(model.catalog.builtIns) { sound in
                        Text(sound.label).tag(SoundValue.builtIn(sound.name).raw)
                    }
                    if case .file(let url) = shown {
                        Text(verbatim: url.lastPathComponent).tag(shown.raw)
                    }
                    if case .invalid(let raw) = shown {
                        Text(verbatim: raw).tag(raw)
                    }
                    Divider()
                    Text(SettingsText.resource("sounds.chooseFile")).tag(Self.chooseTag)
                } label: {
                    Text(CoreSettings.label("config.sounds.\(key)"))
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!isOn)
                Button {
                    Task { await model.preview(key) }
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help(Text(SettingsText.resource("sounds.preview")))
                .accessibilityLabel(Text(SettingsText.resource("sounds.preview")))
                Toggle(
                    isOn: Binding(get: { isOn }, set: { on in Task { await model.setOn(key, on) } })
                ) {
                    Text(CoreSettings.label("config.sounds.\(key)"))
                }
                .labelsHidden()
                .toggleStyle(.switch)
            }
        } label: {
            Text(CoreSettings.label("config.sounds.\(key)"))
            if let error = model.errors[key] {
                Text(verbatim: error).foregroundStyle(.red)
            }
        }
    }

    private func selection(_ shown: SoundValue) -> Binding<String> {
        Binding(
            get: { shown.raw },
            set: { tag in
                if tag == Self.chooseTag {
                    Task { await model.chooseFile(for: key) }
                } else {
                    Task { await model.select(key, SoundValue(tag)) }
                }
            })
    }
}
