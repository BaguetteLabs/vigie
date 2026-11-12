import Foundation

/// A setting a script declares in its front matter (SPEC §9.1, §4.4; `#/$defs/setting` in the schema).
///
/// Strict like the front matter: unknown keys are rejected, and each type accepts only its own keys (a `secret`
/// never has a `default`). The value reaches the script as `VIGIE_SETTING_<KEY>` (Story 12.4).
public struct ScriptSetting: Equatable, Sendable, Codable {
    /// Host-owned keys a script setting may not use (AD-18).
    public static let reservedKeys: Set<String> = ["enabled", "side", "priority", "surfaces", "notify"]

    /// snake_case, not reserved.
    public var key: String
    public var label: String
    public var help: String?
    public var kind: Kind

    /// The declared type with its options and default (defaults applied as the schema states).
    public enum Kind: Equatable, Sendable {
        case bool(default: Bool)
        case int(default: Int, min: Int?, max: Int?, step: Int?)
        case double(default: Double, min: Double?, max: Double?, step: Double?)
        case string(default: String)
        /// Kept only in SecretStore on each Mac (AD-9); no default.
        case secret
        case enumeration(options: [String], default: String)
        /// `raw` is the default as written (passed to the script as is), `value` its parsed duration.
        case duration(default: Duration, raw: String)
        case path(default: String?)
        case list(of: ListElement, default: [String])

        /// The `type` key's value.
        public var typeName: TypeName {
            switch self {
            case .bool: .bool
            case .int: .int
            case .double: .double
            case .string: .string
            case .secret: .secret
            case .enumeration: .enumeration
            case .duration: .duration
            case .path: .path
            case .list: .list
            }
        }
    }

    /// Values of the `type` key (SPEC §4.4 without `hotkey`: a script cannot register a hotkey).
    public enum TypeName: String, CaseIterable, Sendable {
        case bool, int, double, string, secret
        case enumeration = "enum"
        case duration, path, list
    }

    /// Element type of a `list` setting (`of`, default `string`).
    public enum ListElement: String, CaseIterable, Sendable, Codable {
        case string, path
    }

    public init(key: String, label: String, help: String? = nil, kind: Kind) {
        self.key = key
        self.label = label
        self.help = help
        self.kind = kind
    }

    /// Keys every type accepts, then each type's own.
    static let commonKeys: Set<String> = ["key", "type", "label", "help"]
    static func keys(for type: TypeName) -> Set<String> {
        switch type {
        case .bool, .string, .duration, .path: commonKeys.union(["default"])
        case .int, .double: commonKeys.union(["default", "min", "max", "step"])
        case .secret: commonKeys
        case .enumeration: commonKeys.union(["options", "default"])
        case .list: commonKeys.union(["of", "default"])
        }
    }

    public init(from decoder: any Decoder) throws {
        let object = try SchemaObject(decoder)
        // `type` first: it decides which keys are known.
        guard let type = try object.choice(TypeName.self, "type") else {
            throw ScriptSchemaError(object.path("type"), .missingKey)
        }
        try object.rejectUnknownKeys(allowed: Self.keys(for: type))

        let key = try object.required(String.self, "key", expected: .string)
        guard Self.isSnakeCase(key) else {
            throw ScriptSchemaError(object.path("key"), .invalidFormat(key, .settingKey))
        }
        guard !Self.reservedKeys.contains(key) else { throw ScriptSchemaError(object.path("key"), .reservedKey(key)) }
        self.key = key

        guard let label = try object.nonEmptyString("label") else {
            throw ScriptSchemaError(object.path("label"), .missingKey)
        }
        self.label = label
        help = try object.string("help")
        kind = try Self.decodeKind(type, object)
    }

    private static func decodeKind(_ type: TypeName, _ object: SchemaObject) throws -> Kind {
        switch type {
        case .bool:
            return .bool(default: try object.bool("default") ?? false)
        case .int:
            let step = try object.int("step")
            if let step, step < 1 { throw ScriptSchemaError(object.path("step"), .notPositive) }
            return .int(
                default: try object.int("default") ?? 0, min: try object.int("min"), max: try object.int("max"),
                step: step)
        case .double:
            let step = try object.double("step")
            if let step, !(step > 0) { throw ScriptSchemaError(object.path("step"), .notPositive) }
            return .double(
                default: try object.double("default") ?? 0, min: try object.double("min"),
                max: try object.double("max"), step: step)
        case .string:
            return .string(default: try object.string("default") ?? "")
        case .secret:
            return .secret
        case .enumeration:
            guard let options = try object.strings("options") else {
                throw ScriptSchemaError(object.path("options"), .missingKey)
            }
            guard !options.isEmpty else { throw ScriptSchemaError(object.path("options"), .empty) }
            for (index, option) in options.enumerated() {
                let itemPath = object.path("options") + [SchemaKey(intValue: index)!]
                if option.isEmpty { throw ScriptSchemaError(itemPath, .empty) }
                if options[..<index].contains(option) { throw ScriptSchemaError(itemPath, .duplicate(option)) }
            }
            let value = try object.required(String.self, "default", expected: .string)
            return .enumeration(options: options, default: value)
        case .duration:
            let raw = try object.required(String.self, "default", expected: .string)
            guard let value = ScriptDuration.parse(raw) else {
                throw ScriptSchemaError(object.path("default"), .invalidFormat(raw, .duration))
            }
            return .duration(default: value, raw: raw)
        case .path:
            return .path(default: try object.string("default"))
        case .list:
            return .list(
                of: try object.choice(ListElement.self, "of") ?? .string,
                default: try object.strings("default") ?? [])
        }
    }

    /// `^[a-z][a-z0-9_]*$`
    static func isSnakeCase(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first, ("a"..."z").contains(first) else { return false }
        return value.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SchemaKey.self)
        try container.encode(key, forKey: SchemaKey("key"))
        try container.encode(kind.typeName.rawValue, forKey: SchemaKey("type"))
        try container.encode(label, forKey: SchemaKey("label"))
        try container.encodeIfPresent(help, forKey: SchemaKey("help"))
        let defaultKey = SchemaKey("default")
        switch kind {
        case .bool(let value):
            try container.encode(value, forKey: defaultKey)
        case .int(let value, let min, let max, let step):
            try container.encode(value, forKey: defaultKey)
            try container.encodeIfPresent(min, forKey: SchemaKey("min"))
            try container.encodeIfPresent(max, forKey: SchemaKey("max"))
            try container.encodeIfPresent(step, forKey: SchemaKey("step"))
        case .double(let value, let min, let max, let step):
            try container.encode(value, forKey: defaultKey)
            try container.encodeIfPresent(min, forKey: SchemaKey("min"))
            try container.encodeIfPresent(max, forKey: SchemaKey("max"))
            try container.encodeIfPresent(step, forKey: SchemaKey("step"))
        case .string(let value):
            try container.encode(value, forKey: defaultKey)
        case .secret:
            break
        case .enumeration(let options, let value):
            try container.encode(options, forKey: SchemaKey("options"))
            try container.encode(value, forKey: defaultKey)
        case .duration(_, let raw):
            try container.encode(raw, forKey: defaultKey)
        case .path(let value):
            try container.encodeIfPresent(value, forKey: defaultKey)
        case .list(let element, let value):
            try container.encode(element, forKey: SchemaKey("of"))
            try container.encode(value, forKey: defaultKey)
        }
    }
}
