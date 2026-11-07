import Foundation

/// Where a setting is stored (AD-8): `.synced` in `config.toml`, `.local` in `local.toml`.
public enum SettingScope: Hashable, Sendable {
    case synced
    case local
}

/// Element type of a `list` setting.
public enum SettingListElement: Hashable, Sendable {
    case string
    case path
}

/// The typed kind of a setting, with its default (SPEC §4.4). The generated settings UI is built from it.
public enum SettingKind: Hashable, Sendable {
    case bool(default: Bool)
    case int(default: Int, min: Int? = nil, max: Int? = nil, step: Int? = nil)
    case double(default: Double, min: Double? = nil, max: Double? = nil, step: Double? = nil)
    case string(default: String)
    /// Stored only through `SecretStore` (AD-9), never in a config file.
    case secret
    case enumeration(options: [String], default: String)
    /// Written in config as a string such as `"5m"` (Conventions: Config keys). Parsing arrives in Story 2.3.
    case duration(default: Duration)
    /// Shortcut name, e.g. `opt+cmd+n`; nil means no default shortcut.
    case hotkey(default: String?)
    /// A folder or file path as written in config (may start with `~`); nil means none.
    case path(default: String?)
    case list(of: SettingListElement, default: [String])
}

/// A setting a module declares in its manifest (SPEC §4.4, AD-8).
public struct SettingDescriptor: Sendable {
    /// `snake_case` config key under `[modules."<id>"]`.
    public let key: String
    public let label: LocalizedStringResource
    public let kind: SettingKind
    public let scope: SettingScope
    public let help: LocalizedStringResource?

    public init(
        key: String,
        label: LocalizedStringResource,
        kind: SettingKind,
        scope: SettingScope = .synced,
        help: LocalizedStringResource? = nil
    ) {
        self.key = key
        self.label = label
        self.kind = kind
        self.scope = scope
        self.help = help
    }

    /// The declared default, as the Swift type `ModuleSettings.value(_:as:)` returns for this kind
    /// (`Bool`, `Int`, `Double`, `String`, `Duration`, `[String]`), or nil when the kind has none.
    public var defaultValue: (any SettingValue)? {
        switch kind {
        case .bool(let value): value
        case .int(let value, _, _, _): value
        case .double(let value, _, _, _): value
        case .string(let value): value
        case .secret: nil
        case .enumeration(_, let value): value
        case .duration(let value): value
        case .hotkey(let value): value
        case .path(let value): value
        case .list(_, let value): value
        }
    }
}

/// A Swift type a setting value can be read as.
public protocol SettingValue: Sendable {}

extension Bool: SettingValue {}
extension Int: SettingValue {}
extension Double: SettingValue {}
extension String: SettingValue {}
extension Duration: SettingValue {}
extension URL: SettingValue {}
extension Array: SettingValue where Element == String {}
