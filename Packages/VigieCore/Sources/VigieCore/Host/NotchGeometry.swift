import AppKit
import VigieUI

/// The screen facts the closed island needs, read from an `NSScreen` (or built by tests).
public struct ScreenMetrics: Sendable, Equatable {
    /// Screen frame in global AppKit coordinates (bottom-left origin).
    public var frame: CGRect
    /// `safeAreaInsets.top`: the hardware notch height on a notched screen, 0 elsewhere.
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeftArea: CGRect?
    public var auxiliaryTopRightArea: CGRect?

    public init(
        frame: CGRect, safeAreaTop: CGFloat, auxiliaryTopLeftArea: CGRect?, auxiliaryTopRightArea: CGRect?
    ) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
    }

    @MainActor
    public init(screen: NSScreen) {
        self.init(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea)
    }

    /// True when the screen has a hardware notch (AppKit reports the areas beside it).
    public var hasPhysicalNotch: Bool { auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil }
}

/// Closed-island geometry around a hardware notch (SPEC §5.1–5.3, FR9, UX-DR14). Pure: computed from
/// `ScreenMetrics` and theme metrics.
///
/// - `notchRect` and `islandFrame` are global AppKit coordinates (bottom-left origin).
/// - `leadingWing`, `notchSlot` and `trailingWing` are island-local, top-left origin (SwiftUI's space).
public struct NotchGeometry: Sendable, Equatable {
    public var notchRect: CGRect
    public var islandFrame: CGRect
    public var leadingWing: CGRect
    public var notchSlot: CGRect
    public var trailingWing: CGRect
    /// Bottom-corner radius (`rounded.island-closed`).
    public var cornerRadius: CGFloat

    /// Island height: the band height, or the hardware notch height when that is taller so the cut-out
    /// never shows below the island.
    public var height: CGFloat { islandFrame.height }

    public var wings: IslandWings {
        IslandWings(leading: leadingWing.width, notch: notchSlot.width, trailing: trailingWing.width)
    }

    /// Geometry for a screen with a physical notch, or nil when the screen has none.
    ///
    /// The notch spans the screen width minus the two auxiliary areas (only their widths are used, so the
    /// result does not depend on which coordinate space AppKit reports them in). Each wing is the auxiliary
    /// area's width capped by `maxSideWidth` (`closed.max_side_width`, default 120).
    public static func physical(
        screen: ScreenMetrics, bandHeight: CGFloat, maxSideWidth: CGFloat, cornerRadius: CGFloat
    ) -> NotchGeometry? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        let frame = screen.frame
        let notchMinX = frame.minX + left.width
        let notchMaxX = frame.maxX - right.width
        guard notchMaxX > notchMinX else { return nil }
        let notchHeight = max(screen.safeAreaTop, left.height, right.height)
        let notchRect = CGRect(
            x: notchMinX, y: frame.maxY - notchHeight, width: notchMaxX - notchMinX, height: notchHeight)

        let cap = max(maxSideWidth, 0)
        let leadingWidth = min(left.width, cap)
        let trailingWidth = min(right.width, cap)
        let height = max(bandHeight, notchHeight)
        let islandFrame = CGRect(
            x: notchMinX - leadingWidth, y: frame.maxY - height,
            width: leadingWidth + notchRect.width + trailingWidth, height: height)
        return NotchGeometry(
            notchRect: notchRect,
            islandFrame: islandFrame,
            leadingWing: CGRect(x: 0, y: 0, width: leadingWidth, height: height),
            notchSlot: CGRect(x: leadingWidth, y: 0, width: notchRect.width, height: height),
            trailingWing: CGRect(x: leadingWidth + notchRect.width, y: 0, width: trailingWidth, height: height),
            cornerRadius: cornerRadius)
    }
}
