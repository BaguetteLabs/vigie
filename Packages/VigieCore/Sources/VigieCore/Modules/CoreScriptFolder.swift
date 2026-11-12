import Foundation
import ModuleKit

/// `context.scriptFolder` (AD-18, Story 12.2): `<config folder>/modules/` from `AppEnvironment` (AD-17), the
/// built-in ids scripts must not take, a watch on the folder (AD-12) that ends when the module stops, this Mac's
/// confirmations (Story 12.3), and this Mac's enabled flags plus the scripts' configured values (Story 12.6).
public struct CoreScriptFolder: ScriptFolderService {
    public let url: URL?
    public let builtInModuleIDs: Set<ModuleID>
    let tracker: RegistrationTracker
    let makeWatcher: @MainActor @Sendable () -> any DirectoryWatching
    /// This Mac's confirmations (Story 12.3): ``ConfigScriptConfirmations`` when the host has a ConfigStore.
    public let confirmations: any ScriptConfirmationStore
    /// Enabled flags and configured values (Story 12.6): ``ConfigScriptSettings`` when the host has a ConfigStore.
    public let settings: any ScriptSettingsStore

    /// - Parameters:
    ///   - makeWatcher: one watcher per `changes()` stream; tests pass a `ManualDirectoryWatcher`.
    public init(
        url: URL?, builtInModuleIDs: Set<ModuleID>, tracker: RegistrationTracker,
        confirmations: any ScriptConfirmationStore = NoScriptConfirmations(),
        settings: any ScriptSettingsStore = NoScriptSettings(),
        makeWatcher: @escaping @MainActor @Sendable () -> any DirectoryWatching = { DispatchDirectoryWatcher() }
    ) {
        self.url = url
        self.builtInModuleIDs = builtInModuleIDs
        self.tracker = tracker
        self.confirmations = confirmations
        self.settings = settings
        self.makeWatcher = makeWatcher
    }

    /// Watches the folder and, as hints, the `*.md` files in it at each event, so in-place writes (which do not
    /// touch the directory) are seen too. A missing folder is retried by the watcher and reported when it appears.
    @MainActor public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard let url else {
            continuation.finish()
            return stream
        }
        let watch = FolderWatch(folder: url, watcher: makeWatcher()) { continuation.yield() }
        watch.arm()
        let token = tracker.track(
            RegistrationToken {
                continuation.finish()
                Task { @MainActor in watch.stop() }
            })
        continuation.onTermination = { _ in token.cancel() }
        return stream
    }
}

/// Re-arms its watcher with the current `*.md` names after every event.
@MainActor
final class FolderWatch {
    private let folder: URL
    private let watcher: any DirectoryWatching
    private let onChange: @MainActor () -> Void
    private var stopped = false

    init(folder: URL, watcher: any DirectoryWatching, onChange: @escaping @MainActor () -> Void) {
        self.folder = folder
        self.watcher = watcher
        self.onChange = onChange
    }

    func arm() {
        guard !stopped else { return }
        watcher.stopAll()
        watcher.watch(folder, files: Self.markdownFiles(in: folder)) { [weak self] in
            guard let self, !self.stopped else { return }
            self.arm()
            self.onChange()
        }
    }

    func stop() {
        stopped = true
        watcher.stopAll()
    }

    nonisolated static func markdownFiles(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.lowercased().hasSuffix(".md") }.sorted()
    }
}
