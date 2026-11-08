import AppKit
import Foundation
import ModuleKit
import os

/// Why a Stash drop stored nothing (UX-DR101). `reason` goes into the activity entry.
public enum StashFailure: String, Error, Equatable, Sendable {
    /// The payload carried no file, text, link or image.
    case nothingToStash
    /// A dropped file is missing or cannot be read, or image data cannot be decoded.
    case unreadable
    /// The volume holding the module folder is full.
    case diskFull
    /// The security-scoped bookmark could not be created.
    case bookmarkFailed
    /// Any other failure writing into the module folder.
    case writeFailed

    public var reason: String { rawValue }
}

/// Owns the shelf index (`index.json` in `context.storage`, AD-11) and the module folder's `items/` (copies and
/// saved items, one folder per item: `items/<id>/<name>`).
///
/// Every change is written through `ModuleStorage.writeJSON` (atomic). A Stash drop is all or nothing: when
/// one dropped file fails, the copies made for the others are removed again and the index is unchanged.
public actor ShelfStore {
    nonisolated static let indexName = "index"
    nonisolated static let indexSchema = 1
    nonisolated static let itemsFolder = "items"

    private let storage: any ModuleStorage
    private let scope: any SecurityScopedResources
    private let log: Logger
    /// The module folder (`context.storage.directory`).
    public nonisolated let directory: URL
    /// Newest first.
    public private(set) var items: [ShelfItem] = []

    public init(storage: any ModuleStorage, scope: any SecurityScopedResources, log: Logger) {
        self.storage = storage
        self.scope = scope
        self.log = log
        directory = storage.directory
    }

    /// Reads `index.json` (missing or unreadable: an empty shelf).
    @discardableResult
    public func load() async -> [ShelfItem] {
        do {
            items =
                try await storage.readJSON(Self.indexName, as: ShelfIndex.self, schema: Self.indexSchema)?.items ?? []
        } catch {
            log.error("Shelf index not read: \(String(describing: error), privacy: .public)")
            items = []
        }
        return items
    }

    // MARK: Stash

    /// Stores what a Stash drop carried: files as references (`mode = .reference`) or copies, else the dragged
    /// link (`.webloc`), image (`.png`) or text (`.txt`) as a saved file. Returns the added items (newest
    /// first); throws a ``StashFailure`` and adds nothing when any part fails. Finishes reading the dropped
    /// files before it returns.
    @discardableResult
    public func stash(_ payload: DropPayload, mode: StashMode, ttl: Duration, now: Date) async throws -> [ShelfItem] {
        var added: [ShelfItem] = []
        var createdFolders: [URL] = []
        do {
            if !payload.urls.isEmpty {
                for url in payload.urls {
                    let item = try stashFile(url, mode: mode, ttl: ttl, now: now, created: &createdFolders)
                    added.append(item)
                }
            } else if let link = payload.url {
                added.append(
                    try save(Self.webloc(link), name: Self.linkName(link), ttl: ttl, now: now, created: &createdFolders)
                )
            } else if let data = payload.imageData {
                guard let png = Self.png(from: data) else { throw StashFailure.unreadable }
                added.append(
                    try save(
                        png, name: Self.fileName(ShelfText.string("shelf.saved.imageName"), ext: "png"), ttl: ttl,
                        now: now, created: &createdFolders))
            } else if let text = payload.text, !text.isEmpty {
                added.append(
                    try save(Data(text.utf8), name: Self.textName(text), ttl: ttl, now: now, created: &createdFolders))
            } else {
                throw StashFailure.nothingToStash
            }
        } catch {
            let fileManager = FileManager.default
            for folder in createdFolders { try? fileManager.removeItem(at: folder) }
            throw (error as? StashFailure) ?? Self.failure(for: error)
        }
        items.insert(contentsOf: added.reversed(), at: 0)
        await persist()
        return added
    }

    private func stashFile(_ url: URL, mode: StashMode, ttl: Duration, now: Date, created: inout [URL]) throws
        -> ShelfItem
    {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path), fileManager.isReadableFile(atPath: url.path) else {
            throw StashFailure.unreadable
        }
        let size = Self.size(of: url)
        let name = url.lastPathComponent
        let id = UUID()
        switch mode {
        case .reference:
            let bookmark: Data
            do {
                bookmark = try scope.bookmark(for: url)
            } catch {
                throw StashFailure.bookmarkFailed
            }
            return ShelfItem(
                id: id, name: name, size: size, addedAt: now, mode: .reference, bookmark: bookmark,
                expiresAt: ShelfItem.expiry(addedAt: now, ttl: ttl, pinned: false))
        case .copy:
            let (folder, relative) = try makeFolder(for: id, name: name, created: &created)
            do {
                try fileManager.copyItem(at: url, to: folder.appendingPathComponent(name))
            } catch {
                throw Self.failure(for: error)
            }
            return ShelfItem(
                id: id, name: name, size: size, addedAt: now, mode: .copy, relativePath: relative,
                expiresAt: ShelfItem.expiry(addedAt: now, ttl: ttl, pinned: false))
        }
    }

    private func save(_ data: Data, name: String, ttl: Duration, now: Date, created: inout [URL]) throws -> ShelfItem {
        let id = UUID()
        let (folder, relative) = try makeFolder(for: id, name: name, created: &created)
        do {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        } catch {
            throw Self.failure(for: error)
        }
        return ShelfItem(
            id: id, name: name, size: Int64(data.count), addedAt: now, mode: .saved, relativePath: relative,
            expiresAt: ShelfItem.expiry(addedAt: now, ttl: ttl, pinned: false))
    }

    private func makeFolder(for id: UUID, name: String, created: inout [URL]) throws -> (URL, String) {
        let folder = directory.appendingPathComponent(Self.itemsFolder, isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw Self.failure(for: error)
        }
        created.append(folder)
        return (folder, "\(Self.itemsFolder)/\(id.uuidString)/\(name)")
    }

    // MARK: Queries and changes (Story 9.3 builds on these)

    public func item(_ id: UUID) -> ShelfItem? { items.first { $0.id == id } }

    /// The file of a `COPY` or `SAVED` item under the module folder; nil for a reference.
    public nonisolated func fileURL(for item: ShelfItem) -> URL? {
        guard item.mode != .reference, let relativePath = item.relativePath else { return nil }
        return directory.appendingPathComponent(relativePath)
    }

    /// Drops `id` from the index and returns it. Its file is left where it is (the caller moves it out or
    /// recycles it; nothing is deleted permanently).
    @discardableResult
    public func remove(_ id: UUID) async -> ShelfItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = items.remove(at: index)
        await persist()
        return item
    }

    /// Pins (never expires) or unpins (expires `ttl` after it was added) an item.
    public func setPinned(_ id: UUID, _ pinned: Bool, ttl: Duration) async {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].pinned != pinned else { return }
        items[index].pinned = pinned
        items[index].expiresAt = ShelfItem.expiry(addedAt: items[index].addedAt, ttl: ttl, pinned: pinned)
        resetNotice(index)
        await persist()
    }

    /// Records that `shelf.expiring` was posted for these items.
    public func markExpiryNotified(_ ids: [UUID], at date: Date) async {
        let ids = Set(ids)
        for index in items.indices where ids.contains(items[index].id) { items[index].expiryNotifiedAt = date }
        await persist()
    }

    /// Clears the expiry notice when the item is no longer in its last 24 h, so it is posted again next time.
    private func resetNotice(_ index: Int) {
        guard let notified = items[index].expiryNotifiedAt else { return }
        let item = items[index]
        let stillWarned =
            item.expiresAt.map { $0.timeIntervalSince(notified) <= ShelfExpiry.warningWindow } ?? false
        if !stillWarned { items[index].expiryNotifiedAt = nil }
    }

    /// Re-computes `expiresAt` for a new `ttl`, from each item's `addedAt` (pinned items keep none): the ttl
    /// is how long an item stays after it was stashed, so a shorter ttl can expire items at the next sweep.
    /// Returns whether anything changed.
    @discardableResult
    public func recomputeExpiry(ttl: Duration) async -> Bool {
        var changed = false
        for index in items.indices {
            let expiry = ShelfItem.expiry(addedAt: items[index].addedAt, ttl: ttl, pinned: items[index].pinned)
            if items[index].expiresAt != expiry {
                items[index].expiresAt = expiry
                resetNotice(index)
                changed = true
            }
        }
        if changed { await persist() }
        return changed
    }

    /// Runs `body` with the item's file: a reference's bookmark is resolved (`.withSecurityScope`), access is
    /// started before `body` and stopped after it returns or throws; a stale bookmark is replaced by a fresh one.
    /// Copies and saved items need no scope. `body` must finish reading the file before it returns.
    public func withSecurityScopedAccess<T: Sendable>(
        _ id: UUID, _ body: @Sendable (URL) async throws -> T
    ) async throws -> T {
        guard let item = item(id) else { throw ShelfAccessError.notFound }
        guard item.mode == .reference else {
            guard let url = fileURL(for: item), FileManager.default.fileExists(atPath: url.path) else {
                throw ShelfAccessError.missingFile
            }
            return try await body(url)
        }
        guard let bookmark = item.bookmark, let resolved = try? scope.resolve(bookmark) else {
            throw ShelfAccessError.unresolvable
        }
        let started = scope.startAccessing(resolved.url)
        defer { if started { scope.stopAccessing(resolved.url) } }
        if resolved.isStale, let fresh = try? scope.bookmark(for: resolved.url),
            let index = items.firstIndex(where: { $0.id == id })
        {
            items[index].bookmark = fresh
            await persist()
        }
        return try await body(resolved.url)
    }

    // MARK: Persistence

    func persist() async {
        do {
            try await storage.writeJSON(ShelfIndex(items: items), name: Self.indexName, schema: Self.indexSchema)
        } catch {
            log.error("Shelf index not written: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Helpers

    static func failure(for error: any Error) -> StashFailure {
        if let failure = error as? StashFailure { return failure }
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.fileWriteOutOfSpace.rawValue {
            return .diskFull
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) { return .diskFull }
        if underlying?.domain == NSPOSIXErrorDomain, underlying?.code == Int(ENOSPC) { return .diskFull }
        if nsError.domain == NSCocoaErrorDomain,
            [CocoaError.fileReadNoPermission, .fileReadNoSuchFile, .fileReadUnknown, .fileNoSuchFile]
                .map(\.rawValue).contains(nsError.code)
        {
            return .unreadable
        }
        return .writeFailed
    }

    /// Bytes of a file, or the sum of a folder's files.
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else {
            return Int64(values.totalFileSize ?? values.fileSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let child = enumerator?.nextObject() as? URL {
            guard let child = try? child.resourceValues(forKeys: keys), child.isDirectory != true else { continue }
            total += Int64(child.totalFileSize ?? child.fileSize ?? 0)
        }
        return total
    }

    /// A `.webloc`: an XML property list with the `URL` key, as Finder writes it.
    static func webloc(_ url: URL) throws -> Data {
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0)
        } catch {
            throw StashFailure.writeFailed
        }
    }

    /// PNG bytes as they are, other image data (TIFF) converted to PNG; nil when it is not an image.
    static func png(from data: Data) -> Data? {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        if data.starts(with: signature) { return data }
        return NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
    }

    static func linkName(_ url: URL) -> String {
        fileName(url.host() ?? ShelfText.string("shelf.saved.linkName"), ext: "webloc")
    }

    /// The first line of the text (at most 40 characters), else the catalog's fallback name.
    static func textName(_ text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return fileName(firstLine, fallback: ShelfText.string("shelf.saved.textName"), ext: "txt")
    }

    /// A safe file name: no `/` or `:`, no leading dot, trimmed, at most 40 characters.
    static func fileName(_ base: String, fallback: String? = nil, ext: String) -> String {
        var cleaned = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = String(cleaned.prefix(40)).trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { cleaned = fallback ?? base }
        return "\(cleaned).\(ext)"
    }
}
