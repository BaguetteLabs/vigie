import Foundation
import ModuleKit
import VigieUI

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
            if let option = durationOption(value, in: options) { return .success(.string(option)) }
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

    /// An enumeration whose options include durations (`[general] home_after`: `0s`, `30s`, `2m`, … and
    /// `never`) also takes any other duration: the option spelling when it names the same duration (`"120s"` is
    /// `"2m"`), else the value as written. Nil for a listed value, a non-duration or an enumeration of words.
    private static func durationOption(_ value: String, in options: [String]) -> String? {
        guard !options.contains(value), let duration = ConfigDuration.parse(value) else { return nil }
        let durations = options.compactMap { option in ConfigDuration.parse(option).map { (option, $0) } }
        guard !durations.isEmpty else { return nil }
        return durations.first { $0.1 == duration }?.0 ?? value
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
    /// Keys with a ``wildcard`` segment (Story 7.10: `account.*.label` of an adapter). Each concrete key is
    /// registered when a file holds its table (``expandTemplates(in:)``) or when it is written
    /// (``concretize(_:)``).
    public private(set) var templates: [ConfigKeyPath: ConfigSchemaEntry] = [:]
    public private(set) var registeredModules: Set<ModuleID> = []
    public private(set) var openTables: [ConfigKeyPath]
    /// The `modules."<script id>".<key>` entries each script module registered (Story 12.6), so a later
    /// registration replaces them and ``unregisterScriptSettings(_:)`` removes exactly them.
    public private(set) var scriptSettingPaths: [ModuleID: Set<ConfigKeyPath>] = [:]

    /// Per-module tables reserved for core services (`[modules."<id>".notify]`, Notifier, Epic 3).
    public static let reservedModuleTables: Set<String> = ["notify"]

    public init(core: [CoreSetting] = CoreSettings.all, openTables: [ConfigKeyPath] = CoreSettings.openTables) {
        self.openTables = openTables
        for setting in core {
            entries[setting.path] = ConfigSchemaEntry(path: setting.path, descriptor: setting.descriptor, moduleID: nil)
        }
        // `[appearance.colors]` stays free-form, but the roles Settings edits (Story 17.2) are known strings so the
        // window can write them through `ConfigStore.set` (`#RRGGBB`, validated by the theme resolver).
        for role in StatusColors.roles {
            let path = StatusColors.path(role)
            entries[path] = ConfigSchemaEntry(
                path: path,
                descriptor: SettingDescriptor(
                    key: role.rawValue, label: CoreSettings.label(StatusColors.labelKey(role)),
                    kind: .string(default: "")),
                moduleID: nil)
        }
    }

    /// Adds a module's `enabled` key, its settings, and `mute` / `outputs` / `reminder` under
    /// `modules."<id>".notify."<kind>"` for each declared alert kind. Registering the same id again is a no-op; returns whether
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
        // Notifier-owned rule keys of each declared alert kind (Story 3.7, AD-13).
        for (path, descriptor) in AlertSettings.schemaDescriptors(for: manifest) where entries[path] == nil {
            entries[path] = ConfigSchemaEntry(path: path, descriptor: descriptor, moduleID: manifest.id)
        }
        return true
    }

    /// Adds the `local.toml` record keys of one agent integration (`integrations."<id>".installed_at`, `target`,
    /// `backup`, `cli_path`; strings). Returns whether anything was added.
    @discardableResult
    public mutating func registerIntegration(_ adapterID: String) -> Bool {
        var added = false
        for key in CoreSettings.integrationKeys {
            let path = CoreSettings.integrationPath(adapterID, key)
            guard entries[path] == nil else { continue }
            let descriptor = SettingDescriptor(
                key: key, label: CoreSettings.label("config.integrations.\(key)"), kind: .string(default: ""),
                scope: .local)
            entries[path] = ConfigSchemaEntry(path: path, descriptor: descriptor, moduleID: nil)
            added = true
        }
        return added
    }

    /// Adds the settings an agent adapter declares (`AgentAdapter.settings`) under its owning module, at
    /// ``CoreSettings/adapterPath(module:adapter:_:)`` (Story 7.3). Returns whether anything was added.
    @discardableResult
    public mutating func registerAdapter(_ adapterID: String, module: ModuleID, settings: [SettingDescriptor])
        -> Bool
    {
        var added = false
        for descriptor in settings {
            let path = CoreSettings.adapterPath(module: module, adapter: adapterID, descriptor.key)
            if path.segments.contains(Self.wildcard) {
                guard templates[path] == nil else { continue }
                templates[path] = ConfigSchemaEntry(path: path, descriptor: descriptor, moduleID: module)
                added = true
                continue
            }
            guard entries[path] == nil else { continue }
            entries[path] = ConfigSchemaEntry(path: path, descriptor: descriptor, moduleID: module)
            added = true
        }
        return added
    }

    /// The template segment that matches any one key (Story 7.10).
    public static let wildcard = "*"

    /// The template `path` is an instance of: same length, equal segments except where the template has
    /// ``wildcard`` (which never matches `*` itself).
    public func template(matching path: ConfigKeyPath) -> ConfigSchemaEntry? {
        guard !path.segments.contains(Self.wildcard) else { return nil }
        return templates.first { template, _ in
            template.segments.count == path.segments.count
                && zip(template.segments, path.segments).allSatisfy { $0 == Self.wildcard || $0 == $1 }
        }?.value
    }

    /// Registers `path` from its template (the template's kind and scope, the concrete dotted key). Returns
    /// whether it was added; false when already known or no template matches.
    @discardableResult
    public mutating func concretize(_ path: ConfigKeyPath) -> Bool {
        guard entries[path] == nil, let template = template(matching: path) else { return false }
        let keyLength = template.descriptor.key.split(separator: ".", omittingEmptySubsequences: false).count
        let descriptor = SettingDescriptor(
            key: path.segments.suffix(keyLength).joined(separator: "."), label: template.descriptor.label,
            kind: template.descriptor.kind, scope: template.descriptor.scope, help: template.descriptor.help)
        entries[path] = ConfigSchemaEntry(path: path, descriptor: descriptor, moduleID: template.moduleID)
        return true
    }

    /// Registers every instance of every template whose table exists in `documents` (each child table name at a
    /// ``wildcard`` position). Returns whether anything was added.
    @discardableResult
    public mutating func expandTemplates(in documents: [ConfigDocument]) -> Bool {
        var added = false
        for template in templates.keys.sorted() {
            for path in Self.instances(of: template.segments[...], prefix: [], in: documents) where concretize(path) {
                added = true
            }
        }
        return added
    }

    private static func instances(
        of rest: ArraySlice<String>, prefix: [String], in documents: [ConfigDocument]
    ) -> [ConfigKeyPath] {
        guard let index = rest.firstIndex(of: wildcard) else { return [ConfigKeyPath(prefix + rest)] }
        let head = prefix + rest[rest.startIndex..<index]
        var names: Set<String> = []
        for document in documents {
            guard case .table(let table) = document.value(at: ConfigKeyPath(head)) else { continue }
            for (name, value) in table where name != wildcard {
                if case .table = value { names.insert(name) }
            }
        }
        return names.sorted().flatMap { name in
            instances(of: rest[(index + 1)...], prefix: head + [name], in: documents)
        }
    }

    /// Adds `consents."<descriptor id>".granted_at` (a local string, Story 7.3). Returns whether it was added.
    @discardableResult
    public mutating func registerConsent(_ descriptorID: String) -> Bool {
        let path = CoreSettings.consentPath(descriptorID)
        guard entries[path] == nil else { return false }
        let descriptor = SettingDescriptor(
            key: CoreSettings.consentGrantedAtKey, label: CoreSettings.label("config.consents.granted_at"),
            kind: .string(default: ""), scope: .local)
        entries[path] = ConfigSchemaEntry(path: path, descriptor: descriptor, moduleID: nil)
        return true
    }

    /// Adds `scripts.confirmations."<relative path>".sha256` and `scripts.declined."<relative path>".sha256` (local
    /// strings, Story 12.3). Returns whether they were added.
    @discardableResult
    public mutating func registerScriptRecord(_ relativePath: String) -> Bool {
        var added = false
        for kind in CoreSettings.ScriptRecordKind.allCases {
            let path = CoreSettings.scriptRecordPath(kind, relativePath)
            guard entries[path] == nil else { continue }
            let descriptor = SettingDescriptor(
                key: CoreSettings.scriptRecordKey, label: CoreSettings.label("config.scripts.\(kind.rawValue).sha256"),
                kind: .string(default: ""), scope: .local)
            entries[path] = ConfigSchemaEntry(path: path, descriptor: descriptor, moduleID: nil)
            added = true
        }
        return added
    }

    /// Adds `scripts.sources."<relative path>".<url|sig|installed_at>` (local strings, Story 12.9). Returns whether
    /// they were added.
    @discardableResult
    public mutating func registerScriptSource(_ relativePath: String) -> Bool {
        var added = false
        for key in CoreSettings.ScriptSourceKey.allCases {
            let path = CoreSettings.scriptSourcePath(relativePath, key)
            guard entries[path] == nil else { continue }
            let descriptor = SettingDescriptor(
                key: key.rawValue, label: CoreSettings.label("config.scripts.sources.\(key.rawValue)"),
                kind: .string(default: ""), scope: .local)
            entries[path] = ConfigSchemaEntry(path: path, descriptor: descriptor, moduleID: nil)
            added = true
        }
        return added
    }

    /// Adds `scripts.enabled."<relative path>"` (a local bool, default true; Story 12.6). Returns whether it was
    /// added.
    @discardableResult
    public mutating func registerScriptEnabled(_ relativePath: String) -> Bool {
        let path = CoreSettings.scriptEnabledPath(relativePath)
        guard entries[path] == nil else { return false }
        let descriptor = SettingDescriptor(
            key: relativePath, label: CoreSettings.label("config.scripts.enabled"), kind: .bool(default: true),
            scope: .local)
        entries[path] = ConfigSchemaEntry(path: path, descriptor: descriptor, moduleID: nil)
        return true
    }

    /// Makes a script module's declared settings known at `modules."<id>".<key>` in `config.toml` (synced, Story
    /// 12.6), replacing what the script registered before. `secret` settings are skipped (Keychain only, AD-9), and
    /// so is a key another registration (a manifest) already owns. Returns whether the schema changed.
    @discardableResult
    public mutating func registerScriptSettings(_ id: ModuleID, settings: [SettingDescriptor]) -> Bool {
        let previous = scriptSettingPaths[id] ?? []
        var next: [ConfigKeyPath: ConfigSchemaEntry] = [:]
        for descriptor in settings {
            if case .secret = descriptor.kind { continue }
            let path = ConfigKeyPath.module(id, descriptor.key, scope: .synced)
            if entries[path] != nil, !previous.contains(path) { continue }
            let synced = SettingDescriptor(
                key: descriptor.key, label: descriptor.label, kind: descriptor.kind, scope: .synced,
                help: descriptor.help)
            next[path] = ConfigSchemaEntry(path: path, descriptor: synced, moduleID: id)
        }
        let unchanged =
            Set(next.keys) == previous
            && next.allSatisfy { path, entry in entries[path]?.descriptor.kind == entry.descriptor.kind }
        guard !unchanged else { return false }
        for path in previous { entries[path] = nil }
        for (path, entry) in next { entries[path] = entry }
        scriptSettingPaths[id] = next.isEmpty ? nil : Set(next.keys)
        return true
    }

    /// Removes what ``registerScriptSettings(_:settings:)`` added for `id`. Returns whether anything was removed.
    @discardableResult
    public mutating func unregisterScriptSettings(_ id: ModuleID) -> Bool {
        guard let paths = scriptSettingPaths.removeValue(forKey: id) else { return false }
        for path in paths { entries[path] = nil }
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
