import Foundation
import ModuleKit
import os

/// Feeds `[privacy] force` and `[privacy] auto` from `ConfigStore` into ``CorePrivacyService`` (Story 21.3).
///
/// - `force` → ``CorePrivacyService/setForced(_:)``, applied at start and on every change.
/// - `auto` → detection. With the shipped `NoScreenSharingDetection` (spike 21.1: manual only) the detector is
///   unavailable, so `auto` has no effect and the bridge logs that once. With an available detector, turning
///   `auto` on requests the detector's permission (only then, AD-20) and polls ``CorePrivacyService/refreshDetection()``
///   every ``pollInterval``; turning it off stops the polling and clears the detected state.
@MainActor
public final class PrivacyConfigBridge {
    static let forcePath = CoreSettings.path("privacy", "force")
    static let autoPath = CoreSettings.path("privacy", "auto")

    private let store: ConfigStore
    private let privacy: CorePrivacyService
    private let permissions: (any PermissionsService)?
    private let pollInterval: Duration
    private let logger: Logger
    private var changesTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var autoOn = false
    private var loggedUnavailable = false

    public init(
        store: ConfigStore, privacy: CorePrivacyService, permissions: (any PermissionsService)? = nil,
        pollInterval: Duration = .seconds(2),
        logger: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "privacy")
    ) {
        self.store = store
        self.privacy = privacy
        self.permissions = permissions
        self.pollInterval = pollInterval
        self.logger = logger
    }

    /// Applies the current config, then follows changes to the two keys until ``stop()``.
    public func start() {
        guard changesTask == nil else { return }
        let changes = store.changes  // subscribe before the first apply so no change is missed
        apply()
        changesTask = Task { [weak self] in
            for await keys in changes {
                guard let self else { return }
                if keys.contains(Self.forcePath) || keys.contains(Self.autoPath) { self.apply() }
            }
        }
    }

    public func stop() {
        changesTask?.cancel()
        changesTask = nil
        stopPolling()
    }

    /// True while the detection poll runs.
    public var isPolling: Bool { pollTask != nil }

    private func apply() {
        privacy.setForced(store.value(Self.forcePath, as: Bool.self) ?? false)
        let auto = store.value(Self.autoPath, as: Bool.self) ?? false
        guard auto != autoOn else { return }
        autoOn = auto
        if auto { startPolling() } else { stopPolling() }
    }

    private func startPolling() {
        let detector = privacy.detector
        guard detector.isAvailable else {
            if !loggedUnavailable {
                loggedUnavailable = true
                logger.debug("privacy.auto is on but this build has no screen-sharing detector; ignored")
            }
            return
        }
        pollTask?.cancel()
        let permission = detector.requiredPermission
        let permissions = permissions
        let interval = pollInterval
        pollTask = Task { [weak self] in
            if let permission, let permissions, await permissions.status(of: permission) != .granted {
                _ = await permissions.request(permission)
            }
            while !Task.isCancelled {
                let verdict = await detector.detect()
                guard !Task.isCancelled, let self else { return }
                self.privacy.setDetected(verdict.isSharing)
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        privacy.setDetected(false)
    }
}
