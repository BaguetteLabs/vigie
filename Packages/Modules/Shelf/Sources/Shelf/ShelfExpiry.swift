import AppKit
import Foundation
import ModuleKit
import os

/// Moves files to the Trash. ``WorkspaceRecycler`` uses `NSWorkspace.recycle` (AD-11); tests record calls.
/// Shelf never deletes a file permanently.
public protocol Recycler: Sendable {
    func recycle(_ url: URL) async throws
}

public struct WorkspaceRecycler: Recycler {
    public init() {}

    public func recycle(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

/// Expiry rules (SPEC §7.3, UX-DR33, Story 9.4).
public enum ShelfExpiry {
    /// The last 24 h before expiry: the row turns quota-warning yellow and `shelf.expiring` may be posted.
    public static let warningWindow: TimeInterval = 86_400

    /// Seconds left, never negative; nil when the item never expires (pinned).
    static func remaining(_ item: ShelfItem, now: Date) -> TimeInterval? {
        guard !item.pinned, let expiresAt = item.expiresAt else { return nil }
        return max(expiresAt.timeIntervalSince(now), 0)
    }

    /// The row's time-left text: `6D LEFT` (2 days or more), `1D 18H LEFT` (under 2 days), `EXPIRES IN 5H`
    /// (the last 24 h, hours rounded up, at least 1). Nil when pinned.
    public static func timeLeftLabel(_ item: ShelfItem, now: Date) -> String? {
        guard let remaining = remaining(item, now: now) else { return nil }
        if remaining <= warningWindow {
            let hours = max(Int((remaining / 3600).rounded(.up)), 1)
            return ShelfText.format("shelf.timeLeft.hours", hours)
        }
        if remaining < 2 * warningWindow {
            let hours = Int(((remaining - warningWindow) / 3600).rounded(.down))
            return hours > 0
                ? ShelfText.format("shelf.timeLeft.dayHours", 1, hours) : ShelfText.format("shelf.timeLeft.day", 1)
        }
        return ShelfText.format("shelf.timeLeft.days", Int((remaining / warningWindow).rounded(.down)))
    }

    /// True in the last 24 h before expiry (not yet expired).
    public static func isExpiring(_ item: ShelfItem, now: Date) -> Bool {
        guard !item.pinned, let expiresAt = item.expiresAt else { return false }
        let remaining = expiresAt.timeIntervalSince(now)
        return remaining > 0 && remaining <= warningWindow
    }

    /// True once `expiresAt` has passed.
    public static func isExpired(_ item: ShelfItem, now: Date) -> Bool {
        guard !item.pinned, let expiresAt = item.expiresAt else { return false }
        return expiresAt <= now
    }

    /// The card meta `1 EXPIRING`, or nil when nothing is expiring.
    public static func expiringMeta(count: Int) -> String? {
        count > 0 ? ShelfText.format("shelf.expiring.count", count) : nil
    }
}

extension ShelfItem {
    /// `6D LEFT` / `1D 18H LEFT` / `EXPIRES IN 5H`; nil when pinned.
    public func timeLeftLabel(now: Date) -> String? { ShelfExpiry.timeLeftLabel(self, now: now) }
    /// In the last 24 h before expiry: quota-warning yellow + triangle on the row (A43).
    public func isExpiring(now: Date) -> Bool { ShelfExpiry.isExpiring(self, now: now) }
}

/// One pass over the shelf (Story 9.4): items past `expiresAt` leave it (a reference is dropped from the index,
/// its original untouched; a copy or saved item is moved to the Trash first), then, with
/// `expiry_notification` on, each item that entered its last 24 h gets one `shelf.expiring` alert. Running it
/// again with nothing new changes nothing.
public struct ExpirySweeper: Sendable {
    public struct Report: Equatable, Sendable {
        /// Items that left the shelf.
        public var expired: [UUID] = []
        /// Copies and saved items moved to the Trash (a subset of `expired`).
        public var recycled: [UUID] = []
        /// Items whose `shelf.expiring` was posted on this pass.
        public var notified: [UUID] = []

        public var changed: Bool { !expired.isEmpty || !notified.isEmpty }
    }

    public static let alertKind = "shelf.expiring"

    let recycler: any Recycler
    let notifier: any Notifier
    let log: Logger

    public init(recycler: any Recycler, notifier: any Notifier, log: Logger) {
        self.recycler = recycler
        self.notifier = notifier
        self.log = log
    }

    public func sweep(_ store: ShelfStore, now: Date, notify: Bool) async -> Report {
        var report = Report()
        for item in await store.items where ShelfExpiry.isExpired(item, now: now) {
            if let url = store.fileURL(for: item) {
                if Self.exists(url) {
                    do {
                        try await recycler.recycle(url)
                        report.recycled.append(item.id)
                    } catch {
                        // Kept on the shelf; the next pass tries again. Never deleted instead.
                        log.error("Shelf item not moved to the Trash: \(String(describing: error), privacy: .public)")
                        continue
                    }
                }
                Self.removeEmptyFolder(url.deletingLastPathComponent())
            }
            await store.remove(item.id)
            report.expired.append(item.id)
        }
        guard notify else { return report }
        let due = await store.items.filter { $0.isExpiring(now: now) && $0.expiryNotifiedAt == nil }
        for item in due {
            notifier.post(Self.event(for: item, now: now))
            report.notified.append(item.id)
        }
        if !due.isEmpty { await store.markExpiryNotified(due.map(\.id), at: now) }
        return report
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// `items/<id>/` once its file went to the Trash: `rmdir` removes it only when empty.
    static func removeEmptyFolder(_ folder: URL) {
        _ = folder.withUnsafeFileSystemRepresentation { path in path.map { rmdir($0) } }
    }

    /// `shelf.expiring`: macOS notification only (the Notifier's kind default), deduped per item.
    static func event(for item: ShelfItem, now: Date) -> NotifierEvent {
        let remaining = ShelfExpiry.remaining(item, now: now) ?? 0
        let hours = max(Int((remaining / 3600).rounded(.up)), 1)
        let body =
            item.mode == .reference
            ? ShelfText.format("shelf.expiring.body", hours) : ShelfText.format("shelf.expiring.bodyTrash", hours)
        return NotifierEvent(
            kind: alertKind, severity: .warn, title: ShelfText.format("shelf.expiring.title", item.name), body: body,
            dedupeKey: "\(alertKind):\(item.id.uuidString)")
    }
}
