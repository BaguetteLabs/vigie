import AppKit
import Foundation
import SwiftUI
import Testing

@testable import VigieUI

@MainActor @Suite struct DropDisplayViewTests {
    static func theme(_ look: Look, variant: String = ThemeLibrary.defaultVariantID, reduceMotion: Bool = false)
        -> Theme
    {
        Fixtures.library.resolve(
            themeID: variant, look: look, accessibility: AccessibilityAdjustments(reduceMotion: reduceMotion)
        ).theme
    }

    static func text(_ s: String) -> LocalizedStringResource { LocalizedStringResource(stringLiteral: s) }

    // Copy as the Shelf and Ask AI modules will spell it (Stories 9.2, 9.6, 9.8, 9.9).
    static let stash = DropDisplayZone(
        id: "stash", label: text("STASH"), glyph: "drop.stash", accent: .iris2, style: .standard, isPrimary: true,
        meta: text("KEEP 7 DAYS · 5 ITEMS"), releaseLine: text("RELEASE TO STASH"),
        accessibilityLabel: text("Stash, keep 7 days, 5 items"))
    static let ask = DropDisplayZone(
        id: "ask", label: text("ASK AI"), glyph: "plus", accent: .iris2, style: .target, isPrimary: false,
        meta: nil, releaseLine: text("RELEASE TO ASK"),
        accessibilityLabel: text("Ask AI, Claude Code in ~/dev, Option for alternate folder"),
        hint: text("⌥ ALT FOLDER"), hintActive: text("ALT FOLDER"))
    static let airdrop = DropDisplayZone(
        id: "airdrop", label: text("AIRDROP"), glyph: "drop.airdrop", accent: .iris2, style: .standard,
        isPrimary: false, meta: text("NEARBY DEVICES"), releaseLine: text("RELEASE TO SHARE"),
        accessibilityLabel: text("AirDrop, nearby devices"))
    static let ocr = DropDisplayZone(
        id: "ocr", label: text("IMAGE TO TEXT"), glyph: "drop.image-to-text", accent: .iris2, style: .standard,
        isPrimary: false, meta: text("COPY TEXT"), releaseLine: text("RELEASE TO COPY TEXT"),
        accessibilityLabel: text("Image to Text, copy text"))

    static let full = DropGridLayout(
        columns: 4, rows: 2,
        placements: [
            ("stash", DropGridPlacement(column: 1, row: 1, columnSpan: 2, rowSpan: 2)),
            ("ask", DropGridPlacement(column: 3, row: 1, rowSpan: 2)),
            ("airdrop", DropGridPlacement(column: 4, row: 1)),
            ("ocr", DropGridPlacement(column: 4, row: 2)),
        ])
    static let threeColumns = DropGridLayout(
        columns: 3, rows: 2,
        placements: [
            ("stash", DropGridPlacement(column: 1, row: 1, columnSpan: 2, rowSpan: 2)),
            ("ask", DropGridPlacement(column: 3, row: 1, rowSpan: 2)),
        ])

    enum Scene: String, CaseIterable {
        case full
        case hoverStash = "hover-stash"
        case optionAsk = "option-ask"
        case threeColumns = "three-columns"
    }

    static func model(_ scene: Scene) -> DropDisplayModel {
        switch scene {
        case .full:
            return DropDisplayModel(layout: full, zones: [stash, ask, airdrop, ocr], itemCount: 1)
        case .hoverStash:
            return DropDisplayModel(
                layout: full, zones: [stash, ask, airdrop, ocr], itemCount: 1, hoveredZoneID: "stash",
                hoveredAccepts: true)
        case .optionAsk:
            return DropDisplayModel(
                layout: full, zones: [stash, ask, airdrop, ocr], itemCount: 2, hoveredZoneID: "ask",
                hoveredAccepts: true, optionHeld: true)
        case .threeColumns:
            return DropDisplayModel(layout: threeColumns, zones: [stash, ask], itemCount: 1)
        }
    }

    @Test func metricsComeFromTheTheme() {
        let theme = Self.theme(.dark)
        #expect(theme.dropDisplaySize == CGSize(width: 700, height: 196))
        #expect(theme.spacing(.dropGridTop) == 44)
        #expect(theme.spacing(.dropBandPaddingX) == 22)
        #expect(theme.motion(.dropDisplayGrow) == .milliseconds(180))
        #expect(theme.dropDisplayShadow == PeekShadow(y: 18, radius: 20, opacity: 0.45))
    }

    @Test func bandStringsComeFromTheCatalogWithPlurals() {
        #expect(DropDisplayModel.bandPrefix() == "DROP ·")
        #expect(DropDisplayModel.bandCount(1) == "1 ITEM")
        #expect(DropDisplayModel.bandCount(3) == "3 ITEMS")
        #expect(DropDisplayModel.bandCancel() == "ESC · CANCEL")
    }

    @Test func litNeedsHoverAndAcceptance() {
        let m = DropDisplayModel(layout: Self.full, zones: [Self.ocr], itemCount: 1, hoveredZoneID: "ocr")
        #expect(!m.isLit("ocr"))
        m.hoveredAccepts = true
        #expect(m.isLit("ocr"))
        #expect(!m.isLit("stash"))
    }

    @Test func loopsAreOffUnderCalmAndReduceMotion() {
        #expect(!Self.theme(.dark, reduceMotion: true).loopsEnabled)
        #expect(Self.theme(.dark, reduceMotion: true).animation(.dropDisplayGrow) == nil)
        #expect(Self.theme(.dark).animation(.dropDisplayGrow) != nil)
    }

    @Test(arguments: Scene.allCases, [Look.dark, .light])
    func displayRenders(scene: Scene, look: Look) throws {
        try render(scene: scene, look: look, variant: ThemeLibrary.defaultVariantID)
    }

    @Test(arguments: [Scene.full, .hoverStash], [Look.dark, .light])
    func displayRendersInTwinMetal(scene: Scene, look: Look) throws {
        try render(scene: scene, look: look, variant: "twin-metal-tactical")
    }

    private func render(scene: Scene, look: Look, variant: String) throws {
        let theme = Self.theme(look, variant: variant)
        let island = Self.theme(.dark, variant: variant)
        let margin = theme.dropDisplayShadow.margin
        let view = DropDisplayView(model: Self.model(scene), bandTheme: island)
            .padding(.horizontal, margin)
            .padding(.bottom, margin)
            .background(look == .dark ? Color(white: 0.22) : Color(white: 0.85))
        let renderer = ImageRenderer(content: view.vigieTheme(theme))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int((theme.dropDisplaySize.width + 2 * margin) * 2))
        if let dir = ProcessInfo.processInfo.environment["VIGIE_DROP_RENDER_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(
                "drop-\(scene.rawValue)-\(variant)-\(look.rawValue).png")
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}
