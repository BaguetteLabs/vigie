import Darwin
import Foundation

/// Watches the notes folder (AD-12). `handler` runs on the main actor, debounced, after anything changed in it;
/// it does not say which file changed (the store compares stamps).
@MainActor
public protocol NotesFolderWatching: AnyObject {
    func start(_ folder: URL, handler: @escaping @MainActor () -> Void)
    func stop()
}

/// `DispatchSource` (kqueue) watcher on the notes folder, the same approach as VigieCore's
/// `DispatchDirectoryWatcher` (a module cannot import VigieCore). It watches the directory, never a file's inode,
/// so atomic replaces are seen. While the folder does not exist it watches the nearest existing ancestor and
/// re-arms on every event, so a folder created later (first write, iCloud move) is picked up. Events are
/// coalesced: the handler runs once `debounce` after the last one.
@MainActor
public final class NotesFolderWatcher: NotesFolderWatching {
    private var source: (any DispatchSourceFileSystemObject)?
    private var folder: URL?
    private var handler: (@MainActor () -> Void)?
    private var pending: Task<Void, Never>?
    private let debounce: Duration

    public init(debounce: Duration = .milliseconds(250)) {
        self.debounce = debounce
    }

    /// A watcher dropped without `stop()` still cancels its source, which closes the descriptor.
    isolated deinit {
        source?.cancel()
    }

    /// True while the source sits on the folder itself (not an ancestor).
    public private(set) var watchesFolder = false

    public func start(_ folder: URL, handler: @escaping @MainActor () -> Void) {
        stop()
        self.folder = folder.standardizedFileURL
        self.handler = handler
        arm()
    }

    public func stop() {
        generation += 1
        source?.cancel()
        source = nil
        pending?.cancel()
        pending = nil
        folder = nil
        handler = nil
        watchesFolder = false
    }

    /// Bumped by every arm and stop: a registration callback of an older source is stale.
    private var generation = 0
    /// Directories opened and not yet closed by a cancel handler (a leak check for tests).
    private(set) var openDescriptors = 0
    /// Test seam: runs once a source is built, before it is resumed (so before the kernel watch exists).
    var beforeResume: (@MainActor (URL) -> Void)?

    private func nearestExisting(_ folder: URL) -> URL {
        var target = folder
        while !FileManager.default.fileExists(atPath: target.path), target.pathComponents.count > 1 {
            target = target.deletingLastPathComponent()
        }
        return target
    }

    private func arm() {
        source?.cancel()
        source = nil
        generation += 1
        guard let folder else { return }
        let target = nearestExisting(folder)
        let fd = open(target.path, O_EVTONLY)
        guard fd >= 0 else { return }
        openDescriptors += 1
        let generation = generation
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fired() }
        }
        // libdispatch registers the kernel watch asynchronously after `resume()`; whatever happened in the
        // directory before that raised no event, so the check is made once the registration is live.
        source.setRegistrationHandler { [weak self] in
            MainActor.assumeIsolated { self?.registered(generation, target: target) }
        }
        source.setCancelHandler { [weak self] in
            close(fd)
            MainActor.assumeIsolated { self?.openDescriptors -= 1 }
        }
        watchesFolder = target == folder
        self.source = source
        beforeResume?(target)
        source.resume()
    }

    /// The source of `generation` is now watching. A directory created before that moves the watch down; a
    /// watch on the folder itself schedules one read, since a file may have landed before the registration.
    /// Never re-arms when nothing moved, and a stale or stopped source does nothing.
    private func registered(_ generation: Int, target: URL) {
        guard generation == self.generation, let folder else { return }
        if nearestExisting(folder) != target {
            arm()
        } else if target == folder {
            schedule()
        }
    }

    private func schedule() {
        pending?.cancel()
        let debounce = debounce
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.handler?()
        }
    }

    private func fired() {
        let wasOnFolder = watchesFolder
        // Re-open: follows a replaced or re-created folder, and moves from an ancestor to the folder.
        arm()
        if !wasOnFolder && !watchesFolder { return }
        schedule()
    }
}
