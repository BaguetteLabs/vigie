import Foundation

/// Any key of a JSON or YAML object, so the schema decoders can list unknown keys (front matter) and name every
/// key in their errors.
struct SchemaKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init(_ name: String) {
        stringValue = name
        intValue = nil
    }

    init?(stringValue: String) { self.init(stringValue) }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

/// One object of a script document, read with the schema's rules (Story 12.1): a key that is present must have
/// the declared type (`null` counts as a wrong type, as in the JSON Schema), every failure is a
/// ``ScriptSchemaError`` naming the key.
struct SchemaObject {
    let container: KeyedDecodingContainer<SchemaKey>
    let codingPath: [any CodingKey]

    init(_ decoder: any Decoder) throws {
        do {
            container = try decoder.container(keyedBy: SchemaKey.self)
        } catch {
            throw ScriptSchemaError(decoder.codingPath, .wrongType(expected: .object))
        }
        codingPath = decoder.codingPath
    }

    func path(_ key: String) -> [any CodingKey] { codingPath + [SchemaKey(key)] }

    func has(_ key: String) -> Bool { container.contains(SchemaKey(key)) }

    /// Rejects the first unknown key (alphabetically, so the message is stable).
    func rejectUnknownKeys(allowed: Set<String>) throws {
        if let unknown = container.allKeys.map(\.stringValue).filter({ !allowed.contains($0) }).sorted().first {
            throw ScriptSchemaError(path(unknown), .unknownKey)
        }
    }

    /// Decodes `key` when present; nil when absent. Errors thrown by nested schema types pass through.
    func optional<T: Decodable>(_ type: T.Type, _ key: String, expected: ScriptSchemaError.ValueKind) throws -> T? {
        let codingKey = SchemaKey(key)
        guard container.contains(codingKey) else { return nil }
        if (try? container.decodeNil(forKey: codingKey)) == true {
            throw ScriptSchemaError(path(key), .wrongType(expected: expected))
        }
        do {
            return try container.decode(T.self, forKey: codingKey)
        } catch let error as ScriptSchemaError {
            throw error
        } catch {
            throw ScriptSchemaError(path(key), .wrongType(expected: expected))
        }
    }

    func required<T: Decodable>(_ type: T.Type, _ key: String, expected: ScriptSchemaError.ValueKind) throws -> T {
        guard let value = try optional(type, key, expected: expected) else {
            throw ScriptSchemaError(path(key), .missingKey)
        }
        return value
    }

    func string(_ key: String) throws -> String? { try optional(String.self, key, expected: .string) }
    func int(_ key: String) throws -> Int? { try optional(Int.self, key, expected: .integer) }
    func double(_ key: String) throws -> Double? { try optional(Double.self, key, expected: .number) }
    func bool(_ key: String) throws -> Bool? { try optional(Bool.self, key, expected: .boolean) }
    func strings(_ key: String) throws -> [String]? {
        guard let items = try optional([SchemaString].self, key, expected: .array) else { return nil }
        return items.map(\.value)
    }

    /// A non-empty string (`minLength: 1`).
    func nonEmptyString(_ key: String) throws -> String? {
        guard let value = try string(key) else { return nil }
        guard !value.isEmpty else { throw ScriptSchemaError(path(key), .empty) }
        return value
    }

    /// A string from a fixed set (a JSON Schema `enum`); an unknown value names the key and the options.
    func choice<T: RawRepresentable & CaseIterable>(_ type: T.Type, _ key: String) throws -> T?
    where T.RawValue == String {
        guard let raw = try string(key) else { return nil }
        guard let value = T(rawValue: raw) else {
            throw ScriptSchemaError(path(key), .unknownValue(raw, allowed: T.allCases.map(\.rawValue)))
        }
        return value
    }

    /// The document's `schema` version (absent: 1); a version this Vigie does not read is rejected.
    func schemaVersion() throws -> ScriptSchemaVersion {
        guard let raw = try int("schema") else { return .absent }
        guard let version = ScriptSchemaVersion(rawValue: raw) else {
            throw ScriptSchemaError(
                path("schema"), .unsupportedSchema(raw, supported: ScriptSchemaVersion.current.rawValue))
        }
        return version
    }
}

/// An array element that must be a string; a wrong element names its index (`surfaces[1]`).
struct SchemaString: Decodable {
    let value: String

    init(from decoder: any Decoder) throws {
        let container: any SingleValueDecodingContainer
        do {
            container = try decoder.singleValueContainer()
            if container.decodeNil() { throw ScriptSchemaError(decoder.codingPath, .wrongType(expected: .string)) }
            value = try container.decode(String.self)
        } catch let error as ScriptSchemaError {
            throw error
        } catch {
            throw ScriptSchemaError(decoder.codingPath, .wrongType(expected: .string))
        }
    }
}

/// `widget.value`: a string, or a number kept as printed (`3`, `2.5`).
struct SchemaText: Decodable {
    let value: String

    init(from decoder: any Decoder) throws {
        let failure = ScriptSchemaError(decoder.codingPath, .wrongType(expected: .stringOrNumber))
        guard let container = try? decoder.singleValueContainer(), !container.decodeNil() else { throw failure }
        if let text = try? container.decode(String.self) {
            value = text
        } else if (try? container.decode(Bool.self)) != nil {
            throw failure
        } else if let integer = try? container.decode(Int.self) {
            value = String(integer)
        } else if let number = try? container.decode(Double.self), number.isFinite {
            value = String(number)
        } else {
            throw failure
        }
    }
}
