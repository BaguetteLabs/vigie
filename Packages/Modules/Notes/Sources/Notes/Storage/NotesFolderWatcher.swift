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

    /// True while the source sits on the folder itself (not an ancestor).
    public private(set) var watchesFolder = false

    public func start(_ folder: URL, handler: @escaping @MainActor () -> Void) {
        stop()
        self.folder = folder.standardizedFileURL
        self.handler = handler
        arm()
    }

    public func stop() {
        source?.cancel()
        source = nil
        pending?.cancel()
        pending = nil
        folder = nil
        handler = nil
        watchesFolder = false
    }

    private func arm() {
        source?.cancel()
        source = nil
        guard let folder else { return }
        var target = folder
        while !FileManager.default.fileExists(atPath: target.path), target.pathComponents.count > 1 {
            target = target.deletingLastPathComponent()
        }
        let fd = open(target.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchesFolder = target == folder
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fired() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func fired() {
        let wasOnFolder = watchesFolder
        // Re-open: follows a replaced or re-created folder, and moves from an ancestor to the folder.
        arm()
        if !wasOnFolder && !watchesFolder { return }
        pending?.cancel()
        let debounce = debounce
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.handler?()
        }
    }
}
