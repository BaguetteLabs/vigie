import AppKit
import SwiftUI
import Testing

@testable import VigieCore

@Suite struct NotchGeometryTests {
    /// MacBook Pro 14" at the default scaled resolution: 1512 × 982 pt, a ~200 pt notch, 656 pt either side.
    static let macBookPro14 = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32,
        auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 656, height: 32),
        auxiliaryTopRightArea: CGRect(x: 856, y: 950, width: 656, height: 32))

    static let plainDisplay = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        safeAreaTop: 0, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)

    func geometry(_ screen: ScreenMetrics, maxSide: CGFloat = 120) -> NotchGeometry? {
        NotchGeometry.physical(screen: screen, bandHeight: 34, maxSideWidth: maxSide, cornerRadius: 14)
    }

    @Test func detectsPhysicalNotch() {
        #expect(Self.macBookPro14.hasPhysicalNotch)
        #expect(!Self.plainDisplay.hasPhysicalNotch)
    }

    @Test func noNotchGivesNoGeometry() {
        #expect(geometry(Self.plainDisplay) == nil)
    }

    @Test func notchRectSitsBetweenTheAuxiliaryAreas() throws {
        let g = try #require(geometry(Self.macBookPro14))
        #expect(g.notchRect == CGRect(x: 656, y: 950, width: 200, height: 32))
    }

    @Test func islandIsNotchPlusCappedWingsAnchoredAtTheTop() throws {
        let g = try #require(geometry(Self.macBookPro14))
        #expect(g.islandFrame == CGRect(x: 536, y: 948, width: 440, height: 34))
        #expect(g.islandFrame.maxY == 982)
        #expect(g.islandFrame.midX == Self.macBookPro14.frame.midX)
        #expect(g.cornerRadius == 14)
        #expect(g.height == 34)
    }

    @Test func wingRectsAreIslandLocal() throws {
        let g = try #require(geometry(Self.macBookPro14))
        #expect(g.leadingWing == CGRect(x: 0, y: 0, width: 120, height: 34))
        #expect(g.notchSlot == CGRect(x: 120, y: 0, width: 200, height: 34))
        #expect(g.trailingWing == CGRect(x: 320, y: 0, width: 120, height: 34))
        #expect(g.wings.totalWidth == g.islandFrame.width)
    }

    @Test func wingsAreCappedByMaxSideWidth() throws {
        let narrow = try #require(geometry(Self.macBookPro14, maxSide: 80))
        #expect(narrow.leadingWing.width == 80)
        #expect(narrow.trailingWing.width == 80)
        #expect(narrow.islandFrame.width == 360)
    }

    @Test func wingsNeverExceedTheAuxiliaryAreas() throws {
        var screen = Self.macBookPro14
        screen.auxiliaryTopLeftArea?.size.width = 90
        let g = try #require(geometry(screen, maxSide: 400))
        #expect(g.leadingWing.width == 90)
        #expect(g.trailingWing.width == 400)
        #expect(g.notchRect.minX == 90)
    }

    @Test func screensAwayFromTheOriginUseTheirFrame() throws {
        var screen = Self.macBookPro14
        screen.frame.origin = CGPoint(x: -1512, y: 200)
        let g = try #require(geometry(screen))
        #expect(g.notchRect.minX == -856)
        #expect(g.islandFrame.maxY == 1182)
    }

    @Test func tallerHardwareNotchRaisesTheIsland() throws {
        var screen = Self.macBookPro14
        screen.safeAreaTop = 38
        let g = try #require(geometry(screen))
        #expect(g.height == 38)
        #expect(g.islandFrame.minY == 944)
    }

    #if DEBUG
        @Test func simulatedNotchIsCentered() throws {
            let metrics = NotchHost.simulatedMetrics(for: CGRect(x: 0, y: 0, width: 2560, height: 1440))
            let g = try #require(geometry(metrics))
            #expect(g.notchRect.width == 200)
            #expect(g.islandFrame.midX == 1280)
        }
    #endif
}

@MainActor
@Suite struct NotchPanelTests {
    @Test func panelNeverTakesFocusAndSitsAboveTheMenuBar() {
        let panel = NotchPanel(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 34), rootView: EmptyView(), contextMenu: nil)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.level.rawValue > NSWindow.Level.mainMenu.rawValue)
        #expect(panel.level.rawValue > NSWindow.Level.statusBar.rawValue)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!panel.isOpaque && !panel.hasShadow && !panel.hidesOnDeactivate && !panel.isMovable)
        let rect = CGRect(x: 10, y: 2000, width: 440, height: 34)
        #expect(panel.constrainFrameRect(rect, to: nil) == rect)
    }
}
