import Foundation

/// What expiry does to an item, shown on its row (SPEC §7.3): a reference leaves the shelf, a copy or a saved
/// item goes to the Trash.
public enum ShelfItemMode: String, Codable, Hashable, Sendable, CaseIterable {
    /// A security-scoped bookmark to the user's file (`mode = "reference"`, the default).
    case reference = "REF"
    /// A copy under the module folder (`mode = "copy"`).
    case copy = "COPY"
    /// Dragged text, a link or an image saved as a file under the module folder.
    case saved = "SAVED"
}

/// How a dropped file is kept: the `mode` setting.
public enum StashMode: String, Hashable, Sendable, CaseIterable {
    case reference
    case copy
}

/// One stashed item, as stored in `index.json`.
public struct ShelfItem: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    /// File name shown on the row (with its extension).
    public var name: String
    /// Bytes, read from the file at stash time (a folder: the sum of its files).
    public var size: Int64
    /// The app the item was dragged from, when the host knew it (nil today, see `DropPayload`).
    public var sourceApp: String?
    public var addedAt: Date
    public var mode: ShelfItemMode
    /// Security-scoped bookmark of the original (`REF` only).
    public var bookmark: Data?
    /// Path under the module folder (`items/<id>/<name>`, `COPY` and `SAVED` only).
    public var relativePath: String?
    public var pinned: Bool
    /// `addedAt + ttl`; nil while pinned (never expires).
    public var expiresAt: Date?
    /// When `shelf.expiring` was posted for the current `expiresAt` (once per item); nil before, and again
    /// after a pin or `ttl` change moves the item out of its last 24 h.
    public var expiryNotifiedAt: Date?

    public init(
        id: UUID = UUID(), name: String, size: Int64, sourceApp: String? = nil, addedAt: Date, mode: ShelfItemMode,
        bookmark: Data? = nil, relativePath: String? = nil, pinned: Bool = false, expiresAt: Date?
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.sourceApp = sourceApp
        self.addedAt = addedAt
        self.mode = mode
        self.bookmark = bookmark
        self.relativePath = relativePath
        self.pinned = pinned
        self.expiresAt = expiresAt
    }

    /// The expiry date for `ttl`: `addedAt + ttl`, nil when pinned.
    public static func expiry(addedAt: Date, ttl: Duration, pinned: Bool) -> Date? {
        pinned ? nil : addedAt.addingTimeInterval(ttl.timeInterval)
    }
}

/// `index.json` (schema 1): every item on the shelf, newest first.
struct ShelfIndex: Codable, Sendable, Equatable {
    var items: [ShelfItem]
}

extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
