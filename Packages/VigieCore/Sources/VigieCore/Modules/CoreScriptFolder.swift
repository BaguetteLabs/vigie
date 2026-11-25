import Foundation
import ModuleKit
import Wire

/// `context.scriptFolder` (AD-18, Story 12.2): `<config folder>/modules/` from `AppEnvironment` (AD-17), the
/// built-in ids scripts must not take, a watch on the folder (AD-12) that ends when the module stops, this Mac's
/// confirmations (Story 12.3), and this Mac's enabled flags plus the scripts' configured values (Story 12.6).
public struct CoreScriptFolder: ScriptFolderService {
    /// `<config folder>/modules/` now: it follows ``folderLocation`` when the host has one (Story 16.1).
    public var url: URL? { folderLocation?.scriptModulesFolderURL ?? fixedURL }
    let fixedURL: URL?
    /// The config folder in effect (ConfigStore's ``ConfigStore/location``): after a relocation ``url`` points at
    /// the new `modules/` and ``changes()`` yields so the module rescans. Nil: the folder is fixed at `url`.
    public let folderLocation: ConfigFolderLocation?
    public let builtInModuleIDs: Set<ModuleID>
    let tracker: RegistrationTracker
    let makeWatcher: @MainActor @Sendable () -> any DirectoryWatching
    /// This Mac's confirmations (Story 12.3): ``ConfigScriptConfirmations`` when the host has a ConfigStore.
    public let confirmations: any ScriptConfirmationStore
    /// Enabled flags and configured values (Story 12.6): ``ConfigScriptSettings`` when the host has a ConfigStore.
    public let settings: any ScriptSettingsStore
    /// The launch's `vigie://install` inbox (Story 12.9), fed by the App's open-URL handler; nil: no links.
    public let installInbox: ScriptInstallInbox?

    /// - Parameters:
    ///   - makeWatcher: one watcher per `changes()` stream; tests pass a `ManualDirectoryWatcher`.
    public init(
        url: URL?, builtInModuleIDs: Set<ModuleID>, tracker: RegistrationTracker,
        confirmations: any ScriptConfirmationStore = NoScriptConfirmations(),
        settings: any ScriptSettingsStore = NoScriptSettings(),
        folderLocation: ConfigFolderLocation? = nil,
        installInbox: ScriptInstallInbox? = nil,
        makeWatcher: @escaping @MainActor @Sendable () -> any DirectoryWatching = { DispatchDirectoryWatcher() }
    ) {
        fixedURL = url
        self.folderLocation = folderLocation
        self.builtInModuleIDs = builtInModuleIDs
        self.tracker = tracker
        self.confirmations = confirmations
        self.settings = settings
        self.installInbox = installInbox
        self.makeWatcher = makeWatcher
    }

    /// The inbox's requests, queued ones first; the stream ends when the module stops (Story 12.9).
    @MainActor public func installRequests() -> AsyncStream<ScriptInstallRequest> {
        guard let installInbox else { return AsyncStream { $0.finish() } }
        let (stream, finish) = installInbox.subscribe()
        tracker.track(RegistrationToken(cancel: finish))
        return stream
    }

    /// Watches the folder and, as hints, the `*.md` files in it at each event, so in-place writes (which do not
    /// touch the directory) are seen too. A missing folder is retried by the watcher and reported when it appears.
    /// When the config folder is relocated (Story 16.1), the watch moves to the new `modules/` and the stream
    /// yields once.
    @MainActor public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard let url else {
            continuation.finish()
            return stream
        }
        let watch = FolderWatch(folder: url, watcher: makeWatcher()) { continuation.yield() }
        watch.arm()
        let relocations = folderLocation.map { location in
            let moves = location.changes()
            return Task { @MainActor in
                for await folder in moves {
                    watch.retarget(AppEnvironment.scriptModulesFolderURL(in: folder))
                    continuation.yield()
                }
            }
        }
        let token = tracker.track(
            RegistrationToken {
                continuation.finish()
                relocations?.cancel()
                Task { @MainActor in watch.stop() }
            })
        continuation.onTermination = { _ in token.cancel() }
        return stream
    }
}

/// Re-arms its watcher when the `*.md` names change; every event reports a change.
@MainActor
final class FolderWatch {
    private var folder: URL
    private let watcher: any DirectoryWatching
    private let onChange: @MainActor () -> Void
    private var stopped = false
    /// The `*.md` names the current watch was armed with.
    private var armedNames: [String] = []

    init(folder: URL, watcher: any DirectoryWatching, onChange: @escaping @MainActor () -> Void) {
        self.folder = folder
        self.watcher = watcher
        self.onChange = onChange
    }

    func arm() {
        guard !stopped else { return }
        let names = Self.markdownFiles(in: folder)
        armedNames = names
        watcher.stopAll()
        watcher.watch(folder, files: names) { [weak self] in
            guard let self, !self.stopped else { return }
            // The watcher may call this once more after each (re)arm, when its watch goes live: re-arming then
            // would never settle, so the watch is renewed only when the file list changed.
            if Self.markdownFiles(in: self.folder) != self.armedNames { self.arm() }
            self.onChange()
        }
    }

    /// Watches `folder` from now on (the config folder moved).
    func retarget(_ folder: URL) {
        self.folder = folder
        arm()
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
