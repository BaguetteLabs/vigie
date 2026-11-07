import Foundation

/// A JSON value that keeps object key order and number spelling, so editing `~/.claude/settings.json` changes only
/// the lines Vigie adds or removes (AD-22: never reorder other entries). Serialized like `JSON.stringify(v, null, 2)`,
/// which is how Claude Code writes the file.
indirect enum OrderedJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    /// The number exactly as written.
    case number(String)
    case string(String)
    case array([OrderedJSON])
    case object([(key: String, value: OrderedJSON)])

    static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case (.bool(let a), .bool(let b)): a == b
        case (.number(let a), .number(let b)): a == b
        case (.string(let a), .string(let b)): a == b
        case (.array(let a), .array(let b)): a == b
        case (.object(let a), .object(let b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }

    subscript(key: String) -> OrderedJSON? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    // MARK: Serialization

    /// Two-space indentation, `"key": value`, empty containers as `{}` / `[]`, no trailing newline.
    func serialized() -> String {
        var out = ""
        write(to: &out, indent: 0)
        return out
    }

    private func write(to out: inout String, indent: Int) {
        switch self {
        case .null: out += "null"
        case .bool(let value): out += value ? "true" : "false"
        case .number(let text): out += text
        case .string(let value): Self.writeString(value, to: &out)
        case .array(let items):
            guard !items.isEmpty else {
                out += "[]"
                return
            }
            out += "[\n"
            for (index, item) in items.enumerated() {
                out += String(repeating: "  ", count: indent + 1)
                item.write(to: &out, indent: indent + 1)
                out += index < items.count - 1 ? ",\n" : "\n"
            }
            out += String(repeating: "  ", count: indent) + "]"
        case .object(let members):
            guard !members.isEmpty else {
                out += "{}"
                return
            }
            out += "{\n"
            for (index, member) in members.enumerated() {
                out += String(repeating: "  ", count: indent + 1)
                Self.writeString(member.key, to: &out)
                out += ": "
                member.value.write(to: &out, indent: indent + 1)
                out += index < members.count - 1 ? ",\n" : "\n"
            }
            out += String(repeating: "  ", count: indent) + "}"
        }
    }

    private static func writeString(_ value: String, to out: inout String) {
        out += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }

    // MARK: Parsing

    struct ParseError: Error, Equatable {
        let offset: Int
    }

    /// Parses one JSON document (whitespace around it allowed). Throws `ParseError` on anything else.
    static func parse(_ text: String) throws -> OrderedJSON {
        var parser = Parser(scalars: Array(text.unicodeScalars))
        parser.skipWhitespace()
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.scalars.count else { throw ParseError(offset: parser.index) }
        return value
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var index = 0

        static let maxDepth = 256

        var error: ParseError { ParseError(offset: index) }

        mutating func skipWhitespace() {
            while index < scalars.count, [" ", "\n", "\r", "\t"].contains(scalars[index]) { index += 1 }
        }

        mutating func expect(_ literal: String) throws {
            for scalar in literal.unicodeScalars {
                guard index < scalars.count, scalars[index] == scalar else { throw error }
                index += 1
            }
        }

        mutating func value(depth: Int) throws -> OrderedJSON {
            guard depth < Self.maxDepth, index < scalars.count else { throw error }
            switch scalars[index] {
            case "{": return try object(depth: depth)
            case "[": return try array(depth: depth)
            case "\"": return .string(try string())
            case "t":
                try expect("true")
                return .bool(true)
            case "f":
                try expect("false")
                return .bool(false)
            case "n":
                try expect("null")
                return .null
            default: return .number(try number())
            }
        }

        mutating func object(depth: Int) throws -> OrderedJSON {
            index += 1
            var members: [(key: String, value: OrderedJSON)] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "}" {
                index += 1
                return .object(members)
            }
            while true {
                skipWhitespace()
                guard index < scalars.count, scalars[index] == "\"" else { throw error }
                let key = try string()
                skipWhitespace()
                try expect(":")
                skipWhitespace()
                members.append((key, try value(depth: depth + 1)))
                skipWhitespace()
                guard index < scalars.count else { throw error }
                if scalars[index] == "," {
                    index += 1
                } else if scalars[index] == "}" {
                    index += 1
                    return .object(members)
                } else {
                    throw error
                }
            }
        }

        mutating func array(depth: Int) throws -> OrderedJSON {
            index += 1
            var items: [OrderedJSON] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "]" {
                index += 1
                return .array(items)
            }
            while true {
                skipWhitespace()
                items.append(try value(depth: depth + 1))
                skipWhitespace()
                guard index < scalars.count else { throw error }
                if scalars[index] == "," {
                    index += 1
                } else if scalars[index] == "]" {
                    index += 1
                    return .array(items)
                } else {
                    throw error
                }
            }
        }

        mutating func string() throws -> String {
            index += 1
            var result = String.UnicodeScalarView()
            while index < scalars.count {
                let scalar = scalars[index]
                index += 1
                switch scalar {
                case "\"": return String(result)
                case "\\":
                    guard index < scalars.count else { throw error }
                    let escape = scalars[index]
                    index += 1
                    switch escape {
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    case "/": result.append("/")
                    case "b": result.append("\u{08}")
                    case "f": result.append("\u{0C}")
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "t": result.append("\t")
                    case "u":
                        let high = try hex4()
                        if (0xD800...0xDBFF).contains(high) {
                            try expect("\\u")
                            let low = try hex4()
                            guard (0xDC00...0xDFFF).contains(low),
                                let combined = Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))
                            else { throw error }
                            result.append(combined)
                        } else {
                            guard let single = Unicode.Scalar(high) else { throw error }
                            result.append(single)
                        }
                    default: throw error
                    }
                default:
                    guard scalar.value >= 0x20 else { throw error }
                    result.append(scalar)
                }
            }
            throw error
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= scalars.count else { throw error }
            var value: UInt32 = 0
            for scalar in scalars[index..<index + 4] {
                guard let digit = Int(String(scalar), radix: 16) else { throw error }
                value = value * 16 + UInt32(digit)
            }
            index += 4
            return value
        }

        mutating func number() throws -> String {
            let start = index
            if index < scalars.count, scalars[index] == "-" { index += 1 }
            let intStart = index
            while index < scalars.count, ("0"..."9").contains(scalars[index]) { index += 1 }
            guard index > intStart else { throw error }
            if index < scalars.count, scalars[index] == "." {
                index += 1
                let fracStart = index
                while index < scalars.count, ("0"..."9").contains(scalars[index]) { index += 1 }
                guard index > fracStart else { throw error }
            }
            if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
                index += 1
                if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" { index += 1 }
                let expStart = index
                while index < scalars.count, ("0"..."9").contains(scalars[index]) { index += 1 }
                guard index > expStart else { throw error }
            }
            return String(String.UnicodeScalarView(scalars[start..<index]))
        }
    }
}
