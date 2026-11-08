import Foundation
import ModuleKit
import SwiftUI
import VigieUI

/// Non-drag paths to the drop zones (Story 9.10, UX-DR102): the row's `Send to` menu and VoiceOver actions,
/// and `⌘V` on the tab.
extension ShelfModule {
    /// The zone entries of an item's `Send to` menu: every enabled zone of the running modules except the
    /// Stash itself that takes the item's type, in zone order; a zone with a modifier entry (Ask AI) adds it
    /// right after ("Ask AI in alternate folder", ⌥ in `modifiers`).
    func sendToEntries(for id: UUID, zones: [DropZoneSummary]? = nil) -> [ShelfMenuEntry] {
        guard let item = items.first(where: { $0.id == id }) else { return [] }
        let zones = zones ?? zoneDirectory?.zones() ?? []
        let type = Self.contentType(of: item)
        var entries: [ShelfMenuEntry] = []
        for zone in zones where zone.isEnabled && zone.role != .primary {
            guard zone.accepts(contentTypes: [type], loose: nil) else { continue }
            entries.append(
                ShelfMenuEntry(
                    id: zone.id, title: String(localized: zone.menuTitle ?? zone.label),
                    action: .send(zoneID: zone.id, modifiers: [])))
            if let hint = zone.modifierHint, let title = hint.menuTitle {
                entries.append(
                    ShelfMenuEntry(
                        id: "\(zone.id).modified", title: String(localized: title),
                        action: .send(zoneID: zone.id, modifiers: hint.modifiers)))
            }
        }
        return entries
    }

    /// `⌘V`: the host reads the clipboard and runs the Stash zone with `source = .paste`; an empty or
    /// unsupported clipboard changes nothing. The module never reads `NSPasteboard` (AD-19).
    @discardableResult
    func paste() async -> DropResult? {
        guard isRunning, let zoneDirectory else { return nil }
        let result = await zoneDirectory.performPaste(into: Self.stashZoneID)
        if result == nil { log?.debug("Paste: nothing usable on the clipboard") }
        return result
    }
}
