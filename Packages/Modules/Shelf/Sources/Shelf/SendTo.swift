import Foundation
import ModuleKit
import SwiftUI
import UniformTypeIdentifiers
import VigieUI

/// The Shelf tab's `SEND TO` card (Story 9.7, UX-DR84): the Ask AI zone of `agents.sessions` (read through
/// `context.dropZones`, never by importing that module, AD-1) and the Shelf's own mini zones. A stash item
/// dropped on a zone runs that zone's handler through the host with `source = .stashItem`, inside the item's
/// security scope; files dropped from Finder go with `source = .shelfTab`.
extension ShelfModule {
    /// The card, bound to the live module and directory (read in the card's `body`).
    var sendToCard: AnyView {
        AnyView(
            SendToCardView(
                model: { [weak self] in self?.sendToCardModel() ?? Self.emptySendToCard },
                actions: SendToCardActions(
                    internalDragTypes: { [weak self] in self?.internalDragTypes },
                    drop: { [weak self] zoneID, drop, modifiers in
                        guard let self else { return }
                        Task { await self.sendToDrop(zoneID: zoneID, drop: drop, modifiers: modifiers) }
                    })))
    }

    nonisolated static var emptySendToCard: SendToCardModel {
        SendToCardModel(meta: ShelfText.string("shelf.sendTo.meta.defaults"), askZone: nil, miniZones: [])
    }

    /// The card from the directory's zones (default: `context.dropZones`): the first enabled `.target` zone
    /// of another module (Ask AI; none while `agents.sessions` is off), then AirDrop and Image to Text when on.
    func sendToCardModel(zones: [DropZoneSummary]? = nil, calendar: Calendar = .current) -> SendToCardModel {
        let zones = zones ?? zoneDirectory?.zones() ?? []
        let ask = zones.first { $0.isEnabled && $0.style == .target && $0.moduleID != manifest.id }
        var minis: [SendToTarget] = []
        if let display = airDropMiniZone {
            minis.append(SendToTarget(zone: display, summary: DropZoneSummary(airDropZone, moduleID: manifest.id)))
        }
        if let display = imageToTextMiniZone {
            minis.append(
                SendToTarget(zone: display, summary: DropZoneSummary(imageToTextZone, moduleID: manifest.id)))
        }
        return SendToCardModel(
            meta: sendToMeta(calendar: calendar), askZone: ask.map(SendToTarget.init(summary:)), miniZones: minis)
    }

    /// `DEFAULTS`, or `LAST · 3 LINES · 14:48` after an Image to Text copy (DESIGN "Copied readout").
    func sendToMeta(calendar: Calendar = .current) -> String {
        guard let last = lastImageToText else { return ShelfText.string("shelf.sendTo.meta.defaults") }
        return ShelfText.format(
            "shelf.sendTo.meta.last", last.lines, ShelfTabFormat.addedTime(last.at, calendar: calendar))
    }

    /// The type of the stash item being dragged from the rows; nil when no internal drag is in flight.
    var internalDragTypes: [UTType]? {
        guard let id = draggingItemID, let item = items.first(where: { $0.id == id }) else { return nil }
        return [Self.contentType(of: item)]
    }

    nonisolated static func contentType(of item: ShelfItem) -> UTType {
        UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data
    }

    /// A release on a card zone. A stash item: its file opened (scope held) for the length of the handler.
    @discardableResult
    func sendToDrop(zoneID: String, drop: SendToDrop, modifiers: EventModifiers) async -> DropResult {
        guard let zoneDirectory else { return .rejected }
        switch drop {
        case .stashItem:
            guard let id = draggingItemID else { return .rejected }
            return await send(id, to: zoneID, modifiers: modifiers)
        case .files(let urls):
            return await zoneDirectory.perform(
                zoneID: zoneID, payload: DropPayload(urls: urls, modifiers: modifiers, source: .shelfTab))
        }
    }

    /// Runs `zoneID` with the item's file and `source = .stashItem`, its access held until the handler returns.
    @discardableResult
    func send(_ id: UUID, to zoneID: String, modifiers: EventModifiers) async -> DropResult {
        guard let zoneDirectory else { return .rejected }
        guard let access = openFile(id) else {
            notice = ShelfText.string("shelf.notice.missing")
            return .rejected
        }
        defer { access.close() }
        return await zoneDirectory.perform(
            zoneID: zoneID, payload: DropPayload(urls: [access.url], modifiers: modifiers, source: .stashItem))
    }
}
