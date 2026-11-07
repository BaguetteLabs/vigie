import Foundation
import ModuleKit

/// A resolved, typed setting value.
public enum ConfigResolvedValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case duration(Duration)
    case strings([String])
    /// No value (a `hotkey` or `path` with no default, or a `secret`).
    case none

    /// The value as `T` (`Bool`, `Int`, `Double`, `String`, `Duration`, `[String]`, or `URL` for a path),
    /// or nil when it is of another type.
    public func typed<T: SettingValue>(as type: T.Type) -> T? {
        switch self {
        case .bool(let value): return value as? T
        case .int(let value):
            if T.self == Double.self { return Double(value) as? T }
            return value as? T
        case .double(let value): return value as? T
        case .string(let value):
            if T.self == URL.self {
                return URL(fileURLWithPath: (value as NSString).expandingTildeInPath) as? T
            }
            return value as? T
        case .duration(let value): return value as? T
        case .strings(let value): return value as? T
        case .none: return nil
        }
    }

    /// A Swift setting value (`Bool`, `Int`, `Double`, `String`, `Duration`, `URL`, `[String]`) as a resolved
    /// value; a file URL is written as its path with the home folder abbreviated to `~`.
    public init?(settingValue: any SettingValue) {
        switch settingValue {
        case let value as Bool: self = .bool(value)
        case let value as Int: self = .int(value)
        case let value as Double: self = .double(value)
        case let value as String: self = .string(value)
        case let value as Duration: self = .duration(value)
        case let value as URL: self = .string((value.path as NSString).abbreviatingWithTildeInPath)
        case let value as [String]: self = .strings(value)
        default: return nil
        }
    }

    /// The default of a kind.
    public init(defaultOf kind: SettingKind) {
        switch kind {
        case .bool(let value): self = .bool(value)
        case .int(let value, _, _, _): self = .int(value)
        case .double(let value, _, _, _): self = .double(value)
        case .string(let value): self = .string(value)
        case .secret: self = .none
        case .enumeration(_, let value): self = .string(value)
        case .duration(let value): self = .duration(value)
        case .hotkey(let value), .path(let value): self = value.map(Self.string) ?? .none
        case .list(_, let value): self = .strings(value)
        }
    }

    /// Coerces a raw TOML value to `kind`; returns a reason on a wrong type or out-of-range value.
    static func coerce(_ raw: ConfigValue, to kind: SettingKind) -> Result<ConfigResolvedValue, CoercionFailure> {
        func wrongType(_ expected: String) -> Result<ConfigResolvedValue, CoercionFailure> {
            .failure(CoercionFailure(message: "expected \(expected), found \(raw.typeName)"))
        }
        switch kind {
        case .bool:
            guard case .bool(let value) = raw else { return wrongType("boolean") }
            return .success(.bool(value))
        case .int(_, let min, let max, _):
            guard case .int(let value) = raw else { return wrongType("integer") }
            if let min, value < min { return .failure(CoercionFailure(message: "\(value) is below \(min)")) }
            if let max, value > max { return .failure(CoercionFailure(message: "\(value) is above \(max)")) }
            return .success(.int(value))
        case .double(_, let min, let max, _):
            let value: Double
            switch raw {
            case .int(let int): value = Double(int)
            case .double(let double): value = double
            default: return wrongType("number")
            }
            if let min, value < min { return .failure(CoercionFailure(message: "\(value) is below \(min)")) }
            if let max, value > max { return .failure(CoercionFailure(message: "\(value) is above \(max)")) }
            return .success(.double(value))
        case .string:
            guard case .string(let value) = raw else { return wrongType("string") }
            return .success(.string(value))
        case .secret:
            return .failure(CoercionFailure(message: "secrets are stored in the Keychain, not in config"))
        case .enumeration(let options, _):
            guard case .string(let value) = raw else { return wrongType("string") }
            guard options.contains(value) else {
                return .failure(
                    CoercionFailure(message: "\"\(value)\" is not one of \(options.joined(separator: ", "))"))
            }
            return .success(.string(value))
        case .duration:
            guard case .string(let value) = raw else { return wrongType("duration string such as \"20m\"") }
            guard let duration = ConfigDuration.parse(value) else {
                return .failure(CoercionFailure(message: "\"\(value)\" is not a duration such as \"20m\" or \"1h30m\""))
            }
            return .success(.duration(duration))
        case .hotkey, .path:
            guard case .string(let value) = raw else { return wrongType("string") }
            return .success(value.isEmpty ? .none : .string(value))
        case .list:
            guard case .array(let items) = raw else { return wrongType("array of strings") }
            var strings: [String] = []
            for item in items {
                guard case .string(let value) = item else { return wrongType("array of strings") }
                strings.append(value)
            }
            return .success(.strings(strings))
        }
    }

    struct CoercionFailure: Error {
        let message: String
    }
}

/// One known key.
public struct ConfigSchemaEntry: Sendable {
    public let path: ConfigKeyPath
    public let descriptor: SettingDescriptor
    /// nil for core settings.
    public let moduleID: ModuleID?

    public var scope: SettingScope { descriptor.scope }
}

/// The set of known keys: core settings plus every registered module's `enabled` and declared settings
/// (`modules."<id>".<key>`, or `modules."<id>".local.<key>` for `.local` settings).
public struct ConfigSchema: Sendable {
    public private(set) var entries: [ConfigKeyPath: ConfigSchemaEntry] = [:]
    public private(set) var registeredModules: Set<ModuleID> = []
    public private(set) var openTables: [ConfigKeyPath]

    /// Per-module tables reserved for core services (`[modules."<id>".notify]`, Notifier, Epic 3).
    public static let reservedModuleTables: Set<String> = ["notify"]

    public init(core: [CoreSetting] = CoreSettings.all, openTables: [ConfigKeyPath] = CoreSettings.openTables) {
        self.openTables = openTables
        for setting in core {
            entries[setting.path] = ConfigSchemaEntry(path: setting.path, descriptor: setting.descriptor, moduleID: nil)
        }
    }

    /// Adds a module's `enabled` key and settings. Registering the same id again is a no-op; returns whether
    /// anything was added.
    @discardableResult
    public mutating func register(_ manifest: ModuleManifest) -> Bool {
        guard registeredModules.insert(manifest.id).inserted else { return false }
        let enabled = ConfigKeyPath.moduleEnabled(manifest.id)
        entries[enabled] = ConfigSchemaEntry(
            path: enabled,
            descriptor: SettingDescriptor(
                key: "enabled", label: manifest.name, kind: .bool(default: manifest.defaultEnabled)),
            moduleID: manifest.id
        )
        for descriptor in manifest.settings {
            let path = ConfigKeyPath.module(manifest.id, descriptor.key, scope: descriptor.scope)
            guard entries[path] == nil else { continue }
            entries[path] = ConfigSchemaEntry(path: path, descriptor: descriptor, moduleID: manifest.id)
        }
        return true
    }

    /// The path of a module's setting `key`, routed by its declared scope; nil when undeclared.
    public func path(module id: ModuleID, key: String) -> ConfigKeyPath? {
        if key == "enabled" { return .moduleEnabled(id) }
        for scope in [SettingScope.synced, .local] {
            let path = ConfigKeyPath.module(id, key, scope: scope)
            if let entry = entries[path], entry.scope == scope { return path }
        }
        return nil
    }

    /// True for paths that are ignored without an `unknownKey` problem: free-form tables, tables of modules
    /// that are not registered (yet), and reserved per-module tables.
    func isSilentlyIgnored(_ path: ConfigKeyPath) -> Bool {
        if openTables.contains(where: { path.hasPrefix($0) }) { return true }
        let segments = path.segments
        guard segments.count >= 2, segments[0] == "modules" else { return false }
        guard let id = ModuleID(segments[1]), registeredModules.contains(id) else { return true }
        return segments.count >= 3 && Self.reservedModuleTables.contains(segments[2])
    }
}

/// The result of resolving both files against the schema.
struct ConfigResolution: Sendable {
    var values: [ConfigKeyPath: ConfigResolvedValue] = [:]
    /// Keys whose value came from a file (valid, in the right file).
    var explicit: Set<ConfigKeyPath> = []
    /// `modules."<id>".enabled` as configured, for registered and unregistered modules alike.
    var enabled: [ModuleID: Bool] = [:]
    var problems: [ConfigProblem] = []
}

enum ConfigResolver {
    /// Resolves every known key: `.local` keys from `local.toml`, `.synced` keys from `config.toml`, else the
    /// default. Keys in the wrong file are ignored with a `wrongFile` problem.
    static func resolve(
        schema: ConfigSchema,
        config: ConfigDocument,
        local: ConfigDocument,
        configURL: URL,
        localURL: URL
    ) -> ConfigResolution {
        var result = ConfigResolution()
        for (path, entry) in schema.entries {
            let isLocal = entry.scope == .local
            let (document, url) = isLocal ? (local, localURL) : (config, configURL)
            let (otherDocument, otherURL) = isLocal ? (config, configURL) : (local, localURL)
            let key = path.description
            if otherDocument.value(at: path) != nil {
                let message =
                    isLocal
                    ? "\(key) is machine-specific and is read only from local.toml"
                    : "\(key) is shared and is read only from config.toml"
                result.problems.append(ConfigProblem(kind: .wrongFile, path: otherURL, key: key, message: message))
            }
            let fallback = ConfigResolvedValue(defaultOf: entry.descriptor.kind)
            guard let raw = document.value(at: path) else {
                result.values[path] = fallback
                continue
            }
            switch ConfigResolvedValue.coerce(raw, to: entry.descriptor.kind) {
            case .success(let value):
                result.values[path] = value
                result.explicit.insert(path)
            case .failure(let failure):
                result.values[path] = fallback
                result.problems.append(
                    ConfigProblem(kind: .invalidValue, path: url, key: key, message: "\(key): \(failure.message)"))
            }
        }

        for (document, url) in [(config, configURL), (local, localURL)] {
            for path in document.leafPaths(stoppingAt: { schema.entries[$0] != nil })
            where schema.entries[path] == nil && !schema.isSilentlyIgnored(path) {
                let key = path.description
                result.problems.append(
                    ConfigProblem(kind: .unknownKey, path: url, key: key, message: "unknown key \(key) ignored"))
            }
        }

        if case .table(let modules) = config.value(at: "modules") {
            for (rawID, value) in modules {
                guard let id = ModuleID(rawID), case .table = value else { continue }
                let path = ConfigKeyPath.moduleEnabled(id)
                if schema.entries[path] != nil {
                    if result.explicit.contains(path), case .bool(let enabled) = result.values[path] {
                        result.enabled[id] = enabled
                    }
                } else if case .bool(let enabled) = config.value(at: path) {
                    result.enabled[id] = enabled
                }
            }
        }

        result.problems.sort { ($0.path.path, $0.key ?? "", $0.id) < ($1.path.path, $1.key ?? "", $1.id) }
        return result
    }
}
