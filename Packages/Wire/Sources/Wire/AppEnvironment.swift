import Darwin
import Foundation

/// Every path and identity that differs between the release app and the dev app (AD-17).
///
/// Debug builds are the dev flavor and Release builds are the release flavor; the
/// `VIGIE_DEV` compile condition (set for the debug configuration in `Wire/Package.swift`
/// and in `App/project.yml`) is the single source of truth. Nothing outside `Wire`
/// may spell a path literal.
public struct AppEnvironment: Sendable {
    public enum Flavor: Sendable {
        case release
        case dev
    }

    /// Longest socket path (UTF-8 bytes) we accept; `sun_path` is 104 bytes, minus a safety margin.
    public static let maxSocketPathBytes = 100

    /// The release app's bundle id. Vigie Dev names it too: the notes key lives in the release app's
    /// `<TeamID>.<release bundle id>.notes` access group, shared by both builds (AD-9).
    public static let releaseBundleID = "fr.baguettelabs.vigie"

    /// Environment variable that overrides the config folder in dev builds.
    public static let configDirVariable = "VIGIE_CONFIG_DIR"

    /// The environment selected at compile time: dev in Debug, release otherwise.
    public static let current: AppEnvironment = {
        #if VIGIE_DEV
            AppEnvironment(flavor: .dev)
        #else
            AppEnvironment(flavor: .release)
        #endif
    }()

    public let flavor: Flavor
    public let bundleID: String
    public let displayName: String
    public let cliName: String
    /// The URL scheme the app registers (`CFBundleURLTypes`, AD-20): `vigie`, or `vigie-dev` for the dev build
    /// (AD-17, A89), so a link never opens the other flavor. `App/project.yml` sets the same value per configuration
    /// (`VIGIE_URL_SCHEME`).
    public let urlScheme: String
    public let applicationSupportURL: URL
    public let socketURL: URL
    public let spoolURL: URL
    public let spoolReplayingURL: URL
    public let instanceLockURL: URL
    public let localConfigURL: URL
    /// `<Application Support>/drops/`: file promises dropped on the notch are materialized here, one folder per
    /// drop, before a drop zone handler runs (AD-19).
    public let dropsDirectory: URL
    /// The folder used when no override applies: the release one, for both flavors.
    public let defaultConfigFolderURL: URL
    /// The config folder chosen at launch when it is not the default: an explicit override (init parameter, or
    /// `VIGIE_CONFIG_DIR` in dev builds), else the location recorded in `local.toml` (`[config] folder`, Story 16.1).
    public let configFolderOverride: URL?
    /// Where ``configFolderURL`` came from.
    public let configFolderSource: ConfigFolderSource
    /// Why the location recorded in `local.toml` was not used (missing folder, unreadable path), if it was not;
    /// the default folder applies instead. ConfigStore logs it at start.
    public let configFolderRecordProblem: String?
    /// The user's home folder (tilde expansion and abbreviation of recorded paths).
    public let homeDirectoryURL: URL

    /// Where the config folder in effect comes from (Story 16.1).
    public enum ConfigFolderSource: Sendable, Equatable {
        /// The `configFolderOverride` init parameter (tests).
        case explicitOverride
        /// `VIGIE_CONFIG_DIR` (dev builds only).
        case environmentVariable
        /// `[config] folder` in `local.toml`, written by ConfigStore when the user picked a folder.
        case localRecord
        case defaultFolder
    }

    public var logSubsystem: String { bundleID }

    /// The config folder in effect at launch: the override if present, else the default. ConfigStore may relocate
    /// it while running (Story 16.1); its `configFolderURL` is then the current one.
    public var configFolderURL: URL { configFolderOverride ?? defaultConfigFolderURL }

    /// `<config folder>/modules/`: one Markdown file per script module (SPEC §9.1, AD-18). Synced with the config
    /// folder; Vigie never creates it.
    public var scriptModulesFolderURL: URL { Self.scriptModulesFolderURL(in: configFolderURL) }

    /// The name of the shared config file in the config folder.
    public static let configFileName = "config.toml"
    /// `<config folder>/themes/`: custom theme files (AD-14).
    public static let themesFolderName = "themes"
    /// `<config folder>/modules/`: script modules (AD-18).
    public static let scriptModulesFolderName = "modules"
    /// What a config folder relocation carries (Story 16.1, EXPERIENCE "Sync & Encryption"): the shared file,
    /// custom themes and script modules. Everything machine-specific stays in Application Support.
    public static let configFolderItemNames = [configFileName, themesFolderName, scriptModulesFolderName]
    /// `[config] folder` in `local.toml`: the table and key of the recorded config folder location (AD-12).
    public static let configFolderRecordTable = "config"
    public static let configFolderRecordKey = "folder"

    /// `<folder>/modules/`.
    public static func scriptModulesFolderURL(in folder: URL) -> URL {
        folder.appendingPathComponent(scriptModulesFolderName, isDirectory: true)
    }

    /// `path` with the home folder abbreviated to `~` (the form recorded in `local.toml` and shown in Settings).
    public func abbreviatingHome(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = homeDirectoryURL.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// A recorded path as a folder URL: `~` and `~/…` expand to the home folder; nil for a relative path.
    public func expandingHome(_ path: String) -> URL? {
        Self.expandingHome(path, home: homeDirectoryURL)
    }

    public init(
        flavor: Flavor,
        applicationSupportURL: URL? = nil,
        configFolderOverride: URL? = nil,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        tempDirectoryProvider: @Sendable () -> URL? = AppEnvironment.darwinUserTempDirectory
    ) {
        self.flavor = flavor
        switch flavor {
        case .release:
            bundleID = Self.releaseBundleID
            displayName = "Vigie"
            cliName = "vigie"
            urlScheme = "vigie"
        case .dev:
            bundleID = "fr.baguettelabs.vigie.dev"
            displayName = "Vigie Dev"
            cliName = "vigie-dev"
            urlScheme = "vigie-dev"
        }

        let support: URL
        if let applicationSupportURL {
            support = applicationSupportURL
        } else {
            let base =
                FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? homeDirectoryURL.appendingPathComponent("Library/Application Support", isDirectory: true)
            support = base.appendingPathComponent(displayName, isDirectory: true)
        }
        self.applicationSupportURL = support
        socketURL = Self.socketURL(
            applicationSupportURL: support, bundleID: bundleID, tempDirectory: tempDirectoryProvider)
        spoolURL = support.appendingPathComponent("spool.jsonl")
        spoolReplayingURL = support.appendingPathComponent("spool.replaying.jsonl")
        instanceLockURL = support.appendingPathComponent("instance.lock")
        localConfigURL = support.appendingPathComponent("local.toml")
        dropsDirectory = support.appendingPathComponent("drops", isDirectory: true)
        defaultConfigFolderURL = homeDirectoryURL.appendingPathComponent(".config/vigie", isDirectory: true)

        self.homeDirectoryURL = homeDirectoryURL

        // Precedence: explicit override > `VIGIE_CONFIG_DIR` (dev) > `[config] folder` in local.toml > default.
        var problem: String?
        if let configFolderOverride {
            self.configFolderOverride = configFolderOverride
            configFolderSource = .explicitOverride
        } else if flavor == .dev,
            let value = ProcessInfo.processInfo.environment[Self.configDirVariable], !value.isEmpty
        {
            self.configFolderOverride = URL(fileURLWithPath: value, isDirectory: true)
            configFolderSource = .environmentVariable
        } else {
            var recorded: URL?
            if let data = FileManager.default.contents(atPath: localConfigURL.path),
                let text = String(data: data, encoding: .utf8),
                let path = Self.configFolderRecord(inLocalTOML: text), !path.isEmpty
            {
                recorded = Self.expandingHome(path, home: homeDirectoryURL)
                var isDirectory: ObjCBool = false
                if recorded == nil {
                    problem = "The recorded config folder \(path) is not an absolute path; using the default folder"
                } else if !FileManager.default.fileExists(atPath: recorded!.path, isDirectory: &isDirectory)
                    || !isDirectory.boolValue
                {
                    problem = "The recorded config folder \(path) is missing; using the default folder"
                    recorded = nil
                }
            }
            self.configFolderOverride = recorded
            configFolderSource = recorded == nil ? .defaultFolder : .localRecord
        }
        configFolderRecordProblem = problem
    }

    private static func expandingHome(_ path: String, home: URL) -> URL? {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2)), isDirectory: true) }
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The value of `[config] folder` (or a root `config.folder = …`) in `local.toml` text, or nil when absent.
    ///
    /// Wire has no TOML library (it is shared with the CLI), so this reads only that one key: a basic (`"…"`, with
    /// `\\` and `\"` escapes) or literal (`'…'`) string on its own line. ConfigStore writes it in exactly that form.
    public static func configFolderRecord(inLocalTOML text: String) -> String? {
        var table = ""
        var found: String?
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                let inner = line.dropFirst(line.hasPrefix("[[") ? 2 : 1)
                table = String(inner.prefix { $0 != "]" }).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let full = table.isEmpty ? key : table + "." + key
            guard full == configFolderRecordTable + "." + configFolderRecordKey else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            found = parseString(value)
        }
        return found
    }

    /// A TOML basic or literal single-line string at the start of `value` (a trailing comment is ignored).
    static func parseString(_ value: String) -> String? {
        guard let quote = value.first, quote == "\"" || quote == "'" else { return nil }
        var result = ""
        var escaped = false
        for character in value.dropFirst() {
            if quote == "\"" && escaped {
                switch character {
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(character)
                }
                escaped = false
            } else if quote == "\"" && character == "\\" {
                escaped = true
            } else if character == quote {
                return result
            } else {
                result.append(character)
            }
        }
        return nil
    }

    /// Pure socket path rule (AD-17): inside Application Support when it fits in
    /// `maxSocketPathBytes`, else `<temp dir>/<bundle id>/vigie.sock`.
    public static func socketURL(
        applicationSupportURL: URL,
        bundleID: String,
        tempDirectory: () -> URL?
    ) -> URL {
        let preferred = applicationSupportURL.appendingPathComponent("vigie.sock")
        if preferred.path.utf8.count <= maxSocketPathBytes { return preferred }
        guard let temp = tempDirectory() else { return preferred }
        return temp.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("vigie.sock")
    }

    /// `confstr(_CS_DARWIN_USER_TEMP_DIR)`; deliberately not `$TMPDIR` or `NSTemporaryDirectory()`.
    @Sendable public static func darwinUserTempDirectory() -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        guard length > 0, length <= buffer.count else { return nil }
        return URL(
            fileURLWithPath: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
            isDirectory: true)
    }
}
