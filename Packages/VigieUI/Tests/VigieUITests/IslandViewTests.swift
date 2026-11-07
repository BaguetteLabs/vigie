import AppKit
import SwiftUI
import Testing

@testable import VigieUI

@Suite struct IslandOrnamentsTests {
    @Test func fullPresenceRunsRimAndShimmer() {
        let idle = IslandOrnaments(presence: .full)
        #expect(idle.rimUsesIris)
        #expect(idle.rimSlides)
        #expect(idle.shimmerEnabled)
        #expect(idle.loops)
        #expect(idle.rimOpacity > 0 && idle.rimOpacity < 1)
    }

    @Test func hoverRaisesRimToFullStrengthAndLiftsTheInterior() {
        let idle = IslandOrnaments(presence: .full)
        let hovered = IslandOrnaments(presence: .full, isHovered: true)
        #expect(hovered.rimOpacity == 1)
        #expect(hovered.interiorGlowOpacity > idle.interiorGlowOpacity)
    }

    @Test func calmPresenceIsStillAndDimmer() {
        for hovered in [false, true] {
            let calm = IslandOrnaments(presence: .calm, isHovered: hovered)
            #expect(!calm.shimmerEnabled)
            #expect(!calm.rimSlides)
            #expect(!calm.rimUsesIris)
            #expect(!calm.loops)
            #expect(calm.interiorGlowOpacity == 0)
            #expect(calm.rimOpacity < IslandOrnaments(presence: .full).rimOpacity)
        }
    }
}

@MainActor
@Suite struct IslandViewTests {
    static var darkTheme: Theme {
        Fixtures.library.resolve(themeID: ThemeLibrary.defaultVariantID, look: .dark).theme
    }

    @Test func colorRolesUsedAreDefinedInTheBundledDarkLook() {
        let theme = Self.darkTheme
        for role in [ColorRole.island, .iris1, .iris2, .iris3, .ink1] {
            #expect(theme.defines(role), "missing \(role.rawValue)")
        }
        #expect(theme.themeColor(.island) == ThemeColor(red: 0, green: 0, blue: 0))
    }

    @Test func metricsComeFromTheTheme() {
        let theme = Self.darkTheme
        #expect(theme.radius(.islandClosed) == 14)
        #expect(theme.spacing(.bandHeight) == 34)
        #expect(theme.spacing(.wingPaddingX) > 0)
        #expect(theme.motion(.ambientLoop) == .seconds(6))
        #expect(theme.motion(.enter) == .milliseconds(280))
    }

    @Test(arguments: [PresenceLevel.full, .calm])
    func viewRendersWithTheBundledTheme(presence: PresenceLevel) throws {
        var theme = Self.darkTheme
        theme.presence = presence
        let wings = IslandWings(leading: 120, notch: 200, trailing: 120)
        let view = IslandView(wings: wings, leading: { AnyView(Text(verbatim: "L")) })
            .frame(width: wings.totalWidth, height: 34)
            .vigieTheme(theme)
        let renderer = ImageRenderer(content: view)
        let image = try #require(renderer.cgImage)
        #expect(image.width > 0 && image.height > 0)
    }

    @Test func rimShapeExcludesTheTopEdgeAndInterior() {
        let rect = CGRect(x: 0, y: 0, width: 440, height: 34)
        let path = IslandRimShape(radius: 14, lineWidth: 1).path(in: rect)
        let contains = { (p: CGPoint) in path.contains(p, eoFill: true) }
        #expect(contains(CGPoint(x: 0.5, y: 17)))  // leading side
        #expect(contains(CGPoint(x: 439.5, y: 17)))  // trailing side
        #expect(contains(CGPoint(x: 220, y: 33.5)))  // bottom
        #expect(!contains(CGPoint(x: 220, y: 17)))  // interior
        #expect(!contains(CGPoint(x: 220, y: 0.5)))  // top edge
    }
}
