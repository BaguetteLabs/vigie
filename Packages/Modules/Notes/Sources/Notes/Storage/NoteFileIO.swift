import CryptoKit
import Foundation
import ModuleKit

/// One unresolved sync conflict version of a note file (`NSFileVersion`), identified by its storage URL.
public struct ConflictVersion: Hashable, Sendable {
    /// Stable identity of the version (its storage URL's path).
    public let id: String
    /// Where the version's bytes are.
    public let url: URL

    public init(id: String, url: URL) {
        self.id = id
        self.url = url
    }
}

/// The `NSFileVersion` seam (Story 15.2, AD-10 conflicts). Called off the main actor, from ``NoteFileIO``.
public protocol ConflictVersionsProviding: Sendable {
    /// The unresolved conflict versions of the item at `url` (empty when there are none).
    func unresolvedConflicts(of url: URL) -> [ConflictVersion]
    /// The bytes of `version`, through a coordinated read of the item.
    func read(_ version: ConflictVersion, of url: URL) throws -> Data
    /// Marks `version` resolved, through a coordinated write of the item. Never removes other versions (macOS
    /// keeps the history).
    func resolve(_ version: ConflictVersion, of url: URL) throws
}

/// The real ``ConflictVersionsProviding``: `NSFileVersion.unresolvedConflictVersionsOfItem(at:)`.
public struct FileVersionConflicts: ConflictVersionsProviding {
    public init() {}

    public func unresolvedConflicts(of url: URL) -> [ConflictVersion] {
        (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map {
            ConflictVersion(id: $0.url.path, url: $0.url)
        }
    }

    public func read(_ version: ConflictVersion, of url: URL) throws -> Data {
        var result: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) {
            _ in
            result = Result { try Data(contentsOf: version.url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    public func resolve(_ version: ConflictVersion, of url: URL) throws {
        var resolveError: (any Error)?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { _ in
            guard
                let match = NSFileVersion.unresolvedConflictVersionsOfItem(at: url)?.first(where: {
                    $0.url.path == version.id
                })
            else { return }
            match.isResolved = true
            if match.isResolved == false { resolveError = CocoaError(.fileWriteUnknown) }
        }
        if let error = coordinationError ?? resolveError { throw error }
    }
}

/// What the notes folder's listing says about a file, before decryption.
public struct NoteFileStamp: Hashable, Sendable {
    public var modified: Date?
    public var size: Int
    /// SHA-256 of the bytes, when they were read or written.
    public var digest: Data?
}

/// How deleted notes leave the folder.
public enum NoteDeletion: Sendable {
    /// `FileManager.trashItem` (the default): the user can still recover the file.
    case trash
    /// Removed at once (tests).
    case remove
}

/// One entry of the notes folder.
struct NoteFolderEntry: Sendable {
    enum Kind: Sendable {
        /// A `.vnote` file whose bytes are local.
        case file(NoteFileStamp)
        /// iCloud has not downloaded the file yet (dataless or `.icloud` placeholder).
        case downloading
    }

    /// `<id>.vnote` (for a placeholder, the name of the file it stands for).
    let name: String
    let kind: Kind
}

/// The notes folder's file I/O (Story 15.2, AD-12): off the main actor, every read and write coordinated with
/// `NSFileCoordinator`, writes atomic (a temp file in the same folder renamed over the note). Holds no note text.
public actor NoteFileIO {
    let conflicts: any ConflictVersionsProviding
    let deletion: NoteDeletion

    public init(conflicts: any ConflictVersionsProviding = FileVersionConflicts(), deletion: NoteDeletion = .trash) {
        self.conflicts = conflicts
        self.deletion = deletion
    }

    /// The `.vnote` files of `folder` (and iCloud placeholders), plus the key marker's `key_id` when readable. A
    /// missing folder is empty. Asks iCloud to download every file that is not current.
    func list(_ folder: URL) -> (entries: [NoteFolderEntry], markerKeyID: String?) {
        let keys: [URLResourceKey] = [
            .contentModificationDateKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [])
        else { return ([], nil) }
        var entries: [NoteFolderEntry] = []
        var markerKeyID: String?
        for url in urls {
            let name = url.lastPathComponent
            if name == NotesFolder.markerName {
                markerKeyID = NotesFolder.readHeader(url)?.keyID
            } else if url.pathExtension == NotesFolder.noteExtension, !name.hasPrefix(".") {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isUbiquitousItem == true,
                    let status = values?.ubiquitousItemDownloadingStatus, status != .current
                {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                    entries.append(NoteFolderEntry(name: name, kind: .downloading))
                } else {
                    let stamp = NoteFileStamp(
                        modified: values?.contentModificationDate, size: values?.fileSize ?? 0, digest: nil)
                    entries.append(NoteFolderEntry(name: name, kind: .file(stamp)))
                }
            } else if name.hasPrefix("."), url.pathExtension == NotesFolder.placeholderExtension,
                url.deletingPathExtension().pathExtension == NotesFolder.noteExtension
            {
                let realName = String(url.deletingPathExtension().lastPathComponent.dropFirst())
                try? FileManager.default.startDownloadingUbiquitousItem(
                    at: folder.appendingPathComponent(realName))
                entries.append(NoteFolderEntry(name: realName, kind: .downloading))
            }
        }
        return (entries, markerKeyID)
    }

    /// The bytes of `url`, through a coordinated read.
    func read(_ url: URL) throws -> Data {
        var result: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) {
            readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Writes `data` to `url` (creating the folder): a temp file in the same folder, then renamed over `url`,
    /// inside a coordinated write. Returns the written file's stamp.
    func write(_ data: Data, to url: URL) throws -> NoteFileStamp {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var writeError: (any Error)?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [.forReplacing], error: &coordinationError) {
            writeURL in
            let temp = folder.appendingPathComponent(".\(writeURL.lastPathComponent).\(UUID().uuidString).tmp")
            do {
                try data.write(to: temp)
                if rename(temp.path, writeURL.path) != 0 {
                    throw CocoaError(.fileWriteUnknown)
                }
            } catch {
                try? FileManager.default.removeItem(at: temp)
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return NoteFileStamp(
            modified: values?.contentModificationDate, size: values?.fileSize ?? data.count,
            digest: Self.digest(data))
    }

    /// Moves `url` to the Trash (or removes it, per ``deletion``), through a coordinated write.
    func delete(_ url: URL) throws {
        var deleteError: (any Error)?
        var coordinationError: NSError?
        let deletion = deletion
        NSFileCoordinator().coordinate(writingItemAt: url, options: [.forDeleting], error: &coordinationError) {
            deleteURL in
            do {
                switch deletion {
                case .trash: try FileManager.default.trashItem(at: deleteURL, resultingItemURL: nil)
                case .remove: try FileManager.default.removeItem(at: deleteURL)
                }
            } catch {
                deleteError = error
            }
        }
        if let error = coordinationError ?? deleteError { throw error }
    }

    func unresolvedConflicts(of url: URL) -> [ConflictVersion] { conflicts.unresolvedConflicts(of: url) }
    func read(_ version: ConflictVersion, of url: URL) throws -> Data { try conflicts.read(version, of: url) }
    func resolve(_ version: ConflictVersion, of url: URL) throws { try conflicts.resolve(version, of: url) }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    static func digest(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
}
