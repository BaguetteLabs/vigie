import Foundation
import Observation

/// One zone as the drop display draws it. The host builds it from a module's `DropZone` (AD-19).
public struct DropDisplayZone: Identifiable, Sendable {
    public enum Style: Hashable, Sendable {
        /// Glyph, label, meta on a faint fill with a hairline.
        case standard
        /// Dashed accent border with the round `+` target (Ask AI).
        case target
    }

    public let id: String
    public let label: LocalizedStringResource
    /// Glyph name: `drop.stash`, `drop.airdrop` and `drop.image-to-text` are drawn by VigieUI; any other name is
    /// an SF Symbol.
    public let glyph: String
    /// Theme accent role for the lit border, tint and release line (A lilac `iris-2`; C always gold).
    public let accent: ColorRole
    public let style: Style
    /// The primary zone (Stash): larger glyph and label.
    public let isPrimary: Bool
    public let meta: LocalizedStringResource?
    public let releaseLine: LocalizedStringResource?
    public let accessibilityLabel: LocalizedStringResource
    /// The modifier hint: shown while the modifier is up, and lit as `hintActive` while it is held over the zone.
    public let hint: LocalizedStringResource?
    public let hintActive: LocalizedStringResource?

    public init(
        id: String, label: LocalizedStringResource, glyph: String, accent: ColorRole, style: Style,
        isPrimary: Bool, meta: LocalizedStringResource?, releaseLine: LocalizedStringResource?,
        accessibilityLabel: LocalizedStringResource, hint: LocalizedStringResource? = nil,
        hintActive: LocalizedStringResource? = nil
    ) {
        self.id = id
        self.label = label
        self.glyph = glyph
        self.accent = accent
        self.style = style
        self.isPrimary = isPrimary
        self.meta = meta
        self.releaseLine = releaseLine
        self.accessibilityLabel = accessibilityLabel
        self.hint = hint
        self.hintActive = hintActive
    }
}

/// What the drop display shows: the laid-out zones, the dragged item count, the hovered zone and whether it
/// takes the item, and whether the drag modifier (⌥) is held. The Notch Host owns and updates it.
@MainActor @Observable
public final class DropDisplayModel {
    public var layout: DropGridLayout
    public var zones: [DropDisplayZone]
    public var itemCount: Int
    /// The zone under the drag, if any.
    public var hoveredZoneID: String?
    /// True when the hovered zone takes the dragged items; a zone that can't stays unlit.
    public var hoveredAccepts: Bool
    /// True while ⌥ is held during the drag.
    public var optionHeld: Bool
    /// Grown out of the notch (true) or retracted into the band (false).
    public var isRevealed: Bool

    public init(
        layout: DropGridLayout, zones: [DropDisplayZone], itemCount: Int, hoveredZoneID: String? = nil,
        hoveredAccepts: Bool = false, optionHeld: Bool = false, isRevealed: Bool = true
    ) {
        self.layout = layout
        self.zones = zones
        self.itemCount = itemCount
        self.hoveredZoneID = hoveredZoneID
        self.hoveredAccepts = hoveredAccepts
        self.optionHeld = optionHeld
        self.isRevealed = isRevealed
    }

    /// True when `id` is hovered and takes the item: drawn lit with its release line.
    public func isLit(_ id: String) -> Bool { hoveredZoneID == id && hoveredAccepts }

    /// The band's left text: `DROP · 1 ITEM` (count part from the catalog plural).
    public static func bandPrefix() -> String { L10n.string("drop.band.prefix") }
    public static func bandCount(_ count: Int) -> String { L10n.format("drop.band.items", count) }
    /// The band's right text: `ESC · CANCEL`.
    public static func bandCancel() -> String { L10n.string("drop.band.cancel") }
}
