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
        /// Bumped by every `arm`: a registration callback of an older generation is stale.
        var generation = 0
        /// Sources of the current generation whose kernel watch is live, and how many there are in all.
        var registered = 0
        var expected = 0

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
    /// Descriptors opened and not yet closed by a cancel handler (a leak check for tests).
    private(set) var openDescriptors = 0
    /// Test seam: runs with a source's path once the source is built, before it is resumed (so before the
    /// kernel watch exists).
    var beforeResume: (@MainActor (String) -> Void)?

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
        watch.generation += 1
        watch.registered = 0
        watch.expected = 0
        defer { watch.expected = watch.sources.count }
        guard
            let directorySource = makeSource(
                path: watch.directory.path, mask: [.write, .rename, .delete, .link], id: id,
                generation: watch.generation)
        else {
            scheduleRetry(id)
            return false
        }
        watch.sources.append(directorySource)
        for file in watch.files {
            let path = watch.directory.appendingPathComponent(file).path
            if let source = makeSource(
                path: path, mask: [.write, .extend, .rename, .delete], id: id, generation: watch.generation)
            {
                watch.sources.append(source)
            }
        }
        return true
    }

    private func makeSource(
        path: String, mask: DispatchSource.FileSystemEvent, id: UUID, generation: Int
    ) -> (any DispatchSourceFileSystemObject)? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        openDescriptors += 1
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fired(id) }
        }
        // libdispatch registers the kernel watch asynchronously after `resume()`; whatever changed before that
        // raised no event, so one read is requested once every source of this generation is live.
        source.setRegistrationHandler { [weak self] in
            MainActor.assumeIsolated { self?.registered(id, generation: generation) }
        }
        source.setCancelHandler { [weak self] in
            close(fd)
            MainActor.assumeIsolated { self?.openDescriptors -= 1 }
        }
        beforeResume?(path)
        source.resume()
        return source
    }

    /// One source of `generation` is live. When the last one is, the handler runs once, so a change made
    /// between the caller's read and the registration is not lost. Never re-arms (no loop); a stale
    /// generation, a cancelled source or a stopped watch does nothing.
    private func registered(_ id: UUID, generation: Int) {
        guard let watch = watches[id], watch.generation == generation else { return }
        watch.registered += 1
        if watch.registered == watch.expected { watch.handler() }
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
