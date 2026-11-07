import Foundation
import ModuleKit

/// One `[sounds]` value (SPEC §11): `"off"`, `"builtin:<name>"`, or a path to a custom file (absolute or `~`).
public enum SoundValue: Hashable, Sendable {
    case off
    case builtIn(String)
    /// A custom file, `~` expanded.
    case file(URL)
    /// Anything else (a relative path, an empty `builtin:`): a setup problem, never a sound.
    case invalid(String)

    public static let builtInPrefix = "builtin:"

    public init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed == "off" {
            self = .off
        } else if trimmed.hasPrefix(Self.builtInPrefix) {
            let name = String(trimmed.dropFirst(Self.builtInPrefix.count))
            self = name.isEmpty ? .invalid(raw) : .builtIn(name)
        } else if trimmed.hasPrefix("/") || trimmed == "~" || trimmed.hasPrefix("~/") {
            self = .file(URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath))
        } else {
            self = .invalid(raw)
        }
    }

    /// The config text for this value (custom files are written with the home folder abbreviated to `~`).
    public var raw: String {
        switch self {
        case .off: "off"
        case .builtIn(let name): Self.builtInPrefix + name
        case .file(let url): (url.path as NSString).abbreviatingWithTildeInPath
        case .invalid(let raw): raw
        }
    }

    public var isOff: Bool { self == .off }
}

/// The `[sounds]` table as Notifier reads it.
public struct SoundSettings: Equatable, Sendable {
    public var enabled: Bool
    /// `[sounds]` key → raw value.
    public var values: [String: String]

    public init(enabled: Bool, values: [String: String]) {
        self.enabled = enabled
        self.values = values
    }

    /// No sound at all (used before the config loads).
    public static let silent = SoundSettings(enabled: false, values: [:])

    /// The value of `key`; nil when the table has no such key.
    public func value(for key: String) -> SoundValue? { values[key].map(SoundValue.init) }

    /// Reads `[sounds]` from `store` (resolved: file value or schema default). The App builds the
    /// ``NotifierSoundSink`` config closure from this; nothing else reads `[sounds]` for playback (AD-13).
    @MainActor public static func read(from store: ConfigStore) -> SoundSettings {
        var values: [String: String] = [:]
        for key in SoundTable.allSoundKeys {
            if let value = store.value(path(key), as: String.self) { values[key] = value }
        }
        return SoundSettings(enabled: store.value(path("enabled"), as: Bool.self) ?? false, values: values)
    }

    public static func path(_ key: String) -> ConfigKeyPath { CoreSettings.path("sounds", key) }
}
