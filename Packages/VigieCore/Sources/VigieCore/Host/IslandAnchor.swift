import CoreGraphics

/// Where a Vigie island sits on one display, in global AppKit coordinates (bottom-left origin). Surfaces that
/// grow out of the notch (expanded view, peek, drop display) anchor on it.
public struct IslandAnchor: Sendable, Equatable {
    /// The display's frame.
    public var screenFrame: CGRect
    /// The closed island's frame.
    public var islandFrame: CGRect
    /// The hardware (or virtual) notch cut-out.
    public var notchRect: CGRect

    public init(screenFrame: CGRect, islandFrame: CGRect, notchRect: CGRect) {
        self.screenFrame = screenFrame
        self.islandFrame = islandFrame
        self.notchRect = notchRect
    }

    /// The anchor on the display under `pointer`, or the main Vigie display (the first anchor) when that display
    /// shows no island (SPEC §5.4, FR23). Screen edges count as inside, so a pointer pinned to the top edge
    /// still picks its display.
    public static func select(_ anchors: [IslandAnchor], pointer: CGPoint) -> IslandAnchor? {
        anchors.first { anchor in
            let f = anchor.screenFrame
            return pointer.x >= f.minX && pointer.x <= f.maxX && pointer.y >= f.minY && pointer.y <= f.maxY
        } ?? anchors.first
    }

    /// The outline of a panel of `size` that grows out of this notch: top edge on the screen edge (the band is
    /// part of the panel), centred on the notch, kept on screen horizontally.
    public func panelFrame(size: CGSize) -> CGRect {
        let minX = screenFrame.minX
        let maxX = max(screenFrame.maxX - size.width, minX)
        let x = min(max(notchRect.midX - size.width / 2, minX), maxX)
        return CGRect(x: x, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }
}
