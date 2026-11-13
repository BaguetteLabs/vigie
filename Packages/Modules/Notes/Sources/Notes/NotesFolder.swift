import Foundation
import ModuleKit

/// The plaintext first line of every note file (AD-10, Story 15.2): `{"format":1,"key_id":"<16 hex>"}` and a
/// line feed, then the ciphertext. The notes key marker (``NotesFolder/markerName``) holds the same line alone.
public struct NoteFileHeader: Hashable, Sendable, Codable {
    /// The note file format this Vigie writes.
    public static let currentFormat = 1
    /// At most this many bytes are read to find the header line.
    public static let maxLength = 512

    public let format: Int
    public let keyID: String

    public init(format: Int = NoteFileHeader.currentFormat, keyID: String) {
        self.format = format
        self.keyID = keyID
    }

    enum CodingKeys: String, CodingKey {
        case format
        case keyID = "key_id"
    }

    /// The header line, line feed included.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = (try? encoder.encode(self)) ?? Data()
        data.append(0x0A)
        return data
    }

    /// The header at the start of `data` (up to the first line feed), or nil when there is none or the `key_id`
    /// is malformed. Never looks past the first line.
    public static func parse(_ data: Data) -> NoteFileHeader? {
        let line = data.prefix(maxLength).prefix { $0 != 0x0A }
        guard let header = try? JSONDecoder().decode(NoteFileHeader.self, from: Data(line)),
            SyncedKey.isValidKeyID(header.keyID)
        else { return nil }
        return header
    }
}

/// What the notes folder says about keys (Story 15.1), read from note headers only, never contents.
public struct NotesFolderScan: Hashable, Sendable {
    /// `*.vnote` files, including iCloud placeholders not downloaded yet and files whose header is unreadable.
    public var noteFiles = 0
    /// Note files whose `key_id` is not known (not downloaded yet, or no valid header).
    public var unreadableFiles = 0
    /// The `key_id`s of the note headers and of the key marker.
    public var keyIDs: Set<String> = []
    /// Note files per header `key_id` (the marker not counted).
    public var keyIDCounts: [String: Int] = [:]
    /// The marker's `key_id`, when it was read.
    public var markerKeyID: String?
    /// The marker exists but is not downloaded or readable.
    public var markerUnreadable = false

    public init() {}

    /// True when the folder shows that a key exists already (note files or a marker): setup must not create one.
    public var showsExistingKey: Bool { noteFiles > 0 || !keyIDs.isEmpty || markerUnreadable }
}

/// Reads and writes the notes folder's key evidence (Story 15.1). Off the main actor, through
/// `NSFileCoordinator` (AD-12).
public enum NotesFolder {
    /// Note file extension (Story 15.2 writes `<id>.vnote`).
    public static let noteExtension = "vnote"
    /// The key marker: written when the key is created or recovered, so another Mac sees that a key exists even
    /// before any note is written (and waits for it instead of creating a second one, AD-10).
    public static let markerName = "notes-key.json"
    /// iCloud Drive's placeholder for a file not downloaded yet: `.<name>.icloud`.
    static let placeholderExtension = "icloud"

    /// Scans `folder`: a missing folder is empty.
    public static func scan(_ folder: URL) async -> NotesFolderScan {
        await Task.detached(priority: .utility) { scanNow(folder) }.value
    }

    static func scanNow(_ folder: URL) -> NotesFolderScan {
        var scan = NotesFolderScan()
        guard
            let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return scan }
        for name in names {
            let url = folder.appendingPathComponent(name)
            if name == markerName {
                if let header = readHeader(url) {
                    scan.markerKeyID = header.keyID
                    scan.keyIDs.insert(header.keyID)
                } else {
                    scan.markerUnreadable = true
                }
            } else if name == ".\(markerName).\(placeholderExtension)" {
                scan.markerUnreadable = true
            } else if url.pathExtension == noteExtension, !name.hasPrefix(".") {
                scan.noteFiles += 1
                if let header = readHeader(url) {
                    scan.keyIDs.insert(header.keyID)
                    scan.keyIDCounts[header.keyID, default: 0] += 1
                } else {
                    scan.unreadableFiles += 1
                }
            } else if name.hasPrefix("."), url.pathExtension == placeholderExtension,
                url.deletingPathExtension().pathExtension == noteExtension
            {
                scan.noteFiles += 1
                scan.unreadableFiles += 1
            }
        }
        return scan
    }

    /// The header line of `url`, read through a coordinated read of at most ``NoteFileHeader/maxLength`` bytes.
    static func readHeader(_ url: URL) -> NoteFileHeader? {
        var result: NoteFileHeader?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) {
            readURL in
            guard let handle = try? FileHandle(forReadingFrom: readURL) else { return }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: NoteFileHeader.maxLength) else { return }
            result = NoteFileHeader.parse(data)
        }
        return result
    }

    /// Writes the key marker (creating the folder), through a coordinated atomic write.
    public static func writeMarker(keyID: String, in folder: URL) async throws {
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(markerName)
            let data = NoteFileHeader(keyID: keyID).encoded()
            var coordinationError: NSError?
            var writeError: (any Error)?
            NSFileCoordinator().coordinate(writingItemAt: url, options: [.forReplacing], error: &coordinationError) {
                writeURL in
                do { try data.write(to: writeURL, options: .atomic) } catch { writeError = error }
            }
            if let error = coordinationError ?? writeError { throw error }
        }.value
    }
}
