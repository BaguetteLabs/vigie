import Foundation
import ModuleKit
import Observation
import Wire
import os

/// What turning sync on or off will do, checked before anything is touched (Settings shows it before confirming).
public struct SyncPlan: Sendable, Equatable {
    /// True to turn sync on, false to turn it off.
    public let turnsOn: Bool
    /// The config folder move; nil when the config folder is already in place.
    public let config: ConfigRelocationPlan?
    /// The notes folder move; nil when it is already in place or the Notes module is not registered.
    public let notes: UserFolderRelocationPlan?
    /// `[modules.notes] folder` in `local.toml` before the change (restored by a rollback).
    public let previousNotesRecord: String?

    /// The target already holds a config (another Mac turned sync on first, Story 16.3).
    public var adoptsConfig: Bool { config?.adopts ?? false }
    /// The target already holds notes.
    public var adoptsNotes: Bool { notes?.adopts ?? false }
}

/// Why turning sync on or off was refused or failed. On every error the folders and records are as they were.
public enum SyncError: Error, Sendable, Equatable, LocalizedError {
    /// iCloud Drive is off on this Mac (its folder is missing).
    case iCloudDriveUnavailable
    case config(ConfigRelocationError)
    case notes(UserFolderRelocationError)
    /// Items of the config folder are still downloading from iCloud (downloads were started).
    case downloadsPending(Int)
    /// `[sync] icloud` could not be written; the folders were moved back.
    case recordFailed(String)

    public var errorDescription: String? {
        switch self {
        case .iCloudDriveUnavailable: SettingsText.string("settings.sync.error.unavailable")
        case .config(let error): SettingsText.format("settings.sync.error.config", error.errorDescription ?? "")
        case .notes(let error): SettingsText.format("settings.sync.error.notes", error.errorDescription ?? "")
        case .downloadsPending(let count): SettingsText.format("settings.userFolder.error.downloadsPending", count)
        case .recordFailed(let reason): SettingsText.format("settings.sync.error.record", reason)
        }
    }
}

/// iCloud sync (Story 16.2, FR102, SPEC §11.1): one switch that moves the config folder and the notes folder into
/// `iCloud Drive/Vigie/` (``AppEnvironment/iCloudSyncRootURL``) and back.
///
/// Turning on: both moves are planned first (any refusal changes nothing); the config folder moves through
/// ``ConfigStore/relocate(to:)`` (16.1), then the notes folder through ``ConfigStore/relocateUserFolder(_:)``,
/// which records `[modules.notes] folder` in `local.toml` (the Notes module follows its `folder` setting); if the
/// notes step fails the config folder is moved back; `[sync] icloud = true` is written last, only when both
/// succeeded (if it cannot be, both are moved back). A target that already has a `config.toml` / notes is
/// **adopted** (the second Mac, Story 16.3): this Mac's own folders stay where they are.
///
/// Turning off moves both back to their local defaults (the default config folder, ``AppEnvironment/localNotesFolderURL``)
/// and removes the records, then writes `icloud = false`; it refuses while files are still downloading. No restart
/// either way: ConfigStore re-arms its watchers and the Notes module observes its setting.
///
/// `local.toml` and secrets never move: the first lives in `AppEnvironment.applicationSupportURL`, the second in the
/// Keychain.
@MainActor @Observable
public final class SyncController {
    /// `[sync] icloud` (local).
    public nonisolated static let icloudPath = CoreSettings.path("sync", "icloud")
    /// `[modules.notes] folder` (a `.local` path setting of the Notes module, Story 15.1).
    public nonisolated static let notesFolderPath = ConfigKeyPath.module(
        "notes", "folder", scope: .local)

    @ObservationIgnored public let configStore: ConfigStore
    @ObservationIgnored private let logger: Logger

    public init(configStore: ConfigStore) {
        self.configStore = configStore
        logger = Logger(subsystem: configStore.environment.bundleID, category: "sync")
    }

    public var environment: AppEnvironment { configStore.environment }

    /// Mirrors `[sync] icloud`.
    public var isOn: Bool { configStore.value(Self.icloudPath, as: Bool.self) ?? false }

    /// iCloud Drive is on for this Mac (checked on each call).
    public var isAvailable: Bool { environment.isICloudDriveAvailable }

    /// `iCloud Drive/Vigie` (`Vigie Dev` for the dev build).
    public var rootURL: URL { environment.iCloudSyncRootURL }

    /// The notes folder in use as this controller sees it: the recorded `folder`, or this build's local default
    /// while `folder` keeps its declared default; nil when the Notes module is not registered.
    public var currentNotesFolder: URL? {
        guard let declared = notesDefault else { return nil }
        guard let value = configStore.value(Self.notesFolderPath, as: String.self), !value.isEmpty,
            value != declared, let url = environment.expandingHome(value)
        else { return environment.localNotesFolderURL }
        return url
    }

    /// The Notes module's declared default for `folder` (`~/Notes/Vigie`); nil when it is not registered.
    private var notesDefault: String? {
        guard case .path(let value) = configStore.schema.entries[Self.notesFolderPath]?.descriptor.kind else {
            return nil
        }
        return value ?? ""
    }

    // MARK: - Plans

    /// Checks turning sync on. Throws ``SyncError/iCloudDriveUnavailable`` or the first refusal.
    public func planTurnOn() throws(SyncError) -> SyncPlan {
        guard isAvailable else { throw .iCloudDriveUnavailable }
        return try plan(
            turnsOn: true, configTarget: environment.iCloudConfigFolderURL,
            notesTarget: environment.iCloudNotesFolderURL)
    }

    /// Checks turning sync off (back to the local defaults).
    public func planTurnOff() throws(SyncError) -> SyncPlan {
        try plan(
            turnsOn: false, configTarget: environment.defaultConfigFolderURL,
            notesTarget: environment.localNotesFolderURL)
    }

    private func plan(turnsOn: Bool, configTarget: URL, notesTarget: URL) throws(SyncError) -> SyncPlan {
        var config: ConfigRelocationPlan?
        do throws(ConfigRelocationError) {
            config = try configStore.planRelocation(to: configTarget)
        } catch .sameFolder {
            config = nil
        } catch {
            throw .config(error)
        }
        var notes: UserFolderRelocationPlan?
        let previous = configStore.rawValue(at: Self.notesFolderPath, in: .local).flatMap { value -> String? in
            if case .string(let string) = value { return string }
            return nil
        }
        if let current = currentNotesFolder {
            let abbreviated = environment.abbreviatingHome(notesTarget)
            let record: String? = abbreviated == notesDefault ? nil : abbreviated
            do throws(UserFolderRelocationError) {
                notes = try configStore.planUserFolderRelocation(
                    setting: Self.notesFolderPath, from: current, to: notesTarget, record: record)
            } catch .sameFolder {
                notes = nil
            } catch {
                throw .notes(error)
            }
        } else {
            logger.notice("The Notes module is not registered; sync moves the config folder only")
        }
        return SyncPlan(turnsOn: turnsOn, config: config, notes: notes, previousNotesRecord: previous)
    }

    // MARK: - Turning on and off

    /// Turns sync on: plans, then moves the config folder, then the notes folder, then writes `icloud = true`.
    @discardableResult
    public func turnOn() async throws(SyncError) -> SyncPlan {
        let plan = try planTurnOn()
        try await apply(plan)
        return plan
    }

    /// Turns sync off: moves both folders back to their local defaults, then writes `icloud = false`.
    @discardableResult
    public func turnOff() async throws(SyncError) -> SyncPlan {
        let plan = try planTurnOff()
        try await apply(plan)
        return plan
    }

    /// Applies a plan from ``planTurnOn()`` / ``planTurnOff()``. Re-checks iCloud Drive when turning on.
    public func apply(_ plan: SyncPlan) async throws(SyncError) {
        if plan.turnsOn, !isAvailable { throw .iCloudDriveUnavailable }
        // Out of iCloud: every file must be local before anything moves (their downloads are started).
        if !plan.turnsOn {
            if let config = plan.config, !config.adopts {
                let pending = await configStore.pendingDownloads(in: config.current)
                if pending > 0 { throw .downloadsPending(pending) }
            }
            if let notes = plan.notes, !notes.adopts {
                let pending = await configStore.pendingDownloads(in: notes.current)
                if pending > 0 { throw .notes(.downloadsPending(pending)) }
            }
        }
        if let config = plan.config {
            do throws(ConfigRelocationError) {
                try await configStore.relocate(to: config.target)
            } catch {
                throw .config(error)
            }
        }
        if let notes = plan.notes {
            do throws(UserFolderRelocationError) {
                try await configStore.relocateUserFolder(notes)
            } catch {
                await rollBackConfig(plan)
                throw .notes(error)
            }
        }
        do throws(ConfigError) {
            try await configStore.set(Self.icloudPath, to: .bool(plan.turnsOn))
        } catch {
            await rollBackNotes(plan)
            await rollBackConfig(plan)
            throw .recordFailed(String(describing: error))
        }
        logger.info("iCloud sync is \(plan.turnsOn ? "on" : "off", privacy: .public)")
    }

    private func rollBackConfig(_ plan: SyncPlan) async {
        guard let config = plan.config else { return }
        do throws(ConfigRelocationError) {
            try await configStore.relocate(to: config.current)
        } catch {
            logger.error("Could not move the config folder back: \(String(describing: error), privacy: .public)")
        }
    }

    private func rollBackNotes(_ plan: SyncPlan) async {
        guard let notes = plan.notes else { return }
        do throws(UserFolderRelocationError) {
            let back = try configStore.planUserFolderRelocation(
                setting: notes.setting, from: notes.target, to: notes.current, record: plan.previousNotesRecord)
            // An adopted target stays as it was: only the setting goes back.
            let restore =
                notes.adopts
                ? UserFolderRelocationPlan(
                    setting: back.setting, current: back.current, target: back.target, adopts: true,
                    record: back.record)
                : back
            try await configStore.relocateUserFolder(restore)
        } catch {
            logger.error("Could not move the notes folder back: \(String(describing: error), privacy: .public)")
        }
    }
}
