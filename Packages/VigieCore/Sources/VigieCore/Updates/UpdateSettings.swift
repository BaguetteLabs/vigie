import Foundation

/// The `[updates]` keys the updater follows (Story 6.3, SPEC §11 and §12.4, PRD FR-4 and FR-61).
///
/// `channel` is not here: A63 (ruled 2026-11-06) keeps a single stable feed until the public release, so the key
/// is read by nobody yet (Story 19.3). `prices` belongs to the price-table fetch of Story 6.5.
public struct UpdateSettings: Equatable, Sendable {
    /// `[updates] auto_check`: scheduled checks. Off = no update network call at all (FR-4); only an explicit
    /// "Check for Updates…" reaches the feed.
    public var autoCheck: Bool
    /// `[updates] check_interval`.
    public var checkInterval: Duration
    /// `[updates] auto_install`: download in the background and install on quit, without asking (FR-61). Off = ask
    /// before installing.
    public var autoInstall: Bool

    public init(autoCheck: Bool, checkInterval: Duration, autoInstall: Bool) {
        self.autoCheck = autoCheck
        self.checkInterval = checkInterval
        self.autoInstall = autoInstall
    }

    /// SPEC §11 defaults: check every 24 h, ask before installing.
    public static let defaults = UpdateSettings(autoCheck: true, checkInterval: .seconds(24 * 3600), autoInstall: false)

    /// Sparkle ignores intervals under one hour in release builds; shorter values are raised to it.
    public static let minimumInterval: Duration = .seconds(3600)

    public static let autoCheckPath = CoreSettings.path("updates", "auto_check")
    public static let checkIntervalPath = CoreSettings.path("updates", "check_interval")
    public static let autoInstallPath = CoreSettings.path("updates", "auto_install")
    public static let paths: Set<ConfigKeyPath> = [autoCheckPath, checkIntervalPath, autoInstallPath]

    /// The current values, defaults for missing or invalid keys.
    @MainActor
    public static func read(from store: ConfigStore) -> UpdateSettings {
        UpdateSettings(
            autoCheck: store.value(autoCheckPath, as: Bool.self) ?? defaults.autoCheck,
            checkInterval: store.value(checkIntervalPath, as: Duration.self) ?? defaults.checkInterval,
            autoInstall: store.value(autoInstallPath, as: Bool.self) ?? defaults.autoInstall)
    }

    /// The interval handed to the updater, in seconds (never under ``minimumInterval``).
    public var effectiveIntervalSeconds: TimeInterval {
        let interval = max(checkInterval, Self.minimumInterval).components
        return TimeInterval(interval.seconds) + TimeInterval(interval.attoseconds) / 1e18
    }

    /// Background downloads only exist with scheduled checks: `auto_install` without `auto_check` installs nothing.
    public var downloadsAutomatically: Bool { autoCheck && autoInstall }
}

/// What the App's updater must set on Sparkle for a given ``UpdateSettings`` (pure, so VigieCore tests it without
/// Sparkle). The updater is started lazily: never while `auto_check` is off, unless the user asks for a check.
public struct UpdaterPlan: Equatable, Sendable {
    /// `SPUUpdater.automaticallyChecksForUpdates`.
    public let automaticallyChecks: Bool
    /// `SPUUpdater.updateCheckInterval`.
    public let intervalSeconds: TimeInterval
    /// `SPUUpdater.automaticallyDownloadsUpdates`.
    public let automaticallyDownloads: Bool
    /// `SPUUpdaterDelegate.updater(_:mayPerformUpdateCheck:error:)` answer for background (scheduled) checks.
    public let allowsBackgroundChecks: Bool
    /// Start the updater now (it is never stopped once started; turning `auto_check` off only stops scheduling).
    public let startsUpdater: Bool

    public init(_ settings: UpdateSettings, alreadyStarted: Bool, userRequestedCheck: Bool = false) {
        automaticallyChecks = settings.autoCheck
        intervalSeconds = settings.effectiveIntervalSeconds
        automaticallyDownloads = settings.downloadsAutomatically
        allowsBackgroundChecks = settings.autoCheck
        startsUpdater = !alreadyStarted && (settings.autoCheck || userRequestedCheck)
    }
}
