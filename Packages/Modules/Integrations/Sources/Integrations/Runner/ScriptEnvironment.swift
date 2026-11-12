import Foundation
import ModuleKit

/// The environment a script runs with (SPEC §9.2, AD-18): nothing inherited from Vigie but `PATH` (the login
/// shell's, from `context.executables`), `HOME` and `LANG`, plus one `VIGIE_SETTING_<KEY>` per setting that has
/// a value.
enum ScriptEnvironment {
    static let settingPrefix = "VIGIE_SETTING_"
    /// `PATH` when the resolver has no captured `PATH`: the runtime's own folder first, then these.
    static let fallbackPath = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    static let defaultLanguage = "en_US.UTF-8"

    /// `warn_at` → `VIGIE_SETTING_WARN_AT` (keys are snake_case, Story 12.1).
    static func variableName(_ key: String) -> String { settingPrefix + key.uppercased() }

    /// The SecretStore key of a script's `secret` setting in the integrations module's store:
    /// `<script id>.<setting key>`. Story 12.6 writes it under the same key.
    static func secretKey(scriptID: ModuleID, settingKey: String) -> String { scriptID.rawValue + "." + settingKey }

    /// - Parameters:
    ///   - configured: `[modules."<id>"] <key>` as configured, nil when absent (the front-matter default applies).
    ///   - secrets: each `secret` setting's value read at run time, by key; a missing one leaves its variable unset.
    static func build(
        settings: [ScriptSetting], configured: (String) -> (any SettingValue)?, secrets: [String: String],
        searchPath: [String], runtime: URL, home: String, language: String?
    ) -> [String: String] {
        var path = searchPath
        if path.isEmpty { path = [runtime.deletingLastPathComponent().path] + fallbackPath }
        var environment = ["PATH": path.joined(separator: ":"), "HOME": home, "LANG": language ?? defaultLanguage]
        for setting in settings {
            let value: String?
            if case .secret = setting.kind {
                value = secrets[setting.key]
            } else {
                value = configured(setting.key).flatMap(format) ?? defaultValue(setting.kind)
            }
            if let value { environment[variableName(setting.key)] = value }
        }
        return environment
    }

    /// The front-matter default as passed to the script; nil for a `secret` or a `path` without default.
    static func defaultValue(_ kind: ScriptSetting.Kind) -> String? {
        switch kind {
        case .bool(let value): format(value)
        case .int(let value, _, _, _): String(value)
        case .double(let value, _, _, _): format(value)
        case .string(let value): value
        case .secret: nil
        case .enumeration(_, let value): value
        case .duration(_, let raw): raw
        case .path(let value): value.map(expandingTilde)
        case .list(_, let value): format(value)
        }
    }

    /// A configured value: `true`/`false`, numbers as Swift prints them, durations in the config grammar
    /// (`1h30m`), paths with `~` expanded, lists as a JSON array of strings.
    static func format(_ value: any SettingValue) -> String? {
        switch value {
        case let value as Bool: value ? "true" : "false"
        case let value as Int: String(value)
        case let value as Double: String(value)
        case let value as String: value
        case let value as Duration: ScriptDuration.format(value)
        case let value as URL: value.path
        case let value as [String]: format(value)
        default: nil
        }
    }

    private static func format(_ value: Bool) -> String { value ? "true" : "false" }
    private static func format(_ value: Double) -> String { String(value) }

    private static func format(_ list: [String]) -> String {
        guard let data = try? JSONEncoder().encode(list) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func expandingTilde(_ path: String) -> String { (path as NSString).expandingTildeInPath }

    /// The temporary file's extension for a code block's language tag, so runtimes that care (`swift`, `node`)
    /// accept it; an unknown tag made of letters and digits is used as is.
    static func fileExtension(language: String?) -> String? {
        guard let language = language?.lowercased(), !language.isEmpty else { return nil }
        let known = [
            "python": "py", "python3": "py", "py": "py", "javascript": "js", "js": "js", "node": "js",
            "typescript": "ts", "ts": "ts", "ruby": "rb", "rb": "rb", "shell": "sh", "sh": "sh", "bash": "sh",
            "zsh": "zsh", "swift": "swift", "applescript": "applescript", "perl": "pl", "php": "php", "lua": "lua",
        ]
        if let mapped = known[language] { return mapped }
        return language.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) })
            ? language : nil
    }
}
