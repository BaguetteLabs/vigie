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
    /// The meta line under the label, read each time the drop display opens (e.g. `KEEP 7 DAYS · 5 ITEMS`).
    public let meta: LocalizedStringResource?
    /// What replaces the meta line while a drag hovers the zone and it accepts the item (`RELEASE TO STASH`).
    public let releaseLine: LocalizedStringResource?
    /// The VoiceOver label naming the zone and its target ("Stash, keep 7 days, 5 items"); nil reads `label`.
    public let accessibilityLabel: LocalizedStringResource?
    /// A modifier the handler reads, with its hint (Ask AI: ⌥ = alternate folder).
    public let modifierHint: DropModifierHint?
    /// How the host draws the zone.
    public let style: DropZoneStyle
    /// False hides the zone (its setting is off); the host reflows the grid. A stopped module's zones are
    /// hidden anyway.
    public let isEnabled: Bool
    /// The loose content (a drag without any file: text, a web link, image data) the zone takes. A zone with an
    /// empty `accepts` takes any loose content too; otherwise only the kinds listed here (Story 9.9: a
    /// files-only zone such as AirDrop or Ask AI stays unlit for a text drag).
    public let looseContent: Set<DropLooseContent>
    /// When set, the host shows this transient readout on the left wing while the handler runs (Image to Text:
    /// `READING…`), until the handler's result replaces it.
    public let progressReadout: LocalizedStringResource?

    public init(
        id: String,
        label: LocalizedStringResource,
        glyph: String,
        accentToken: String,
        role: DropRole,
        cell: DropCell,
        order: Int,
        accepts: [UTType],
        handler: @escaping @Sendable (DropPayload) async -> DropResult,
        meta: LocalizedStringResource? = nil,
        releaseLine: LocalizedStringResource? = nil,
        accessibilityLabel: LocalizedStringResource? = nil,
        modifierHint: DropModifierHint? = nil,
        style: DropZoneStyle = .standard,
        isEnabled: Bool = true,
        looseContent: Set<DropLooseContent> = [],
        progressReadout: LocalizedStringResource? = nil
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
        self.meta = meta
        self.releaseLine = releaseLine
        self.accessibilityLabel = accessibilityLabel
        self.modifierHint = modifierHint
        self.style = style
        self.isEnabled = isEnabled
        self.looseContent = looseContent
        self.progressReadout = progressReadout
    }

    /// True when the zone takes items of these content types: every type conforms to one of `accepts`. An
    /// empty `accepts` takes anything; an empty `contentTypes` (nothing known yet) is taken only then.
    public func accepts(contentTypes: [UTType]) -> Bool {
        if accepts.isEmpty { return true }
        guard !contentTypes.isEmpty else { return false }
        return contentTypes.allSatisfy { type in accepts.contains { type.conforms(to: $0) } }
    }

    /// True when the zone takes this drag: with `loose` nil (files or promises), ``accepts(contentTypes:)``;
    /// with loose content, an empty `accepts` or a kind listed in ``looseContent``.
    public func accepts(contentTypes: [UTType], loose: DropLooseContent?) -> Bool {
        guard let loose else { return accepts(contentTypes: contentTypes) }
        return accepts.isEmpty || looseContent.contains(loose)
    }
}

/// What a drag without any file carries (Story 9.2): the host reads, in this order, a web link, image data,
/// then plain text.
public enum DropLooseContent: Hashable, Sendable, CaseIterable {
    case link
    case image
    case text
}

/// How the host draws a zone in the drop display.
public enum DropZoneStyle: Hashable, Sendable {
    /// Glyph, label and meta on a faint fill with a hairline (Stash, AirDrop, Image to Text).
    case standard
    /// Dashed accent border with the round `+` target (Ask AI).
    case target
}

/// A modifier a zone's handler reads while dropping, and its hint line (`⌥ ALT FOLDER`, lit as `ALT FOLDER`
/// while the modifier is held over the zone).
public struct DropModifierHint: Sendable {
    public let modifiers: EventModifiers
    /// Shown while the modifier is up.
    public let idle: LocalizedStringResource
    /// Shown, lit, while the modifier is held over the zone.
    public let active: LocalizedStringResource

    public init(modifiers: EventModifiers, idle: LocalizedStringResource, active: LocalizedStringResource) {
        self.modifiers = modifiers
        self.idle = idle
        self.active = active
    }
}

/// Exactly one enabled zone is `.primary` (Stash).
public enum DropRole: Hashable, Sendable {
    case primary
    case secondary
}

/// Preferred placement in the host's 4 × 2 drop display grid. Columns and rows count from 1, as in DESIGN
/// (Stash column 1 row 1 span 2 × 2; Ask AI column 3 row 1 span 1 × 2; AirDrop column 4 row 1; Image to Text
/// column 4 row 2).
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
///
/// File drags fill `urls`. A drag without any file (text, a web link, an image from another app) leaves `urls`
/// empty and fills the one of `text`, `url` or `imageData` the pasteboard offered (Story 9.2): the host reads,
/// in that order of preference, a web link (`public.url`), image data (PNG, else TIFF), then plain text.
public struct DropPayload: Sendable {
    public let urls: [URL]
    public let modifiers: EventModifiers
    public let source: DropSource
    /// Dragged plain text, when no file was dragged.
    public let text: String?
    /// A dragged web link (not a file URL), when no file was dragged.
    public let url: URL?
    /// Dragged image data (PNG or TIFF bytes), when no file was dragged.
    public let imageData: Data?
    /// The entries of `urls` the host materialized from file promises into its drops folder (AD-19). A handler
    /// that only reads the files (Image to Text) deletes these afterwards; every other URL is the user's file.
    public let materializedURLs: [URL]

    public init(
        urls: [URL], modifiers: EventModifiers, source: DropSource, text: String? = nil, url: URL? = nil,
        imageData: Data? = nil, materializedURLs: [URL] = []
    ) {
        self.urls = urls
        self.modifiers = modifiers
        self.source = source
        self.text = text
        self.url = url
        self.imageData = imageData
        self.materializedURLs = materializedURLs
    }

    /// True when the payload carries nothing a handler can use.
    public var isEmpty: Bool { urls.isEmpty && text == nil && url == nil && imageData == nil }
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
    /// The handler did not take the payload and asks the host to say so briefly: the closed notch's left wing
    /// shows the text as a transient readout for `motion.confirm-readout` (2 s), e.g. `NOT STASHED` (UX-DR101).
    /// No alert, peek or sound follows.
    case readout(LocalizedStringResource)
    /// A confirmation readout (Image to Text `COPIED · 3 LINES`, `NO TEXT FOUND`; DESIGN "Copied readout"): the
    /// same left-wing slot for `motion.confirm-readout`, held while the pointer is over the notch, optionally
    /// with a draining 1px line, and a VoiceOver announcement. No alert, peek or sound.
    case confirmation(DropReadout)
}

/// The content of ``DropResult/confirmation(_:)``.
public struct DropReadout: Sendable {
    /// The readout text, uppercase (`COPIED · 3 LINES`).
    public let text: LocalizedStringResource
    /// What VoiceOver announces ("Copied 3 lines"); nil announces nothing.
    public let announcement: LocalizedStringResource?
    /// True draws the 1px drain line under the readout (a static full line under Reduce motion).
    public let drains: Bool

    public init(text: LocalizedStringResource, announcement: LocalizedStringResource? = nil, drains: Bool = true) {
        self.text = text
        self.announcement = announcement
        self.drains = drains
    }
}
