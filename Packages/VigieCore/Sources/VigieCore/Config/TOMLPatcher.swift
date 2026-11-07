import Foundation

/// A value the patcher can write: one TOML scalar or an inline array of them.
public enum TOMLScalar: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    /// Written as a quoted duration string (`ConfigDuration.format`), e.g. `"1h30m"`.
    case duration(Duration)
    case array([TOMLScalar])

    /// TOML spelling: basic strings with escapes, floats without exponent, inline arrays `["a", "b"]`.
    public var tomlText: String {
        switch self {
        case .bool(let value): value ? "true" : "false"
        case .int(let value): String(value)
        case .double(let value): Self.format(value)
        case .string(let value): Self.quote(value)
        case .duration(let value): Self.quote(ConfigDuration.format(value))
        case .array(let items): "[" + items.map(\.tomlText).joined(separator: ", ") + "]"
        }
    }

    /// The value swift-toml decodes from `tomlText`; the writer compares it after re-parsing.
    public var configValue: ConfigValue {
        switch self {
        case .bool(let value): .bool(value)
        case .int(let value): .int(value)
        case .double(let value): .double(value)
        case .string(let value): .string(value)
        case .duration(let value): .string(ConfigDuration.format(value))
        case .array(let items): .array(items.map(\.configValue))
        }
    }

    static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// Shortest round-tripping decimal spelling, never with an exponent, always with a fraction (`2.0`).
    static func format(_ value: Double) -> String {
        if value.isNaN { return "nan" }
        if value.isInfinite { return value < 0 ? "-inf" : "inf" }
        let text = "\(value)"
        guard let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }),
            let exponent = Int(text[text.index(after: e)...])
        else { return text.contains(".") ? text : text + ".0" }
        var mantissa = Substring(text[..<e])
        let sign = mantissa.hasPrefix("-") ? "-" : ""
        if !sign.isEmpty { mantissa = mantissa.dropFirst() }
        let parts = mantissa.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integer = String(parts[0])
        let digits = integer + (parts.count > 1 ? String(parts[1]) : "")
        let point = integer.count + exponent
        var whole: String
        var fraction: String
        if point <= 0 {
            whole = "0"
            fraction = String(repeating: "0", count: -point) + digits
        } else if point >= digits.count {
            whole = digits + String(repeating: "0", count: point - digits.count)
            fraction = ""
        } else {
            whole = String(digits.prefix(point))
            fraction = String(digits.dropFirst(point))
        }
        while whole.count > 1, whole.hasPrefix("0") { whole.removeFirst() }
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return sign + whole + "." + (fraction.isEmpty ? "0" : fraction)
    }
}

public enum TOMLPatchError: Error, Equatable, Sendable {
    /// The key lives (or would live) inside an inline table, an array of tables, or under a non-table
    /// value; the line patcher does not edit those.
    case unsupportedLocation(ConfigKeyPath)
    /// The text could not be split into TOML statements (1-based line).
    case malformed(line: Int)
    case emptyPath
}

/// ConfigStore's line-level TOML patcher (AD-8). It replaces, inserts or removes a single `key = value`
/// statement and leaves every other byte as it was: comments, blank lines, ordering, unknown keys, line
/// endings (LF or CRLF), a byte-order mark and the presence of a final newline.
///
/// swift-toml is decode only (AD-16); this is the only code that produces TOML text.
public enum TOMLPatcher {
    /// Sets `path` to `value`: replaces the value of its existing statement (keeping indentation, the
    /// spacing around `=` and any trailing comment), or inserts `key = value` into its table, creating the
    /// table at the end of the file when it does not exist.
    public static func set(_ text: String, path: ConfigKeyPath, value: TOMLScalar) throws(TOMLPatchError) -> String {
        guard !path.segments.isEmpty else { throw .emptyPath }
        var file = try PatchFile(text)
        try file.checkEditable(path)
        if let index = file.entryIndex(path) {
            file.replaceValue(of: index, with: value.tomlText)
        } else {
            file.insert(path, valueText: value.tomlText)
        }
        return file.render()
    }

    /// Removes the statement that defines `path`. Text without it is returned unchanged.
    public static func remove(_ text: String, path: ConfigKeyPath) throws(TOMLPatchError) -> String {
        guard !path.segments.isEmpty else { throw .emptyPath }
        var file = try PatchFile(text)
        guard let index = file.entryIndex(path) else {
            try file.checkEditable(path)
            return text
        }
        try file.checkEditable(path)
        file.removeStatement(index)
        return file.render()
    }
}

// MARK: - Lines and statements

private typealias Scalars = [Unicode.Scalar]

private struct Cursor {
    var line: Int
    var column: Int
}

private struct PatchLine {
    var content: Scalars
    /// `\n`, `\r\n`, or empty for a last line without a newline.
    var terminator: String
}

private struct Statement {
    enum Kind {
        case blank
        case comment
        case header(ConfigKeyPath, isArray: Bool)
        /// `key` relative to `table`; the value spans `valueStart..<valueEnd`.
        case entry(key: ConfigKeyPath, valueStart: Cursor, valueEnd: Cursor)
    }

    let kind: Kind
    let firstLine: Int
    let lastLine: Int
    /// The table this statement belongs to (for a header, the table it opens).
    let table: ConfigKeyPath
    /// Index of the header that opened `table`, nil for the root table.
    let headerIndex: Int?

    var fullPath: ConfigKeyPath? {
        guard case .entry(let key, _, _) = kind else { return nil }
        return ConfigKeyPath(table.segments + key.segments)
    }

    var isEntry: Bool {
        if case .entry = kind { return true }
        return false
    }
}

private struct PatchFile {
    var bom: Bool
    var newline: String
    var lines: [PatchLine]
    var statements: [Statement] = []

    init(_ text: String) throws(TOMLPatchError) {
        var scalars = Scalars(text.unicodeScalars)
        bom = scalars.first == "\u{FEFF}"
        if bom { scalars.removeFirst() }
        lines = []
        var current: Scalars = []
        var sawCRLF = false
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\n" {
                lines.append(PatchLine(content: current, terminator: "\n"))
                current = []
            } else if scalar == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" {
                lines.append(PatchLine(content: current, terminator: "\r\n"))
                current = []
                sawCRLF = true
                index += 1
            } else {
                current.append(scalar)
            }
            index += 1
        }
        if !current.isEmpty { lines.append(PatchLine(content: current, terminator: "")) }
        newline = sawCRLF ? "\r\n" : "\n"
        statements = try Self.parse(lines.map(\.content))
    }

    func render() -> String {
        var out = String.UnicodeScalarView()
        if bom { out.append("\u{FEFF}") }
        for line in lines {
            out.append(contentsOf: line.content)
            out.append(contentsOf: line.terminator.unicodeScalars)
        }
        return String(out)
    }

    // MARK: Lookup

    func entryIndex(_ path: ConfigKeyPath) -> Int? {
        statements.firstIndex { $0.fullPath == path }
    }

    func headerIndex(_ path: ConfigKeyPath) -> Int? {
        statements.firstIndex {
            if case .header(let header, false) = $0.kind { return header == path }
            return false
        }
    }

    /// Throws when `path` sits in an array of tables, inside an inline table (or under any non-table value),
    /// or names a table rather than a value.
    func checkEditable(_ path: ConfigKeyPath) throws(TOMLPatchError) {
        for statement in statements {
            switch statement.kind {
            case .header(let header, let isArray):
                if isArray, path.hasPrefix(header) { throw .unsupportedLocation(path) }
                if header.hasPrefix(path) { throw .unsupportedLocation(path) }
            case .entry:
                guard let full = statement.fullPath, full != path else { continue }
                if path.hasPrefix(full) || full.hasPrefix(path) { throw .unsupportedLocation(path) }
            case .blank, .comment:
                continue
            }
        }
    }

    /// Statement indices of a table's body: after its header up to the next header. The root table is
    /// everything before the first header.
    func body(ofHeader header: Int?) -> Range<Int> {
        let start = header.map { $0 + 1 } ?? 0
        var end = start
        while end < statements.count {
            if case .header = statements[end].kind { break }
            end += 1
        }
        return start..<end
    }

    // MARK: Edits

    mutating func replaceValue(of index: Int, with valueText: String) {
        guard case .entry(_, let start, let end) = statements[index].kind else { return }
        let prefix = lines[start.line].content[..<start.column]
        let suffix = lines[end.line].content[end.column...]
        let merged = PatchLine(
            content: Scalars(prefix) + Scalars(valueText.unicodeScalars) + Scalars(suffix),
            terminator: lines[end.line].terminator)
        lines.replaceSubrange(start.line...end.line, with: [merged])
    }

    mutating func removeStatement(_ index: Int) {
        let statement = statements[index]
        let wasLast = statement.lastLine == lines.count - 1
        let hadNewline = !lines[statement.lastLine].terminator.isEmpty
        lines.removeSubrange(statement.firstLine...statement.lastLine)
        if wasLast, !hadNewline, !lines.isEmpty { lines[lines.count - 1].terminator = "" }
    }

    mutating func insert(_ path: ConfigKeyPath, valueText: String) {
        let parent = ConfigKeyPath(Array(path.segments.dropLast()))

        // 1. The table has a header.
        if let header = headerIndex(parent) {
            let key = ConfigKeyPath([path.segments.last!])
            insert(key: key, valueText: valueText, intoTableWithHeader: header)
            return
        }

        // 2. The table is defined by dotted keys in an ancestor table: add one more dotted key next to them.
        if parent.segments.count > 0 {
            for depth in stride(from: parent.segments.count - 1, through: 0, by: -1) {
                let tablePath = ConfigKeyPath(Array(path.segments.prefix(depth)))
                let header: Int?
                if depth == 0 {
                    header = nil
                } else if let found = headerIndex(tablePath) {
                    header = found
                } else {
                    continue
                }
                let range = body(ofHeader: header)
                guard
                    let last = range.last(where: { index in
                        statements[index].fullPath.map { $0.hasPrefix(parent) } ?? false
                    })
                else { continue }
                let key = ConfigKeyPath(Array(path.segments.dropFirst(depth)))
                let line = indentation(of: statements[last]) + key.description + " = " + valueText
                insertLines([line], at: statements[last].lastLine + 1)
                return
            }
        }

        // 3. A root key.
        if parent.segments.isEmpty {
            insert(key: path, valueText: valueText, intoTableWithHeader: nil)
            return
        }

        // 4. A new table at the end of the file.
        var newLines: [String] = []
        if let last = lines.last, !last.content.allSatisfy(Self.isSpace) { newLines.append("") }
        newLines.append("[" + parent.description + "]")
        newLines.append(ConfigKeyPath([path.segments.last!]).description + " = " + valueText)
        insertLines(newLines, at: lines.count)
    }

    /// Inserts `key = value` into a table: right after a commented default of the same key in the table's
    /// block, else after its last key, else right after its header. An empty root table gets the key just
    /// before the first header (and its attached comments), else at the end of the file.
    private mutating func insert(key: ConfigKeyPath, valueText: String, intoTableWithHeader header: Int?) {
        let range = body(ofHeader: header)
        let lastEntry = range.last { statements[$0].isEntry }
        var blockEnd = lastEntry ?? header ?? (range.lowerBound - 1)
        while blockEnd + 1 < range.upperBound, case .comment = statements[blockEnd + 1].kind { blockEnd += 1 }

        let text = key.description + " = " + valueText
        if blockEnd >= range.lowerBound {
            for index in range.lowerBound...blockEnd where commentedKey(statements[index]) == key {
                insertLines([indentation(of: statements[index]) + text], at: statements[index].lastLine + 1)
                return
            }
        }
        if let lastEntry {
            insertLines([indentation(of: statements[lastEntry]) + text], at: statements[lastEntry].lastLine + 1)
        } else if let header {
            insertLines([indentation(of: statements[header]) + text], at: statements[header].lastLine + 1)
        } else if range.upperBound < statements.count {
            var position = range.upperBound
            while position > range.lowerBound, case .comment = statements[position - 1].kind { position -= 1 }
            insertLines([text, ""], at: statements[position].firstLine)
        } else {
            insertLines([text], at: lines.count)
        }
    }

    private mutating func insertLines(_ texts: [String], at position: Int) {
        var new = texts.map { PatchLine(content: Scalars($0.unicodeScalars), terminator: newline) }
        if position == lines.count, let last = lines.last, last.terminator.isEmpty {
            lines[lines.count - 1].terminator = newline
            new[new.count - 1].terminator = ""
        }
        lines.insert(contentsOf: new, at: position)
    }

    private func indentation(of statement: Statement) -> String {
        var out = String.UnicodeScalarView()
        out.append(contentsOf: lines[statement.firstLine].content.prefix(while: Self.isSpace))
        return String(out)
    }

    /// For `# key = value`, the key; nil for other comments.
    private func commentedKey(_ statement: Statement) -> ConfigKeyPath? {
        guard case .comment = statement.kind else { return nil }
        let content = lines[statement.firstLine].content
        guard var start = content.firstIndex(of: "#") else { return nil }
        start += 1
        while start < content.count, content[start] == "#" || Self.isSpace(content[start]) { start += 1 }
        guard let equals = Self.find("=", in: content, from: start) else { return nil }
        return ConfigKeyPath(parsing: Self.string(content[start..<equals]))
    }

    // MARK: Parsing

    static func isSpace(_ scalar: Unicode.Scalar) -> Bool { scalar == " " || scalar == "\t" }

    static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars)
        return String(out)
    }

    /// Index of the first `target` outside quoted strings on the line, from `start`.
    static func find(_ target: Unicode.Scalar, in line: Scalars, from start: Int) -> Int? {
        var index = start
        while index < line.count {
            let scalar = line[index]
            if scalar == target { return index }
            if scalar == "\"" || scalar == "'" {
                guard let end = closingQuote(scalar, in: line, from: index + 1) else { return nil }
                index = end + 1
                continue
            }
            index += 1
        }
        return nil
    }

    /// Index of the quote closing a single-line string that opened before `start`.
    static func closingQuote(_ quote: Unicode.Scalar, in line: Scalars, from start: Int) -> Int? {
        var index = start
        while index < line.count {
            if quote == "\"", line[index] == "\\" {
                index += 2
                continue
            }
            if line[index] == quote { return index }
            index += 1
        }
        return nil
    }

    static func parse(_ lines: [Scalars]) throws(TOMLPatchError) -> [Statement] {
        var statements: [Statement] = []
        var table = ConfigKeyPath([])
        var tableHeader: Int?
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let start = line.firstIndex { !isSpace($0) } ?? line.count
            if start == line.count {
                statements.append(
                    Statement(
                        kind: .blank, firstLine: lineIndex, lastLine: lineIndex, table: table, headerIndex: tableHeader)
                )
                lineIndex += 1
            } else if line[start] == "#" {
                statements.append(
                    Statement(
                        kind: .comment, firstLine: lineIndex, lastLine: lineIndex, table: table,
                        headerIndex: tableHeader))
                lineIndex += 1
            } else if line[start] == "[" {
                let isArray = start + 1 < line.count && line[start + 1] == "["
                let keyStart = start + (isArray ? 2 : 1)
                guard let close = find("]", in: line, from: keyStart),
                    !isArray || (close + 1 < line.count && line[close + 1] == "]"),
                    let path = ConfigKeyPath(parsing: string(line[keyStart..<close]))
                else { throw .malformed(line: lineIndex + 1) }
                table = path
                tableHeader = statements.count
                statements.append(
                    Statement(
                        kind: .header(path, isArray: isArray), firstLine: lineIndex, lastLine: lineIndex,
                        table: path, headerIndex: tableHeader))
                lineIndex += 1
            } else {
                guard let equals = find("=", in: line, from: start),
                    let key = ConfigKeyPath(parsing: string(line[start..<equals]))
                else { throw .malformed(line: lineIndex + 1) }
                var valueStart = equals + 1
                while valueStart < line.count, isSpace(line[valueStart]) { valueStart += 1 }
                let begin = Cursor(line: lineIndex, column: valueStart)
                let end = try scanValue(lines, from: begin)
                statements.append(
                    Statement(
                        kind: .entry(key: key, valueStart: begin, valueEnd: end), firstLine: lineIndex,
                        lastLine: end.line, table: table, headerIndex: tableHeader))
                lineIndex = end.line + 1
            }
        }
        return statements
    }

    /// The end (exclusive) of the value starting at `start`, which may span lines (multi-line strings,
    /// arrays, inline tables).
    static func scanValue(_ lines: [Scalars], from start: Cursor) throws(TOMLPatchError) -> Cursor {
        let line = lines[start.line]
        let column = start.column
        guard column < line.count, line[column] != "#" else { throw .malformed(line: start.line + 1) }
        let first = line[column]
        if first == "\"" || first == "'" {
            if column + 2 < line.count, line[column + 1] == first, line[column + 2] == first {
                return try scanMultilineString(first, lines, from: Cursor(line: start.line, column: column + 3))
            }
            guard let close = closingQuote(first, in: line, from: column + 1) else {
                throw .malformed(line: start.line + 1)
            }
            return Cursor(line: start.line, column: close + 1)
        }
        if first == "[" || first == "{" {
            return try scanBracketed(lines, from: start)
        }
        var end = column
        while end < line.count, line[end] != "#" { end += 1 }
        while end > column, isSpace(line[end - 1]) { end -= 1 }
        return Cursor(line: start.line, column: end)
    }

    static func scanMultilineString(_ quote: Unicode.Scalar, _ lines: [Scalars], from start: Cursor)
        throws(TOMLPatchError) -> Cursor
    {
        var cursor = start
        while cursor.line < lines.count {
            let line = lines[cursor.line]
            while cursor.column < line.count {
                if quote == "\"", line[cursor.column] == "\\" {
                    cursor.column += 2
                    continue
                }
                if line[cursor.column] == quote, cursor.column + 2 < line.count, line[cursor.column + 1] == quote,
                    line[cursor.column + 2] == quote
                {
                    var end = cursor.column + 3
                    var extra = 0
                    while extra < 2, end < line.count, line[end] == quote {
                        end += 1
                        extra += 1
                    }
                    return Cursor(line: cursor.line, column: end)
                }
                cursor.column += 1
            }
            cursor = Cursor(line: cursor.line + 1, column: 0)
        }
        throw .malformed(line: start.line + 1)
    }

    static func scanBracketed(_ lines: [Scalars], from start: Cursor) throws(TOMLPatchError) -> Cursor {
        var depth = 0
        var cursor = start
        while cursor.line < lines.count {
            let line = lines[cursor.line]
            guard cursor.column < line.count else {
                cursor = Cursor(line: cursor.line + 1, column: 0)
                continue
            }
            let scalar = line[cursor.column]
            switch scalar {
            case "#":
                cursor.column = line.count
            case "\"", "'":
                if cursor.column + 2 < line.count, line[cursor.column + 1] == scalar, line[cursor.column + 2] == scalar
                {
                    cursor = try scanMultilineString(
                        scalar, lines, from: Cursor(line: cursor.line, column: cursor.column + 3))
                } else {
                    guard let close = closingQuote(scalar, in: line, from: cursor.column + 1) else {
                        throw .malformed(line: cursor.line + 1)
                    }
                    cursor.column = close + 1
                }
            case "[", "{":
                depth += 1
                cursor.column += 1
            case "]", "}":
                depth -= 1
                cursor.column += 1
                if depth == 0 { return cursor }
            default:
                cursor.column += 1
            }
        }
        throw .malformed(line: start.line + 1)
    }
}
