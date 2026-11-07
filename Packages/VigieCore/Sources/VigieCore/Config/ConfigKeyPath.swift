import Foundation
import ModuleKit

/// A dotted TOML key path such as `general.hover_delay` or `modules."agents.sessions".local.terminal`.
///
/// Segments are raw key names; a module id is always one segment (quoted when it contains a dot), so
/// `modules.time.breaks.work` is key `breaks.work` of module `time`.
public struct ConfigKeyPath: Hashable, Sendable, Comparable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let segments: [String]

    public init(_ segments: [String]) {
        self.segments = segments
    }

    public init(_ segments: String...) {
        self.segments = segments
    }

    /// Parses TOML dotted-key syntax: bare keys (`A-Za-z0-9_-`), `"basic"` (with `\"` and `\\` escapes) or
    /// `'literal'` segments, separated by dots with optional surrounding spaces. Returns nil on bad syntax.
    public init?(parsing text: String) {
        var segments: [String] = []
        var scalars = Array(text.unicodeScalars)[...]

        func skipSpaces() {
            while let first = scalars.first, first == " " || first == "\t" { scalars.removeFirst() }
        }

        while true {
            skipSpaces()
            guard let first = scalars.first else { return nil }
            var segment = ""
            if first == "\"" || first == "'" {
                scalars.removeFirst()
                var closed = false
                while let scalar = scalars.popFirst() {
                    if scalar == first {
                        closed = true
                        break
                    }
                    if first == "\"", scalar == "\\" {
                        guard let escaped = scalars.popFirst() else { return nil }
                        switch escaped {
                        case "\"", "\\": segment.unicodeScalars.append(escaped)
                        case "n": segment += "\n"
                        case "t": segment += "\t"
                        default: return nil
                        }
                    } else {
                        segment.unicodeScalars.append(scalar)
                    }
                }
                guard closed else { return nil }
            } else {
                while let scalar = scalars.first, Self.isBare(scalar) {
                    segment.unicodeScalars.append(scalar)
                    scalars.removeFirst()
                }
                guard !segment.isEmpty else { return nil }
            }
            segments.append(segment)
            skipSpaces()
            guard let next = scalars.popFirst() else { break }
            guard next == "." else { return nil }
        }
        self.segments = segments
    }

    /// For literals in code and tests. Traps on invalid syntax: that is a programming error.
    public init(stringLiteral value: String) {
        guard let path = ConfigKeyPath(parsing: value) else { preconditionFailure("Invalid config key path: \(value)") }
        self = path
    }

    /// `modules."<id>".<key>`; `key` may itself be dotted (`breaks.work`).
    public static func module(_ id: ModuleID, _ key: String, scope: SettingScope = .synced) -> ConfigKeyPath {
        let keySegments = key.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let local = scope == .local ? ["local"] : []
        return ConfigKeyPath(["modules", id.rawValue] + local + keySegments)
    }

    /// `modules."<id>".enabled`.
    public static func moduleEnabled(_ id: ModuleID) -> ConfigKeyPath {
        ConfigKeyPath(["modules", id.rawValue, "enabled"])
    }

    public func appending(_ segment: String) -> ConfigKeyPath {
        ConfigKeyPath(segments + [segment])
    }

    public var parent: ConfigKeyPath? {
        segments.isEmpty ? nil : ConfigKeyPath(Array(segments.dropLast()))
    }

    public func hasPrefix(_ prefix: ConfigKeyPath) -> Bool {
        segments.count >= prefix.segments.count && Array(segments.prefix(prefix.segments.count)) == prefix.segments
    }

    /// Canonical TOML spelling: bare segments when possible, else double-quoted.
    public var description: String {
        segments.map(Self.render).joined(separator: ".")
    }

    public static func < (lhs: ConfigKeyPath, rhs: ConfigKeyPath) -> Bool {
        lhs.segments.lexicographicallyPrecedes(rhs.segments)
    }

    static func isBare(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
            || scalar == "_" || scalar == "-"
    }

    static func render(_ segment: String) -> String {
        if !segment.isEmpty, segment.unicodeScalars.allSatisfy(isBare) { return segment }
        var out = "\""
        for scalar in segment.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
