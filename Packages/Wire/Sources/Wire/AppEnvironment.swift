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
    /// An explicit override (init parameter, or `VIGIE_CONFIG_DIR` in dev builds), if any.
    public let configFolderOverride: URL?

    public var logSubsystem: String { bundleID }

    /// The config folder in effect: the override if present, else the default.
    public var configFolderURL: URL { configFolderOverride ?? defaultConfigFolderURL }

    /// `<config folder>/modules/`: one Markdown file per script module (SPEC §9.1, AD-18). Synced with the config
    /// folder; Vigie never creates it.
    public var scriptModulesFolderURL: URL { configFolderURL.appendingPathComponent("modules", isDirectory: true) }

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

        if let configFolderOverride {
            self.configFolderOverride = configFolderOverride
        } else if flavor == .dev,
            let value = ProcessInfo.processInfo.environment[Self.configDirVariable], !value.isEmpty
        {
            self.configFolderOverride = URL(fileURLWithPath: value, isDirectory: true)
        } else {
            self.configFolderOverride = nil
        }
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
