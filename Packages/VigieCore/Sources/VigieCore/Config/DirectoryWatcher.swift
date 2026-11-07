import Darwin
import Foundation

/// Watches folders for changes (AD-12): the containing directory, never only a file's inode, so editors that
/// save by atomic replace (write a temp file, rename it over the original) are seen.
@MainActor
public protocol DirectoryWatching: AnyObject {
    /// Watches `directory` and, as a hint, the named files in it. `handler` runs on the main actor after any
    /// event; it does not say which file changed (callers re-read and compare).
    func watch(_ directory: URL, files: [String], handler: @escaping @MainActor () -> Void)
    /// Stops every watch.
    func stopAll()
}

/// `DispatchSource` file-system watcher. Opens the directory with `O_EVTONLY` and listens for writes,
/// renames and deletes. Files named in `watch(_:files:)` are watched too, so in-place writes (which do not
/// touch the directory) are seen; every event re-opens all sources of that watch, which follows atomic
/// replaces (new inode) and a replaced or re-created directory.
@MainActor
public final class DispatchDirectoryWatcher: DirectoryWatching {
    private final class Watch {
        let directory: URL
        let files: [String]
        let handler: @MainActor () -> Void
        var sources: [any DispatchSourceFileSystemObject] = []
        var retryScheduled = false

        init(directory: URL, files: [String], handler: @escaping @MainActor () -> Void) {
            self.directory = directory
            self.files = files
            self.handler = handler
        }

        func cancelSources() {
            for source in sources { source.cancel() }
            sources = []
        }

        deinit { cancelSources() }
    }

    private var watches: [UUID: Watch] = [:]
    private let retryInterval: Duration

    /// - Parameter retryInterval: how often to retry opening a directory that disappeared.
    public init(retryInterval: Duration = .seconds(1)) {
        self.retryInterval = retryInterval
    }

    public func watch(_ directory: URL, files: [String], handler: @escaping @MainActor () -> Void) {
        let id = UUID()
        let watch = Watch(directory: directory, files: files, handler: handler)
        watches[id] = watch
        arm(id)
    }

    public func stopAll() {
        for watch in watches.values { watch.cancelSources() }
        watches = [:]
    }

    /// (Re)opens every source of a watch. Returns false when the directory cannot be opened.
    @discardableResult
    private func arm(_ id: UUID) -> Bool {
        guard let watch = watches[id] else { return false }
        watch.cancelSources()
        guard
            let directorySource = makeSource(
                path: watch.directory.path, mask: [.write, .rename, .delete, .link], id: id)
        else {
            scheduleRetry(id)
            return false
        }
        watch.sources.append(directorySource)
        for file in watch.files {
            let path = watch.directory.appendingPathComponent(file).path
            if let source = makeSource(path: path, mask: [.write, .extend, .rename, .delete], id: id) {
                watch.sources.append(source)
            }
        }
        return true
    }

    private func makeSource(
        path: String, mask: DispatchSource.FileSystemEvent, id: UUID
    ) -> (any DispatchSourceFileSystemObject)? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fired(id) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func fired(_ id: UUID) {
        guard let watch = watches[id] else { return }
        arm(id)
        watch.handler()
    }

    private func scheduleRetry(_ id: UUID) {
        guard let watch = watches[id], !watch.retryScheduled else { return }
        watch.retryScheduled = true
        let interval = retryInterval
        Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard let self, let watch = self.watches[id] else { return }
            watch.retryScheduled = false
            if self.arm(id) { watch.handler() }
        }
    }
}

/// A watcher for tests: nothing happens until the test calls `fire(_:)`.
@MainActor
public final class ManualDirectoryWatcher: DirectoryWatching {
    private var handlers: [(directory: URL, handler: @MainActor () -> Void)] = []

    public init() {}

    /// Directories currently watched (standardized).
    public var watchedDirectories: [URL] { handlers.map(\.directory) }

    public func watch(_ directory: URL, files: [String], handler: @escaping @MainActor () -> Void) {
        handlers.append((directory.standardizedFileURL, handler))
    }

    public func stopAll() { handlers = [] }

    /// Delivers an event for `directory` (every watch when nil).
    public func fire(_ directory: URL? = nil) {
        let target = directory?.standardizedFileURL
        for entry in handlers where target == nil || entry.directory.path == target?.path {
            entry.handler()
        }
    }
}
