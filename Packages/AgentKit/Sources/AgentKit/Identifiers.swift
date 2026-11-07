import Foundation

/// An agent adapter id: a lowercase single word, stable forever (Conventions: Adapter ids), e.g. `claude`,
/// `codex`, `gemini`. It is the `agent` of `vigie hook <agent>` and the first half of a session identity (AD-5).
public struct AgentID: AdapterIdentifier {
    public let rawValue: String

    public init?(_ rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }
}

/// A terminal adapter id: a lowercase single word (Conventions: Adapter ids): `terminal`, `warp`, `ghostty`,
/// `iterm`.
public struct TerminalID: AdapterIdentifier {
    public let rawValue: String

    public init?(_ rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }
}

/// Shared shape of `AgentID` and `TerminalID`: one segment that starts with a lowercase ASCII letter and
/// contains only lowercase ASCII letters, digits, `_` or `-`.
public protocol AdapterIdentifier: Hashable, Sendable, Codable, Comparable, CustomStringConvertible,
    ExpressibleByStringLiteral
{
    var rawValue: String { get }
    init?(_ rawValue: String)
}

extension AdapterIdentifier {
    /// For literals in adapters. Traps on an invalid literal: that is a programming error.
    public init(stringLiteral value: String) {
        guard let id = Self(value) else { preconditionFailure("Invalid adapter id literal: \(value)") }
        self = id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let id = Self(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid adapter id: \(raw)")
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func isValid(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first, ("a"..."z").contains(first) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-"
        }
    }
}
