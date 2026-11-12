import Foundation
import ModuleKit
import SwiftUI
import UniformTypeIdentifiers
import VigieUI

/// The Home shelf widget (Story 11.3, FR57, FR60, UX-DR33, UX-DR97): the stash list with the Stash and Ask AI
/// zones. Ask AI belongs to `agents.sessions` and is read through `context.dropZones` (AD-1); AirDrop and
/// Image to Text are not shown on Home. Every drop on a widget zone runs that zone's handler through the host
/// with `source = .homeWidget` (AD-19): files from Finder, and a stash item dragged from the widget's list
/// (inside its security scope). The host leaves the card out while the Shelf is off (it lists running modules
/// only).
extension ShelfModule {
    /// The card, bound to the live module: items, expiry tags and the warning re-render on every change and
    /// on each expiry sweep.
    public func homeCard() -> AnyView? {
        AnyView(
            ShelfHomeCardView(
                model: { [weak self] in self?.homeCardModel() ?? Self.emptyHomeCard },
                actions: homeCardActions))
    }

    var homeCardActions: ShelfHomeCardActions {
        ShelfHomeCardActions(
            internalDragTypes: { [weak self] in self?.internalDragTypes },
            drop: { [weak self] zoneID, drop, modifiers in
                guard let self else { return }
                Task { await self.homeWidgetDrop(zoneID: zoneID, drop: drop, modifiers: modifiers) }
            },
            beginDrag: { [weak self] id in self?.beginDrag(id) },
            endDrag: { [weak self] id, operation in
                guard let self else { return }
                Task { await self.endDrag(id, operation) }
            })
    }

    nonisolated static var emptyHomeCard: ShelfHomeCardModel {
        ShelfHomeCardModel(
            title: ShelfText.string("shelf.home.title"), meta: ShelfHomeFormat.meta(count: 0), items: [],
            stashZone: nil, askZone: nil)
    }

    /// The widget at `now` (default: the last sweep) from the directory's zones (default: `context.dropZones`).
    func homeCardModel(
        zones: [DropZoneSummary]? = nil, now date: Date? = nil, calendar: Calendar = .current
    ) -> ShelfHomeCardModel {
        let date = date ?? lastSweep ?? now()
        let zones = zones ?? zoneDirectory?.zones() ?? []
        let ask = zones.first { $0.isEnabled && $0.style == .target && $0.moduleID != manifest.id }
        let stash = stashZone
        let ordered = ShelfHomeFormat.ordered(items, now: date)
        let homeItems = ordered.map { item in
            ShelfHomeItem(
                row: ShelfTabFormat.row(item, ttl: ttl, now: date, calendar: calendar),
                tag: ShelfExpiry.warningHours(item, now: date).map { ShelfText.format("shelf.home.tag", $0) })
        }
        return ShelfHomeCardModel(
            title: ShelfText.string("shelf.home.title"),
            meta: ShelfHomeFormat.meta(count: items.count),
            items: homeItems,
            warning: ShelfHomeFormat.warning(items, now: date),
            stashZone: stash.isEnabled ? SendToTarget(summary: DropZoneSummary(stash, moduleID: manifest.id)) : nil,
            askZone: ask.map(SendToTarget.init(summary:)))
    }

    /// A release on a widget zone, with `source = .homeWidget`. A stash item: its file opened (scope held) for
    /// the length of the handler; never back onto the Stash.
    @discardableResult
    func homeWidgetDrop(zoneID: String, drop: SendToDrop, modifiers: EventModifiers) async -> DropResult {
        guard let zoneDirectory else { return .rejected }
        switch drop {
        case .stashItem:
            guard zoneID != Self.stashZoneID, let id = draggingItemID else { return .rejected }
            return await send(id, to: zoneID, modifiers: modifiers, source: .homeWidget)
        case .files(let urls):
            return await zoneDirectory.perform(
                zoneID: zoneID, payload: DropPayload(urls: urls, modifiers: modifiers, source: .homeWidget))
        }
    }
}

/// The widget's texts and order, from the Shelf catalog.
enum ShelfHomeFormat {
    /// `2 items`.
    static func meta(count: Int) -> String { ShelfText.format("shelf.home.meta", count) }

    /// Items in their last 24 h first, soonest first; then the others in their order (newest first).
    static func ordered(_ items: [ShelfItem], now: Date) -> [ShelfItem] {
        let expiring = items.filter { ShelfExpiry.warningHours($0, now: now) != nil }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        let rest = items.filter { ShelfExpiry.warningHours($0, now: now) == nil }
        return expiring + rest
    }

    /// `1 EXPIRES IN 5H` (`2 EXPIRE IN 3H`: the count, then the soonest item's hours); nil when no item is in
    /// its last 24 h.
    static func warning(_ items: [ShelfItem], now: Date) -> String? {
        let hours = items.compactMap { ShelfExpiry.warningHours($0, now: now) }
        guard let soonest = hours.min() else { return nil }
        return ShelfText.format("shelf.home.warning", hours.count, soonest)
    }
}
