import Foundation
import os

/// Feeds `[updates] auto_check`, `check_interval` and `auto_install` from `ConfigStore` into the updater (Story
/// 6.3): applied at start and on every change (live reload, AD-8), and writes `auto_install` back when the user
/// flips Sparkle's own "Automatically download and install" checkbox.
@MainActor
public final class UpdatesConfigBridge {
    private let store: ConfigStore
    private let updater: any UpdaterControlling
    private let logger: Logger
    private var changesTask: Task<Void, Never>?

    public init(
        store: ConfigStore, updater: any UpdaterControlling,
        logger: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "updates")
    ) {
        self.store = store
        self.updater = updater
        self.logger = logger
    }

    public func start() {
        guard changesTask == nil else { return }
        if let reason = updater.unavailableReason {
            // Once per launch; the bridge does not follow the keys of a build that cannot update.
            logger.info("updater off in this build (\(String(describing: reason), privacy: .public))")
            return
        }
        let changes = store.changes  // subscribe before the first apply so no change is missed
        updater.apply(UpdateSettings.read(from: store))
        updater.onAutoInstallChangedByUser = { [weak self] on in self?.userChangedAutoInstall(on) }
        changesTask = Task { [weak self] in
            for await keys in changes {
                guard let self else { return }
                if !keys.isDisjoint(with: UpdateSettings.paths) {
                    self.updater.apply(UpdateSettings.read(from: self.store))
                }
            }
        }
    }

    public func stop() {
        changesTask?.cancel()
        changesTask = nil
        updater.onAutoInstallChangedByUser = nil
    }

    private func userChangedAutoInstall(_ on: Bool) {
        guard (store.value(UpdateSettings.autoInstallPath, as: Bool.self) ?? false) != on else { return }
        let store = store
        let logger = logger
        Task {
            do {
                try await store.set(UpdateSettings.autoInstallPath, to: .bool(on))
            } catch {
                logger.error("updates.auto_install not written: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
