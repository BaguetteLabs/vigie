import AppKit
import SwiftUI
import Testing

@testable import VigieUI

@MainActor @Suite struct ShelfMenuTests {
    static let zones = [
        ShelfMenuEntry(id: "ask", title: "Ask AI", action: .send(zoneID: "ask", modifiers: [])),
        ShelfMenuEntry(
            id: "ask.modified", title: "Ask AI in alternate folder", action: .send(zoneID: "ask", modifiers: .option)),
        ShelfMenuEntry(id: "airdrop", title: "AirDrop", action: .send(zoneID: "airdrop", modifiers: [])),
    ]

    @Test func entriesAreTheZonesThenQuickLookRevealPin() {
        #expect(
            ShelfMenuEntry.entries(sendTo: Self.zones, isPinned: false).map(\.title)
                == ["Ask AI", "Ask AI in alternate folder", "AirDrop", "Quick Look", "Reveal", "Pin"])
        #expect(ShelfMenuEntry.entries(sendTo: [], isPinned: true).map(\.title) == ["Quick Look", "Reveal", "Unpin"])
    }

    @Test func performDispatchesToTheTabActions() {
        let item = UUID()
        var log: [String] = []
        let actions = ShelfTabActions(
            quickLook: { _ in log.append("ql") }, reveal: { _ in log.append("reveal") },
            togglePin: { _ in log.append("pin") },
            send: { id, zone, modifiers in
                #expect(id == item)
                log.append("\(zone)\(modifiers.contains(.option) ? "+opt" : "")")
            })
        for entry in ShelfMenuEntry.entries(sendTo: Self.zones, isPinned: false) {
            entry.perform(on: item, actions)
        }
        #expect(log == ["ask", "ask+opt", "airdrop", "ql", "reveal", "pin"])
    }

    @Test func theNSMenuSeparatesZonesFromItemActionsAndRunsEntries() throws {
        var ran: [String] = []
        let menu = ShelfMenuAnchorView.menu(ShelfMenuEntry.entries(sendTo: Self.zones, isPinned: false)) {
            ran.append($0.id)
        }
        #expect(
            menu.items.map { $0.isSeparatorItem ? "—" : $0.title } == [
                "Ask AI", "Ask AI in alternate folder", "AirDrop", "—", "Quick Look", "Reveal", "Pin",
            ])
        let alt = try #require(menu.items.first { $0.title == "Ask AI in alternate folder" })
        _ = (alt.target as? NSObject)?.perform(alt.action)
        #expect(ran == ["ask.modified"])
        #expect(L10n.string("shelf.menu.title") == "Send to")
    }
}
