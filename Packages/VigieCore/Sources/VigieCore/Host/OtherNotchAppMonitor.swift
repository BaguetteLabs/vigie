import Foundation
import ModuleKit
import Observation
import os

/// Warns when another notch app runs while Vigie draws on a physical notch (Story 17.5, FR-60).
///
/// One `setup.problem` alert per listed app (``KnownNotchApps``), posted through the core notifier with Open
/// settings › Display. It is resolved when that app quits or Vigie no longer draws on a physical notch, and by
/// ``stop()``. Once the user has dismissed the alert for an app, that app is never posted again until the next
/// launch (this instance's lifetime), even if it quits and reopens or the display changes. An alert resolved
/// without a dismissal may be posted again when the conflict returns. Nothing is persisted.
@MainActor
public final class OtherNotchAppMonitor {
    /// The pane Open settings goes to (`SettingsPaneCatalog`: Settings › Display).
    public nonisolated static let settingsPane = "display"

    private let apps: any RunningApplicationsObserving
    private let drawsOnPhysicalNotch: @MainActor () -> Bool
    private let notifier: any Notifier
    private let wasDismissed: @MainActor (UUID) -> Bool
    private let known: [KnownNotchApp]
    private let log: Logger
    /// Open alerts by lowercased bundle id.
    private var handles: [String: AlertHandle] = [:]
    /// Lowercased bundle ids the user dismissed this launch.
    private var dismissed: Set<String> = []
    private var observing = false
    private var changesTask: Task<Void, Never>?

    /// - Parameters:
    ///   - apps: the running-apps seam.
    ///   - drawsOnPhysicalNotch: whether an island is shown on a physical-notch display (read under observation
    ///     tracking: the monitor re-reconciles when what it reads changes).
    ///   - notifier: the core notifier (`SetupProblemReporter.manifest`).
    ///   - wasDismissed: whether the alert with this id was dismissed by the user (read-only; the App passes
    ///     `AlertCenter.history`).
    public init(
        apps: any RunningApplicationsObserving, drawsOnPhysicalNotch: @escaping @MainActor () -> Bool,
        notifier: any Notifier, wasDismissed: @escaping @MainActor (UUID) -> Bool,
        known: [KnownNotchApp] = KnownNotchApps.all,
        log: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "notch-apps")
    ) {
        self.apps = apps
        self.drawsOnPhysicalNotch = drawsOnPhysicalNotch
        self.notifier = notifier
        self.wasDismissed = wasDismissed
        self.known = known
        self.log = log
    }

    /// Reconciles now, then again on every app launch or termination and every change of what is drawn.
    public func start() {
        guard !observing else { return }
        observing = true
        let changes = apps.changes
        changesTask = Task { @MainActor [weak self] in
            for await _ in changes {
                guard let self, self.observing else { return }
                self.refresh()
            }
        }
        refresh()
        track()
    }

    /// Ends observation and resolves the open alerts.
    public func stop() {
        guard observing else { return }
        observing = false
        changesTask?.cancel()
        changesTask = nil
        noteDismissals()
        for handle in handles.values { handle.resolve() }
        handles = [:]
    }

    /// Posts alerts for listed apps that conflict now and resolves those that no longer do. Idempotent.
    public func refresh() {
        noteDismissals()
        let running = Set(apps.runningBundleIDs().map { $0.lowercased() })
        let conflicting: [KnownNotchApp] =
            drawsOnPhysicalNotch() ? known.filter { running.contains($0.bundleID.lowercased()) } : []
        let current = Set(conflicting.map { $0.bundleID.lowercased() })
        for (key, handle) in handles where !current.contains(key) {
            handle.resolve()
            handles[key] = nil
        }
        for app in conflicting {
            let key = app.bundleID.lowercased()
            guard handles[key] == nil, !dismissed.contains(key) else { continue }
            handles[key] = notifier.post(Self.event(for: app))
            log.info("Other notch app alert posted")
        }
    }

    private func noteDismissals() {
        for (key, handle) in handles where wasDismissed(handle.id) { dismissed.insert(key) }
    }

    private func track() {
        guard observing else { return }
        withObservationTracking {
            _ = drawsOnPhysicalNotch()
            // Read unconditionally (an id that matches nothing): the hook follows the alert history, so a
            // dismissal of any open alert, including one posted after this was armed, is noted before the history
            // can trim it.
            _ = wasDismissed(UUID())
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observing else { return }
                self.refresh()
                self.track()
            }
        }
    }

    static func event(for app: KnownNotchApp) -> NotifierEvent {
        NotifierEvent(
            kind: SetupProblemReporter.alertKind, severity: .warn,
            title: String(
                format: String(localized: "vigiecore.setup.title.notchApp", bundle: .module), app.name),
            body: String(
                format: String(localized: "vigiecore.setup.body.notchApp", bundle: .module), app.name),
            action: .openSettings(pane: settingsPane), dedupeKey: "notch-app." + app.bundleID.lowercased(),
            category: String(localized: "vigiecore.setup.category.display", bundle: .module))
    }
}
