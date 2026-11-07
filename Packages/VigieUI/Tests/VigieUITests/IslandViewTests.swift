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

    @Test func reduceMotionStopsRimAndShimmerButKeepsTheIrisRim() {
        let still = IslandOrnaments(presence: .full, motionEnabled: false)
        #expect(still.rimUsesIris)
        #expect(!still.rimSlides)
        #expect(!still.shimmerEnabled)
        #expect(!still.loops)
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

    static var lightTheme: Theme {
        Fixtures.library.resolve(themeID: ThemeLibrary.defaultVariantID, look: .light).theme
    }

    @Test func blackSurfaceReadsTheIslandRole() {
        #expect(IslandSurface.black.roles(Self.darkTheme) == [.island])
        #expect(IslandSurface.black.roles(Self.lightTheme) == [.island])
    }

    @Test func menuBarSurfaceIsTheVirtualNotchGradientInLightLooks() {
        let theme = Self.lightTheme
        #expect(IslandSurface.menuBar.roles(theme) == [.surfaceVNTop, .surfaceVNBottom])
        #expect(theme.defines(.surfaceVNTop) && theme.defines(.surfaceVNBottom))
    }

    @Test(arguments: [
        AccessibilityAdjustments(reduceTransparency: true), AccessibilityAdjustments(increaseContrast: true),
    ])
    func menuBarSurfaceIsFlatVNBottomUnderAccessibilitySettings(_ adjustments: AccessibilityAdjustments) {
        var theme = Self.lightTheme
        theme.accessibility = adjustments
        #expect(IslandSurface.menuBar.roles(theme) == [.surfaceVNBottom])
    }

    @Test func darkMenuBarSurfaceFallsBackToTheBlackIsland() {
        let theme = Self.darkTheme
        for role in IslandSurface.menuBar.roles(theme) {
            #expect(theme.themeColor(role) == theme.themeColor(.island))
        }
    }

    @Test func floatingShapeRoundsTheTopCorners() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 34)
        let flush = IslandShape(radius: 14).path(in: rect)
        let floating = IslandShape(radius: 14, topRadius: 14).path(in: rect)
        #expect(flush.contains(CGPoint(x: 0.5, y: 0.5)))
        #expect(!floating.contains(CGPoint(x: 0.5, y: 0.5)))
    }

    @Test(arguments: [IslandSurface.black, .menuBar])
    func virtualNotchRendersWithEitherSurface(surface: IslandSurface) throws {
        let wings = IslandWings(leading: 0, notch: 200, trailing: 0)
        let view = IslandView(wings: wings, surface: surface, floating: true, hoverHighlight: true)
            .frame(width: wings.totalWidth, height: 34)
            .vigieTheme(Self.lightTheme)
        let image = try #require(ImageRenderer(content: view).cgImage)
        #expect(image.width > 0 && image.height > 0)
    }

    @Test func markerRendersInsideTheIsland() throws {
        let wings = IslandWings(leading: 120, notch: 200, trailing: 120)
        let view = IslandView(wings: wings, marker: true)
            .frame(width: wings.totalWidth, height: 34)
            .vigieTheme(Self.darkTheme)
        let image = try #require(ImageRenderer(content: view).cgImage)
        #expect(image.width > 0)
        #expect(IslandOrnaments.markerInset < Self.darkTheme.spacing(.wingPaddingX))
    }
}
