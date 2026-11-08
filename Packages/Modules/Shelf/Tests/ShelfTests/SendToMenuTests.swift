import Foundation
import ModuleKit
import SwiftUI
import Testing
import VigieUI

@testable import Shelf

@MainActor @Suite struct SendToMenuTests {
    static func zones(_ h: ShelfHarness, ask: Bool = true) -> [DropZoneSummary] {
        let shelf = h.module.dropZones.map { DropZoneSummary($0, moduleID: "shelf") }
        let askZone = DropZone(
            id: "agents.sessions.ask", label: "ASK AI", glyph: "plus", accentToken: "iris-2", role: .secondary,
            cell: DropCell(preferredColumn: 3, preferredRow: 1, span: .init(columns: 1, rows: 2)), order: 10,
            accepts: [.item], handler: { _ in .accepted },
            modifierHint: DropModifierHint(
                modifiers: .option, idle: "⌥ ALT FOLDER", active: "ALT FOLDER", menuTitle: "Ask AI in alternate folder"),
            style: .target, menuTitle: "Ask AI")
        return ((ask ? [DropZoneSummary(askZone, moduleID: "agents.sessions")] : []) + shelf).sorted {
            $0.order < $1.order
        }
    }

    static func modifiers(_ entry: ShelfMenuEntry) -> EventModifiers? {
        if case .send(_, let modifiers) = entry.action { modifiers } else { nil }
    }

    @Test func entriesFollowTheEnabledZonesThatTakeTheItem() async throws {
        let h = ShelfHarness(settings: ["image_to_text": true])
        try await h.start()
        await h.stash(makeFile("shot.png"))
        await h.stash(makeFile("notes.txt"))
        let txt = try #require(h.module.items.first { $0.name == "notes.txt" }?.id)
        let png = try #require(h.module.items.first { $0.name == "shot.png" }?.id)
        let pngEntries = h.module.sendToEntries(for: png, zones: Self.zones(h))
        #expect(pngEntries.map(\.title) == ["Ask AI", "Ask AI in alternate folder", "AirDrop", "Image to Text"])
        #expect(pngEntries.map(Self.modifiers) == [[], .option, [], []])
        #expect(
            h.module.sendToEntries(for: txt, zones: Self.zones(h)).map(\.title)
                == ["Ask AI", "Ask AI in alternate folder", "AirDrop"], "Image to Text does not take text files")
        #expect(
            h.module.sendToEntries(for: png, zones: Self.zones(h, ask: false)).map(\.title) == [
                "AirDrop", "Image to Text",
            ])
        let full = ShelfMenuEntry.entries(sendTo: pngEntries, isPinned: false).map(\.title)
        #expect(full.suffix(3) == ["Quick Look", "Reveal", "Pin"])
    }

    @Test func offZonesAreNotListed() async throws {
        let h = ShelfHarness(settings: ["airdrop": false])
        try await h.start()
        await h.stash(makeFile("shot.png"))
        let id = try #require(h.module.items.first?.id)
        #expect(
            h.module.sendToEntries(for: id, zones: Self.zones(h)).map(\.id) == [
                "agents.sessions.ask", "agents.sessions.ask.modified",
            ])
    }

    @Test func choosingTheAlternateEntryRunsTheZoneWithOptionAndStashItemSource() async throws {
        let h = ShelfHarness()
        try await h.start()
        let file = makeFile("notes.txt")
        await h.stash(file)
        let id = try #require(h.module.items.first?.id)
        let entry = try #require(
            h.module.sendToEntries(for: id, zones: Self.zones(h)).first { $0.id.hasSuffix(".modified") })
        guard case .send(let zoneID, let modifiers) = entry.action else {
            Issue.record("not a zone entry")
            return
        }
        let result = await h.module.send(id, to: zoneID, modifiers: modifiers)
        #expect(result.isAccepted)
        let call = try #require(h.context.fakeDropZones.performed.first)
        #expect(call.zoneID == "agents.sessions.ask")
        #expect(call.payload.modifiers == .option)
        #expect(call.payload.source == .stashItem)
        #expect(call.payload.urls.map(\.lastPathComponent) == ["notes.txt"])
        #expect(h.scope.starts == h.scope.stops, "scope released after the handler")
    }

    @Test func pasteGoesToTheStashThroughTheHostAndEmptyDoesNothing() async throws {
        let h = ShelfHarness()
        try await h.start()
        #expect(await h.module.paste() == nil)
        #expect(h.context.fakeDropZones.pastes == ["shelf.stash"])
        #expect(h.context.fakeDropZones.performed.isEmpty, "an empty clipboard changes nothing")
        h.context.fakeDropZones.clipboard = DropPayload(urls: [], modifiers: [], source: .paste, text: "hello")
        _ = await h.module.paste()
        let call = try #require(h.context.fakeDropZones.performed.first)
        #expect(call.zoneID == "shelf.stash" && call.payload.source == .paste)
        await h.module.stop()
        #expect(await h.module.paste() == nil, "Shelf off: no paste")
    }
}
