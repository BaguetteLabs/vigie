import ModuleKit
import SwiftUI
import VigieUI

/// What one running module offers the closed notch at arbitration time.
public struct ArbiterModuleSnapshot: Sendable {
    public let moduleID: ModuleID
    public let state: ModuleState
    public let items: [LeftWingItem]

    public init(moduleID: ModuleID, state: ModuleState, items: [LeftWingItem]) {
        self.moduleID = moduleID
        self.state = state
        self.items = items
    }
}

/// One item in a side's lane, with the state it is ranked by.
public struct LaneItem: Sendable {
    public let moduleID: ModuleID
    public let item: LeftWingItem
    /// `item.state ?? module state`.
    public let state: ModuleState

    /// Unique across the lane: `<module id>/<item id>`.
    public var id: String { "\(moduleID.rawValue)/\(item.id)" }
}

/// A shown position in a side's lane.
public enum LaneEntry: Sendable {
    case item(LaneItem)
    case transient(TransientReadout)

    public var id: String {
        switch self {
        case .item(let item): item.id
        case .transient: "transient"
        }
    }
}

/// What a side shows: its entries in order, then `+X`.
public struct SideLayout: Sendable {
    public var shown: [LaneEntry]
    public var overflowCount: Int

    public init(shown: [LaneEntry] = [], overflowCount: Int = 0) {
        self.shown = shown
        self.overflowCount = overflowCount
    }

    public static let empty = SideLayout()
    public var isEmpty: Bool { shown.isEmpty && overflowCount == 0 }
}

/// Closed-notch arbitration (SPEC §5.1, FR9, FR10). Pure value logic, in two phases:
///
/// 1. **Order** (``leadingLane(_:)``, ``trailingLane(_:)``): the full ranked lane of a side. Leading: items of
///    every module with state ≠ hidden, except `agents.sessions`, sorted by effective state (descending),
///    then `priority` (ascending), then `order`, then module id and item id for determinism. Trailing: only
///    `agents.sessions` (its items, same sort) when its state ≠ hidden.
/// 2. **Pick** (``layout(lane:slots:transient:isRenderable:)``): walks the lane in order and takes the first
///    `slots` items that can render at some size; an item that renders at no size yields its slot to the next
///    one and is not counted in `+X` (it could never be shown). Items that are renderable but past the slots
///    are the `+X` count. Because the walk is in rank order, an item in `alert` is never in `+X` while a
///    lower-state item is shown.
///
/// The `isRenderable` predicate is the only impure input: the host passes one that asks the item's
/// `compactView` at each size (``LaneRenderer/canRender(_:)``); tests pass plain closures.
public enum ClosedNotchArbiter {
    /// The only module allowed on the trailing (right) side (SPEC §5).
    public static let sessionsModuleID: ModuleID = "agents.sessions"
    /// `closed.slots` bounds and default (UX-DR73).
    public static let slotRange = 1...4
    public static let defaultSlots = 3

    public static func clampSlots(_ slots: Int) -> Int {
        min(max(slots, slotRange.lowerBound), slotRange.upperBound)
    }

    /// The ranked left-wing lane.
    public static func leadingLane(_ snapshots: [ArbiterModuleSnapshot]) -> [LaneItem] {
        rank(snapshots.filter { $0.moduleID != sessionsModuleID })
    }

    /// The ranked right-wing lane: `agents.sessions` only.
    public static func trailingLane(_ snapshots: [ArbiterModuleSnapshot]) -> [LaneItem] {
        rank(snapshots.filter { $0.moduleID == sessionsModuleID })
    }

    /// Picks what a side shows from its ranked lane.
    ///
    /// With a `transient` readout, it sits after the first shown item and takes one item slot, so the last
    /// visible item moves into `+X` meanwhile. The first item always stays: with `slots == 1` the side shows
    /// that item and the readout. With an empty lane the readout shows alone.
    public static func layout(
        lane: [LaneItem],
        slots: Int,
        transient: TransientReadout? = nil,
        isRenderable: (LeftWingItem) -> Bool = { _ in true }
    ) -> SideLayout {
        let slots = clampSlots(slots)
        let itemSlots = transient == nil ? slots : max(slots - 1, 1)
        var shown: [LaneItem] = []
        var overflow = 0
        for candidate in lane where isRenderable(candidate.item) {
            if shown.count < itemSlots {
                shown.append(candidate)
            } else {
                overflow += 1
            }
        }
        var entries = shown.map(LaneEntry.item)
        if let transient {
            entries.insert(.transient(transient), at: min(1, entries.count))
        }
        return SideLayout(shown: entries, overflowCount: overflow)
    }

    /// Both phases for the left wing.
    public static func leading(
        _ snapshots: [ArbiterModuleSnapshot],
        slots: Int,
        transient: TransientReadout? = nil,
        isRenderable: (LeftWingItem) -> Bool = { _ in true }
    ) -> SideLayout {
        layout(lane: leadingLane(snapshots), slots: slots, transient: transient, isRenderable: isRenderable)
    }

    /// Both phases for the right wing (never carries a transient readout).
    public static func trailing(
        _ snapshots: [ArbiterModuleSnapshot],
        slots: Int,
        isRenderable: (LeftWingItem) -> Bool = { _ in true }
    ) -> SideLayout {
        layout(lane: trailingLane(snapshots), slots: slots, isRenderable: isRenderable)
    }

    private static func rank(_ snapshots: [ArbiterModuleSnapshot]) -> [LaneItem] {
        snapshots
            .filter { $0.state != .hidden }
            .flatMap { snapshot in
                snapshot.items.map {
                    LaneItem(moduleID: snapshot.moduleID, item: $0, state: $0.state ?? snapshot.state)
                }
            }
            .filter { $0.state != .hidden }
            .sorted(by: precedes)
    }

    static func precedes(_ lhs: LaneItem, _ rhs: LaneItem) -> Bool {
        if lhs.state != rhs.state { return lhs.state > rhs.state }
        if lhs.item.priority != rhs.item.priority { return lhs.item.priority < rhs.item.priority }
        if lhs.item.order != rhs.item.order { return lhs.item.order < rhs.item.order }
        if lhs.moduleID != rhs.moduleID { return lhs.moduleID < rhs.moduleID }
        return lhs.item.id < rhs.item.id
    }
}

/// Turns a shown lane item into a view (SPEC §5.1 size fallback).
///
/// Size rule: an entry alone on its side starts at `.wide` (the single-provider readout layout, DESIGN
/// "Closed, left wing"); with two or more entries each slot is a fraction of a ≤ `closed.max_side_width`
/// wing, too narrow for a wide readout, so entries start at `.short`. From the starting size the renderer
/// falls back to smaller sizes; if none renders it tries the larger ones, so an item the arbiter kept as
/// renderable never comes out empty.
@MainActor
public enum LaneRenderer {
    /// The sizes to try, in order, for an entry on a side showing `entryCount` entries.
    public static func sizes(entryCount: Int) -> [CompactSize] {
        entryCount <= 1 ? [.wide, .short, .icon] : [.short, .icon, .wide]
    }

    /// Whether the item renders at any size.
    public static func canRender(_ item: LeftWingItem) -> Bool {
        CompactSize.allCases.contains { item.compactView($0) != nil }
    }

    /// The item's view at the first size in ``sizes(entryCount:)`` that renders.
    public static func view(for item: LeftWingItem, entryCount: Int) -> AnyView? {
        for size in sizes(entryCount: entryCount) {
            if let view = item.compactView(size) { return view }
        }
        return nil
    }

    /// The lane entries for ``WingLane``.
    public static func entries(_ layout: SideLayout) -> [WingLane.Entry] {
        let count = layout.shown.count
        return layout.shown.compactMap { entry in
            switch entry {
            case .item(let lane):
                view(for: lane.item, entryCount: count).map { WingLane.Entry(id: entry.id, view: $0) }
            case .transient(let readout):
                WingLane.Entry(id: entry.id, view: AnyView(TransientReadoutView(readout)))
            }
        }
    }
}
