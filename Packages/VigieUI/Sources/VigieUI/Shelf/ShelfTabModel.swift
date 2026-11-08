import Foundation
import ModuleKit
import SwiftUI

/// One Stash row of the Shelf tab (DESIGN "Shelf row", UX-DR33), with every text already formatted by the
/// Shelf module from its catalog.
public struct ShelfRowModel: Identifiable, Equatable, Sendable {
    /// What the expires column shows.
    public enum Expiry: Equatable, Sendable {
        /// `6D LEFT` over the metal TTL bar; `fraction` = time left / ttl (0...1).
        case timeLeft(String, fraction: Double)
        /// The last 24 h: `EXPIRES IN 5H` with the triangle, in quota-warning yellow (A43, never color only).
        case expiring(String, fraction: Double)
        /// `PINNED` over the dashed line (lilac in A, struct in C); no bar.
        case pinned
    }

    public let id: UUID
    /// File name with its extension. Sensitive (Privacy mode, AD-24); the `kind` tile stays.
    @Sensitive public var name: String
    /// The file tile's label (`PDF`, `TXT`), empty when the name has no extension.
    public var kind: String
    /// `184 KB · REF`.
    public var sizeMode: String
    /// The app it came from; nil shows `—`.
    public var sourceApp: String?
    /// `14:31` over `TODAY` / `TUE 03` / `FRI 30 OCT`.
    public var addedTime: String
    public var addedDay: String
    public var expiry: Expiry
    public var accessibilityLabel: String

    public init(
        id: UUID, name: String, kind: String, sizeMode: String, sourceApp: String?, addedTime: String,
        addedDay: String, expiry: Expiry, accessibilityLabel: String
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sizeMode = sizeMode
        self.sourceApp = sourceApp
        self.addedTime = addedTime
        self.addedDay = addedDay
        self.expiry = expiry
        self.accessibilityLabel = accessibilityLabel
    }

    public var isPinned: Bool { expiry == .pinned }
}

extension ShelfRowModel: PrivacyRedactable {
    /// The file name masked, in the row and its VoiceOver label; kind, size, times and expiry stay.
    public func redacted() -> ShelfRowModel {
        var copy = self
        copy.accessibilityLabel = PrivacyMask.scrub(accessibilityLabel, removing: [name])
        copy.name = $name.masked
        return copy
    }
}

/// What the Shelf tab shows now.
public struct ShelfTabSnapshot: Sendable {
    /// `STASH · 5`.
    public var title: String
    /// `1 EXPIRING`, nil when nothing is in its last 24 h.
    public var expiringMeta: String?
    /// `TTL 7D` (`TTL 12H` when the ttl is not whole days).
    public var ttlMeta: String
    /// Newest first.
    public var rows: [ShelfRowModel]
    /// The selected row (click, ↑↓); Space opens Quick Look on it.
    public var selectedID: UUID?
    /// The empty state's sentence, naming the ttl.
    public var emptySentence: LocalizedStringResource
    /// A short line in the footer after an action could not run (`FILE NOT FOUND`); nil otherwise.
    public var notice: String?

    public init(
        title: String, expiringMeta: String? = nil, ttlMeta: String, rows: [ShelfRowModel], selectedID: UUID? = nil,
        emptySentence: LocalizedStringResource, notice: String? = nil
    ) {
        self.title = title
        self.expiringMeta = expiringMeta
        self.ttlMeta = ttlMeta
        self.rows = rows
        self.selectedID = selectedID
        self.emptySentence = emptySentence
        self.notice = notice
    }

    /// The snapshot as Privacy mode shows it (AD-24).
    public func privacy(_ privacyActive: Bool) -> ShelfTabSnapshot {
        guard privacyActive else { return self }
        var copy = self
        copy.rows = rows.map { $0.redacted() }
        return copy
    }
}

/// How a drag out of the Stash ended, as the drop target reported it.
public enum ShelfDragOperation: Equatable, Sendable {
    /// Moved (Finder without ⌥, or the Trash): the item leaves the shelf once its file is gone.
    case move
    /// Copied (⌥ held, or another volume): the item stays.
    case copy
    /// Cancelled or refused.
    case none
}

/// What the Shelf tab asks of its module. Every closure runs on the main actor.
public struct ShelfTabActions {
    /// A click on a row or ↑↓: the new selection.
    public var select: @MainActor (UUID?) -> Void
    /// Space on the selection, or the `QUICK LOOK` chip.
    public var quickLook: @MainActor (UUID) -> Void
    /// The `REVEAL` chip: Finder at the file.
    public var reveal: @MainActor (UUID) -> Void
    /// The `PIN` / `UNPIN` chip.
    public var togglePin: @MainActor (UUID) -> Void
    /// A drag from the row's grip starts: the file to drag, with its access held until ``endDrag``; nil
    /// refuses the drag (the file is gone).
    public var beginDrag: @MainActor (UUID) -> URL?
    /// The drag ended with this operation.
    public var endDrag: @MainActor (UUID, ShelfDragOperation) -> Void
    /// The `Send to` zone entries for an item (Story 9.10): enabled zones that take it, Ask AI's alternate
    /// folder included. Quick Look, Reveal and Pin are added by the row.
    public var sendToEntries: @MainActor (UUID) -> [ShelfMenuEntry]
    /// A zone entry chosen: run the zone with the item, these modifiers held.
    public var send: @MainActor (UUID, String, EventModifiers) -> Void
    /// `⌘V` on the tab: stash the clipboard (the host reads it).
    public var paste: @MainActor () -> Void

    public init(
        select: @escaping @MainActor (UUID?) -> Void = { _ in },
        quickLook: @escaping @MainActor (UUID) -> Void = { _ in },
        reveal: @escaping @MainActor (UUID) -> Void = { _ in },
        togglePin: @escaping @MainActor (UUID) -> Void = { _ in },
        beginDrag: @escaping @MainActor (UUID) -> URL? = { _ in nil },
        endDrag: @escaping @MainActor (UUID, ShelfDragOperation) -> Void = { _, _ in },
        sendToEntries: @escaping @MainActor (UUID) -> [ShelfMenuEntry] = { _ in [] },
        send: @escaping @MainActor (UUID, String, EventModifiers) -> Void = { _, _, _ in },
        paste: @escaping @MainActor () -> Void = {}
    ) {
        self.select = select
        self.quickLook = quickLook
        self.reveal = reveal
        self.togglePin = togglePin
        self.beginDrag = beginDrag
        self.endDrag = endDrag
        self.sendToEntries = sendToEntries
        self.send = send
        self.paste = paste
    }
}

/// Keyboard selection over the rows (↑↓, FR91).
public enum ShelfSelection {
    /// One step up (`-1`) or down (`+1`), clamped; from no selection, ↓ picks the first row and ↑ the last.
    public static func move(_ selection: UUID?, by step: Int, in ids: [UUID]) -> UUID? {
        guard !ids.isEmpty else { return nil }
        guard let selection, let index = ids.firstIndex(of: selection) else {
            return step >= 0 ? ids.first : ids.last
        }
        return ids[min(max(index + step, 0), ids.count - 1)]
    }

    /// The selection if its row still exists.
    public static func valid(_ selection: UUID?, in ids: [UUID]) -> UUID? {
        guard let selection, ids.contains(selection) else { return nil }
        return selection
    }
}
