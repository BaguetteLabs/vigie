import Foundation

/// The iCloud download state of one file (Story 16.2, AD-12).
public enum UbiquitousItemStatus: Sendable, Equatable {
    /// Not an iCloud item: an ordinary local file.
    case local
    /// An iCloud item whose content is local (current, or an older local copy while a newer one downloads).
    case downloaded
    /// An iCloud item with no local content yet (dataless, or an old-style `.<name>.icloud` placeholder).
    case notDownloaded
}

/// Reads an item's iCloud status and asks for its download. Tests pass a fake (never the real iCloud Drive).
public protocol UbiquitousItemStatusProviding: Sendable {
    func status(of url: URL) -> UbiquitousItemStatus
    func startDownloading(_ url: URL)
}

/// The system's answer: `URLResourceValues.ubiquitousItemDownloadingStatus` and
/// `FileManager.startDownloadingUbiquitousItem(at:)`.
public struct SystemUbiquitousItemStatus: UbiquitousItemStatusProviding {
    public init() {}

    public func status(of url: URL) -> UbiquitousItemStatus {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            // Before macOS 14 a dataless item showed as `.<name>.icloud`.
            let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
            return fm.fileExists(atPath: placeholder.path) ? .notDownloaded : .local
        }
        guard
            let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
            values.isUbiquitousItem == true, let status = values.ubiquitousItemDownloadingStatus
        else { return .local }
        return status == .notDownloaded ? .notDownloaded : .downloaded
    }

    public func startDownloading(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}

/// The outcome of one coordinated read.
public enum CoordinatedRead: Sendable, Equatable {
    case data(Data)
    case missing
    /// An iCloud item that is not downloaded yet; its download was requested. Keep the last good value.
    case pending
    case failed(String)
}

/// Reads files that may live in iCloud Drive (AD-12, Story 16.2): checks `ubiquitousItemDownloadingStatus` first;
/// a dataless file is not read (that would block on the network) but its download is started and the caller keeps
/// its last good value; anything else is read through `NSFileCoordinator`, off the main actor.
public actor CoordinatedFileReader {
    public nonisolated let status: any UbiquitousItemStatusProviding

    public init(status: any UbiquitousItemStatusProviding = SystemUbiquitousItemStatus()) {
        self.status = status
    }

    /// The file's bytes, or nil while it downloads from iCloud (a download was requested).
    /// - Throws: `CocoaError(.fileReadNoSuchFile)` when missing, `CocoaError(.fileReadUnknown)` when unreadable.
    public func read(_ url: URL) throws -> Data? {
        switch Self.readNow(url, status: status) {
        case .data(let data): return data
        case .pending: return nil
        case .missing: throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        case .failed(let reason):
            throw CocoaError(
                .fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path, NSLocalizedDescriptionKey: reason])
        }
    }

    /// The read with its four outcomes (ConfigStore tells a missing file from a pending one).
    public func readResult(_ url: URL) -> CoordinatedRead {
        Self.readNow(url, status: status)
    }

    /// The same read on the calling thread (ConfigWriter, already off the main actor).
    nonisolated static func readNow(_ url: URL, status: any UbiquitousItemStatusProviding) -> CoordinatedRead {
        if status.status(of: url) == .notDownloaded {
            status.startDownloading(url)
            return .pending
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .missing }
        var coordinationError: NSError?
        var result = CoordinatedRead.failed("coordination failed")
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do {
                result = .data(try Data(contentsOf: readURL))
            } catch {
                result = fm.fileExists(atPath: readURL.path) ? .failed(error.localizedDescription) : .missing
            }
        }
        if let coordinationError { return .failed(coordinationError.localizedDescription) }
        return result
    }
}
