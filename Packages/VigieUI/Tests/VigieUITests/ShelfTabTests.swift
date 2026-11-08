import AppKit
import Foundation
import SwiftUI
import Testing

@testable import VigieUI

@MainActor @Suite struct ShelfTabTests {
    static let ids = (0..<5).map { _ in UUID() }

    /// The mockup's main state: two plain rows, a copy, an expiring saved image and a pinned (hovered) row.
    static let rows: [ShelfRowModel] = [
        ShelfRowModel(
            id: ids[0], name: "build-log-2026-11-04.txt", kind: "TXT", sizeMode: "184 KB · REF", sourceApp: "Safari",
            addedTime: "14:31", addedDay: "TODAY", expiry: .timeLeft("6D LEFT", fraction: 1),
            accessibilityLabel: "build-log-2026-11-04.txt"),
        ShelfRowModel(
            id: ids[1], name: "schema.sql", kind: "SQL", sizeMode: "8 KB · REF", sourceApp: nil, addedTime: "11:40",
            addedDay: "TUE 03", expiry: .timeLeft("5D LEFT", fraction: 0.84), accessibilityLabel: "schema.sql"),
        ShelfRowModel(
            id: ids[2], name: "invoice-oct.pdf", kind: "PDF", sizeMode: "92 KB · COPY", sourceApp: nil,
            addedTime: "09:12", addedDay: "FRI 30 OCT", expiry: .timeLeft("1D 18H LEFT", fraction: 0.25),
            accessibilityLabel: "invoice-oct.pdf"),
        ShelfRowModel(
            id: ids[3], name: "mock-usage-tab.png", kind: "PNG", sizeMode: "1.2 MB · SAVED", sourceApp: nil,
            addedTime: "19:50", addedDay: "WED 28 OCT", expiry: .expiring("EXPIRES IN 5H", fraction: 0.03),
            accessibilityLabel: "mock-usage-tab.png"),
        ShelfRowModel(
            id: ids[4], name: "deploy-checklist.md", kind: "MD", sizeMode: "3 KB · REF", sourceApp: nil,
            addedTime: "10:05", addedDay: "MON 26 OCT", expiry: .pinned, accessibilityLabel: "deploy-checklist.md"),
    ]

    static func snapshot(_ rows: [ShelfRowModel], selected: UUID? = nil) -> ShelfTabSnapshot {
        ShelfTabSnapshot(
            title: "STASH · \(rows.count)", expiringMeta: rows.isEmpty ? nil : "1 EXPIRING", ttlMeta: "TTL 7D",
            rows: rows, selectedID: selected, emptySentence: L10n.resource("shelf.empty.label"))
    }

    @Test func selectionMovesAndClamps() {
        let ids = Self.ids
        #expect(ShelfSelection.move(nil, by: 1, in: ids) == ids[0])
        #expect(ShelfSelection.move(nil, by: -1, in: ids) == ids[4])
        #expect(ShelfSelection.move(ids[0], by: 1, in: ids) == ids[1])
        #expect(ShelfSelection.move(ids[0], by: -1, in: ids) == ids[0])
        #expect(ShelfSelection.move(ids[4], by: 1, in: ids) == ids[4])
        #expect(ShelfSelection.move(ids[0], by: 1, in: []) == nil)
        #expect(ShelfSelection.valid(UUID(), in: ids) == nil)
        #expect(ShelfSelection.valid(ids[2], in: ids) == ids[2])
    }

    @Test func dragOperationsMapToMoveOrCopy() {
        #expect(ShelfDragSourceView.operation([]) == .none)
        #expect(ShelfDragSourceView.operation(.move) == .move)
        #expect(ShelfDragSourceView.operation(.delete) == .move)
        #expect(ShelfDragSourceView.operation(.generic) == .move)
        #expect(ShelfDragSourceView.operation(.copy) == .copy)
        #expect(ShelfDragSourceView.operation(.link) == .copy)
        #expect(ShelfDragSourceView.operationMask.contains([.move, .copy]))
    }

    @Test func staticCopyIsInTheCatalog() {
        #expect(L10n.string("shelf.empty.label") == "STASH EMPTY")
        #expect(L10n.string("shelf.footer.quickLook") == "␣ QUICK LOOK")
        #expect(L10n.string("shelf.tip.drag") == "DRAG · MOVE  ⌥ DRAG · COPY")
        #expect(
            ["shelf.action.quickLook", "shelf.action.reveal", "shelf.action.pin"].map(L10n.string)
                == ["QUICK LOOK", "REVEAL", "PIN"])
        #expect(L10n.string("shelf.row.pinned") == "PINNED")
    }

    /// Renders the main state (pinned row hovered, first row selected), a three-row state and the empty
    /// stash at 720 × 350 in A dark, A light and C dark. Set `VIGIE_RENDER_DIR` to keep the PNGs.
    @Test(arguments: [
        (Look.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID),
        (.dark, "twin-metal-tactical"),
    ])
    func rendersTheTab(look: Look, variant: String) throws {
        let theme = SessionsTabTests.theme(look, variant: variant)
        let name = "shelf-\(variant)-\(look.rawValue)"
        let full = Self.snapshot(Self.rows, selected: Self.ids[0])
        var main = ShelfTabView(hovered: Self.ids[4], snapshot: { full }, actions: ShelfTabActions())
        main.interactive = false
        #expect(SessionGlyphTests.inkedPixels(try SessionsTabTests.render(main, theme: theme, name: name)) > 4000)

        let three = Self.snapshot([Self.rows[0], Self.rows[3], Self.rows[4]])
        var short = ShelfTabView(hovered: Self.ids[0], snapshot: { three }, actions: ShelfTabActions())
        short.interactive = false
        _ = try SessionsTabTests.render(short, theme: theme, name: "\(name)-three")

        let emptySnapshot = ShelfTabSnapshot(
            title: "STASH · 0", ttlMeta: "TTL 7D", rows: [],
            emptySentence: LocalizedStringResource(
                "Drag a file, text or image onto the notch, or press ⌘V, to keep it here for 7 days."))
        var empty = ShelfTabView(snapshot: { emptySnapshot }, actions: ShelfTabActions())
        empty.interactive = false
        #expect(
            SessionGlyphTests.inkedPixels(try SessionsTabTests.render(empty, theme: theme, name: "\(name)-empty")) > 500
        )
    }
}
