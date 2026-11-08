import AppKit
import ModuleKit
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import VigieUI

@MainActor @Suite struct SendToCardTests {
    static func askSummary() -> DropZoneSummary {
        let zone = DropZone(
            id: "agents.sessions.ask", label: "ASK AI", glyph: "plus", accentToken: "iris-2", role: .secondary,
            cell: DropCell(preferredColumn: 3, preferredRow: 1, span: .init(columns: 1, rows: 2)), order: 10,
            accepts: [.item], handler: { _ in .accepted }, releaseLine: "RELEASE TO ASK",
            accessibilityLabel: "Ask AI, Claude Code in the file's folder, Option for alternate folder",
            style: .target,
            details: [
                DropZoneDetail(id: "agent", label: "AGENT", value: "Claude Code"),
                DropZoneDetail(id: "folder", label: "FOLDER", value: "File's folder", emphasis: .dimmedWhile(.option)),
                DropZoneDetail(id: "alt_folder", label: "⌥ FOLDER", value: "~/Code", emphasis: .litWhile(.option)),
            ])
        return DropZoneSummary(zone, moduleID: "agents.sessions")
    }

    static func mini(_ display: DropDisplayZone, accepts: [UTType]) -> SendToTarget {
        let zone = DropZone(
            id: display.id, label: display.label, glyph: display.glyph, accentToken: "iris-2", role: .secondary,
            cell: DropCell(preferredColumn: 4, preferredRow: 1, span: .init(columns: 1, rows: 1)), order: 20,
            accepts: accepts, handler: { _ in .accepted })
        return SendToTarget(zone: display, summary: DropZoneSummary(zone, moduleID: "shelf"))
    }

    static let model = SendToCardModel(
        meta: "LAST · 3 LINES · 14:48", askZone: SendToTarget(summary: askSummary()),
        miniZones: [
            mini(DropMiniZoneTests.airdrop, accepts: [.item]), mini(DropMiniZoneTests.ocr, accepts: [.image, .pdf]),
        ])

    @Test func releaseTargetNamesAgentAndFolderAndFollowsOption() {
        let details = Self.askSummary().details
        #expect(SendToCardModel.releaseTarget(details, modifiers: []) == "Claude Code in File's folder")
        #expect(SendToCardModel.releaseTarget(details, modifiers: .option) == "Claude Code in ~/Code")
        #expect(SendToCardModel.releaseTarget([], modifiers: []) == nil)
        #expect(L10n.string("shelf.sendTo.noTargets") == "NO TARGETS")
    }

    @Test func modelTargetsAndEmpty() {
        #expect(Self.model.targets.map(\.id) == ["agents.sessions.ask", "airdrop", "ocr"])
        #expect(SendToCardModel(meta: "DEFAULTS", askZone: nil, miniZones: []).isEmpty)
        let ask = Self.askSummary()
        let display = DropDisplayZone(summary: ask)
        #expect(display.style == .target && display.accent == .iris2)
        #expect(String(localized: display.accessibilityLabel).hasPrefix("Ask AI, Claude Code"))
    }

    @Test func badgedGhostKeepsTheIconSize() {
        let icon = NSImage(size: NSSize(width: 32, height: 32))
        let badged = ShelfDragSourceView.badged(icon, color: .systemPurple)
        #expect(badged.size == NSSize(width: 32, height: 32))
        #expect(badged.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
    }

    enum State: String, CaseIterable { case idle, hovered, option, refused, empty }

    static func hover(_ state: State) -> SendToHover {
        switch state {
        case .idle, .empty: SendToHover()
        case .hovered: SendToHover(zoneID: "agents.sessions.ask", contentTypes: [.plainText])
        case .option: SendToHover(zoneID: "agents.sessions.ask", contentTypes: [.plainText], optionHeld: true)
        case .refused: SendToHover(zoneID: "ocr", contentTypes: [.plainText])
        }
    }

    /// The card at 212 × 330 in each state for A dark, A light, C dark and C light. Set `VIGIE_RENDER_DIR` to
    /// keep the PNGs.
    @Test(arguments: [
        (Look.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID),
        (.dark, "twin-metal-tactical"), (.light, "twin-metal-tactical"),
    ])
    func renders(look: Look, variant: String) throws {
        let theme = SessionsTabTests.theme(look, variant: variant)
        for state in State.allCases {
            let model = state == .empty ? SendToCardModel(meta: "DEFAULTS", askZone: nil, miniZones: []) : Self.model
            var card = SendToCardView(hover: Self.hover(state), model: { model })
            card.interactive = false
            let framed = card.frame(width: 212, height: 330).padding(12)
                .background(theme.color(.surfacePanel)).vigieTheme(theme)
            let renderer = ImageRenderer(content: framed)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            #expect(SessionGlyphTests.inkedPixels(image) > (state == .empty ? 100 : 2000))
            if let directory = ProcessInfo.processInfo.environment["VIGIE_RENDER_DIR"] {
                let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(
                    to: URL(fileURLWithPath: directory).appendingPathComponent(
                        "send-to-\(variant)-\(look.rawValue)-\(state.rawValue).png"))
            }
        }
        // In the tab, next to the Stash.
        let full = ShelfTabTests.snapshot(ShelfTabTests.rows, selected: ShelfTabTests.ids[0])
        let model = Self.model
        var tab = ShelfTabView(
            snapshot: { full }, actions: ShelfTabActions(),
            sendTo: AnyView(
                { () -> SendToCardView in
                    var card = SendToCardView(model: { model })
                    card.interactive = false
                    return card
                }()))
        tab.interactive = false
        _ = try SessionsTabTests.render(tab, theme: theme, name: "shelf-send-to-\(variant)-\(look.rawValue)")
    }
}
