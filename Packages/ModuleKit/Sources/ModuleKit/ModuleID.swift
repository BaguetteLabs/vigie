import Foundation

/// A module identifier: lowercase dotted, stable forever (Conventions: Module ids).
///
/// Each dot-separated segment is non-empty, starts with a lowercase ASCII letter and contains only
/// lowercase ASCII letters, digits, `_` or `-`. Examples: `agents.sessions`, `shelf`, `dev.sample`.
public struct ModuleID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    /// Returns nil when `rawValue` is not a valid module id (empty, uppercase, whitespace, empty segment, ...).
    public init?(_ rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// For literals in manifests. Traps on an invalid literal: that is a programming error.
    /// Note: `ModuleID("literal")` also takes this path (SE-0213); use a `String` value to get the failable init.
    public init(stringLiteral value: String) {
        guard let id = ModuleID(value) else { preconditionFailure("Invalid module id literal: \(value)") }
        self = id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let id = ModuleID(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid module id: \(raw)")
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static func < (lhs: ModuleID, rhs: ModuleID) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        return segments.allSatisfy { segment in
            guard let first = segment.unicodeScalars.first, ("a"..."z").contains(first) else { return false }
            return segment.unicodeScalars.allSatisfy { scalar in
                ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-"
            }
        }
    }
}
