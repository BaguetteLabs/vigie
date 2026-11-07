import Foundation
import ModuleKit
import Wire

@testable import VigieCore

/// Separate temp folders for the app support folder (local.toml) and the config folder (config.toml).
struct ConfigFixture {
    let support: URL
    let configFolder: URL
    let environment: AppEnvironment

    init() {
        let root = makeTempDirectory()
        support = root.appendingPathComponent("support", isDirectory: true)
        configFolder = root.appendingPathComponent("config", isDirectory: true)
        environment = AppEnvironment(flavor: .dev, applicationSupportURL: support, configFolderOverride: configFolder)
    }

    var configURL: URL { configFolder.appendingPathComponent("config.toml") }
    var localURL: URL { environment.localConfigURL }

    /// Writes `text` the way editors that save by atomic replace do: a temp file renamed over the target.
    func atomicReplace(_ url: URL, with text: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try Data(text.utf8).write(to: temp)
        guard rename(temp.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    func writeConfig(_ text: String) throws { try atomicReplace(configURL, with: text) }
    func writeLocal(_ text: String) throws { try atomicReplace(localURL, with: text) }

    @MainActor
    func makeStore(
        manifests: [ModuleManifest] = [],
        config: String? = nil,
        local: String? = nil
    ) async throws -> (ConfigStore, ManualDirectoryWatcher) {
        if let config { try writeConfig(config) }
        if let local { try writeLocal(local) }
        let watcher = ManualDirectoryWatcher()
        let store = ConfigStore(environment: environment, manifests: manifests, watcher: watcher, debounce: .zero)
        await store.start()
        return (store, watcher)
    }
}

extension ConfigStore {
    /// Simulates a watcher event and waits for the resulting reload.
    func fireAndSettle(_ watcher: ManualDirectoryWatcher) async {
        watcher.fire()
        await waitForScheduledReload()
    }
}

/// A module manifest for config tests.
let testManifest = ModuleManifest(
    id: "agents.sessions",
    name: "Sessions",
    icon: "terminal",
    settings: [
        SettingDescriptor(key: "priority", label: "Priority", kind: .int(default: 1, min: 0, max: 10)),
        SettingDescriptor(key: "done_to_idle", label: "Done to idle", kind: .duration(default: .seconds(900))),
        SettingDescriptor(
            key: "terminal", label: "Terminal",
            kind: .enumeration(options: ["terminal", "warp", "ghostty", "iterm"], default: "terminal"),
            scope: .local),
        SettingDescriptor(key: "ask_alt_cwd", label: "Alt cwd", kind: .path(default: "~/Code")),
    ]
)

/// Collects how many times a stream yields.
final class StreamCounter: Sendable {
    let counter: Counter
    let task: Task<Void, Never>

    init<Element: Sendable>(_ stream: AsyncStream<Element>, onElement: (@Sendable (Element) -> Void)? = nil) {
        let counter = Counter()
        self.counter = counter
        task = Task {
            for await element in stream {
                onElement?(element)
                counter.increment()
            }
        }
    }

    var count: Int { counter.count }

    deinit { task.cancel() }
}
