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

/// The menu bar of one display, read from the window server (or built by tests). AppKit coordinates.
public struct MenuBarMetrics: Sendable, Equatable {
    /// Menu bar height in points.
    public var height: CGFloat
    /// The left edge of the status items (global x), when known: `virtual_notch.position = "right"` sits just
    /// left of it.
    public var statusItemsMinX: CGFloat?

    public init(height: CGFloat, statusItemsMinX: CGFloat? = nil) {
        self.height = height
        self.statusItemsMinX = statusItemsMinX
    }
}

/// Closed-island geometry around a hardware notch or a virtual notch (SPEC §5.1–5.5, FR9, FR18, FR24, FR27,
/// UX-DR14). Pure: computed from `ScreenMetrics`, theme metrics and, for a virtual notch, the settings.
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
    /// True for a virtual notch: Vigie draws the band (a hardware notch is its own band).
    public var isVirtual = false
    /// True when the island sits below the menu bar (`virtual_notch.placement = "below"`): rounded on top too.
    public var isFloating = false
    /// The top-center strip of a plain display that triggers the hover reaction (FR27): a few points tall at the
    /// screen's top edge, wider than the pill. Nil on a hardware notch, where the island itself is the target.
    public var hoverStrip: CGRect?

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
    ///
    /// The reported cut-out can be a few points smaller than the glass, so `overlap` (`closed.notch_overlap`)
    /// points are added below the reported height and `sideInset` (`closed.notch_side_inset`) points to each side
    /// of the notch slot (the wings shrink accordingly: the island keeps its outer width). Zero values give the
    /// reported cut-out exactly.
    public static func physical(
        screen: ScreenMetrics, bandHeight: CGFloat, maxSideWidth: CGFloat, cornerRadius: CGFloat,
        overlap: CGFloat = 0, sideInset: CGFloat = 0
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
        let height = max(bandHeight, notchHeight) + max(overlap, 0)
        let inset = max(sideInset, 0)
        let islandFrame = CGRect(
            x: notchMinX - leadingWidth, y: frame.maxY - height,
            width: leadingWidth + notchRect.width + trailingWidth, height: height)
        // The slot eats `inset` from each wing (never more than the wing has).
        let leadingInset = min(inset, leadingWidth)
        let trailingInset = min(inset, trailingWidth)
        let leadingWing = leadingWidth - leadingInset
        let trailingWing = trailingWidth - trailingInset
        let slotWidth = notchRect.width + leadingInset + trailingInset
        return NotchGeometry(
            notchRect: notchRect,
            islandFrame: islandFrame,
            leadingWing: CGRect(x: 0, y: 0, width: leadingWing, height: height),
            notchSlot: CGRect(x: leadingWing, y: 0, width: slotWidth, height: height),
            trailingWing: CGRect(x: leadingWing + slotWidth, y: 0, width: trailingWing, height: height),
            cornerRadius: cornerRadius)
    }

    /// Gap between a `position = "right"` pill and the status items.
    public static let statusItemsGap: CGFloat = 8
    /// How far the hover strip reaches past each side of the pill.
    public static let hoverStripMargin: CGFloat = 80
    /// Height of the hover strip at the top edge.
    public static let hoverStripHeight: CGFloat = 4

    /// Geometry for a virtual notch on a display without a hardware notch (SPEC §5.3, §5.5).
    ///
    /// The notch part is `settings.width` wide (default 200, the MacBook notch) and `bandHeight` tall. Each wing
    /// is `maxSideWidth` (`closed.max_side_width`) while a module wants a side, or with `idle = keep`; when
    /// `isIdle` and `idle` is `shrink` or `hide` the pill is the notch alone (the host hides it for `hide`).
    /// `placement = menu_bar` puts the top edge on the screen edge, over the menu bar; `below` hangs it just
    /// under the menu bar. `position = center` centres it; `right` puts its right edge just left of the status
    /// items (centred when they are unknown). The pill always stays on screen.
    public static func virtual(
        screen: ScreenMetrics, settings: VirtualNotchSettings, menuBar: MenuBarMetrics, bandHeight: CGFloat,
        maxSideWidth: CGFloat, cornerRadius: CGFloat, isIdle: Bool
    ) -> NotchGeometry {
        let frame = screen.frame
        let notchWidth = min(max(settings.width, 1), frame.width)
        let showsWings = !isIdle || settings.idle == .keep
        let side = showsWings ? min(max(maxSideWidth, 0), max((frame.width - notchWidth) / 2, 0)) : 0
        let width = notchWidth + 2 * side
        let height = bandHeight
        let top = settings.placement == .menuBar ? frame.maxY : frame.maxY - max(menuBar.height, 0)

        var minX = frame.midX - width / 2
        if settings.position == .right, let statusMinX = menuBar.statusItemsMinX {
            minX = statusMinX - statusItemsGap - width
        }
        minX = min(max(minX, frame.minX), frame.maxX - width)

        let islandFrame = CGRect(x: minX, y: top - height, width: width, height: height)
        let stripWidth = min(width + 2 * hoverStripMargin, frame.width)
        let stripMinX = min(max(islandFrame.midX - stripWidth / 2, frame.minX), frame.maxX - stripWidth)
        return NotchGeometry(
            notchRect: CGRect(x: minX + side, y: top - height, width: notchWidth, height: height),
            islandFrame: islandFrame,
            leadingWing: CGRect(x: 0, y: 0, width: side, height: height),
            notchSlot: CGRect(x: side, y: 0, width: notchWidth, height: height),
            trailingWing: CGRect(x: side + notchWidth, y: 0, width: side, height: height),
            cornerRadius: cornerRadius,
            isVirtual: true,
            isFloating: settings.placement == .below,
            hoverStrip: CGRect(
                x: stripMinX, y: frame.maxY - hoverStripHeight, width: stripWidth, height: hoverStripHeight))
    }
}
