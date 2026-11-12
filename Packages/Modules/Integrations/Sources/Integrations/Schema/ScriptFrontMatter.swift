import Foundation
import ModuleKit
import Yams

/// The widget a script fills (front matter `widget`, output `widget.type`).
public enum ScriptWidgetType: String, CaseIterable, Sendable, Codable {
    case status
    case number
    case text
}

/// Where a script's widget shows (front matter `surfaces`).
public enum ScriptSurface: String, CaseIterable, Sendable, Codable {
    /// A Home card.
    case home
    /// An item on the closed notch's left-wing lane (SPEC §5); there is no per-script side setting.
    case side
    /// Its own tab in the expanded view.
    case page
}

/// The YAML front matter of a script module file (SPEC §9.1, `#/$defs/frontMatter` in
/// `schemas/script-module.schema.json`).
///
/// Strict, like the schema: an unknown key is an error (``ScriptSchemaError/Reason/unknownKey``), so a typo never
/// silently falls back to a default; new keys arrive with a `schema` bump. Defaults: `schema` 1, `icon`
/// `terminal`, `surfaces` `[home]`, `settings` none, `priority` nil (the host's default).
///
/// Checks that need more than one file or the module registry (reserved and duplicate ids, AD-18) and
/// cross-field checks the schema cannot express (a `default` inside `min`...`max` or among `options`) belong to
/// discovery (Story 12.2).
public struct ScriptFrontMatter: Equatable, Sendable, Codable {
    public static let defaultIcon = "terminal"
    public static let defaultSurfaces: [ScriptSurface] = [.home]

    public var schema: ScriptSchemaVersion
    public var id: ModuleID
    public var name: String
    /// SF Symbol name.
    public var icon: String
    public var interval: Duration
    /// Executable name resolved through `context.executables` (AD-18, AD-19).
    public var runtime: String
    public var widget: ScriptWidgetType
    public var surfaces: [ScriptSurface]
    /// Left-wing item priority (lower is shown first); nil when the file does not set one.
    public var priority: Int?
    public var settings: [ScriptSetting]

    public init(
        schema: ScriptSchemaVersion = .current,
        id: ModuleID,
        name: String,
        icon: String = ScriptFrontMatter.defaultIcon,
        interval: Duration,
        runtime: String,
        widget: ScriptWidgetType,
        surfaces: [ScriptSurface] = ScriptFrontMatter.defaultSurfaces,
        priority: Int? = nil,
        settings: [ScriptSetting] = []
    ) {
        self.schema = schema
        self.id = id
        self.name = name
        self.icon = icon
        self.interval = interval
        self.runtime = runtime
        self.widget = widget
        self.surfaces = surfaces
        self.priority = priority
        self.settings = settings
    }

    static let keys: Set<String> = [
        "schema", "id", "name", "icon", "interval", "runtime", "widget", "surfaces", "priority", "settings",
    ]

    public init(from decoder: any Decoder) throws {
        let object = try SchemaObject(decoder)
        try object.rejectUnknownKeys(allowed: Self.keys)
        schema = try object.schemaVersion()

        let rawID = try object.required(String.self, "id", expected: .string)
        guard let id = ModuleID(rawID) else {
            throw ScriptSchemaError(object.path("id"), .invalidFormat(rawID, .moduleID))
        }
        self.id = id

        guard let name = try object.nonEmptyString("name") else {
            throw ScriptSchemaError(object.path("name"), .missingKey)
        }
        self.name = name

        let icon = try object.string("icon") ?? Self.defaultIcon
        guard Self.isSymbolName(icon) else { throw ScriptSchemaError(object.path("icon"), .invalidFormat(icon, .icon)) }
        self.icon = icon

        let rawInterval = try object.required(String.self, "interval", expected: .string)
        guard let interval = ScriptDuration.parseInterval(rawInterval) else {
            throw ScriptSchemaError(object.path("interval"), .invalidFormat(rawInterval, .interval))
        }
        self.interval = interval

        let runtime = try object.required(String.self, "runtime", expected: .string)
        guard Self.isExecutableName(runtime) else {
            throw ScriptSchemaError(object.path("runtime"), .invalidFormat(runtime, .runtime))
        }
        self.runtime = runtime

        guard let widget = try object.choice(ScriptWidgetType.self, "widget") else {
            throw ScriptSchemaError(object.path("widget"), .missingKey)
        }
        self.widget = widget

        surfaces = try Self.decodeSurfaces(object) ?? Self.defaultSurfaces
        priority = try object.int("priority")
        settings = try object.optional([ScriptSetting].self, "settings", expected: .array) ?? []
    }

    private static func decodeSurfaces(_ object: SchemaObject) throws -> [ScriptSurface]? {
        guard let raw = try object.strings("surfaces") else { return nil }
        guard !raw.isEmpty else { throw ScriptSchemaError(object.path("surfaces"), .empty) }
        var surfaces: [ScriptSurface] = []
        for (index, item) in raw.enumerated() {
            let itemPath = object.path("surfaces") + [SchemaKey(intValue: index)!]
            guard let surface = ScriptSurface(rawValue: item) else {
                throw ScriptSchemaError(
                    itemPath, .unknownValue(item, allowed: ScriptSurface.allCases.map(\.rawValue)))
            }
            guard !surfaces.contains(surface) else { throw ScriptSchemaError(itemPath, .duplicate(item)) }
            surfaces.append(surface)
        }
        return surfaces
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SchemaKey.self)
        try container.encode(schema, forKey: SchemaKey("schema"))
        try container.encode(id, forKey: SchemaKey("id"))
        try container.encode(name, forKey: SchemaKey("name"))
        try container.encode(icon, forKey: SchemaKey("icon"))
        try container.encode(ScriptDuration.format(interval), forKey: SchemaKey("interval"))
        try container.encode(runtime, forKey: SchemaKey("runtime"))
        try container.encode(widget, forKey: SchemaKey("widget"))
        try container.encode(surfaces, forKey: SchemaKey("surfaces"))
        try container.encodeIfPresent(priority, forKey: SchemaKey("priority"))
        try container.encode(settings, forKey: SchemaKey("settings"))
    }

    /// Decodes front matter written in YAML (the text between the `---` fences), with Yams (AD-16). A schema
    /// problem throws ``ScriptSchemaError``; YAML that does not parse throws Yams' error.
    public static func decode(yaml: String) throws -> ScriptFrontMatter {
        do {
            return try YAMLDecoder().decode(ScriptFrontMatter.self, from: yaml)
        } catch let DecodingError.dataCorrupted(context) {
            // Yams wraps errors thrown by `init(from:)`.
            if let error = context.underlyingError as? ScriptSchemaError { throw error }
            throw DecodingError.dataCorrupted(context)
        }
    }

    /// `^[a-z0-9]+(\.[a-z0-9]+)*$`
    static func isSymbolName(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
        }
    }

    /// `^[A-Za-z0-9][A-Za-z0-9._+-]*$`
    static func isExecutableName(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first, isAlphanumeric(first) else { return false }
        return value.unicodeScalars.allSatisfy { isAlphanumeric($0) || "._+-".unicodeScalars.contains($0) }
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
    }
}
