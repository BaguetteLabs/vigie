import CoreGraphics
import Foundation

/// Where one zone sits in the drop display grid. Columns and rows count from 1 (DESIGN "Drop display").
public struct DropGridPlacement: Hashable, Sendable {
    public var column: Int
    public var row: Int
    public var columnSpan: Int
    public var rowSpan: Int

    public init(column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 1) {
        self.column = column
        self.row = row
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
    }
}

/// The laid-out drop display grid: `columns` equal columns × `rows` rows, and each zone's cells. The Notch Host
/// computes it from the zones' roles, preferred cells and order (AD-19); the view only draws it.
public struct DropGridLayout: Hashable, Sendable {
    public var columns: Int
    public var rows: Int
    /// Zone id → placement, in drawing order.
    public var placements: [(id: String, placement: DropGridPlacement)] {
        order.compactMap { id in cells[id].map { (id, $0) } }
    }

    private var order: [String]
    private var cells: [String: DropGridPlacement]

    public init(columns: Int, rows: Int, placements: [(String, DropGridPlacement)]) {
        self.columns = columns
        self.rows = rows
        order = placements.map(\.0)
        cells = Dictionary(placements, uniquingKeysWith: { first, _ in first })
    }

    public func placement(of id: String) -> DropGridPlacement? { cells[id] }

    public var zoneIDs: [String] { order }
}

extension Theme {
    /// `components.drop-display` width × height (700 × 196).
    public var dropDisplaySize: CGSize {
        CGSize(
            width: componentLength("drop-display", "width") ?? DropMetrics.width,
            height: componentLength("drop-display", "height") ?? DropMetrics.height)
    }

    /// The neutral drop shadow of the drop display (`components.drop-display.shadow-dark`; light looks share
    /// the peek's light shadow).
    public var dropDisplayShadow: PeekShadow {
        let own = look == .dark ? component("drop-display", "shadow-dark").flatMap(PeekShadow.init(css:)) : nil
        return own ?? peekShadow
    }
}

/// Zone frames inside the drop display (pure; shared by the view and the host's drag hit-testing).
public enum DropDisplayGeometry {
    /// The frame of every placed zone, in the display's own coordinates (top-left origin, 700 × 196): the grid
    /// sits `drop-grid-top` below the top edge, `drop-grid-inset-x` from the sides and `drop-grid-bottom` above
    /// the bottom, with `drop-grid-gap` between cells.
    public static func zoneFrames(_ layout: DropGridLayout, theme: Theme) -> [String: CGRect] {
        zoneFrames(
            layout, size: theme.dropDisplaySize, top: theme.spacing(.dropGridTop),
            side: theme.spacing(.dropGridInsetX), bottom: theme.spacing(.dropGridBottom),
            gap: theme.spacing(.dropGridGap))
    }

    public static func zoneFrames(
        _ layout: DropGridLayout, size: CGSize, top: CGFloat, side: CGFloat, bottom: CGFloat, gap: CGFloat
    ) -> [String: CGRect] {
        guard layout.columns > 0, layout.rows > 0 else { return [:] }
        let gridWidth = size.width - 2 * side
        let gridHeight = size.height - top - bottom
        let columnWidth = (gridWidth - gap * CGFloat(layout.columns - 1)) / CGFloat(layout.columns)
        let rowHeight = (gridHeight - gap * CGFloat(layout.rows - 1)) / CGFloat(layout.rows)
        var frames: [String: CGRect] = [:]
        for (id, p) in layout.placements {
            let x = side + CGFloat(p.column - 1) * (columnWidth + gap)
            let y = top + CGFloat(p.row - 1) * (rowHeight + gap)
            let width = columnWidth * CGFloat(p.columnSpan) + gap * CGFloat(p.columnSpan - 1)
            let height = rowHeight * CGFloat(p.rowSpan) + gap * CGFloat(p.rowSpan - 1)
            frames[id] = CGRect(x: x, y: y, width: width, height: height)
        }
        return frames
    }

    /// The zone under `point` (display coordinates, top-left origin), if any.
    public static func zone(at point: CGPoint, in frames: [String: CGRect]) -> String? {
        frames.first { $0.value.contains(point) }?.key
    }
}

/// DESIGN values for the drop display, used only if a theme file lacks `components.drop-display`, plus the
/// opacities DESIGN states in prose.
enum DropMetrics {
    static let width: CGFloat = 700
    static let height: CGFloat = 196
    /// A: Stash 3.5% fill and 9% hairline; AirDrop / Image to Text 2% fill and 7% hairline.
    static let primaryFill = 0.035
    static let primaryHairline = 0.09
    static let secondaryFill = 0.02
    static let secondaryHairline = 0.07
    /// Ask AI: dashed accent border (A 35%, C 55%), radial accent tint 10%.
    static let targetBorderA = 0.35
    static let targetBorderC = 0.55
    static let targetTint = 0.10
    static let targetTintRadius: CGFloat = 90
    /// Dashed 1px border pattern.
    static let dash: [CGFloat] = [3, 3]
    /// The round `+` ring: accent 45%; lit fill 16%.
    static let plusRing = 0.45
    static let plusLitFill = 0.16
    /// Lit zone: radial accent tint 22% → 4% (A), 3px inner halo 10% (A dark); C gold 16% → 3%.
    static let litTintCenter = 0.22
    static let litTintEdge = 0.04
    static let litTintRadius: CGFloat = 120
    static let litHalo = 0.10
    static let litHaloWidth: CGFloat = 3
    static let litGoldStart = 0.16
    static let litGoldEnd = 0.03
    /// C struct inner border at 22%.
    static let structBorder = 0.22
    /// A iris rim at half strength.
    static let rimStrength = 0.5
    /// Glyph sizes: primary 22px, secondary 18px; the `+` target 22px.
    static let primaryGlyph: CGFloat = 22
    static let secondaryGlyph: CGFloat = 18
    static let plusTarget: CGFloat = 22
    /// Gap between glyph and text block, and between label and meta lines (mock: 6 / 5).
    static let glyphGap: CGFloat = 6
    static let lineGap: CGFloat = 5
}
