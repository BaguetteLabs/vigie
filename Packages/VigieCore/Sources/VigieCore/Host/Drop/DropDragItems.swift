import AppKit
import Synchronization
import UniformTypeIdentifiers

/// A file promise on the dragging pasteboard (a browser image, a Mail attachment): the host materializes it into
/// `AppEnvironment.dropsDirectory` before any handler runs (AD-19). ``SystemPromisedFile`` wraps
/// `NSFilePromiseReceiver`; tests use a fake.
@MainActor
public protocol PromisedFileReceiving: AnyObject {
    /// The promised files' types, known before the drop.
    var contentTypes: [UTType] { get }
    /// How many files the promise delivers (the reader is called once per file).
    var fileCount: Int { get }
    /// Asks the source to write the files into `folder`; `reader` is called once per file, on any queue.
    func receive(into folder: URL, reader: @escaping @Sendable (Result<URL, any Error>) -> Void)
}

/// What is being dragged: file URLs, file promises, the item count and the drag session's sequence number.
/// Without any file or promise, a drag can still carry a web link, image data or plain text (Story 9.2): those
/// open the display too, and reach the handler as `DropPayload.url` / `imageData` / `text`.
@MainActor
public struct DropDragItems {
    public var fileURLs: [URL]
    public var promises: [any PromisedFileReceiving]
    /// Dragged plain text (only read when there is no file, link or image).
    public var text: String?
    /// A dragged web link (not a file URL; only read when there is no file).
    public var webURL: URL?
    /// Dragged PNG (else TIFF) bytes (only read when there is no file or link).
    public var imageData: Data?
    /// Pasteboard items (shown in the band as `DROP · <N> ITEMS`).
    public var count: Int
    /// `NSDraggingInfo.draggingSequenceNumber`: one drag session.
    public var sequence: Int
    /// The operations the source allows.
    public var sourceOperations: NSDragOperation

    public init(
        fileURLs: [URL] = [], promises: [any PromisedFileReceiving] = [], count: Int? = nil, sequence: Int = 0,
        sourceOperations: NSDragOperation = .every, text: String? = nil, webURL: URL? = nil, imageData: Data? = nil
    ) {
        self.fileURLs = fileURLs
        self.promises = promises
        self.text = text
        self.webURL = webURL
        self.imageData = imageData
        let loose = text != nil || webURL != nil || imageData != nil
        self.count =
            count ?? (fileURLs.count + promises.reduce(0) { $0 + max($1.fileCount, 1) } + (loose ? 1 : 0))
        self.sequence = sequence
        self.sourceOperations = sourceOperations
    }

    /// True when there is at least one file or promise.
    public var hasFiles: Bool { !fileURLs.isEmpty || !promises.isEmpty }

    /// True when the drag carries something a zone can take: a file, a promise, a web link, an image or text.
    /// Only such drags open the drop display.
    public var hasContent: Bool { hasFiles || webURL != nil || imageData != nil || text != nil }

    /// The dragged content types, for `DropZone.accepts(contentTypes:)`. A file whose type can't be read counts
    /// as `public.data`.
    public var contentTypes: [UTType] {
        let fileTypes = fileURLs.map { url -> UTType in
            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType { return type }
            if url.hasDirectoryPath { return .folder }
            return UTType(filenameExtension: url.pathExtension) ?? .data
        }
        let fileAndPromiseTypes =
            fileTypes + promises.flatMap { $0.contentTypes.isEmpty ? [UTType.data] : $0.contentTypes }
        guard !hasFiles else { return fileAndPromiseTypes }
        if webURL != nil { return [.url] }
        if imageData != nil { return [.image] }
        if text != nil { return [.plainText] }
        return []
    }

    /// The pasteboard types a drop destination registers for: file URLs, file promises, then web links, images
    /// and text (Story 9.2).
    public static var draggedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
            + [.URL, .png, .tiff, .string]
    }

    /// Reads a drag: per pasteboard item, a file URL when there is one, else a file promise. Without either,
    /// the first of a web link, image data (PNG, else TIFF) or plain text.
    public static func read(_ info: any NSDraggingInfo) -> DropDragItems {
        let pasteboard = info.draggingPasteboard
        let objects =
            pasteboard.readObjects(
                forClasses: [NSURL.self, NSFilePromiseReceiver.self],
                options: [.urlReadingFileURLsOnly: true]) ?? []
        var urls: [URL] = []
        var promises: [any PromisedFileReceiving] = []
        for object in objects {
            if let url = object as? URL {
                urls.append(url)
            } else if let receiver = object as? NSFilePromiseReceiver {
                promises.append(SystemPromisedFile(receiver))
            }
        }
        var text: String?
        var webURL: URL?
        var imageData: Data?
        if urls.isEmpty, promises.isEmpty {
            let links = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
            webURL = links.first { !$0.isFileURL && $0.scheme != nil }
            if webURL == nil {
                imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
            }
            if webURL == nil, imageData == nil, let string = pasteboard.string(forType: .string), !string.isEmpty {
                text = string
            }
        }
        return DropDragItems(
            fileURLs: urls, promises: promises,
            count: max(info.numberOfValidItemsForDrop, pasteboard.pasteboardItems?.count ?? 0, 0),
            sequence: info.draggingSequenceNumber, sourceOperations: info.draggingSourceOperationMask,
            text: text, webURL: webURL, imageData: imageData)
    }

    /// The operation the destination answers: copy when the source allows it (the host never moves the user's
    /// files), else generic, link or move.
    public static func operation(for mask: NSDragOperation) -> NSDragOperation {
        for candidate: NSDragOperation in [.copy, .generic, .link, .move] where mask.contains(candidate) {
            return candidate
        }
        return []
    }
}

/// `NSFilePromiseReceiver` as a ``PromisedFileReceiving``.
@MainActor
final class SystemPromisedFile: PromisedFileReceiving {
    private let receiver: NSFilePromiseReceiver
    /// Promise readers run here, off the main thread (Apple's guidance for file promises).
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(_ receiver: NSFilePromiseReceiver) {
        self.receiver = receiver
    }

    var contentTypes: [UTType] { receiver.fileTypes.compactMap { UTType($0) } }
    var fileCount: Int { max(receiver.fileTypes.count, 1) }

    func receive(into folder: URL, reader: @escaping @Sendable (Result<URL, any Error>) -> Void) {
        receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: Self.queue) { url, error in
            if let error {
                reader(.failure(error))
            } else {
                reader(.success(url))
            }
        }
    }
}

/// Materializes file promises into a fresh folder under the drops directory (AD-17, AD-19), then hands back
/// the file URLs. ``start(_:in:)`` asks every promise synchronously (inside `performDragOperation`, while the
/// pasteboard is still valid); ``PendingFiles/files()`` waits for them.
@MainActor
public enum FilePromiseMaterializer {
    /// How long a promise may take before the files received so far are used.
    public static let timeout: Duration = .seconds(30)

    public enum Failure: Error, Equatable {
        case noDropsDirectory
    }

    /// Creates `<drops>/<UUID>/` and asks each promise to write into it.
    public static func start(
        _ promises: [any PromisedFileReceiving], in dropsDirectory: URL?, fileManager: FileManager = .default,
        timeout: Duration = timeout
    ) throws -> PendingFiles {
        guard !promises.isEmpty else { return PendingFiles(expected: 0, folder: nil, timeout: timeout) }
        guard let dropsDirectory else { throw Failure.noDropsDirectory }
        let folder = dropsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let pending = PendingFiles(
            expected: promises.reduce(0) { $0 + max($1.fileCount, 1) }, folder: folder, timeout: timeout)
        for promise in promises {
            promise.receive(into: folder) { result in pending.add(result) }
        }
        return pending
    }

    /// The results of one drop's promises, delivered on any queue.
    public final class PendingFiles: @unchecked Sendable {
        private struct State {
            var urls: [URL] = []
            var errors: [String] = []
            var received = 0
            var expired = false
            var waiters: [CheckedContinuation<Void, Never>] = []
        }

        private let state = Mutex(State())
        private let expected: Int
        /// The folder the files land in (nil when there were no promises). Set before the promises start.
        public private(set) var folder: URL?

        /// No promises: ``files()`` returns at once.
        public static var empty: PendingFiles { PendingFiles(expected: 0, folder: nil, timeout: .zero) }

        init(expected: Int, folder: URL?, timeout: Duration) {
            self.expected = expected
            self.folder = folder
            guard expected > 0 else { return }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(expired: true)
            }
        }

        func add(_ result: Result<URL, any Error>) {
            state.withLock { state in
                switch result {
                case .success(let url): state.urls.append(url)
                case .failure(let error): state.errors.append(String(describing: error))
                }
                state.received += 1
            }
            finish(expired: false)
        }

        private func finish(expired: Bool) {
            let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
                if expired { state.expired = true }
                guard state.expired || state.received >= expected else { return [] }
                defer { state.waiters = [] }
                return state.waiters
            }
            for waiter in waiters { waiter.resume() }
        }

        /// Waits until every promised file arrived (or the timeout passed), then returns the files received and
        /// the errors.
        public func files() async -> (urls: [URL], errors: [String]) {
            await withCheckedContinuation { continuation in
                let ready = state.withLock { state -> Bool in
                    if state.expired || state.received >= expected { return true }
                    state.waiters.append(continuation)
                    return false
                }
                if ready { continuation.resume() }
            }
            return state.withLock { ($0.urls, $0.errors) }
        }
    }
}
