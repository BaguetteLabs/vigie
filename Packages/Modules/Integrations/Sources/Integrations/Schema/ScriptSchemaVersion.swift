/// The `schema` version a script's front matter or output is written for (FR107, Story 12.1).
///
/// Optional in both documents (default 1). Bumped on every breaking change to
/// `schemas/script-module.schema.json` (`schemas/README.md`); a version this Vigie does not read is rejected with
/// ``ScriptSchemaError/Reason/unsupportedSchema(_:supported:)``.
public struct ScriptSchemaVersion: RawRepresentable, Hashable, Comparable, Sendable, Codable {
    public let rawValue: Int

    /// Versions this Vigie reads (the schema's `schemaVersion` enum).
    public static let supported: ClosedRange<Int> = 1...1
    public static let current = ScriptSchemaVersion(uncheckedRawValue: supported.upperBound)

    /// nil for a version outside ``supported``.
    public init?(rawValue: Int) {
        guard Self.supported.contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    private init(uncheckedRawValue: Int) { rawValue = uncheckedRawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw: Int
        do { raw = try container.decode(Int.self) } catch {
            throw ScriptSchemaError(decoder.codingPath, .wrongType(expected: .integer))
        }
        guard let version = ScriptSchemaVersion(rawValue: raw) else {
            throw ScriptSchemaError(decoder.codingPath, .unsupportedSchema(raw, supported: Self.current.rawValue))
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
