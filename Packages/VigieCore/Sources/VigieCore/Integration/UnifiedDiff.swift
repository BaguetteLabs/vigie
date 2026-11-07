import Foundation

/// A minimal line diff (Myers) rendered as a unified diff with three lines of context, for the integration
/// confirmation (AD-22). No third-party code (AD-16).
enum UnifiedDiff {
    enum Edit: Equatable {
        case same(String)
        case delete(String)
        case insert(String)
    }

    /// Lines of `text`; a final newline does not start an extra empty line.
    static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    /// The shortest edit script from `old` to `new` (common prefix and suffix trimmed first).
    static func edits(_ old: [String], _ new: [String]) -> [Edit] {
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
            old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
        {
            suffix += 1
        }
        let a = Array(old[prefix..<(old.count - suffix)])
        let b = Array(new[prefix..<(new.count - suffix)])
        return old[..<prefix].map(Edit.same) + myers(a, b) + old[(old.count - suffix)...].map(Edit.same)
    }

    private static func myers(_ a: [String], _ b: [String]) -> [Edit] {
        let n = a.count
        let m = b.count
        if n == 0 { return b.map(Edit.insert) }
        if m == 0 { return a.map(Edit.delete) }
        let max = n + m
        let offset = max
        var v = [Int](repeating: 0, count: 2 * max + 2)
        var trace: [[Int]] = []
        search: for d in 0...max {
            trace.append(v)
            for k in stride(from: -d, through: d, by: 2) {
                var x: Int
                if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                    x = v[offset + k + 1]
                } else {
                    x = v[offset + k - 1] + 1
                }
                var y = x - k
                while x < n, y < m, a[x] == b[y] {
                    x += 1
                    y += 1
                }
                v[offset + k] = x
                if x >= n, y >= m { break search }
            }
        }
        // Backtrack through the saved frontiers.
        var edits: [Edit] = []
        var x = n
        var y = m
        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let v = trace[d]
            let k = x - y
            let previousK: Int
            if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                previousK = k + 1
            } else {
                previousK = k - 1
            }
            let previousX = d == 0 ? 0 : v[offset + previousK]
            let previousY = previousX - previousK
            while x > previousX, y > previousY {
                edits.append(.same(a[x - 1]))
                x -= 1
                y -= 1
            }
            if d > 0 {
                if x == previousX {
                    edits.append(.insert(b[y - 1]))
                } else {
                    edits.append(.delete(a[x - 1]))
                }
            }
            x = previousX
            y = previousY
        }
        return edits.reversed()
    }

    /// `--- <label>` / `+++ <label>` (`/dev/null` for a file that does not exist yet), then `@@` hunks.
    /// Empty when the texts are equal.
    static func render(old: String, new: String, label: String, oldExists: Bool, context: Int = 3) -> String {
        let edits = edits(lines(old), lines(new))
        guard edits.contains(where: { if case .same = $0 { false } else { true } }) else { return "" }
        var out = [oldExists ? "--- \(label)" : "--- /dev/null", "+++ \(label)"]

        // Line numbers (1-based) before each edit.
        var positions: [(old: Int, new: Int)] = []
        var o = 1
        var n = 1
        for edit in edits {
            positions.append((o, n))
            switch edit {
            case .same:
                o += 1
                n += 1
            case .delete: o += 1
            case .insert: n += 1
            }
        }
        let changed = edits.indices.filter { if case .same = edits[$0] { false } else { true } }
        var groups: [ClosedRange<Int>] = []
        for index in changed {
            let low = Swift.max(0, index - context)
            let high = Swift.min(edits.count - 1, index + context)
            if let last = groups.last, low <= last.upperBound + 1 {
                groups[groups.count - 1] = last.lowerBound...Swift.max(last.upperBound, high)
            } else {
                groups.append(low...high)
            }
        }
        for group in groups {
            var oldCount = 0
            var newCount = 0
            var body: [String] = []
            for edit in edits[group] {
                switch edit {
                case .same(let line):
                    oldCount += 1
                    newCount += 1
                    body.append(" " + line)
                case .delete(let line):
                    oldCount += 1
                    body.append("-" + line)
                case .insert(let line):
                    newCount += 1
                    body.append("+" + line)
                }
            }
            let start = positions[group.lowerBound]
            let oldStart = oldCount == 0 ? start.old - 1 : start.old
            let newStart = newCount == 0 ? start.new - 1 : start.new
            out.append("@@ -\(range(oldStart, oldCount)) +\(range(newStart, newCount)) @@")
            out.append(contentsOf: body)
        }
        return out.joined(separator: "\n") + "\n"
    }

    private static func range(_ start: Int, _ count: Int) -> String {
        count == 1 ? "\(start)" : "\(start),\(count)"
    }
}
