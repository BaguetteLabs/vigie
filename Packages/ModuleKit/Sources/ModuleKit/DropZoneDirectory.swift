import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The running modules' drop zones, for a module that shows or invokes zones it does not own (Stories 9.7,
/// 9.10: the Shelf tab's `SEND TO` card shows the Ask AI zone of `agents.sessions`; the stash items dropped on the card
/// run zone handlers). Implemented by VigieCore over the same collection the drop display
/// uses (`NotchModule.dropZones` of the running modules); modules never reference each other (AD-1, AD-19).
///
/// ``zones()`` is read on the main actor; a view that calls it in `body` re-renders when the zones' observed
/// module state changes (zones are computed from `@Observable` modules).
public protocol DropZoneDirectory: Sendable {
    /// Every zone of the running modules, disabled ones included (check ``DropZoneSummary/isEnabled``), first
    /// declaration of an id wins, in `order`.
    @MainActor func zones() -> [DropZoneSummary]

    /// Runs the zone's handler through the host, exactly as a drop on the drop display would: the zone's
    /// progress readout while it runs, then its readout or confirmation on the closed notch. An unknown,
    /// stopped or disabled zone, or an empty payload, answers `.rejected` without calling anything. The caller
    /// keeps any security-scoped access open until this returns (AD-19).
    @MainActor func perform(zoneID: String, payload: DropPayload) async -> DropResult

}

/// A ``DropZone`` as another module sees it: everything but the handler, plus the owning module.
public struct DropZoneSummary: Identifiable, Sendable {
    public let id: String
    public let moduleID: ModuleID
    public let label: LocalizedStringResource
    public let glyph: String
    public let accentToken: String
    public let role: DropRole
    public let order: Int
    public let accepts: [UTType]
    public let looseContent: Set<DropLooseContent>
    public let meta: LocalizedStringResource?
    public let releaseLine: LocalizedStringResource?
    public let accessibilityLabel: LocalizedStringResource?
    public let modifierHint: DropModifierHint?
    public let style: DropZoneStyle
    public let isEnabled: Bool
    public let details: [DropZoneDetail]

    public init(_ zone: DropZone, moduleID: ModuleID) {
        id = zone.id
        self.moduleID = moduleID
        label = zone.label
        glyph = zone.glyph
        accentToken = zone.accentToken
        role = zone.role
        order = zone.order
        accepts = zone.accepts
        looseContent = zone.looseContent
        meta = zone.meta
        releaseLine = zone.releaseLine
        accessibilityLabel = zone.accessibilityLabel
        modifierHint = zone.modifierHint
        style = zone.style
        isEnabled = zone.isEnabled
        details = zone.details
    }

    /// Same rule as ``DropZone/accepts(contentTypes:)``.
    public func accepts(contentTypes: [UTType]) -> Bool {
        DropAcceptance.accepts(accepts, contentTypes: contentTypes)
    }

    /// Same rule as ``DropZone/accepts(contentTypes:loose:)``.
    public func accepts(contentTypes: [UTType], loose: DropLooseContent?) -> Bool {
        DropAcceptance.accepts(accepts, looseContent: looseContent, contentTypes: contentTypes, loose: loose)
    }
}

/// The directory of a context that has none (tests, previews): no zones, nothing runs.
public struct EmptyDropZoneDirectory: DropZoneDirectory {
    public init() {}
    @MainActor public func zones() -> [DropZoneSummary] { [] }
    @MainActor public func perform(zoneID: String, payload: DropPayload) async -> DropResult { .rejected }
}
