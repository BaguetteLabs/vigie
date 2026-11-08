import ModuleKit
import VigieUI

/// What the layout engine reads of a zone (AD-19): its role, preferred cell and order.
public struct DropLayoutInput: Hashable, Sendable {
    public var id: String
    public var role: DropRole
    public var cell: DropCell
    public var order: Int

    public init(id: String, role: DropRole, cell: DropCell, order: Int) {
        self.id = id
        self.role = role
        self.cell = cell
        self.order = order
    }

    public init(_ zone: DropZone) {
        self.init(id: zone.id, role: zone.role, cell: zone.cell, order: zone.order)
    }
}

/// Lays the enabled zones out in the drop display's 4 × 2 grid (AD-19, UX-DR83, pure). Modules never position
/// views: the host places each zone at its preferred cell (the primary first, then by `order`), then reflows
/// the cells hidden zones left free:
///
/// 1. a zone grows down or up into free cells of its own columns (AirDrop or Image to Text alone spans
///    column 4);
/// 2. columns and rows that hold no zone are removed (both off → 3 columns; Shelf off → Ask AI alone);
/// 3. a zone grows right into free cells of its own rows.
///
/// A zone whose preferred cell is taken goes to the first free spot that fits its span, else the first free
/// cell; a zone that finds none is left out. No zone → nil: no drop display at all.
public enum DropGridLayoutEngine {
    public static let columns = 4
    public static let rows = 2

    public static func layout(_ zones: [DropLayoutInput], columns: Int = columns, rows: Int = rows)
        -> DropGridLayout?
    {
        var seen: Set<String> = []
        let ordered = zones.filter { seen.insert($0.id).inserted }.sorted(by: precedes)
        var grid = Grid(columns: columns, rows: rows)
        var placed: [(String, DropGridPlacement)] = []
        for zone in ordered {
            guard let placement = grid.place(zone.cell) else { continue }
            grid.occupy(placement, by: zone.id)
            placed.append((zone.id, placement))
        }
        guard !placed.isEmpty else { return nil }
        placed = placed.map { ($0.0, grid.growVertically($0.1, id: $0.0)) }
        let (compacted, usedColumns, usedRows) = compact(placed)
        var compactGrid = Grid(columns: usedColumns, rows: usedRows)
        for (id, p) in compacted { compactGrid.occupy(p, by: id) }
        let grown = compacted.map { ($0.0, compactGrid.growHorizontally($0.1, id: $0.0)) }
        return DropGridLayout(columns: usedColumns, rows: usedRows, placements: grown)
    }

    /// Primary first, then `order`, then id.
    static func precedes(_ a: DropLayoutInput, _ b: DropLayoutInput) -> Bool {
        let ra = a.role == .primary ? 0 : 1
        let rb = b.role == .primary ? 0 : 1
        if ra != rb { return ra < rb }
        if a.order != b.order { return a.order < b.order }
        return a.id < b.id
    }

    /// Removes the columns and rows no zone touches and renumbers the rest from 1.
    private static func compact(_ placed: [(String, DropGridPlacement)]) -> ([(String, DropGridPlacement)], Int, Int) {
        let usedColumns = Set(placed.flatMap { p in p.1.column..<(p.1.column + p.1.columnSpan) }).sorted()
        let usedRows = Set(placed.flatMap { p in p.1.row..<(p.1.row + p.1.rowSpan) }).sorted()
        let columnIndex = Dictionary(uniqueKeysWithValues: usedColumns.enumerated().map { ($1, $0 + 1) })
        let rowIndex = Dictionary(uniqueKeysWithValues: usedRows.enumerated().map { ($1, $0 + 1) })
        let mapped = placed.map { id, p -> (String, DropGridPlacement) in
            let firstColumn = columnIndex[p.column] ?? 1
            let lastColumn = columnIndex[p.column + p.columnSpan - 1] ?? firstColumn
            let firstRow = rowIndex[p.row] ?? 1
            let lastRow = rowIndex[p.row + p.rowSpan - 1] ?? firstRow
            return (
                id,
                DropGridPlacement(
                    column: firstColumn, row: firstRow, columnSpan: lastColumn - firstColumn + 1,
                    rowSpan: lastRow - firstRow + 1)
            )
        }
        return (mapped, usedColumns.count, usedRows.count)
    }

    /// Occupancy of the grid cells (1-based).
    private struct Grid {
        let columns: Int
        let rows: Int
        private var owner: [Int: String] = [:]

        init(columns: Int, rows: Int) {
            self.columns = columns
            self.rows = rows
        }

        private func key(_ column: Int, _ row: Int) -> Int { row * 100 + column }

        func isFree(_ column: Int, _ row: Int, except id: String? = nil) -> Bool {
            guard column >= 1, column <= columns, row >= 1, row <= rows else { return false }
            let current = owner[key(column, row)]
            return current == nil || current == id
        }

        func fits(_ p: DropGridPlacement) -> Bool {
            for c in p.column..<(p.column + p.columnSpan) {
                for r in p.row..<(p.row + p.rowSpan) where !isFree(c, r) { return false }
            }
            return true
        }

        mutating func occupy(_ p: DropGridPlacement, by id: String) {
            for c in p.column..<(p.column + p.columnSpan) {
                for r in p.row..<(p.row + p.rowSpan) { owner[key(c, r)] = id }
            }
        }

        /// The preferred cell (clamped into the grid), else the first spot that fits the span, else any free cell.
        func place(_ cell: DropCell) -> DropGridPlacement? {
            let columnSpan = min(max(cell.span.columns, 1), columns)
            let rowSpan = min(max(cell.span.rows, 1), rows)
            let preferred = DropGridPlacement(
                column: min(max(cell.preferredColumn, 1), columns - columnSpan + 1),
                row: min(max(cell.preferredRow, 1), rows - rowSpan + 1), columnSpan: columnSpan, rowSpan: rowSpan)
            if fits(preferred) { return preferred }
            for spans in [(columnSpan, rowSpan), (1, 1)] {
                for r in 1...rows {
                    for c in 1...columns {
                        let candidate = DropGridPlacement(column: c, row: r, columnSpan: spans.0, rowSpan: spans.1)
                        if candidate.column + candidate.columnSpan - 1 <= columns,
                            candidate.row + candidate.rowSpan - 1 <= rows, fits(candidate)
                        {
                            return candidate
                        }
                    }
                }
            }
            return nil
        }

        private func rowFree(_ row: Int, columns range: Range<Int>, id: String) -> Bool {
            range.allSatisfy { isFree($0, row, except: id) }
        }

        private func columnFree(_ column: Int, rows range: Range<Int>, id: String) -> Bool {
            range.allSatisfy { isFree(column, $0, except: id) }
        }

        mutating func growVertically(_ p: DropGridPlacement, id: String) -> DropGridPlacement {
            var p = p
            let span = p.column..<(p.column + p.columnSpan)
            while rowFree(p.row + p.rowSpan, columns: span, id: id) { p.rowSpan += 1 }
            while rowFree(p.row - 1, columns: span, id: id) {
                p.row -= 1
                p.rowSpan += 1
            }
            occupy(p, by: id)
            return p
        }

        mutating func growHorizontally(_ p: DropGridPlacement, id: String) -> DropGridPlacement {
            var p = p
            let span = p.row..<(p.row + p.rowSpan)
            while columnFree(p.column + p.columnSpan, rows: span, id: id) { p.columnSpan += 1 }
            while columnFree(p.column - 1, rows: span, id: id) {
                p.column -= 1
                p.columnSpan += 1
            }
            occupy(p, by: id)
            return p
        }
    }
}
