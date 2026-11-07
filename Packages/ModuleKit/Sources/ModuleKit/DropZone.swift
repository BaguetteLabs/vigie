import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A drop target a module declares on `NotchModule.dropZones` (AD-19, SPEC §4.6). The host lays them out.
public struct DropZone: Identifiable, Sendable {
    public let id: String
    public let label: LocalizedStringResource
    /// Glyph name resolved by the theme.
    public let glyph: String
    /// Theme accent token name (AD-14).
    public let accentToken: String
    public let role: DropRole
    public let cell: DropCell
    public let order: Int
    public let accepts: [UTType]
    public let handler: @Sendable (DropPayload) async -> DropResult

    public init(
        id: String,
        label: LocalizedStringResource,
        glyph: String,
        accentToken: String,
        role: DropRole,
        cell: DropCell,
        order: Int,
        accepts: [UTType],
        handler: @escaping @Sendable (DropPayload) async -> DropResult
    ) {
        self.id = id
        self.label = label
        self.glyph = glyph
        self.accentToken = accentToken
        self.role = role
        self.cell = cell
        self.order = order
        self.accepts = accepts
        self.handler = handler
    }
}

/// Exactly one enabled zone is `.primary` (Stash).
public enum DropRole: Hashable, Sendable {
    case primary
    case secondary
}

/// Preferred placement in the host's 4 × 2 drop display grid.
public struct DropCell: Hashable, Sendable {
    public struct Span: Hashable, Sendable {
        public let columns: Int
        public let rows: Int

        public init(columns: Int, rows: Int) {
            self.columns = columns
            self.rows = rows
        }
    }

    public let preferredColumn: Int
    public let preferredRow: Int
    public let span: Span

    public init(preferredColumn: Int, preferredRow: Int, span: Span) {
        self.preferredColumn = preferredColumn
        self.preferredRow = preferredRow
        self.span = span
    }
}

/// What reached a drop zone handler.
public struct DropPayload: Sendable {
    public let urls: [URL]
    public let modifiers: EventModifiers
    public let source: DropSource

    public init(urls: [URL], modifiers: EventModifiers, source: DropSource) {
        self.urls = urls
        self.modifiers = modifiers
        self.source = source
    }
}

public enum DropSource: Hashable, Sendable {
    case dropDisplay
    case shelfTab
    case homeWidget
    case stashItem
    case paste
    case service
}

/// A handler's outcome, reported back to the host for feedback.
public enum DropResult: Sendable {
    case accepted
    /// The handler did not take the payload (wrong type, setting off, ...).
    case rejected
    case failed(LocalizedStringResource)
}
