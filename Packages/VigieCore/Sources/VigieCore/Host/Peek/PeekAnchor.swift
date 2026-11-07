import AppKit

/// Where a peek grows from: the screen of a Vigie island and its notch (hardware or virtual).
///
/// Frames are global AppKit coordinates (bottom-left origin), as in ``NotchGeometry``.
public struct PeekAnchor: Sendable, Equatable {
    /// The frame of the screen that shows the island.
    public var screenFrame: CGRect
    /// The notch (or virtual notch) the peek is centered under.
    public var notchRect: CGRect
    /// The island band height (`spacing.band-height`, or the notch height when taller).
    public var bandHeight: CGFloat

    public init(screenFrame: CGRect, notchRect: CGRect, bandHeight: CGFloat) {
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.bandHeight = bandHeight
    }

    @MainActor
    public init(screen: NSScreen, notchRect: CGRect, bandHeight: CGFloat) {
        self.init(screenFrame: screen.frame, notchRect: notchRect, bandHeight: bandHeight)
    }

    /// The anchor for a placed island (`NotchGeometry.notchRect` and its height).
    public init(screenFrame: CGRect, geometry: NotchGeometry) {
        self.init(screenFrame: screenFrame, notchRect: geometry.notchRect, bandHeight: geometry.height)
    }

    /// True when `point` lies on this screen (edges included: the pointer can sit on the top row).
    public func contains(_ point: NSPoint) -> Bool {
        point.x >= screenFrame.minX && point.x <= screenFrame.maxX
            && point.y >= screenFrame.minY && point.y <= screenFrame.maxY
    }

    /// FR23 / PRD FR-9: the island on the display under the pointer, else the main Vigie display, else any
    /// island. Nil when Vigie shows no island at all.
    ///
    /// - Parameters:
    ///   - islands: an anchor per display that shows a Vigie island.
    ///   - main: the main Vigie display's anchor (the notched display, or the one `display` names).
    public static func select(pointer: NSPoint?, islands: [PeekAnchor], main: PeekAnchor?) -> PeekAnchor? {
        if let pointer, let hit = islands.first(where: { $0.contains(pointer) }) { return hit }
        return main ?? islands.first
    }
}

/// Supplies the peek's anchor (AD-13: only the Notch Host shows peeks). `NotchHost` conforms: it knows which
/// displays show an island and which one is the main Vigie display; ``PeekAnchor/select(pointer:islands:main:)``
/// implements the choice.
@MainActor
public protocol PeekAnchorProvider: AnyObject {
    /// The anchor on the display under `pointer` when it shows Vigie, else on the main Vigie display. Nil when
    /// no island is placed (the peek is then skipped).
    func anchor(forDisplayUnder pointer: NSPoint?) -> PeekAnchor?
}

/// Peek placement (pure).
public enum PeekLayout {
    /// The 700 × 150 panel frame: flush with the top of the anchor's screen, centered under the notch, kept on
    /// the screen horizontally.
    public static func panelFrame(anchor: PeekAnchor, size: CGSize) -> CGRect {
        let screen = anchor.screenFrame
        let centered = anchor.notchRect.midX - size.width / 2
        let x = min(max(centered, screen.minX), max(screen.maxX - size.width, screen.minX))
        return CGRect(x: x, y: screen.maxY - size.height, width: size.width, height: size.height)
    }

    /// The window frame: the panel plus room for its drop shadow on the sides and below.
    public static func windowFrame(panel: CGRect, shadowMargin margin: CGFloat) -> CGRect {
        CGRect(
            x: panel.minX - margin, y: panel.minY - margin,
            width: panel.width + 2 * margin, height: panel.height + margin)
    }
}
