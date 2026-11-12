import AppKit
import OSLog
import Observation
import Sparkle
import VigieCore

/// Sparkle 2 behind VigieCore's ``UpdaterControlling`` (Story 6.3, SPEC §12.4, AD-2: Sparkle is App-only).
///
/// - **Configuration.** `SUFeedURL` and `SUPublicEDKey` come from `Config/Updates.xcconfig` through Info.plist. When
///   either is unusable (dev builds, an empty key, the `OWNER/…` placeholder repository) the updater is off:
///   Sparkle is never created, one line is logged, Settings and the context menu show the action disabled.
/// - **Lazy start.** `SPUStandardUpdaterController` is created with `startingUpdater: false` and started only when
///   `[updates] auto_check` is on, or when the user asks for a check. With `auto_check = false` nothing schedules a
///   check and ``updater(_:mayPerformUpdateCheck:error:)`` refuses background checks, so no update request leaves
///   the Mac (PRD FR-4). `SUEnableAutomaticChecks = NO` in Info.plist and
///   ``updaterShouldPromptForPermissionToCheck(forUpdates:)`` keep Sparkle from asking its own permission
///   question: `[updates]` decides.
/// - **Ask first.** `automaticallyDownloadsUpdates` follows `auto_install` (off by default): Sparkle shows the update
///   alert and installs only on "Install Update" (PRD FR-61). On, it downloads in the background and installs when
///   Vigie quits.
/// - **Rejection.** Sparkle verifies the archive's EdDSA signature against `SUPublicEDKey` before extracting it
///   (`SUVerifyUpdateBeforeExtraction`), the appcast's own signature (`SURequireSignedFeed`), and that the new app's
///   Developer ID signature matches the running one; Gatekeeper then checks notarization at first launch. Any
///   failure aborts the update with Sparkle's error alert and leaves the installed version untouched.
/// - **Relaunch (AD-21).** "Install and Relaunch" makes Sparkle's installer wait for this process to exit, then
///   replace the bundle and launch the new one. Sparkle quits Vigie with `NSApp.terminate`, so the normal quit path
///   runs: `applicationShouldTerminate` stops modules, the Event Server (socket closed, unlinked only if still its
///   inode) and the config store; `applicationWillTerminate` releases the instance lock. Events sent meanwhile are
///   spooled by the CLI and replayed by the new instance before `host.ready` (`RelaunchHandoverTests`).
@MainActor @Observable
final class SparkleUpdater: NSObject, UpdaterControlling {
    let unavailableReason: UpdaterUnavailableReason?
    var onAutoInstallChangedByUser: (@MainActor (Bool) -> Void)?

    /// Mirrors `SPUUpdater.canCheckForUpdates` (KVO) so Settings re-renders when a session starts or ends.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var settings = UpdateSettings.defaults
    @ObservationIgnored private var allowsBackgroundChecks = false
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let logger: Logger

    init(bundle: Bundle = .main, logger: Logger) {
        self.logger = logger
        unavailableReason = UpdaterConfiguration.check(infoDictionary: bundle.infoDictionary ?? [:])
        super.init()
        guard unavailableReason == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        // Before start, the user may already check: the first check starts the updater.
        canCheckForUpdates = true
    }

    func apply(_ settings: UpdateSettings) {
        self.settings = settings
        guard let updater = controller?.updater else { return }
        let plan = UpdaterPlan(settings, alreadyStarted: started)
        allowsBackgroundChecks = plan.allowsBackgroundChecks
        updater.automaticallyChecksForUpdates = plan.automaticallyChecks
        updater.updateCheckInterval = plan.intervalSeconds
        updater.automaticallyDownloadsUpdates = plan.automaticallyDownloads
        if plan.startsUpdater { start() }
        logger.info(
            "updates: auto_check \(plan.automaticallyChecks), every \(Int(plan.intervalSeconds)) s, auto_install \(plan.automaticallyDownloads)"
        )
    }

    func checkForUpdates() {
        guard let controller else { return }
        if !started {
            let plan = UpdaterPlan(settings, alreadyStarted: false, userRequestedCheck: true)
            if plan.startsUpdater { start() }
        }
        guard started, controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    private func start() {
        guard let controller, !started else { return }
        do {
            try controller.updater.start()
            started = true
        } catch {
            // A bad bundle setup (key, feed) surfaces here rather than as an exception; never fatal.
            logger.error("updater did not start: \(String(describing: error), privacy: .public)")
            canCheckForUpdates = false
            return
        }
        let updater = controller.updater
        canCheckForUpdates = updater.canCheckForUpdates
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in self?.canCheckForUpdates = value }
            },
            // Sparkle's update alert has its own "Automatically download and install updates" checkbox.
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in self?.sparkleChangedAutoInstall(value) }
            },
        ]
    }

    private func sparkleChangedAutoInstall(_ value: Bool) {
        guard value != settings.downloadsAutomatically else { return }  // our own apply
        onAutoInstallChangedByUser?(value)
    }
}

extension SparkleUpdater: SPUUpdaterDelegate {
    /// Scheduled (background) checks only while `[updates] auto_check` is on; user-initiated checks always.
    nonisolated func updater(
        _ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck
    ) throws {
        let allowed = MainActor.assumeIsolated { allowsBackgroundChecks }
        if updateCheck == .updatesInBackground && !allowed {
            throw NSError(
                domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "automatic update checks are off ([updates] auto_check)"])
        }
    }

    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    nonisolated func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        let version = item.displayVersionString
        MainActor.assumeIsolated {
            logger.info("update \(version, privacy: .public) downloaded; installs when Vigie quits")
        }
        return false  // Sparkle installs on the next normal quit; no forced relaunch.
    }

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        MainActor.assumeIsolated {
            // Next: NSApp.terminate -> applicationShouldTerminate (modules, Event Server, config) ->
            // applicationWillTerminate (instance lock). The installer relaunches once this process has exited.
            logger.info("relaunching for an update; the event server stops in applicationShouldTerminate")
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let description = String(describing: error)
        MainActor.assumeIsolated {
            logger.error("update aborted: \(description, privacy: .public)")
        }
    }
}
