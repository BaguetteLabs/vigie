import Foundation

/// A tiny deterministic TOML writer for generated theme files. swift-toml is decode only (AD-16), so the
/// generator writes text itself: sorted keys, one table per header, quoted and escaped strings.
public indirect enum TOMLNode: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case table([String: TOMLNode])
}

public enum TOMLEmitter {
    /// Emits a document. `leadingKeys` are written first at the top level (e.g. `schema`, `id`), then the rest
    /// sorted. Tables with no scalar keys of their own get no header (their sub-tables carry dotted headers).
    public static func emit(_ root: [String: TOMLNode], header: String, leadingKeys: [String] = []) -> String {
        var out = header.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "# \($0)".trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        out += "\n\n"
        let scalars = root.filter { if case .table = $0.value { false } else { true } }
        let ordered =
            leadingKeys.filter { scalars[$0] != nil }
            + scalars.keys.filter { !leadingKeys.contains($0) }.sorted()
        for key in ordered {
            out += "\(bareOrQuoted(key)) = \(scalar(scalars[key]!))\n"
        }
        emitTables(root, path: [], into: &out)
        return out
    }

    private static func emitTables(_ table: [String: TOMLNode], path: [String], into out: inout String) {
        for key in table.keys.sorted() {
            guard case .table(let child) = table[key]! else { continue }
            let childPath = path + [key]
            let scalars = child.filter { if case .table = $0.value { false } else { true } }
            if !scalars.isEmpty || child.isEmpty {
                out += "\n[\(childPath.map(bareOrQuoted).joined(separator: "."))]\n"
                for scalarKey in scalars.keys.sorted() {
                    out += "\(bareOrQuoted(scalarKey)) = \(scalar(scalars[scalarKey]!))\n"
                }
            }
            emitTables(child, path: childPath, into: &out)
        }
    }

    private static func scalar(_ node: TOMLNode) -> String {
        switch node {
        case .string(let s): quoted(s)
        case .integer(let i): String(i)
        case .table: ""
        }
    }

    static func bareOrQuoted(_ key: String) -> String {
        let bare =
            !key.isEmpty
            && key.unicodeScalars.allSatisfy { scalar in
                ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
                    || scalar == "-" || scalar == "_"
            }
        return bare ? key : quoted(key)
    }

    /// TOML basic string with escapes.
    static func quoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
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
}
