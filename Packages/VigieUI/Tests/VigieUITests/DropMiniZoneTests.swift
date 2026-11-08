import AppKit
import SwiftUI
import Testing

@testable import VigieUI

@MainActor @Suite struct DropMiniZoneTests {
    static let airdrop = DropDisplayZone(
        id: "airdrop", label: DropDisplayViewTests.text("AIRDROP"), glyph: "drop.airdrop", accent: .iris2,
        style: .standard, isPrimary: false, meta: DropDisplayViewTests.text("SHARE"),
        releaseLine: DropDisplayViewTests.text("RELEASE TO SHARE"),
        accessibilityLabel: DropDisplayViewTests.text("AirDrop"))
    static let ocr = DropDisplayZone(
        id: "ocr", label: DropDisplayViewTests.text("IMAGE TO TEXT"), glyph: "drop.image-to-text", accent: .iris2,
        style: .standard, isPrimary: false, meta: DropDisplayViewTests.text("COPY"),
        releaseLine: DropDisplayViewTests.text("RELEASE TO COPY TEXT"),
        accessibilityLabel: DropDisplayViewTests.text("Image to Text"))

    @Test func heightAndGapComeFromTheSendToCardTokens() {
        let theme = DropDisplayViewTests.theme(.dark)
        #expect(DropMiniZone.height(theme) == 38)
        #expect(theme.spacing(.miniZoneGap) == 6)
        #expect(theme.radius(.miniZone) == 11)
    }

    @Test func hoverShowsTheReleaseLineElseTheMeta() {
        #expect(
            DropMiniZone(zone: Self.airdrop, phase: .hovered).trailingLine.map { String(localized: $0) }
                == "RELEASE TO SHARE")
        for phase in [DropMiniZone.Phase.idle, .lit, .disabled] {
            #expect(
                DropMiniZone(zone: Self.airdrop, phase: phase).trailingLine.map { String(localized: $0) }
                    == "SHARE")
        }
        #expect(DropMiniZone(zone: Self.ocr, phase: .lit).isLit)
        #expect(!DropMiniZone(zone: Self.ocr, phase: .disabled).isLit)
    }

    @Test(
        arguments: [DropMiniZone.Phase.idle, .lit, .hovered, .disabled],
        [ThemeLibrary.defaultVariantID, "twin-metal-tactical"])
    func stackRenders(phase: DropMiniZone.Phase, variant: String) throws {
        for look in [Look.dark, .light] {
            try render(phase: phase, look: look, variant: variant)
        }
    }

    private func render(phase: DropMiniZone.Phase, look: Look, variant: String) throws {
        let theme = DropDisplayViewTests.theme(look, variant: variant)
        let width: CGFloat = 212
        let view = DropMiniZoneStack(zones: [Self.airdrop, Self.ocr]) { _ in phase }
            .frame(width: width)
            .background(theme.color(.surfaceCard))
            .vigieTheme(theme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(width * 2))
        #expect(image.height == Int((2 * 38 + 6) * 2))
    }
}

@MainActor @Suite struct TransientReadoutDrainTests {
    @Test func copiedAndNoTextAnnounceAndDrain() {
        #expect(TransientReadout.copied(lines: 3).announcement == "Copied 3 lines")
        #expect(TransientReadout.copied(lines: 1).announcement == "Copied 1 line")
        #expect(TransientReadout.noTextFound.announcement == "No text found")
        #expect(TransientReadout.copied(lines: 3).drains && TransientReadout.noTextFound.drains)
        #expect(!TransientReadout.message("NOT STASHED").drains)
        #expect(TransientReadout.message("NOT STASHED").announcement == nil)
        let confirmation = TransientReadout.confirmation(
            "COPIED · 2 LINES", announcement: "Copied 2 lines", drains: true)
        #expect(confirmation.text == "COPIED · 2 LINES")
        #expect(confirmation.announcement == "Copied 2 lines")
        #expect(confirmation.drains)
    }

    @Test(arguments: [TransientDrain.draining(.seconds(2), trigger: 1), .held], [false, true])
    func drainRendersOverTheIsland(drain: TransientDrain, reduceMotion: Bool) throws {
        let theme = DropDisplayViewTests.theme(.dark, reduceMotion: reduceMotion)
        let view = TransientReadoutDrain(drain)
            .frame(width: 120, height: 34)
            .background(theme.color(.island))
            .vigieTheme(theme)
        let image = try #require(ImageRenderer(content: view).cgImage)
        #expect(image.width > 0)
        #expect(TransientReadoutDrain.bottomInset == 6)
    }
}
