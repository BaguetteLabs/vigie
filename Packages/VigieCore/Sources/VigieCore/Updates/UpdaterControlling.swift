import Foundation

/// Why the updater is off in this build.
public enum UpdaterUnavailableReason: Equatable, Sendable {
    /// `SUPublicEDKey` is empty or not a base64 Ed25519 key (dev builds, or `VIGIE_SPARKLE_PUBLIC_KEY` unset).
    case missingPublicKey
    /// `SUFeedURL` is missing, not HTTPS, or still names the `OWNER/…` placeholder release repository (A49).
    case missingFeed
}

/// The app's update engine as VigieCore sees it (Story 6.3). The App target implements it with Sparkle's
/// `SPUUpdater` (AD-2: Sparkle is App-only); VigieCore stays Sparkle-free and drives it from `[updates]`
/// (``UpdatesConfigBridge``), Settings › Updates and the context menu.
@MainActor
public protocol UpdaterControlling: AnyObject {
    /// nil when updates work in this build.
    var unavailableReason: UpdaterUnavailableReason? { get }
    /// False while a check or an update is already in progress, or when unavailable.
    var canCheckForUpdates: Bool { get }
    /// Applies `[updates]` (at start and on every change).
    func apply(_ settings: UpdateSettings)
    /// A user-initiated check, with Sparkle's own progress and result UI. Allowed even with `auto_check = false`:
    /// the user asked for this one request.
    func checkForUpdates()
    /// Called when the user changes "Automatically download and install updates" in Sparkle's update alert, so the
    /// bridge can write `[updates] auto_install` (config stays the source of truth, AD-8).
    var onAutoInstallChangedByUser: (@MainActor (Bool) -> Void)? { get set }
}

extension UpdaterControlling {
    public var isAvailable: Bool { unavailableReason == nil }
}

/// Validates the updater's Info.plist values (`SUFeedURL`, `SUPublicEDKey`) before Sparkle is touched: an
/// unconfigured build disables the updater with one log line instead of letting Sparkle raise at start.
public enum UpdaterConfiguration {
    /// `SUFeedURL`, `SUPublicEDKey` from `infoDictionary`; nil reason = usable.
    public static func check(infoDictionary: [String: Any]) -> UpdaterUnavailableReason? {
        let key = (infoDictionary["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard let raw = Data(base64Encoded: key), raw.count == 32 else { return .missingPublicKey }
        guard let feed = (infoDictionary["SUFeedURL"] as? String).flatMap(URL.init(string:)),
            feed.scheme == "https", let host = feed.host(), !host.isEmpty,
            !feed.path.hasPrefix("/OWNER/"), !feed.path.hasPrefix("//")
        else { return .missingFeed }
        return nil
    }
}
