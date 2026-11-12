import Foundation

/// A line diff of two script files (Story 12.10, EXPERIENCE "Script Confirmation": an update shows the diff from
/// the confirmed version). Pure and synchronous: Myers' O((N+M)·D) shortest edit script over the lines left once
/// the common prefix and suffix are set aside. A diff with more than ``maxEdits`` edits (a rewrite) is shown as
/// every old line removed, then every new line added, so memory stays bounded.
public enum ScriptLineDiff {
    /// Beyond this many inserted plus deleted lines the diff falls back to remove-all / add-all.
    public static let maxEdits = 1000
    /// Unchanged lines kept around each change by ``rows(_:context:)``.
    public static let defaultContext = 3

    public struct Line: Equatable, Hashable, Sendable {
        public enum Kind: Equatable, Hashable, Sendable {
            case context
            case added
            case removed
        }

        public var kind: Kind
        public var text: String
        /// 1-based line number in the old file (nil for an added line).
        public var oldNumber: Int?
        /// 1-based line number in the new file (nil for a removed line).
        public var newNumber: Int?

        public init(kind: Kind, text: String, oldNumber: Int?, newNumber: Int?) {
            self.kind = kind
            self.text = text
            self.oldNumber = oldNumber
            self.newNumber = newNumber
        }

        public static func context(_ text: String, _ old: Int, _ new: Int) -> Line {
            Line(kind: .context, text: text, oldNumber: old, newNumber: new)
        }
        public static func added(_ text: String, _ new: Int) -> Line {
            Line(kind: .added, text: text, oldNumber: nil, newNumber: new)
        }
        public static func removed(_ text: String, _ old: Int) -> Line {
            Line(kind: .removed, text: text, oldNumber: old, newNumber: nil)
        }
    }

    /// What the update sheet draws: a line, or a run of unchanged lines folded away.
    public enum Row: Equatable, Hashable, Sendable {
        case line(Line)
        case skipped(Int)
    }

    /// The file's lines: split on `\n`, a final newline does not add an empty line, `\r` before `\n` is dropped.
    public static func split(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }

    /// Every line of both files in order: unchanged lines as context, removed lines before the lines added in
    /// their place.
    public static func lines(old: String, new: String) -> [Line] {
        lines(old: split(old), new: split(new))
    }

    public static func lines(old a: [String], new b: [String]) -> [Line] {
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix,
            a[a.count - 1 - suffix] == b[b.count - 1 - suffix]
        {
            suffix += 1
        }
        var result: [Line] = (0..<prefix).map { .context(a[$0], $0 + 1, $0 + 1) }
        let oldMiddle = Array(a[prefix..<(a.count - suffix)])
        let newMiddle = Array(b[prefix..<(b.count - suffix)])
        result += middle(oldMiddle, newMiddle, oldStart: prefix + 1, newStart: prefix + 1)
        for index in 0..<suffix {
            let old = a.count - suffix + index
            let new = b.count - suffix + index
            result.append(.context(a[old], old + 1, new + 1))
        }
        return result
    }

    /// Myers on the part that differs; line numbers start at `oldStart` / `newStart`.
    private static func middle(_ a: [String], _ b: [String], oldStart: Int, newStart: Int) -> [Line] {
        let n = a.count
        let m = b.count
        if n == 0 { return b.enumerated().map { .added($0.element, newStart + $0.offset) } }
        if m == 0 { return a.enumerated().map { .removed($0.element, oldStart + $0.offset) } }
        let limit = min(n + m, maxEdits)
        let offset = limit + 1
        var v = [Int](repeating: 0, count: 2 * limit + 3)
        var trace: [[Int]] = []
        var found = false
        search: for d in 0...limit {
            trace.append(v)
            for k in stride(from: -d, through: d, by: 2) {
                var x =
                    (k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset]))
                    ? v[k + 1 + offset] : v[k - 1 + offset] + 1
                var y = x - k
                while x < n, y < m, a[x] == b[y] {
                    x += 1
                    y += 1
                }
                v[k + offset] = x
                if x >= n, y >= m {
                    found = true
                    break search
                }
            }
        }
        guard found else {
            return a.enumerated().map { .removed($0.element, oldStart + $0.offset) }
                + b.enumerated().map { .added($0.element, newStart + $0.offset) }
        }

        // Walk back from (n, m) through the recorded frontiers.
        var reversed: [Line] = []
        var x = n
        var y = m
        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let v = trace[d]
            let k = x - y
            let previousK =
                (k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])) ? k + 1 : k - 1
            let previousX = v[previousK + offset]
            let previousY = previousX - previousK
            while x > previousX, y > previousY {
                reversed.append(.context(a[x - 1], oldStart + x - 1, newStart + y - 1))
                x -= 1
                y -= 1
            }
            if d > 0 {
                if x == previousX {
                    reversed.append(.added(b[y - 1], newStart + y - 1))
                } else {
                    reversed.append(.removed(a[x - 1], oldStart + x - 1))
                }
            }
            x = previousX
            y = previousY
        }
        return normalized(reversed.reversed())
    }

    /// Within each run of changes, removed lines come before added ones (reads as "this became that").
    private static func normalized(_ lines: [Line]) -> [Line] {
        var result: [Line] = []
        var removed: [Line] = []
        var added: [Line] = []
        func flush() {
            result += removed + added
            removed = []
            added = []
        }
        for line in lines {
            switch line.kind {
            case .removed: removed.append(line)
            case .added: added.append(line)
            case .context:
                flush()
                result.append(line)
            }
        }
        flush()
        return result
    }

    /// The rows to draw: every change with `context` unchanged lines around it; longer unchanged runs fold into
    /// ``Row/skipped(_:)``. A diff without changes is one skipped row (or nothing for two empty files).
    public static func rows(_ lines: [Line], context: Int = defaultContext) -> [Row] {
        let changed = lines.indices.filter { lines[$0].kind != .context }
        var shown = Set<Int>()
        for index in changed {
            for near in max(0, index - context)...min(lines.count - 1, index + context) { shown.insert(near) }
        }
        var rows: [Row] = []
        var skipped = 0
        for index in lines.indices {
            if shown.contains(index) {
                if skipped > 0 { rows.append(.skipped(skipped)) }
                skipped = 0
                rows.append(.line(lines[index]))
            } else {
                skipped += 1
            }
        }
        if skipped > 0 { rows.append(.skipped(skipped)) }
        return rows
    }

    /// Added and removed line counts.
    public static func counts(_ lines: [Line]) -> (added: Int, removed: Int) {
        (lines.filter { $0.kind == .added }.count, lines.filter { $0.kind == .removed }.count)
    }
}
