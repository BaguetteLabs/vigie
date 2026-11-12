import Foundation
import ModuleKit

/// The JSON document a script run prints to stdout (SPEC §9.3, `#/$defs/output` in the schema).
///
/// Tolerant, like the schema: unknown keys are ignored, so a script may print extra fields; `notify` is accepted
/// with any value and ignored in v1 (script-raised alerts are deferred). Known keys are still checked strictly:
/// a wrong type or an unknown enum value is an error naming the key. Defaults: `schema` 1, `state` `ambient`.
public struct ScriptOutput: Equatable, Sendable, Codable {
    public var schema: ScriptSchemaVersion
    /// Relevance for closed-notch arbitration (`hidden | ambient | active | alert`).
    public var state: ModuleState
    public var widget: ScriptWidget
    public var action: ScriptAction?

    public static let defaultState: ModuleState = .ambient

    public init(
        schema: ScriptSchemaVersion = .current, state: ModuleState = ScriptOutput.defaultState,
        widget: ScriptWidget, action: ScriptAction? = nil
    ) {
        self.schema = schema
        self.state = state
        self.widget = widget
        self.action = action
    }

    /// `state` values, in `ModuleState` order.
    enum StateName: String, CaseIterable {
        case hidden, ambient, active, alert

        var state: ModuleState {
            switch self {
            case .hidden: .hidden
            case .ambient: .ambient
            case .active: .active
            case .alert: .alert
            }
        }

        init(_ state: ModuleState) {
            switch state {
            case .hidden: self = .hidden
            case .ambient: self = .ambient
            case .active: self = .active
            case .alert: self = .alert
            }
        }
    }

    public init(from decoder: any Decoder) throws {
        let object = try SchemaObject(decoder)
        schema = try object.schemaVersion()
        state = try object.choice(StateName.self, "state")?.state ?? Self.defaultState
        widget = try object.required(ScriptWidget.self, "widget", expected: .object)
        action = try object.optional(ScriptAction.self, "action", expected: .object)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SchemaKey.self)
        try container.encode(schema, forKey: SchemaKey("schema"))
        try container.encode(StateName(state).rawValue, forKey: SchemaKey("state"))
        try container.encode(widget, forKey: SchemaKey("widget"))
        try container.encodeIfPresent(action, forKey: SchemaKey("action"))
    }

    /// Decodes one run's stdout.
    public static func decode(json data: Data) throws -> ScriptOutput {
        try JSONDecoder().decode(ScriptOutput.self, from: data)
    }
}

/// The shared status vocabulary level (`ok` → OK, `warn` → WARN, `error` → DOWN).
public enum ScriptLevel: String, CaseIterable, Sendable, Codable {
    case ok, warn, error
}

/// `widget` in a script's output. Unknown keys are ignored. A `status` widget requires `level`; `number` and
/// `text` widgets require `value`. Its `type` must equal the front matter's `widget` (checked by the runner,
/// Story 12.4: it spans two documents).
public struct ScriptWidget: Equatable, Sendable, Codable {
    public var type: ScriptWidgetType
    /// A number arrives as printed (`3`, `2.5`).
    public var value: String?
    public var label: String?
    public var detail: String?
    public var level: ScriptLevel?

    public init(
        type: ScriptWidgetType, value: String? = nil, label: String? = nil, detail: String? = nil,
        level: ScriptLevel? = nil
    ) {
        self.type = type
        self.value = value
        self.label = label
        self.detail = detail
        self.level = level
    }

    public init(from decoder: any Decoder) throws {
        let object = try SchemaObject(decoder)
        guard let type = try object.choice(ScriptWidgetType.self, "type") else {
            throw ScriptSchemaError(object.path("type"), .missingKey)
        }
        self.type = type
        value = try object.optional(SchemaText.self, "value", expected: .stringOrNumber)?.value
        label = try object.string("label")
        detail = try object.string("detail")
        level = try object.choice(ScriptLevel.self, "level")
        switch type {
        case .status where level == nil:
            throw ScriptSchemaError(object.path("level"), .missingKey)
        case .number where value == nil, .text where value == nil:
            throw ScriptSchemaError(object.path("value"), .missingKey)
        default:
            break
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SchemaKey.self)
        try container.encode(type, forKey: SchemaKey("type"))
        try container.encodeIfPresent(value, forKey: SchemaKey("value"))
        try container.encodeIfPresent(label, forKey: SchemaKey("label"))
        try container.encodeIfPresent(detail, forKey: SchemaKey("detail"))
        try container.encodeIfPresent(level, forKey: SchemaKey("level"))
    }
}

/// `action`: what a click on the widget does, exactly one of `open`, `run`, `copy`. Unknown keys are ignored.
public enum ScriptAction: Equatable, Sendable, Codable {
    /// A URL with a scheme, opened by the host.
    case open(String)
    /// argv run through the script runner (Story 12.5); never empty.
    case run([String])
    /// Text copied through `context.clipboard`.
    case copy(String)

    /// `open`'s URL, when Foundation can parse it.
    public var url: URL? {
        if case .open(let text) = self { URL(string: text) } else { nil }
    }

    public init(from decoder: any Decoder) throws {
        let object = try SchemaObject(decoder)
        let present = ["open", "run", "copy"].filter(object.has)
        guard present.count == 1 else { throw ScriptSchemaError(decoder.codingPath, .actionCount) }
        switch present[0] {
        case "open":
            let text = try object.required(String.self, "open", expected: .string)
            guard Self.isURL(text) else { throw ScriptSchemaError(object.path("open"), .invalidFormat(text, .url)) }
            self = .open(text)
        case "run":
            let argv = try object.strings("run") ?? []
            guard !argv.isEmpty else { throw ScriptSchemaError(object.path("run"), .empty) }
            self = .run(argv)
        default:
            self = .copy(try object.required(String.self, "copy", expected: .string))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SchemaKey.self)
        switch self {
        case .open(let text): try container.encode(text, forKey: SchemaKey("open"))
        case .run(let argv): try container.encode(argv, forKey: SchemaKey("run"))
        case .copy(let text): try container.encode(text, forKey: SchemaKey("copy"))
        }
    }

    /// `^[A-Za-z][A-Za-z0-9+.-]*:[^\s]+$`
    static func isURL(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon].unicodeScalars
        let rest = text[text.index(after: colon)...]
        guard let first = scheme.first, ("a"..."z").contains(first) || ("A"..."Z").contains(first) else { return false }
        let schemeOK = scheme.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
                || "+.-".unicodeScalars.contains($0)
        }
        return schemeOK && !rest.isEmpty && !rest.contains(where: \.isWhitespace)
    }
}
