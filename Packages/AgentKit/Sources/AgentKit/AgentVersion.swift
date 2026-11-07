import Foundation

/// An installed agent CLI version, as `AgentAdapter.detectVersion` reports it (AD-23: outside its
/// fixture-tested range an adapter emits no events and reports `unsupported(version)`).
public struct AgentVersion: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The version text as the CLI printed it, trimmed, e.g. `2.1.319 (Claude Code)`.
    public let raw: String
    /// The first `major.minor[.patch]` found in `raw` (a leading `v` is allowed); a missing patch reads as 0.
    public let semver: Semver?

    public struct Semver: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
        public let major: Int
        public let minor: Int
        public let patch: Int

        public init(_ major: Int, _ minor: Int, _ patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        public static func < (lhs: Semver, rhs: Semver) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }

        public var description: String { "\(major).\(minor).\(patch)" }
    }

    public init(raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.raw = trimmed
        self.semver = Self.parse(trimmed)
    }

    public var description: String { semver?.description ?? raw }

    /// Finds the first `[v]<int>.<int>[.<int>]` token, e.g. `2.1.319` in `2.1.319 (Claude Code)` or `1.2` in `v1.2`.
    static func parse(_ text: String) -> Semver? {
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let isBoundary = index == 0 || !isDigit(scalars[index - 1]) && scalars[index - 1] != "."
            if isBoundary, isDigit(scalars[index]) {
                var parts: [Int] = []
                var cursor = index
                while cursor < scalars.count, parts.count < 3 {
                    var digits = ""
                    while cursor < scalars.count, isDigit(scalars[cursor]) {
                        digits.unicodeScalars.append(scalars[cursor])
                        cursor += 1
                    }
                    guard !digits.isEmpty, let value = Int(digits) else { break }
                    parts.append(value)
                    guard cursor < scalars.count, scalars[cursor] == ".", cursor + 1 < scalars.count,
                        isDigit(scalars[cursor + 1])
                    else { break }
                    cursor += 1
                }
                if parts.count >= 2 {
                    return Semver(parts[0], parts[1], parts.count > 2 ? parts[2] : 0)
                }
                index = max(cursor, index + 1)
            } else {
                index += 1
            }
        }
        return nil
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool { ("0"..."9").contains(scalar) }
}
