import Foundation

/// Security-scoped bookmarks (AD-19): ``SystemSecurityScope`` uses the URL APIs; tests count the calls.
public protocol SecurityScopedResources: Sendable {
    /// A bookmark created with `.withSecurityScope`.
    func bookmark(for url: URL) throws -> Data
    /// Resolves a bookmark created by ``bookmark(for:)``; `isStale` asks for a fresh one.
    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool)
    /// `startAccessingSecurityScopedResource`; false when the URL needs no (or got no) scope.
    func startAccessing(_ url: URL) -> Bool
    /// `stopAccessingSecurityScopedResource`, called once for every successful ``startAccessing(_:)``.
    func stopAccessing(_ url: URL)
}

public struct SystemSecurityScope: SecurityScopedResources {
    public init() {}

    public func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }

    public func startAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    public func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

/// Why an item's file cannot be reached.
public enum ShelfAccessError: Error, Equatable, Sendable {
    /// No item with this id.
    case notFound
    /// The bookmark no longer resolves (the original was deleted or its volume is gone).
    case unresolvable
    /// A copy or saved item whose file is missing.
    case missingFile
}
